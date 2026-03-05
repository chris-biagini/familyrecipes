# frozen_string_literal: true

# Orchestrates IngredientCatalog create/update/destroy with post-write side
# effects: syncing new aisles to the kitchen's aisle_order, recalculating
# nutrition for affected recipes, and broadcasting meal plan refreshes.
# Mirrors RecipeWriteService — controllers call class methods, never inline
# post-save logic.
#
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution for affected-recipe queries
# - RecipeNutritionJob: recalculates recipe nutrition_data
# - MealPlan: broadcasts meal plan refresh signals
class CatalogWriteService
  Result = Data.define(:entry, :persisted)

  WEB_SOURCE = [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }].freeze

  def self.upsert(kitchen:, ingredient_name:, params:)
    new(kitchen:, ingredient_name:).upsert(params:) # rubocop:disable Rails/SkipsModelValidations
  end

  def self.destroy(kitchen:, ingredient_name:)
    new(kitchen:, ingredient_name:).destroy
  end

  def initialize(kitchen:, ingredient_name:)
    @kitchen = kitchen
    @ingredient_name = ingredient_name
  end

  def upsert(params:)
    entry = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name:)
    entry.assign_from_params(**params, sources: WEB_SOURCE)
    return Result.new(entry:, persisted: false) unless entry.save

    sync_aisle_to_kitchen(entry.aisle) if entry.aisle
    recalculate_affected_recipes if entry.basis_grams.present?
    broadcast_meal_plan_refresh if entry.aisle

    Result.new(entry:, persisted: true)
  end

  def destroy
    entry = IngredientCatalog.find_by!(kitchen:, ingredient_name:)
    entry.destroy!
    recalculate_affected_recipes
    broadcast_meal_plan_refresh
    Result.new(entry:, persisted: true)
  end

  private

  attr_reader :kitchen, :ingredient_name

  def sync_aisle_to_kitchen(aisle)
    return if aisle == 'omit'
    return if kitchen.parsed_aisle_order.include?(aisle)

    existing = kitchen.aisle_order.to_s
    kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
  end

  def recalculate_affected_recipes
    resolver = IngredientCatalog.resolver_for(kitchen)
    raw_names = resolver.all_keys_for(ingredient_name)
    kitchen.recipes
           .joins(steps: :ingredients)
           .where(ingredients: { name: raw_names })
           .distinct
           .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end

  def broadcast_meal_plan_refresh
    kitchen.broadcast_update
  end
end

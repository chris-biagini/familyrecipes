# frozen_string_literal: true

# Orchestrates IngredientCatalog create/update/destroy with post-write side
# effects: syncing new aisles to the kitchen's aisle_order, recalculating
# nutrition for affected recipes, and broadcasting a page-refresh morph.
# Mirrors RecipeWriteService — controllers call class methods, never inline
# post-save logic. Also provides bulk_import for ImportService: batch save
# with single-pass aisle sync and nutrition recalc, no per-entry broadcast.
#
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution for affected-recipe queries
# - RecipeNutritionJob: recalculates recipe nutrition_data
# - AisleWriteService: aisle sync after catalog saves
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
class CatalogWriteService
  Result = Data.define(:entry, :persisted)
  BulkResult = Data.define(:persisted_count, :errors)

  WEB_SOURCE = [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }].freeze

  def self.upsert(kitchen:, ingredient_name:, params:)
    new(kitchen:, ingredient_name:).upsert(params:) # rubocop:disable Rails/SkipsModelValidations
  end

  def self.destroy(kitchen:, ingredient_name:)
    new(kitchen:, ingredient_name:).destroy
  end

  def self.bulk_import(kitchen:, entries_hash:)
    new(kitchen:, ingredient_name: nil).bulk_import(entries_hash:)
  end

  def initialize(kitchen:, ingredient_name:)
    @kitchen = kitchen
    @ingredient_name = ingredient_name
  end

  def upsert(params:)
    entry = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name:)
    entry.assign_from_params(**params, sources: WEB_SOURCE)
    return Result.new(entry:, persisted: false) unless entry.save

    AisleWriteService.sync_new_aisle(kitchen:, aisle: entry.aisle) if entry.aisle
    recalculate_affected_recipes if entry.basis_grams.present?
    kitchen.broadcast_update

    Result.new(entry:, persisted: true)
  end

  def destroy
    entry = IngredientCatalog.find_by!(kitchen:, ingredient_name:)
    entry.destroy!
    recalculate_affected_recipes
    kitchen.broadcast_update
    Result.new(entry:, persisted: true)
  end

  def bulk_import(entries_hash:)
    return BulkResult.new(persisted_count: 0, errors: []) if entries_hash.blank?

    persisted_count, errors = save_all_entries(entries_hash)
    sync_bulk_aisles(entries_hash)
    recalculate_all_affected_recipes(entries_hash)
    BulkResult.new(persisted_count:, errors:)
  end

  private

  attr_reader :kitchen, :ingredient_name

  def recalculate_affected_recipes
    resolver = IngredientCatalog.resolver_for(kitchen)
    raw_names = resolver.all_keys_for(ingredient_name)
    kitchen.recipes
           .joins(steps: :ingredients)
           .where(ingredients: { name: raw_names })
           .distinct
           .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end

  def save_all_entries(entries_hash)
    persisted = 0
    errors = []

    entries_hash.each do |name, entry|
      record = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name: name)
      record.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))
      if record.save
        persisted += 1
      else
        errors << "#{name}: #{record.errors.full_messages.join(', ')}"
      end
    end

    [persisted, errors]
  end

  def sync_bulk_aisles(entries_hash)
    aisles = entries_hash.values.filter_map { |e| e['aisle'] }
    AisleWriteService.sync_new_aisles(kitchen:, aisles:)
  end

  def recalculate_all_affected_recipes(entries_hash)
    return if kitchen.recipes.none?

    resolver = IngredientCatalog.resolver_for(kitchen)
    raw_names = entries_hash.keys.flat_map { |name| resolver.all_keys_for(name) }.uniq
    kitchen.recipes
           .joins(steps: :ingredients)
           .where(ingredients: { name: raw_names })
           .distinct
           .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end
end

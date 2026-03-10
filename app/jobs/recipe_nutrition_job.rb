# frozen_string_literal: true

# Recalculates a recipe's nutrition_data JSON from its ingredients and the
# IngredientCatalog. Bridges the AR world (IngredientCatalog entries) to the
# domain NutritionCalculator by building a lookup hash in the format the
# calculator expects. Runs synchronously via perform_now at import time.
# Accepts an optional resolver: to avoid redundant catalog queries when called
# in a batch (e.g., from CatalogWriteService).
class RecipeNutritionJob < ApplicationJob
  def perform(recipe, resolver: nil)
    loaded = eager_load_recipe(recipe)
    resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)
    return if resolver.lookup.empty?

    nutrition_data = build_nutrition_data(resolver.lookup)
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: resolver.omit_set)
    result = calculator.calculate(loaded, {})

    recipe.update_column(:nutrition_data, serialize_result(result)) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def eager_load_recipe(recipe)
    Recipe.with_full_tree.find(recipe.id)
  end

  def build_nutrition_data(catalog)
    catalog.transform_values do |entry|
      data = { 'nutrients' => nutrients_hash(entry) }
      data['density'] = density_hash(entry) if entry.density_grams && entry.density_volume && entry.density_unit
      data['portions'] = entry.portions if entry.portions.present?
      data
    end
  end

  def nutrients_hash(entry)
    IngredientCatalog::NUTRIENT_COLUMNS.each_with_object({ 'basis_grams' => entry.basis_grams.to_f }) do |col, hash|
      hash[col.to_s] = entry.public_send(col)&.to_f || 0
    end
  end

  def density_hash(entry)
    {
      'grams' => entry.density_grams.to_f,
      'volume' => entry.density_volume.to_f,
      'unit' => entry.density_unit
    }
  end

  def serialize_result(result)
    {
      'totals' => stringify_nutrient_keys(result.totals),
      'serving_count' => result.serving_count,
      'per_serving' => stringify_nutrient_keys(result.per_serving),
      'per_unit' => stringify_nutrient_keys(result.per_unit),
      'makes_quantity' => result.makes_quantity,
      'makes_unit_singular' => result.makes_unit_singular,
      'makes_unit_plural' => result.makes_unit_plural,
      'units_per_serving' => result.units_per_serving,
      'missing_ingredients' => result.missing_ingredients,
      'partial_ingredients' => result.partial_ingredients,
      'skipped_ingredients' => result.skipped_ingredients,
      'total_weight_grams' => result.total_weight_grams
    }
  end

  def stringify_nutrient_keys(hash)
    return unless hash

    hash.transform_keys(&:to_s).transform_values(&:to_f)
  end
end

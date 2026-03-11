# frozen_string_literal: true

# Recalculates a recipe's nutrition_data JSON from its ingredients and the
# IngredientCatalog. Passes the resolver's catalog lookup directly to
# NutritionCalculator — no format translation needed. Runs synchronously
# via perform_now at import time. Accepts an optional resolver: to avoid
# redundant catalog queries when called in a batch.
#
# Collaborators:
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution
# - FamilyRecipes::NutritionCalculator: FDA-label computation
class RecipeNutritionJob < ApplicationJob
  def perform(recipe, resolver: nil)
    loaded = eager_load_recipe(recipe)
    resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)
    return if resolver.lookup.empty?

    calculator = FamilyRecipes::NutritionCalculator.new(resolver.lookup, omit_set: resolver.omit_set)
    result = calculator.calculate(loaded, {})

    recipe.update_column(:nutrition_data, serialize_result(result)) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def eager_load_recipe(recipe)
    Recipe.with_full_tree.find(recipe.id)
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

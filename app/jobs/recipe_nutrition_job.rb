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

    recipe.update_column(:nutrition_data, result.as_json) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def eager_load_recipe(recipe)
    Recipe.with_full_tree.find(recipe.id)
  end
end

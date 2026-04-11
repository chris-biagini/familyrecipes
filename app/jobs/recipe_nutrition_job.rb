# frozen_string_literal: true

# Recalculates a recipe's nutrition_data JSON from its ingredients and the
# IngredientCatalog. Always writes a result — even with an empty catalog,
# the calculator produces valid zero-value totals with missing_ingredients.
# Runs synchronously via perform_now at import time. Failures are logged
# and re-raised in test so they surface immediately.
#
# Collaborators:
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution
# - Mirepoix::NutritionCalculator: FDA-label computation
class RecipeNutritionJob < ApplicationJob
  def perform(recipe, resolver: nil)
    loaded = eager_load_recipe(recipe)
    resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)

    if resolver.lookup.empty?
      Rails.logger.warn { "Nutrition: empty catalog for kitchen #{loaded.kitchen_id}, recipe #{recipe.id}" }
    end

    calculator = Mirepoix::NutritionCalculator.new(resolver.lookup, omit_set: resolver.omit_set)
    result = calculator.calculate(loaded, {})
    recipe.update_column(:nutrition_data, result.as_json) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => error
    Rails.logger.error { "Nutrition failed for recipe #{recipe.id}: #{error.message}" }
    raise if Rails.env.test?
  end

  private

  def eager_load_recipe(recipe)
    Recipe.with_full_tree.find(recipe.id)
  end
end

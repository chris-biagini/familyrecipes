# frozen_string_literal: true

# After a recipe's nutrition changes, recalculates nutrition for all recipes
# that reference it via cross-references. Prevents stale per-serving numbers
# when a sub-recipe's ingredients change.
class CascadeNutritionJob < ApplicationJob
  def perform(recipe)
    ActsAsTenant.with_tenant(recipe.kitchen) do
      recipe.referencing_recipes.find_each do |dependent|
        RecipeNutritionJob.perform_now(dependent)
      end
    end
  end
end

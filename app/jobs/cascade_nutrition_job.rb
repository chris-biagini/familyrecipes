# frozen_string_literal: true

class CascadeNutritionJob < ApplicationJob
  def perform(recipe)
    ActsAsTenant.with_tenant(recipe.kitchen) do
      recipe.referencing_recipes.find_each do |dependent|
        RecipeNutritionJob.perform_now(dependent)
      end
    end
  end
end

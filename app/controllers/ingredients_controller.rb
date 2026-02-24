# frozen_string_literal: true

class IngredientsController < ApplicationController
  def index
    @ingredients_with_recipes = build_ingredient_index
    @nutrition_lookup = IngredientCatalog.lookup_for(current_kitchen)
    @missing_ingredients = find_missing_ingredients
  end

  private

  def build_ingredient_index
    recipes_by_ingredient.sort_by { |name, _| name.downcase }
  end

  def recipes_by_ingredient
    recipes = current_kitchen.recipes.includes(steps: :ingredients)
    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        index[ingredient.name] << recipe unless index[ingredient.name].include?(recipe)
      end
    end
  end

  def find_missing_ingredients
    @ingredients_with_recipes.filter_map { |name, _| name unless @nutrition_lookup.key?(name) }
  end
end

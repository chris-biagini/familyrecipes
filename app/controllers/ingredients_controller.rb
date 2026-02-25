# frozen_string_literal: true

class IngredientsController < ApplicationController
  before_action :require_membership

  def index
    @ingredients_with_recipes = build_ingredient_index
    @nutrition_lookup = IngredientCatalog.lookup_for(current_kitchen)
    @missing_ingredients = find_missing_ingredients
    @available_aisles = current_kitchen.all_aisles
  end

  private

  def build_ingredient_index
    recipes_by_ingredient.sort_by { |name, _| name.downcase }
  end

  def recipes_by_ingredient
    seen = Hash.new { |h, k| h[k] = Set.new }
    recipes = current_kitchen.recipes.includes(steps: :ingredients)

    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        index[ingredient.name] << recipe if seen[ingredient.name].add?(recipe.id)
      end
    end
  end

  def find_missing_ingredients
    @ingredients_with_recipes.filter_map { |name, _| name unless @nutrition_lookup.key?(name) }
  end
end

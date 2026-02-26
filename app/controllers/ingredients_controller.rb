# frozen_string_literal: true

class IngredientsController < ApplicationController
  before_action :require_membership

  def index
    @nutrition_lookup = IngredientCatalog.lookup_for(current_kitchen)
    @ingredients_with_recipes = build_ingredient_index
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
        name = canonical_ingredient_name(ingredient.name, index)
        index[name] << recipe if seen[name].add?(recipe.id)
      end
    end
  end

  def canonical_ingredient_name(name, index)
    entry = @nutrition_lookup[name]
    return entry.ingredient_name if entry

    FamilyRecipes::Inflector.ingredient_variants(name).find { |v| index.key?(v) } || name
  end

  def find_missing_ingredients
    @ingredients_with_recipes.filter_map { |name, _| name unless @nutrition_lookup.key?(name) }
  end
end

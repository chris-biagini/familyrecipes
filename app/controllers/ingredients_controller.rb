# frozen_string_literal: true

class IngredientsController < ApplicationController
  def index
    @ingredients_with_recipes = build_ingredient_index
  end

  private

  def build_ingredient_index
    alias_map = load_alias_map
    index = recipes_by_ingredient(alias_map)
    index.sort_by { |name, _| name.downcase }
  end

  def recipes_by_ingredient(alias_map)
    recipes = current_kitchen.recipes.includes(steps: :ingredients)
    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        canonical = alias_map[ingredient.name.downcase] || ingredient.name
        index[canonical] << recipe unless index[canonical].include?(recipe)
      end
    end
  end

  def load_alias_map
    FamilyRecipes.build_alias_map(load_grocery_aisles)
  end

  def load_grocery_aisles
    content = SiteDocument.content_for('grocery_aisles')
    return FamilyRecipes.parse_grocery_aisles_markdown(content) if content

    FamilyRecipes.parse_grocery_info(Rails.root.join('db/seeds/resources/grocery-info.yaml'))
  end
end

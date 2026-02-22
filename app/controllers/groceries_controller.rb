# frozen_string_literal: true

class GroceriesController < ApplicationController
  def show
    @categories = Category.ordered.includes(recipes: { steps: :ingredients })
    @grocery_aisles = load_grocery_aisles
    @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
    @omit_set = build_omit_set
    @recipe_map = build_recipe_map
    @unit_plurals = collect_unit_plurals
  end

  private

  def load_grocery_aisles
    FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
  end

  def build_omit_set
    (@grocery_aisles['Omit_From_List'] || []).flat_map do |item|
      [item[:name], *item[:aliases]].map(&:downcase)
    end.to_set
  end

  def build_recipe_map
    FamilyRecipes.parse_recipes(Rails.root.join('recipes')).to_h { |r| [r.id, r] }
  end

  def collect_unit_plurals
    @recipe_map.values
               .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
               .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
               .uniq
               .to_h { |u| [u, FamilyRecipes::Inflector.unit_display(u, 2)] }
  end
end

# frozen_string_literal: true

# Ingredients management page — member-only. Displays a searchable, filterable
# table of all ingredients across recipes with their nutrition/density status
# and aisle assignments. The edit action renders the nutrition editor form as a
# partial for the dialog. Uses the shared IngredientRows concern for row-building
# logic shared with NutritionEntriesController and RecipeBroadcaster.
class IngredientsController < ApplicationController
  include IngredientRows

  before_action :require_membership
  before_action :prevent_html_caching, only: :index

  def index
    @ingredient_rows = build_ingredient_rows(catalog_lookup)
    @summary = build_summary(@ingredient_rows)
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles
    recipes = recipes_for_ingredient(ingredient_name)

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles,
                     next_name: next_needing_attention(after: ingredient_name, lookup: catalog_lookup),
                     recipes: }
  end

  private

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def recipes_for_ingredient(name)
    current_kitchen.recipes.includes(steps: :ingredients).select do |recipe|
      recipe.ingredients.any? { |i| (catalog_lookup[i.name]&.ingredient_name || i.name) == name }
    end
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    [name, catalog_lookup[name]]
  end

  def catalog_lookup
    @catalog_lookup ||= IngredientCatalog.lookup_for(current_kitchen)
  end

  def decoded_ingredient_name
    params[:ingredient_name]
  end
end

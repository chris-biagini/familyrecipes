# frozen_string_literal: true

# Ingredients management page — member-only. Displays a searchable, filterable
# table of all ingredients across recipes with their nutrition/density status
# and aisle assignments. The edit action renders the nutrition editor form as a
# partial for the dialog. Delegates row-building to IngredientRowBuilder.
#
# - IngredientResolver: canonical name resolution and catalog entry lookup
# - IngredientRowBuilder: builds ingredient rows and summary from kitchen recipes
class IngredientsController < ApplicationController
  before_action :require_membership
  before_action :prevent_html_caching, only: :index

  def index
    @ingredient_rows = row_builder.rows
    @summary = row_builder.summary
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles
    recipes = recipes_for_ingredient(ingredient_name)

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles,
                     next_name: row_builder.next_needing_attention(after: ingredient_name),
                     recipes: }
  end

  private

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen, resolver:)
  end

  def resolver
    @resolver ||= IngredientCatalog.resolver_for(current_kitchen)
  end

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def recipes_for_ingredient(name)
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where(ingredients: { name: resolver.all_keys_for(name) })
                   .distinct
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    [name, resolver.catalog_entry(name)]
  end

  def decoded_ingredient_name
    params[:ingredient_name]
  end
end

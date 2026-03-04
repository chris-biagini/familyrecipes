# frozen_string_literal: true

# Ingredients management page — member-only. Displays a searchable, filterable
# table of all ingredients across recipes with their nutrition/density status
# and aisle assignments. The edit action renders the nutrition editor form as a
# partial for the dialog. Delegates row-building to IngredientRowBuilder.
#
# - IngredientRowBuilder: builds ingredient rows and summary from kitchen recipes
# - IngredientCatalog: lookup overlay for name resolution and status
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
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen, lookup: catalog_lookup)
  end

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def recipes_for_ingredient(name)
    raw_names = matching_raw_names(name)
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where(ingredients: { name: raw_names })
                   .distinct
  end

  def matching_raw_names(canonical_name)
    catalog_lookup.filter_map { |raw, entry| raw if entry.ingredient_name == canonical_name }
                  .push(canonical_name)
                  .uniq
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

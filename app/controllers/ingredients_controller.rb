# frozen_string_literal: true

# Ingredients management page — member-only. Displays a searchable, filterable
# table of all ingredients across recipes and Quick Bites with their
# nutrition/density status and aisle assignments. The edit action renders the
# nutrition editor form as a partial for the dialog. Delegates all data
# computation to IngredientRowBuilder (rows, sources, unit resolution).
#
# - IngredientRowBuilder: rows, summary, sources, needed_units, coverage
class IngredientsController < ApplicationController
  before_action :require_membership
  before_action :prevent_html_caching, only: :index

  def index
    @ingredient_rows = row_builder.rows
    @summary = row_builder.summary
    @coverage = row_builder.coverage
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles
    sources = row_builder.sources_for(ingredient_name)
    needed_units = row_builder.needed_units(ingredient_name)

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles, sources:, needed_units: }
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

  def load_ingredient_data
    name = decoded_ingredient_name
    [name, resolver.catalog_entry(name)]
  end

  def decoded_ingredient_name
    params[:ingredient_name]
  end
end

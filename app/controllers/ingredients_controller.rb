# frozen_string_literal: true

class IngredientsController < ApplicationController
  include IngredientRows

  before_action :require_membership

  def index
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    @ingredient_rows = build_ingredient_rows(lookup)
    @summary = build_summary(@ingredient_rows)
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles,
                     next_name: next_needing_attention(ingredient_name) }
  end

  private

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def next_needing_attention(current_name)
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    sorted = sorted_ingredient_names(lookup)
    idx = sorted.index(current_name)
    return unless idx

    sorted[(idx + 1)..].find { |name| row_status(lookup[name]) != 'complete' }
  end

  def sorted_ingredient_names(lookup)
    recipes_by_ingredient(lookup).keys.sort_by(&:downcase)
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    entry = IngredientCatalog.lookup_for(current_kitchen)[name]
    [name, entry]
  end

  def decoded_ingredient_name
    params[:ingredient_name].tr('-', ' ')
  end
end

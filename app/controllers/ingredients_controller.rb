# frozen_string_literal: true

class IngredientsController < ApplicationController
  before_action :require_membership

  def index
    @nutrition_lookup = IngredientCatalog.lookup_for(current_kitchen)
    @ingredient_rows = build_ingredient_rows
    @summary = build_summary
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def show
    ingredient_name, entry, recipes = load_ingredient_or_not_found
    return unless ingredient_name

    render partial: 'ingredients/detail_panel',
           locals: { ingredient_name:, entry:, recipes: }
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles,
                     next_name: next_needing_attention(ingredient_name) }
  end

  private

  def build_ingredient_rows
    @nutrition_lookup ||= IngredientCatalog.lookup_for(current_kitchen)
    index = recipes_by_ingredient
    index.sort_by { |name, _| name.downcase }.map { |name, recipes| ingredient_row(name, recipes) }
  end

  def ingredient_row(name, recipes)
    entry = @nutrition_lookup[name]
    { name:, entry:, recipe_count: recipes.size, recipes:,
      has_nutrition: entry&.calories.present?,
      has_density: entry&.density_grams.present?,
      aisle: entry&.aisle,
      source: entry_source(entry),
      status: row_status(entry) }
  end

  def build_summary
    { total: @ingredient_rows.size,
      complete: @ingredient_rows.count { |r| r[:status] == 'complete' },
      missing_nutrition: @ingredient_rows.count { |r| !r[:has_nutrition] },
      missing_density: @ingredient_rows.count { |r| r[:has_nutrition] && !r[:has_density] } }
  end

  def entry_source(entry)
    return 'missing' unless entry

    entry.custom? ? 'custom' : 'global'
  end

  def row_status(entry)
    return 'missing' if entry&.calories.blank?

    return 'incomplete' if entry.density_grams.blank?

    'complete'
  end

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def next_needing_attention(current_name)
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    sorted = sorted_ingredient_names
    idx = sorted.index(current_name)
    return unless idx

    sorted[(idx + 1)..].find { |name| row_status(lookup[name]) != 'complete' }
  end

  def sorted_ingredient_names
    recipes_by_ingredient.keys.sort_by(&:downcase)
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    entry = IngredientCatalog.lookup_for(current_kitchen)[name]
    [name, entry]
  end

  def load_ingredient_or_not_found
    name = decoded_ingredient_name
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    entry = lookup[name]
    recipes = recipes_for_ingredient(name, lookup)

    unless entry || recipes.any?
      head :not_found
      return
    end

    [name, entry, recipes]
  end

  def recipes_for_ingredient(name, lookup)
    seen = Set.new
    current_kitchen.recipes.includes(steps: :ingredients).select do |recipe|
      recipe.ingredients.any? do |i|
        resolved = lookup[i.name]&.ingredient_name || i.name
        resolved == name && seen.add?(recipe.id)
      end
    end
  end

  def decoded_ingredient_name
    params[:ingredient_name].tr('-', ' ')
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
end

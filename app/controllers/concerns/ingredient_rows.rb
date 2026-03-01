# frozen_string_literal: true

# Shared logic for building ingredient table row data.
# Used by IngredientsController (full index) and NutritionEntriesController (turbo stream updates).
module IngredientRows
  extend ActiveSupport::Concern

  private

  def build_ingredient_rows(lookup, recipes: nil)
    index = recipes_by_ingredient(lookup, recipes:)
    index.sort_by { |name, _| name.downcase }.map { |name, recipes| ingredient_row(name, recipes, lookup) }
  end

  def ingredient_row(name, recipes, lookup)
    entry = lookup[name]
    { name:, entry:, recipe_count: recipes.size, recipes:,
      has_nutrition: entry&.basis_grams.present?,
      has_density: entry&.density_grams.present?,
      aisle: entry&.aisle,
      source: entry_source(entry),
      status: row_status(entry) }
  end

  def build_summary(rows)
    { total: rows.size,
      complete: rows.count { |r| r[:status] == 'complete' },
      missing_nutrition: rows.count { |r| !r[:has_nutrition] },
      missing_density: rows.count { |r| r[:has_nutrition] && !r[:has_density] } }
  end

  def entry_source(entry)
    return 'missing' unless entry

    entry.custom? ? 'custom' : 'global'
  end

  def row_status(entry)
    return 'missing' if entry&.basis_grams.blank?
    return 'incomplete' if entry.density_grams.blank?

    'complete'
  end

  def recipes_by_ingredient(lookup, recipes: nil)
    seen = Hash.new { |h, k| h[k] = Set.new }
    recipes ||= current_kitchen.recipes.includes(steps: :ingredients)

    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name, index, lookup)
        index[name] << recipe if seen[name].add?(recipe.id)
      end
    end
  end

  def canonical_ingredient_name(name, index, lookup)
    entry = lookup[name]
    return entry.ingredient_name if entry

    FamilyRecipes::Inflector.ingredient_variants(name).find { |v| index.key?(v) } || name
  end
end

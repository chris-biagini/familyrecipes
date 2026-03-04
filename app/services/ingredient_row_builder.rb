# frozen_string_literal: true

# Builds ingredient table row data for the ingredients index page, Turbo Stream
# updates, and real-time broadcasts. Delegates name resolution to an
# IngredientResolver, then computes nutrition/density status for each unique
# ingredient across all recipes.
#
# Collaborators:
# - IngredientResolver (name resolution, catalog entry access)
# - IngredientCatalog.resolver_for (default resolver factory)
# - IngredientsController, NutritionEntriesController, RecipeBroadcaster
class IngredientRowBuilder
  def initialize(kitchen:, recipes: nil, resolver: nil)
    @kitchen = kitchen
    @recipes = recipes || kitchen.recipes.includes(steps: :ingredients)
    @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
  end

  def rows
    @rows ||= build_rows
  end

  def summary
    @summary ||= build_summary
  end

  def next_needing_attention(after:)
    sorted = recipes_by_ingredient.keys.sort_by(&:downcase)
    idx = sorted.index { |name| name.casecmp(after).zero? }
    return unless idx

    sorted[(idx + 1)..].find { |name| row_status(@resolver.catalog_entry(name)) != 'complete' }
  end

  private

  attr_reader :kitchen, :recipes

  def lookup
    @resolver.lookup
  end

  def build_rows
    recipes_by_ingredient
      .sort_by { |name, _| name.downcase }
      .map { |name, recs| ingredient_row(name, recs) }
  end

  def build_summary
    { total: rows.size,
      complete: rows.count { |r| r[:status] == 'complete' },
      missing_nutrition: rows.count { |r| !r[:has_nutrition] },
      missing_density: rows.count { |r| r[:has_nutrition] && !r[:has_density] } }
  end

  def ingredient_row(name, recs)
    entry = @resolver.catalog_entry(name)
    { name:, entry:, recipe_count: recs.size, recipes: recs,
      has_nutrition: entry&.basis_grams.present?,
      has_density: entry&.density_grams.present?,
      aisle: entry&.aisle,
      source: entry_source(entry),
      status: row_status(entry) }
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

  def recipes_by_ingredient
    @recipes_by_ingredient ||= compute_recipes_by_ingredient
  end

  def compute_recipes_by_ingredient
    seen = Hash.new { |h, k| h[k] = Set.new }

    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name)
        index[name] << recipe if seen[name].add?(recipe.id)
      end
    end
  end

  def canonical_ingredient_name(name)
    @resolver.resolve(name)
  end
end

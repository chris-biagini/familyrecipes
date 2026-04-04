# frozen_string_literal: true

# Builds ingredient table row data for the ingredients index page, Turbo Stream
# updates, and real-time broadcasts. Delegates name resolution to an
# IngredientResolver, then computes nutrition/density status for each unique
# ingredient across all recipes and Quick Bites. Also provides per-ingredient
# source lists, unit resolution analysis, and aggregate coverage stats.
# Resolution checking is self-contained — no NutritionCalculator dependency.
#
# Collaborators:
# - IngredientResolver (name resolution, catalog entry access)
# - IngredientCatalog.resolver_for (default resolver factory)
# - IngredientsController, NutritionEntriesController
# - QuickBite / QuickBiteIngredient (AR-backed grocery bundles)
class IngredientRowBuilder # rubocop:disable Metrics/ClassLength
  QuickBiteSource = Data.define(:title)

  def initialize(kitchen:, recipes: nil, resolver: nil)
    @kitchen = kitchen
    @recipes = recipes || kitchen.recipes.select(:id, :title, :slug).includes(:ingredients, steps: :ingredients)
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

  def needed_units(ingredient_name)
    entry = @resolver.catalog_entry(ingredient_name)
    units = collect_units_for(ingredient_name)
    return [] if units.empty?

    units.map do |unit|
      resolvable = unit_resolvable?(unit, entry)
      { unit:, resolvable:, method: resolution_method(unit, resolvable, entry) }
    end
  end

  def coverage
    @coverage ||= build_coverage
  end

  def sources_for(name)
    recipes_by_ingredient[name] || []
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
      custom: rows.count { |r| r[:source] == 'custom' },
      missing_aisle: rows.count { |r| r[:aisle].blank? && !r[:omit_from_shopping] },
      missing_nutrition: rows.count { |r| !r[:has_nutrition] },
      missing_density: rows.count { |r| !r[:has_density] } }
  end

  def build_coverage
    resolvable_count, unresolvable = partition_by_resolvability(units_by_ingredient)

    summary.merge(fully_resolvable: resolvable_count, unresolvable:)
  end

  def partition_by_resolvability(units_map)
    unresolvable = rows.filter_map do |row|
      unresolvable_units_for(row[:name], row[:entry], units_map[row[:name]])
    end

    [rows.size - unresolvable.size, unresolvable]
  end

  def unresolvable_units_for(name, entry, units)
    return nil if units.blank?

    bad = find_bad_units(name, entry, units)
    return nil if bad.empty?

    { name:, units: bad, recipes: recipes_by_ingredient[name] }
  end

  def find_bad_units(_name, entry, units)
    return units.map { |u| { unit: u, method: 'no nutrition data' } } if entry&.basis_grams.blank?

    units.reject { |u| unit_resolvable?(u, entry) }
         .map { |u| { unit: u, method: resolution_method(u, false, entry) } }
  end

  def ingredient_row(name, recs)
    entry = @resolver.catalog_entry(name)
    units = collect_units_for(name)
    all_resolvable = units.empty? || (entry&.basis_grams.present? && units.all? { |u| unit_resolvable?(u, entry) })
    { name:, entry:, recipe_count: recs.size, recipes: recs,
      has_nutrition: entry&.basis_grams.present?,
      has_density: entry&.density_grams.present?,
      aisle: entry&.aisle,
      omit_from_shopping: entry&.omit_from_shopping || false,
      source: entry_source(entry),
      status: row_status(entry),
      resolvable: all_resolvable }
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

    index = recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, idx|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name)
        idx[name] << recipe if seen[name].add?(recipe.id)
      end
    end

    merge_quick_bite_sources(index, seen)
  end

  def merge_quick_bite_sources(index, seen)
    kitchen.quick_bites.includes(:quick_bite_ingredients).find_each do |qb|
      source = QuickBiteSource.new(title: qb.title)
      qb.all_ingredient_names.each do |raw_name|
        name = canonical_ingredient_name(raw_name)
        qb_key = "qb:#{qb.id}"
        index[name] << source if seen[name].add?(qb_key)
      end
    end

    index
  end

  def collect_units_for(ingredient_name)
    (units_by_ingredient[ingredient_name] || Set.new).to_a
  end

  def units_by_ingredient
    @units_by_ingredient ||= compute_units_by_ingredient
  end

  def compute_units_by_ingredient
    recipes.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |recipe, map|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name)
        unit = ingredient.quantity_unit
        map[name] << unit if unit || ingredient.quantity_low
      end
    end
  end

  def unit_resolvable?(unit, entry)
    FamilyRecipes::UnitResolver.new(entry).resolvable?(1, unit)
  end

  def resolution_method(unit, resolvable, entry)
    return 'weight' if FamilyRecipes::UnitResolver.weight_unit?(unit)
    return 'no nutrition data' if entry&.basis_grams.blank?
    return unitless_method(resolvable) if unit.nil?
    return volume_method(resolvable) if FamilyRecipes::UnitResolver.volume_unit?(unit)

    resolvable ? "via #{unit}" : 'no portion'
  end

  def unitless_method(resolvable)
    resolvable ? 'via ~unitless' : 'no ~unitless portion'
  end

  def volume_method(resolvable)
    resolvable ? 'via density' : 'no density'
  end

  def canonical_ingredient_name(name)
    @resolver.resolve(name)
  end
end

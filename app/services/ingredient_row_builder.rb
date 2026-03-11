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
# - FamilyRecipes::QuickBite (parsed from Kitchen#quick_bites_content)
class IngredientRowBuilder # rubocop:disable Metrics/ClassLength
  QuickBiteSource = Data.define(:title)
  WEIGHT_UNITS = FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS.keys.freeze
  VOLUME_UNITS = FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.keys.freeze

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
      missing_aisle: rows.count { |r| r[:aisle].blank? },
      missing_nutrition: rows.count { |r| !r[:has_nutrition] },
      missing_density: rows.count { |r| !r[:has_density] } }
  end

  def build_coverage
    units_map = all_units_by_ingredient
    resolvable_count, unresolvable = partition_by_resolvability(units_map)

    summary.merge(fully_resolvable: resolvable_count, unresolvable:)
  end

  def partition_by_resolvability(units_map)
    unresolvable = []

    resolvable_count = rows.count do |row|
      bad = unresolvable_units_for(row[:name], row[:entry], units_map[row[:name]])
      unresolvable << bad unless bad.nil?
      bad.nil?
    end

    [resolvable_count, unresolvable]
  end

  def all_units_by_ingredient
    recipes.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |recipe, map|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name)
        map[name] << ingredient.quantity_unit
      end
    end
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

    index = recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, idx|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name)
        idx[name] << recipe if seen[name].add?(recipe.id)
      end
    end

    merge_quick_bite_sources(index, seen)
  end

  def merge_quick_bite_sources(index, seen)
    kitchen.parsed_quick_bites.each do |qb|
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
    keys = @resolver.all_keys_for(ingredient_name).to_set(&:downcase)

    recipes.each_with_object(Set.new) do |recipe, units|
      recipe.ingredients
            .select { |i| keys.include?(i.name.downcase) }
            .each { |i| units << i.quantity_unit }
    end.to_a
  end

  def unit_resolvable?(unit, entry)
    return true if weight_unit?(unit)
    return false if entry&.basis_grams.blank?
    return portion_defined?(entry, unit) if unit && !volume_unit?(unit)
    return density_defined?(entry) if unit && volume_unit?(unit)

    entry.portions&.key?('~unitless')
  end

  def volume_unit?(unit)
    unit && VOLUME_UNITS.include?(unit.downcase)
  end

  def portion_defined?(entry, unit)
    return false if entry.portions.blank?

    entry.portions.any? { |k, _| k.casecmp(unit).zero? }
  end

  def density_defined?(entry)
    entry.density_grams.present? && entry.density_volume.present? && entry.density_unit.present?
  end

  def weight_unit?(unit)
    unit && WEIGHT_UNITS.include?(unit.downcase)
  end

  def resolution_method(unit, resolvable, entry)
    return 'weight' if weight_unit?(unit)
    return 'no nutrition data' if entry&.basis_grams.blank?
    return unitless_method(resolvable) if unit.nil?
    return volume_method(resolvable) if VOLUME_UNITS.include?(unit.downcase)

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

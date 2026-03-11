# frozen_string_literal: true

# Builds ingredient table row data for the ingredients index page, Turbo Stream
# updates, and real-time broadcasts. Delegates name resolution to an
# IngredientResolver, then computes nutrition/density status for each unique
# ingredient across all recipes and Quick Bites.
#
# Collaborators:
# - IngredientResolver (name resolution, catalog entry access)
# - IngredientCatalog.resolver_for (default resolver factory)
# - IngredientsController, NutritionEntriesController
# - FamilyRecipes::QuickBite (parsed from Kitchen#quick_bites_content)
class IngredientRowBuilder
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

    calculator = FamilyRecipes::NutritionCalculator.new(
      entry ? { ingredient_name => entry } : {}, omit_set: Set.new
    )
    calc_entry = calculator.nutrition_data[ingredient_name]

    units.map { |unit| build_unit_row(unit, calculator, calc_entry, entry) }
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

  def build_unit_row(unit, calculator, calc_entry, entry)
    resolvable = weight_unit?(unit) || (calc_entry && calculator.resolvable?(1, unit, calc_entry))
    { unit:, resolvable: resolvable || false, method: resolution_method(unit, resolvable, entry) }
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

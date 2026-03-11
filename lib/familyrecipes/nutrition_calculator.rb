# frozen_string_literal: true

module FamilyRecipes
  # Computes FDA-label nutrition facts for a recipe from IngredientCatalog
  # entries. Resolves ingredient quantities to grams via a priority chain:
  # weight units → named portions → density-derived volume conversions. Produces
  # a Result with totals, per-serving, and per-unit breakdowns, plus lists of
  # missing and partially resolvable ingredients.
  #
  # - RecipeNutritionJob: calls this at save time; Result stored as JSON on Recipe
  # - NutritionConstraints: defines NUTRIENT_KEYS consumed here
  # - IngredientCatalog: AR model whose accessors this class reads directly
  class NutritionCalculator # rubocop:disable Metrics/ClassLength
    NUTRIENTS = NutritionConstraints::NUTRIENT_KEYS

    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
      'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
      'gal' => 3785.41, 'ml' => 1, 'l' => 1000
    }.freeze

    # Subset of VOLUME_TO_ML for the density editor dropdown — excludes bulk
    # units (pt, qt, gal) that don't make sense for expressing ingredient density.
    DENSITY_UNITS = ['cup', 'tbsp', 'tsp', 'fl oz', 'ml', 'l'].freeze

    Result = Data.define(
      :totals, :serving_count, :per_serving, :per_unit,
      :makes_quantity, :makes_unit_singular, :makes_unit_plural,
      :units_per_serving, :total_weight_grams,
      :missing_ingredients, :partial_ingredients, :skipped_ingredients
    ) do
      def complete?
        missing_ingredients.empty? && partial_ingredients.empty?
      end
    end

    attr_reader :nutrition_data

    def initialize(nutrition_data, omit_set: Set.new)
      @omit_set = omit_set

      @nutrition_data = nutrition_data.select do |_name, entry|
        entry.basis_grams.present? && entry.basis_grams.positive?
      end.to_h
    end

    def calculate(recipe, recipe_map)
      totals, total_weight, missing, partial, skipped = sum_totals(recipe, recipe_map)
      serving_count = parse_serving_count(recipe)

      Result.new(
        totals: totals,
        serving_count: serving_count,
        per_serving: divide_nutrients(totals, serving_count),
        total_weight_grams: total_weight,
        **per_unit_metadata(recipe, totals, serving_count),
        missing_ingredients: missing,
        partial_ingredients: partial,
        skipped_ingredients: skipped
      )
    end

    def resolvable?(value, unit, entry)
      !to_grams(value, unit, entry).nil?
    end

    private

    def sum_totals(recipe, recipe_map)
      active = recipe.all_ingredients_with_quantities(recipe_map)
                     .reject { |name, _| @omit_set.include?(name.downcase) }
      known, unknown = active.partition { |name, _| @nutrition_data.key?(name) }

      totals = NUTRIENTS.index_with { |_n| 0.0 }
      weight = { grams: 0.0 }
      missing, partial, skipped = partition_ingredients(totals, weight, known, unknown)
      [totals, weight[:grams], missing, partial, skipped]
    end

    def partition_ingredients(totals, weight, known, unknown)
      known_quantified, known_skipped = split_by_quantified(known)
      unknown_quantified, unknown_skipped = split_by_quantified(unknown)

      partial = known_quantified.each_with_object([]) do |(name, amounts), partials|
        accumulate_amounts(totals, weight, partials, name, amounts, @nutrition_data[name])
      end

      skipped = known_skipped.map(&:first).concat(unknown_skipped.map(&:first))
      [unknown_quantified.map(&:first), partial, skipped]
    end

    def split_by_quantified(ingredients)
      ingredients.partition { |_, amounts| amounts.any? { |a| !a.nil? } }
    end

    def accumulate_amounts(totals, weight, partial, name, amounts, entry) # rubocop:disable Metrics/ParameterLists
      amounts.each do |amount|
        next if amount.nil? || amount.value.nil?

        grams = to_grams(amount.value, amount.unit, entry)
        if grams.nil?
          partial << name unless partial.include?(name)
          next
        end

        weight[:grams] += grams
        NUTRIENTS.each { |nutrient| totals[nutrient] += nutrient_per_gram(entry, nutrient) * grams }
      end
    end

    def divide_nutrients(totals, divisor)
      NUTRIENTS.index_with { |n| totals[n] / divisor } if divisor
    end

    def per_unit_metadata(recipe, totals, serving_count)
      makes_qty = recipe.makes_quantity&.to_i
      makes_qty = nil unless makes_qty&.positive?
      unit_singular = Inflector.safe_singular(recipe.makes_unit_noun) if recipe.makes_unit_noun

      {
        per_unit: divide_nutrients(totals, makes_qty),
        makes_quantity: makes_qty,
        makes_unit_singular: unit_singular,
        makes_unit_plural: (Inflector.safe_plural(unit_singular) if unit_singular),
        units_per_serving: (makes_qty.to_f / serving_count if makes_qty && recipe.serves)
      }
    end

    def nutrient_per_gram(entry, nutrient)
      (entry.public_send(nutrient) || 0) / entry.basis_grams.to_f
    end

    def to_grams(value, unit, entry) # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      portions = entry.portions || {}

      # 1. Bare count with no unit (e.g. "Eggs, 3") — use ~unitless portion
      if unit.nil?
        grams_per_unit = portions['~unitless']
        return grams_per_unit ? value * grams_per_unit : nil
      end

      unit_down = unit.downcase

      # 2. Weight unit — direct conversion
      weight_factor = WEIGHT_CONVERSIONS[unit_down]
      return value * weight_factor if weight_factor

      # 3. Named portion — explicit user-verified value from portions hash
      grams_per_unit = portions[unit] || portions[unit_down] ||
                       portions.find { |k, _| k.downcase == unit_down }&.last
      return value * grams_per_unit if grams_per_unit

      # 4. Volumetric with density — derive from serving block
      ml_factor = VOLUME_TO_ML[unit_down]
      if ml_factor
        density = derive_density(entry)
        return value * ml_factor * density if density
      end

      # 5. Can't resolve
      nil
    end # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def derive_density(entry)
      return nil unless entry.density_grams && entry.density_volume && entry.density_unit

      ml_factor = VOLUME_TO_ML[entry.density_unit.downcase]
      return nil unless ml_factor

      volume_ml = entry.density_volume * ml_factor
      return nil if volume_ml <= 0

      entry.density_grams / volume_ml
    end

    def parse_serving_count(recipe)
      if recipe.serves
        recipe.serves.to_i
      elsif recipe.makes_quantity
        recipe.makes_quantity&.to_i
      end
    end
  end
end

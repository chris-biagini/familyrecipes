# frozen_string_literal: true

module FamilyRecipes
  # Aggregates nutrient totals for a recipe from IngredientCatalog entries.
  # Delegates quantity-to-grams resolution to UnitResolver, then sums nutrients
  # proportionally. Produces a Result with totals, per-serving, and per-unit
  # breakdowns, plus lists of missing and partially resolvable ingredients.
  #
  # Collaborators:
  # - RecipeNutritionJob: calls this at save time; Result stored as JSON on Recipe
  # - NutritionConstraints: defines NUTRIENT_KEYS consumed here
  # - IngredientCatalog: AR model whose accessors this class reads directly
  # - UnitResolver: resolves ingredient quantities to grams
  class NutritionCalculator
    NUTRIENTS = NutritionConstraints::NUTRIENT_KEYS

    IngredientDetail = Data.define(:grams, :nutrients)

    Result = Data.define(
      :totals, :serving_count, :per_serving, :per_unit,
      :makes_quantity, :makes_unit_singular, :makes_unit_plural,
      :units_per_serving, :total_weight_grams,
      :missing_ingredients, :partial_ingredients, :skipped_ingredients,
      :ingredient_details
    ) do
      def as_json(_options = nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        to_h.transform_keys(&:to_s).tap do |h|
          %w[totals per_serving per_unit].each do |key|
            h[key] = h[key]&.transform_keys(&:to_s)&.transform_values(&:to_f)
          end
          %w[total_weight_grams serving_count makes_quantity units_per_serving].each do |key|
            h[key] = h[key]&.to_f
          end
          h['ingredient_details'] = h['ingredient_details']&.transform_values do |detail|
            { 'grams' => detail.grams.to_f,
              'nutrients' => detail.nutrients.transform_keys(&:to_s).transform_values(&:to_f) }
          end
        end
      end
    end

    attr_reader :nutrition_data, :omit_set

    def initialize(nutrition_data, omit_set: Set.new)
      @omit_set = omit_set

      @nutrition_data = nutrition_data.select do |_name, entry|
        entry.basis_grams.present? && entry.basis_grams.positive?
      end.to_h
    end

    def calculate(recipe, recipe_map)
      totals, total_weight, missing, partial, skipped, details = sum_totals(recipe, recipe_map)
      serving_count = parse_serving_count(recipe)

      Result.new(
        totals: totals,
        serving_count: serving_count,
        per_serving: divide_nutrients(totals, serving_count),
        total_weight_grams: total_weight,
        **per_unit_metadata(recipe, totals, serving_count),
        missing_ingredients: missing,
        partial_ingredients: partial,
        skipped_ingredients: skipped,
        ingredient_details: details
      )
    end

    private

    def sum_totals(recipe, recipe_map)
      active = recipe.all_ingredients_with_quantities(recipe_map)
                     .reject { |name, _| @omit_set.include?(name.downcase) }
      known, unknown = active.partition { |name, _| @nutrition_data.key?(name) }

      totals = NUTRIENTS.index_with { |_n| 0.0 }
      weight = { grams: 0.0 }
      details = {}
      missing, partial, skipped = partition_ingredients(totals, weight, details, known, unknown)
      [totals, weight[:grams], missing, partial, skipped, details]
    end

    def partition_ingredients(totals, weight, details, known, unknown)
      known_quantified, known_skipped = split_by_quantified(known)
      unknown_quantified, unknown_skipped = split_by_quantified(unknown)

      partial = known_quantified.each_with_object([]) do |(name, amounts), partials|
        accumulate_amounts(totals, weight, details, partials, name, amounts, @nutrition_data[name])
      end

      skipped = known_skipped.map(&:first).concat(unknown_skipped.map(&:first))
      [unknown_quantified.map(&:first), partial, skipped]
    end

    def split_by_quantified(ingredients)
      ingredients.partition { |_, amounts| amounts.any? { |a| !a.nil? } }
    end

    def accumulate_amounts(totals, weight, details, partial, name, amounts, entry) # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
      ingredient_grams = 0.0
      ingredient_nutrients = NUTRIENTS.index_with { |_n| 0.0 }

      amounts.each do |amount|
        next if amount.nil? || amount.value.nil?

        grams = UnitResolver.new(entry).to_grams(amount.value, amount.unit)
        if grams.nil?
          partial << name unless partial.include?(name)
          next
        end

        weight[:grams] += grams
        ingredient_grams += grams
        NUTRIENTS.each do |nutrient|
          contribution = nutrient_per_gram(entry, nutrient) * grams
          totals[nutrient] += contribution
          ingredient_nutrients[nutrient] += contribution
        end
      end

      return unless ingredient_grams.positive?

      details[name] = IngredientDetail.new(grams: ingredient_grams, nutrients: ingredient_nutrients)
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

    def parse_serving_count(recipe)
      if recipe.serves
        recipe.serves.to_i
      elsif recipe.makes_quantity
        recipe.makes_quantity&.to_i
      end
    end
  end
end

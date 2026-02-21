# frozen_string_literal: true

# NutritionCalculator
#
# Calculates nutrition facts for a recipe by looking up each ingredient
# in a nutrition data table and converting quantities to grams.
# Expects density-first schema with nutrients block and optional density.

module FamilyRecipes
  class NutritionCalculator
    NUTRIENTS = %i[calories fat saturated_fat trans_fat cholesterol sodium
                   carbs fiber total_sugars added_sugars protein].freeze

    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'cup' => 236.588, 'tbsp' => 14.787, 'tsp' => 4.929, 'ml' => 1, 'l' => 1000
    }.freeze

    Result = Data.define(
      :totals, :serving_count, :per_serving,
      :missing_ingredients, :partial_ingredients
    ) do
      def complete?
        missing_ingredients.empty? && partial_ingredients.empty?
      end
    end

    attr_reader :nutrition_data

    def initialize(nutrition_data, omit_set: Set.new)
      @omit_set = omit_set

      @nutrition_data = nutrition_data.select do |name, entry|
        unless entry['nutrients'].is_a?(Hash)
          warn "WARNING: Nutrition entry '#{name}' has invalid nutrients (#{entry['nutrients'].inspect}), skipping."
          next false
        end
        basis_grams = entry.dig('nutrients', 'basis_grams')
        unless basis_grams.is_a?(Numeric) && basis_grams.positive?
          warn "WARNING: Nutrition entry '#{name}' has invalid basis_grams (#{basis_grams.inspect}), skipping."
          next false
        end
        true
      end.to_h
    end

    def calculate(recipe, alias_map, recipe_map)
      totals = NUTRIENTS.to_h { |n| [n, 0.0] }
      missing = []
      partial = []

      ingredient_amounts = recipe.all_ingredients_with_quantities(alias_map, recipe_map)

      ingredient_amounts.each do |name, amounts|
        next if @omit_set.include?(name.downcase)

        entry = @nutrition_data[name]
        unless entry
          missing << name
          next
        end

        amounts.each do |amount|
          next if amount.nil?
          next if amount.value.nil?

          grams = to_grams(amount.value, amount.unit, entry)
          if grams.nil?
            partial << name unless partial.include?(name)
            next
          end

          NUTRIENTS.each do |nutrient|
            totals[nutrient] += nutrient_per_gram(entry, nutrient) * grams
          end
        end
      end

      serving_count = parse_serving_count(recipe)
      per_serving = (NUTRIENTS.to_h { |n| [n, totals[n] / serving_count] } if serving_count)

      Result.new(
        totals: totals,
        serving_count: serving_count,
        per_serving: per_serving,
        missing_ingredients: missing,
        partial_ingredients: partial
      )
    end

    def resolvable?(value, unit, entry)
      !to_grams(value, unit, entry).nil?
    end

    private

    def nutrient_per_gram(entry, nutrient)
      basis_grams = entry.dig('nutrients', 'basis_grams')
      return 0 if basis_grams.nil? || basis_grams <= 0

      (entry.dig('nutrients', nutrient.to_s) || 0) / basis_grams.to_f
    end

    def to_grams(value, unit, entry)
      portions = entry['portions'] || {}

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
    end

    def derive_density(entry)
      density = entry['density']
      return nil unless density
      return nil unless density['volume'] && density['unit']

      ml_factor = VOLUME_TO_ML[density['unit'].to_s.downcase]
      return nil unless ml_factor

      volume_ml = density['volume'] * ml_factor
      return nil if volume_ml <= 0

      density['grams'] / volume_ml
    end

    def parse_serving_count(recipe)
      if recipe.serves
        recipe.serves.to_i
      elsif recipe.makes
        recipe.makes_quantity&.to_i
      end
    end
  end
end

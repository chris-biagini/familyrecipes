# NutritionCalculator
#
# Calculates nutrition facts for a recipe by looking up each ingredient
# in a nutrition data table and converting quantities to grams.
# Expects per_serving schema with serving block and optional density.

module FamilyRecipes
  class NutritionCalculator
    NUTRIENTS = [:calories, :fat, :saturated_fat, :trans_fat, :cholesterol, :sodium,
                 :carbs, :fiber, :total_sugars, :added_sugars, :protein].freeze

    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'cup' => 236.588, 'tbsp' => 14.787, 'tsp' => 4.929, 'ml' => 1, 'l' => 1000
    }.freeze

    Result = Struct.new(
      :totals, :serving_count, :per_serving,
      :missing_ingredients, :partial_ingredients,
      keyword_init: true
    ) do
      def complete?
        missing_ingredients.empty? && partial_ingredients.empty?
      end
    end

    attr_reader :nutrition_data

    def initialize(nutrition_data, omit_set: Set.new)
      @nutrition_data = {}
      @omit_set = omit_set

      nutrition_data.each do |name, entry|
        serving_grams = entry.dig('serving', 'grams')
        unless serving_grams.is_a?(Numeric) && serving_grams > 0
          warn "WARNING: Nutrition entry '#{name}' has invalid serving.grams (#{serving_grams.inspect}), skipping."
          next
        end
        unless entry['per_serving'].is_a?(Hash)
          warn "WARNING: Nutrition entry '#{name}' has invalid per_serving (#{entry['per_serving'].inspect}), skipping."
          next
        end
        @nutrition_data[name] = entry
      end
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

          value, unit = amount
          next if value.nil?

          grams = to_grams(value, unit, entry)
          if grams.nil?
            partial << name unless partial.include?(name)
            next
          end

          NUTRIENTS.each do |nutrient|
            totals[nutrient] += nutrient_per_gram(entry, nutrient) * grams
          end
        end
      end

      serving_count = parse_serving_count(recipe.yield_line)
      per_serving = if serving_count
        NUTRIENTS.to_h { |n| [n, totals[n] / serving_count] }
      end

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
      serving_grams = entry.dig('serving', 'grams')
      return 0 if serving_grams.nil? || serving_grams <= 0
      (entry.dig('per_serving', nutrient.to_s) || 0) / serving_grams.to_f
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
      serving = entry['serving']
      return nil unless serving
      return nil unless serving['volume_amount'] && serving['volume_unit']
      ml_factor = VOLUME_TO_ML[serving['volume_unit'].to_s.downcase]
      return nil unless ml_factor
      volume_ml = serving['volume_amount'] * ml_factor
      return nil if volume_ml <= 0
      serving['grams'] / volume_ml
    end

    def parse_serving_count(yield_line)
      return nil if yield_line.nil? || yield_line.strip.empty?
      yield_line[/\d+/]&.to_i
    end
  end
end

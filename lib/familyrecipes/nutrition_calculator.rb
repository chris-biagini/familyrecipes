# NutritionCalculator
#
# Calculates nutrition facts for a recipe by looking up each ingredient
# in a nutrition data table and converting quantities to grams.

module FamilyRecipes
  class NutritionCalculator
    NUTRIENTS = [:calories, :protein, :fat, :carbs, :fiber, :sodium].freeze

    # Universal weight/volume conversions that never vary by ingredient.
    # These are checked before per-ingredient portions, so they don't need
    # entries in nutrition-data.yaml.
    STANDARD_CONVERSIONS = {
      'oz'  => 28.35,
      'lbs' => 453.59,
      'kg'  => 1000,
      'ml'  => 1,
      'l'   => 1000
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

    def initialize(nutrition_data, omit_set: Set.new)
      @nutrition_data = nutrition_data
      @omit_set = omit_set
    end

    def calculate(recipe, alias_map, recipe_map)
      totals = NUTRIENTS.each_with_object({}) { |n, h| h[n] = 0.0 }
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

          factor = grams / 100.0
          NUTRIENTS.each do |nutrient|
            totals[nutrient] += (entry['per_100g'][nutrient.to_s] || 0) * factor
          end
        end
      end

      serving_count = parse_serving_count(recipe.yield_line)
      per_serving = if serving_count
        NUTRIENTS.each_with_object({}) { |n, h| h[n] = totals[n] / serving_count }
      end

      Result.new(
        totals: totals,
        serving_count: serving_count,
        per_serving: per_serving,
        missing_ingredients: missing,
        partial_ingredients: partial
      )
    end

    private

    def to_grams(value, unit, entry)
      portions = entry['portions'] || {}

      # Bare count with no unit (e.g. "Eggs, 3") — use ~unitless portion
      if unit.nil?
        grams_per_unit = portions['~unitless']
        return grams_per_unit ? value * grams_per_unit : value
      end

      unit_down = unit.downcase
      return value if unit_down == 'g'

      # Universal weight/volume conversions (oz, lbs, kg, ml, l)
      standard = STANDARD_CONVERSIONS[unit] || STANDARD_CONVERSIONS[unit_down]
      return value * standard if standard

      # Per-ingredient portions: try exact match, then case-insensitive match
      grams_per_unit = portions[unit] || portions.find { |k, _| k.downcase == unit_down }&.last

      return nil if grams_per_unit.nil?

      value * grams_per_unit
    end

    def parse_serving_count(yield_line)
      return nil if yield_line.nil? || yield_line.strip.empty?
      match = yield_line.match(/\d+/)
      match ? match[0].to_i : nil
    end
  end
end

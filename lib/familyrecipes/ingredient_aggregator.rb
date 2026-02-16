# IngredientAggregator module
#
# Sums ingredient quantities by unit for grocery list display

module IngredientAggregator
  # Given an array of Ingredient objects with the same name,
  # returns an array of [numeric_value, unit] pairs (plus nil for unquantified).
  def self.aggregate_amounts(ingredients)
    sums = {}        # unit -> numeric sum
    has_unquantified = false

    ingredients.each do |ingredient|
      raw_value = ingredient.quantity_value
      unit = ingredient.quantity_unit
      unit = Ingredient::UNIT_NORMALIZATIONS[unit] || unit if unit

      numeric = begin
        Float(raw_value)
      rescue StandardError
        nil
      end if raw_value

      if numeric
        sums[unit] = (sums[unit] || 0.0) + numeric
      else
        has_unquantified = true
      end
    end

    result = sums.map { |unit, value| [value, unit] }
    result << nil if has_unquantified
    result = [nil] if result.empty?
    result
  end
end

# frozen_string_literal: true

# IngredientAggregator module
#
# Sums ingredient quantities by unit for grocery list display

module IngredientAggregator
  # Given an array of Ingredient objects with the same name,
  # returns an array of Quantity objects (plus nil for unquantified).
  def self.aggregate_amounts(ingredients)
    parsed = ingredients.map do |ingredient|
      unit = ingredient.quantity_unit
      unit = FamilyRecipes::Inflector.normalize_unit(unit) if unit
      numeric = Float(ingredient.quantity_value, exception: false) if ingredient.quantity_value
      [unit, numeric]
    end

    sums = parsed
           .select { |_, numeric| numeric }
           .group_by { |unit, _| unit }
           .transform_values { |pairs| pairs.sum { |_, n| n } }

    has_unquantified = parsed.any? { |_, numeric| numeric.nil? }

    amounts = sums.map { |unit, value| Quantity[value, unit] }
    amounts << nil if has_unquantified
    amounts.empty? ? [nil] : amounts
  end
end

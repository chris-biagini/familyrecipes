# frozen_string_literal: true

module IngredientAggregator
  # Merges two Quantity arrays, summing values per unit.
  # nil entries represent unquantified ingredients ("Salt" with no amount).
  def self.merge_amounts(existing, new_amounts)
    all = existing + new_amounts
    has_nil = all.include?(nil)

    sums = all.compact.each_with_object(Hash.new(0.0)) do |quantity, h|
      h[quantity.unit] += quantity.value
    end

    result = sums.map { |unit, value| Quantity[value, unit] }
    result << nil if has_nil
    result
  end

  def self.aggregate_amounts(ingredients)
    parsed = ingredients.map do |ingredient|
      unit = ingredient.quantity_unit
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

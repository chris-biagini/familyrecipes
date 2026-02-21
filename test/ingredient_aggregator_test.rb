# frozen_string_literal: true

require_relative 'test_helper'

class IngredientAggregatorTest < Minitest::Test
  def test_sums_same_unit
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '60 g'),
      FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '140 g')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)

    assert_equal 1, result.length
    assert_in_delta 200.0, result[0].value
    assert_equal 'g', result[0].unit
  end

  def test_keeps_different_units_separate
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '200 g'),
      FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '3 Tbsp')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)

    assert_equal 2, result.length
    units = result.map(&:unit).sort

    assert_includes units, 'g'
    assert_includes units, 'tbsp'
  end

  def test_mixed_quantified_and_unquantified
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Oil', quantity: '50 g'),
      FamilyRecipes::Ingredient.new(name: 'Oil')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    numeric = result.find { |a| a.is_a?(Quantity) }

    assert_equal Quantity[50.0, 'g'], numeric
    assert_includes result, nil
  end

  def test_all_unquantified
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Salt')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)

    assert_equal [nil], result
  end

  def test_unitless_numeric_sums
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Egg', quantity: '2'),
      FamilyRecipes::Ingredient.new(name: 'Egg', quantity: '1')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)

    assert_equal 1, result.length
    assert_in_delta 3.0, result[0].value
    assert_nil result[0].unit
  end

  def test_fractional_quantities_sum
    ingredients = [
      FamilyRecipes::Ingredient.new(name: 'Cream', quantity: '1/2 cup'),
      FamilyRecipes::Ingredient.new(name: 'Cream', quantity: '1/4 cup')
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)

    assert_equal 1, result.length
    assert_in_delta 0.75, result[0].value
    assert_equal 'cup', result[0].unit
  end
end

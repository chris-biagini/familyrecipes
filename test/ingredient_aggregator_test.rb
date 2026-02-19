require_relative 'test_helper'

class IngredientAggregatorTest < Minitest::Test
  def test_sums_same_unit
    ingredients = [
      Ingredient.new(name: "Butter", quantity: "60 g"),
      Ingredient.new(name: "Butter", quantity: "140 g")
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    assert_equal 1, result.length
    assert_equal 200.0, result[0][0]
    assert_equal "g", result[0][1]
  end

  def test_keeps_different_units_separate
    ingredients = [
      Ingredient.new(name: "Butter", quantity: "200 g"),
      Ingredient.new(name: "Butter", quantity: "3 Tbsp")
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    assert_equal 2, result.length
    units = result.map { |a| a[1] }.sort
    assert_includes units, "g"
    assert_includes units, "tbsp"
  end

  def test_mixed_quantified_and_unquantified
    ingredients = [
      Ingredient.new(name: "Oil", quantity: "50 g"),
      Ingredient.new(name: "Oil")
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    numeric = result.find { |a| a.is_a?(Array) }
    assert_equal [50.0, "g"], numeric
    assert_includes result, nil
  end

  def test_all_unquantified
    ingredients = [
      Ingredient.new(name: "Salt")
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    assert_equal [nil], result
  end

  def test_unitless_numeric_sums
    ingredients = [
      Ingredient.new(name: "Egg", quantity: "2"),
      Ingredient.new(name: "Egg", quantity: "1")
    ]
    result = IngredientAggregator.aggregate_amounts(ingredients)
    assert_equal 1, result.length
    assert_equal 3.0, result[0][0]
    assert_nil result[0][1]
  end
end

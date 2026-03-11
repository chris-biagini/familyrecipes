# frozen_string_literal: true

require_relative 'test_helper'

class IngredientTest < Minitest::Test
  # Quantity parsing tests
  def test_quantity_value_simple_number
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '250 g')

    assert_equal '250', ingredient.quantity_value
  end

  def test_quantity_value_decimal
    ingredient = FamilyRecipes::Ingredient.new(name: 'Salt', quantity: '3.5 g')

    assert_equal '3.5', ingredient.quantity_value
  end

  def test_quantity_value_fraction_half
    ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '1/2 cup')

    assert_equal '0.5', ingredient.quantity_value
  end

  def test_quantity_value_fraction_quarter
    ingredient = FamilyRecipes::Ingredient.new(name: 'Oil', quantity: '1/4 cup')

    assert_equal '0.25', ingredient.quantity_value
  end

  def test_quantity_value_range_takes_high_end
    ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '2-3')

    assert_equal '3', ingredient.quantity_value
  end

  def test_quantity_value_nil_when_no_quantity
    ingredient = FamilyRecipes::Ingredient.new(name: 'Salt')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_value_nil_when_empty_quantity
    ingredient = FamilyRecipes::Ingredient.new(name: 'Salt', quantity: '  ')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_unit
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '250 g')

    assert_equal 'g', ingredient.quantity_unit
  end

  def test_quantity_unit_nil_when_no_unit
    ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '4')

    assert_nil ingredient.quantity_unit
  end

  # Fraction tests - 1/3, 2/3, 3/4
  def test_quantity_value_fraction_third
    ingredient = FamilyRecipes::Ingredient.new(name: 'Cream', quantity: '1/3 cup')

    assert_equal (1.0 / 3).to_s, ingredient.quantity_value
  end

  def test_quantity_value_fraction_two_thirds
    ingredient = FamilyRecipes::Ingredient.new(name: 'Cream', quantity: '2/3 cup')

    assert_equal (2.0 / 3).to_s, ingredient.quantity_value
  end

  def test_quantity_value_fraction_three_quarters
    ingredient = FamilyRecipes::Ingredient.new(name: 'Cream', quantity: '3/4 cup')

    assert_equal '0.75', ingredient.quantity_value
  end

  def test_quantity_value_vulgar_half
    ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '½ cup')

    assert_equal '0.5', ingredient.quantity_value
  end

  def test_quantity_value_vulgar_quarter
    ingredient = FamilyRecipes::Ingredient.new(name: 'Oil', quantity: '¼ cup')

    assert_equal '0.25', ingredient.quantity_value
  end

  def test_quantity_value_mixed_vulgar
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '2½ cups')

    assert_equal '2.5', ingredient.quantity_value
  end

  # Representative integration tests for unit normalization
  # (Inflector.normalize_unit is exhaustively tested in inflector_test.rb)
  def test_quantity_unit_downcases
    ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '2 Tbsp')

    assert_equal 'tbsp', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_tablespoon
    ingredient = FamilyRecipes::Ingredient.new(name: 'Oil', quantity: '2 tablespoons')

    assert_equal 'tbsp', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_cups
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '2 cups')

    assert_equal 'cup', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_small_slices
    ingredient = FamilyRecipes::Ingredient.new(name: 'Bread', quantity: '8 small slices')

    assert_equal 'slice', ingredient.quantity_unit
  end

  # Mixed ASCII fraction tests (e.g., "1 1/2 cups")
  def test_quantity_value_mixed_ascii
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

    assert_equal '1.5', ingredient.quantity_value
  end

  def test_quantity_unit_mixed_ascii
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

    assert_equal 'cup', ingredient.quantity_unit
  end

  def test_quantity_value_mixed_ascii_three_quarters
    ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '2 3/4 tbsp')

    assert_equal '2.75', ingredient.quantity_value
  end

  def test_quantity_value_mixed_ascii_no_unit
    ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

    assert_equal '1.5', ingredient.quantity_value
  end

  def test_quantity_unit_mixed_ascii_no_unit
    ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

    assert_nil ingredient.quantity_unit
  end

  # Non-numeric quantity tests
  def test_split_quantity_non_numeric_keeps_whole_string
    assert_equal ['a few leaves', nil], FamilyRecipes::Ingredient.split_quantity('a few leaves')
  end

  def test_split_quantity_freeform_single_word
    assert_equal ['some', nil], FamilyRecipes::Ingredient.split_quantity('some')
  end

  def test_split_quantity_freeform_handful
    assert_equal ['a handful', nil], FamilyRecipes::Ingredient.split_quantity('a handful')
  end

  def test_quantity_value_nil_for_freeform_text
    ingredient = FamilyRecipes::Ingredient.new(name: 'Basil', quantity: 'a few leaves')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_value_nil_for_single_word_freeform
    ingredient = FamilyRecipes::Ingredient.new(name: 'Parsley', quantity: 'some')

    assert_nil ingredient.quantity_value
  end

  # Normalized name tests
  def test_normalized_name_returns_name
    ingredient = FamilyRecipes::Ingredient.new(name: 'Flour')

    assert_equal 'Flour', ingredient.normalized_name
  end
end

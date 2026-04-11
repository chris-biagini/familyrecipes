# frozen_string_literal: true

require_relative 'test_helper'

class IngredientTest < Minitest::Test
  # Quantity parsing tests
  def test_quantity_value_simple_number
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '250 g')

    assert_equal '250', ingredient.quantity_value
  end

  def test_quantity_value_decimal
    ingredient = Mirepoix::Ingredient.new(name: 'Salt', quantity: '3.5 g')

    assert_equal '3.5', ingredient.quantity_value
  end

  def test_quantity_value_fraction_half
    ingredient = Mirepoix::Ingredient.new(name: 'Butter', quantity: '1/2 cup')

    assert_equal '0.5', ingredient.quantity_value
  end

  def test_quantity_value_fraction_quarter
    ingredient = Mirepoix::Ingredient.new(name: 'Oil', quantity: '1/4 cup')

    assert_equal '0.25', ingredient.quantity_value
  end

  def test_quantity_value_range_takes_high_end
    ingredient = Mirepoix::Ingredient.new(name: 'Eggs', quantity: '2-3')

    assert_equal '3', ingredient.quantity_value
  end

  def test_quantity_value_nil_when_no_quantity
    ingredient = Mirepoix::Ingredient.new(name: 'Salt')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_value_nil_when_empty_quantity
    ingredient = Mirepoix::Ingredient.new(name: 'Salt', quantity: '  ')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_unit
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '250 g')

    assert_equal 'g', ingredient.quantity_unit
  end

  def test_quantity_unit_nil_when_no_unit
    ingredient = Mirepoix::Ingredient.new(name: 'Eggs', quantity: '4')

    assert_nil ingredient.quantity_unit
  end

  # Fraction tests - 1/3, 2/3, 3/4
  def test_quantity_value_fraction_third
    ingredient = Mirepoix::Ingredient.new(name: 'Cream', quantity: '1/3 cup')

    assert_equal (1.0 / 3).to_s, ingredient.quantity_value
  end

  def test_quantity_value_fraction_two_thirds
    ingredient = Mirepoix::Ingredient.new(name: 'Cream', quantity: '2/3 cup')

    assert_equal (2.0 / 3).to_s, ingredient.quantity_value
  end

  def test_quantity_value_fraction_three_quarters
    ingredient = Mirepoix::Ingredient.new(name: 'Cream', quantity: '3/4 cup')

    assert_equal '0.75', ingredient.quantity_value
  end

  def test_quantity_value_vulgar_half
    ingredient = Mirepoix::Ingredient.new(name: 'Butter', quantity: '½ cup')

    assert_equal '0.5', ingredient.quantity_value
  end

  def test_quantity_value_vulgar_quarter
    ingredient = Mirepoix::Ingredient.new(name: 'Oil', quantity: '¼ cup')

    assert_equal '0.25', ingredient.quantity_value
  end

  def test_quantity_value_mixed_vulgar
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '2½ cups')

    assert_equal '2.5', ingredient.quantity_value
  end

  # Representative integration tests for unit normalization
  # (Inflector.normalize_unit is exhaustively tested in inflector_test.rb)
  def test_quantity_unit_downcases
    ingredient = Mirepoix::Ingredient.new(name: 'Butter', quantity: '2 Tbsp')

    assert_equal 'tbsp', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_tablespoon
    ingredient = Mirepoix::Ingredient.new(name: 'Oil', quantity: '2 tablespoons')

    assert_equal 'tbsp', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_cups
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '2 cups')

    assert_equal 'cup', ingredient.quantity_unit
  end

  def test_quantity_unit_normalizes_small_slices
    ingredient = Mirepoix::Ingredient.new(name: 'Bread', quantity: '8 small slices')

    assert_equal 'slice', ingredient.quantity_unit
  end

  # Mixed ASCII fraction tests (e.g., "1 1/2 cups")
  def test_quantity_value_mixed_ascii
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

    assert_equal '1.5', ingredient.quantity_value
  end

  def test_quantity_unit_mixed_ascii
    ingredient = Mirepoix::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

    assert_equal 'cup', ingredient.quantity_unit
  end

  def test_quantity_value_mixed_ascii_three_quarters
    ingredient = Mirepoix::Ingredient.new(name: 'Butter', quantity: '2 3/4 tbsp')

    assert_equal '2.75', ingredient.quantity_value
  end

  def test_quantity_value_mixed_ascii_no_unit
    ingredient = Mirepoix::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

    assert_equal '1.5', ingredient.quantity_value
  end

  def test_quantity_unit_mixed_ascii_no_unit
    ingredient = Mirepoix::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

    assert_nil ingredient.quantity_unit
  end

  # Non-numeric quantity tests
  def test_split_quantity_non_numeric_keeps_whole_string
    assert_equal ['a few leaves', nil], Mirepoix::Ingredient.split_quantity('a few leaves')
  end

  def test_split_quantity_freeform_single_word
    assert_equal ['some', nil], Mirepoix::Ingredient.split_quantity('some')
  end

  def test_split_quantity_freeform_handful
    assert_equal ['a handful', nil], Mirepoix::Ingredient.split_quantity('a handful')
  end

  def test_quantity_value_nil_for_freeform_text
    ingredient = Mirepoix::Ingredient.new(name: 'Basil', quantity: 'a few leaves')

    assert_nil ingredient.quantity_value
  end

  def test_quantity_value_nil_for_single_word_freeform
    ingredient = Mirepoix::Ingredient.new(name: 'Parsley', quantity: 'some')

    assert_nil ingredient.quantity_value
  end

  # normalize_quantity tests

  def test_normalize_quantity_vulgar_half
    assert_equal '1/2 cup', Mirepoix::Ingredient.normalize_quantity('½ cup')
  end

  def test_normalize_quantity_vulgar_quarter
    assert_equal '1/4 cup', Mirepoix::Ingredient.normalize_quantity('¼ cup')
  end

  def test_normalize_quantity_mixed_vulgar
    assert_equal '2 1/2 cups', Mirepoix::Ingredient.normalize_quantity('2½ cups')
  end

  def test_normalize_quantity_en_dash_to_hyphen
    assert_equal '2-3 cups', Mirepoix::Ingredient.normalize_quantity('2–3 cups')
  end

  def test_normalize_quantity_vulgar_and_en_dash
    assert_equal '1/2-1 sticks', Mirepoix::Ingredient.normalize_quantity('½–1 sticks')
  end

  def test_normalize_quantity_already_ascii
    assert_equal '2-3 cups', Mirepoix::Ingredient.normalize_quantity('2-3 cups')
  end

  def test_normalize_quantity_em_dash_to_hyphen
    assert_equal '2-3 cups', Mirepoix::Ingredient.normalize_quantity("2\u20143 cups")
  end

  def test_parse_range_em_dash
    assert_equal [2.0, 3.0], Mirepoix::Ingredient.parse_range("2\u20143")
  end

  def test_numeric_value_em_dash_range
    ingredient = Mirepoix::Ingredient.new(name: 'Eggs', quantity: "2\u20143")

    assert_equal '3', ingredient.quantity_value
  end

  def test_normalize_quantity_nil
    assert_nil Mirepoix::Ingredient.normalize_quantity(nil)
  end

  def test_normalize_quantity_blank
    assert_nil Mirepoix::Ingredient.normalize_quantity('  ')
  end

  def test_normalize_quantity_freeform
    assert_equal 'a pinch', Mirepoix::Ingredient.normalize_quantity('a pinch')
  end

  # parse_range tests

  def test_parse_range_simple
    assert_equal [2.0, 3.0], Mirepoix::Ingredient.parse_range('2-3')
  end

  def test_parse_range_fractions
    low, high = Mirepoix::Ingredient.parse_range('1/2-1')

    assert_in_delta 0.5, low
    assert_in_delta 1.0, high
  end

  def test_parse_range_single_value
    assert_equal [2.0, nil], Mirepoix::Ingredient.parse_range('2')
  end

  def test_parse_range_single_fraction
    low, high = Mirepoix::Ingredient.parse_range('1/2')

    assert_in_delta 0.5, low
    assert_nil high
  end

  def test_parse_range_low_greater_than_high
    assert_equal [nil, nil], Mirepoix::Ingredient.parse_range('1-1/2')
  end

  def test_parse_range_nil
    assert_equal [nil, nil], Mirepoix::Ingredient.parse_range(nil)
  end

  def test_parse_range_blank
    assert_equal [nil, nil], Mirepoix::Ingredient.parse_range('  ')
  end

  def test_parse_range_non_numeric
    assert_equal [nil, nil], Mirepoix::Ingredient.parse_range('a pinch')
  end

  def test_parse_range_equal_endpoints
    assert_equal [2.0, nil], Mirepoix::Ingredient.parse_range('2-2')
  end

  def test_parse_range_mixed_number_high
    low, high = Mirepoix::Ingredient.parse_range('3/4-1 1/2')

    assert_in_delta 0.75, low
    assert_in_delta 1.5, high
  end
end

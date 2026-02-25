# frozen_string_literal: true

require_relative 'test_helper'

class NumericParsingTest < Minitest::Test
  def test_integer
    assert_in_delta 3.0, FamilyRecipes::NumericParsing.parse_fraction('3')
  end

  def test_decimal
    assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1.5')
  end

  def test_fraction
    assert_in_delta 0.5, FamilyRecipes::NumericParsing.parse_fraction('1/2'), 0.001
  end

  def test_fraction_with_decimal_numerator
    assert_in_delta 0.75, FamilyRecipes::NumericParsing.parse_fraction('1.5/2'), 0.001
  end

  def test_zero
    assert_in_delta 0.0, FamilyRecipes::NumericParsing.parse_fraction('0')
  end

  def test_nil_returns_nil
    assert_nil FamilyRecipes::NumericParsing.parse_fraction(nil)
  end

  def test_strips_whitespace
    assert_in_delta 3.0, FamilyRecipes::NumericParsing.parse_fraction('  3  ')
  end

  def test_division_by_zero_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('1/0') }
  end

  def test_garbage_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('abc') }
  end

  def test_empty_string_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('') }
  end
end

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

  def test_vulgar_half
    assert_in_delta 0.5, FamilyRecipes::NumericParsing.parse_fraction('½'), 0.001
  end

  def test_vulgar_third
    assert_in_delta 0.333, FamilyRecipes::NumericParsing.parse_fraction('⅓'), 0.001
  end

  def test_vulgar_two_thirds
    assert_in_delta 0.667, FamilyRecipes::NumericParsing.parse_fraction('⅔'), 0.001
  end

  def test_vulgar_quarter
    assert_in_delta 0.25, FamilyRecipes::NumericParsing.parse_fraction('¼'), 0.001
  end

  def test_vulgar_three_quarters
    assert_in_delta 0.75, FamilyRecipes::NumericParsing.parse_fraction('¾'), 0.001
  end

  def test_vulgar_eighth
    assert_in_delta 0.125, FamilyRecipes::NumericParsing.parse_fraction('⅛'), 0.001
  end

  def test_mixed_vulgar
    assert_in_delta 2.5, FamilyRecipes::NumericParsing.parse_fraction('2½'), 0.001
  end

  def test_mixed_vulgar_with_space
    assert_in_delta 1.25, FamilyRecipes::NumericParsing.parse_fraction('1 ¼'), 0.001
  end

  def test_mixed_ascii_fraction
    assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1 1/2'), 0.001
  end

  def test_mixed_ascii_fraction_three_quarters
    assert_in_delta 2.75, FamilyRecipes::NumericParsing.parse_fraction('2 3/4'), 0.001
  end

  def test_mixed_ascii_fraction_third
    assert_in_delta 1.333, FamilyRecipes::NumericParsing.parse_fraction('1 1/3'), 0.001
  end

  def test_mixed_ascii_fraction_with_extra_spaces
    assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1  1/2'), 0.001
  end
end

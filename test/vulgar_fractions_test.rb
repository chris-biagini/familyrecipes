# frozen_string_literal: true

require_relative 'test_helper'

class VulgarFractionsTest < Minitest::Test
  # --- format ---

  def test_integer_formats_as_integer
    assert_equal '6', FamilyRecipes::VulgarFractions.format(6.0)
  end

  def test_one_formats_as_integer
    assert_equal '1', FamilyRecipes::VulgarFractions.format(1.0)
  end

  def test_zero_formats_as_integer
    assert_equal '0', FamilyRecipes::VulgarFractions.format(0.0)
  end

  def test_half_formats_as_vulgar
    assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5)
  end

  def test_third_formats_as_vulgar
    assert_equal "\u2153", FamilyRecipes::VulgarFractions.format(1.0 / 3)
  end

  def test_two_thirds_formats_as_vulgar
    assert_equal "\u2154", FamilyRecipes::VulgarFractions.format(2.0 / 3)
  end

  def test_quarter_formats_as_vulgar
    assert_equal "\u00BC", FamilyRecipes::VulgarFractions.format(0.25)
  end

  def test_three_quarters_formats_as_vulgar
    assert_equal "\u00BE", FamilyRecipes::VulgarFractions.format(0.75)
  end

  def test_eighth_formats_as_vulgar
    assert_equal "\u215B", FamilyRecipes::VulgarFractions.format(0.125)
  end

  def test_three_eighths_formats_as_vulgar
    assert_equal "\u215C", FamilyRecipes::VulgarFractions.format(0.375)
  end

  def test_five_eighths_formats_as_vulgar
    assert_equal "\u215D", FamilyRecipes::VulgarFractions.format(0.625)
  end

  def test_seven_eighths_formats_as_vulgar
    assert_equal "\u215E", FamilyRecipes::VulgarFractions.format(0.875)
  end

  def test_mixed_number_with_half
    assert_equal "1\u00BD", FamilyRecipes::VulgarFractions.format(1.5)
  end

  def test_mixed_number_with_third
    assert_equal "1\u2153", FamilyRecipes::VulgarFractions.format(4.0 / 3)
  end

  def test_mixed_number_with_quarter
    assert_equal "2\u00BC", FamilyRecipes::VulgarFractions.format(2.25)
  end

  def test_non_matching_decimal_formats_as_decimal
    assert_equal '0.4', FamilyRecipes::VulgarFractions.format(0.4)
  end

  def test_non_matching_mixed_formats_as_decimal
    assert_equal '1.4', FamilyRecipes::VulgarFractions.format(1.4)
  end

  def test_large_integer
    assert_equal '24', FamilyRecipes::VulgarFractions.format(24.0)
  end

  # --- singular_noun? ---

  def test_singular_for_exactly_one
    assert FamilyRecipes::VulgarFractions.singular_noun?(1.0)
  end

  def test_singular_for_pure_vulgar_fraction
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.5)
  end

  def test_singular_for_quarter
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.25)
  end

  def test_singular_for_third
    assert FamilyRecipes::VulgarFractions.singular_noun?(1.0 / 3)
  end

  def test_singular_for_eighth
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.125)
  end

  def test_plural_for_mixed_number
    refute FamilyRecipes::VulgarFractions.singular_noun?(1.5)
  end

  def test_plural_for_integer_greater_than_one
    refute FamilyRecipes::VulgarFractions.singular_noun?(6.0)
  end

  def test_plural_for_zero
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.0)
  end

  def test_plural_for_non_matching_decimal
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.4)
  end

  def test_plural_for_non_matching_decimal_less_than_one
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.7)
  end
end

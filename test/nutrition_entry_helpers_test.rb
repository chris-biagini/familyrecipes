# frozen_string_literal: true

require_relative 'test_helper'

class NutritionEntryHelpersTest < Minitest::Test
  Helpers = FamilyRecipes::NutritionEntryHelpers

  # --- parse_serving_size ---

  def test_parse_serving_size_simple_grams
    result = Helpers.parse_serving_size('30g')

    assert_in_delta(30.0, result[:grams])
  end

  def test_parse_serving_size_grams_spelled_out
    result = Helpers.parse_serving_size('30 grams')

    assert_in_delta(30.0, result[:grams])
  end

  def test_parse_serving_size_gram_singular
    result = Helpers.parse_serving_size('30 gram')

    assert_in_delta(30.0, result[:grams])
  end

  def test_parse_serving_size_decimal_grams
    result = Helpers.parse_serving_size('0.5g')

    assert_in_delta(0.5, result[:grams])
  end

  def test_parse_serving_size_volume_with_grams
    result = Helpers.parse_serving_size('1/4 cup (30g)')

    assert_in_delta(30.0, result[:grams])
    assert_in_delta(0.25, result[:volume_amount])
    assert_equal 'cup', result[:volume_unit]
  end

  def test_parse_serving_size_discrete_with_grams
    result = Helpers.parse_serving_size('about 14 crackers (30g)')

    assert_in_delta(30.0, result[:grams])
    assert_equal 'cracker', result[:auto_portion][:unit]
    assert_in_delta 2.14, result[:auto_portion][:grams], 0.01
  end

  def test_parse_serving_size_about_prefix
    result = Helpers.parse_serving_size('About 3 pieces (45g)')

    assert_in_delta(45.0, result[:grams])
    assert_equal 'piece', result[:auto_portion][:unit]
    assert_in_delta 15.0, result[:auto_portion][:grams], 0.01
  end

  def test_parse_serving_size_size_modifier
    result = Helpers.parse_serving_size('1 3.5 inch piece (28g)')

    assert_in_delta(28.0, result[:grams])
    assert_equal 'piece', result[:auto_portion][:unit]
    assert_in_delta 28.0, result[:auto_portion][:grams], 0.01
  end

  def test_parse_serving_size_no_gram_weight
    result = Helpers.parse_serving_size('1/4 cup')

    assert_nil result
  end

  def test_parse_serving_size_zero_grams
    result = Helpers.parse_serving_size('0g')

    assert_nil result
  end

  # --- parse_fraction ---

  def test_parse_fraction_simple_integer
    assert_in_delta(3.0, Helpers.parse_fraction('3'))
  end

  def test_parse_fraction_decimal
    assert_in_delta(1.5, Helpers.parse_fraction('1.5'))
  end

  def test_parse_fraction_fraction
    assert_in_delta 0.5, Helpers.parse_fraction('1/2'), 0.001
  end

  def test_parse_fraction_zero
    assert_in_delta(0.0, Helpers.parse_fraction('0'))
  end

  def test_parse_fraction_division_by_zero
    assert_nil Helpers.parse_fraction('/0')
  end

  def test_parse_fraction_garbage
    assert_nil Helpers.parse_fraction('abc')
  end
end

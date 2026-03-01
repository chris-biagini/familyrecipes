# frozen_string_literal: true

require_relative 'test_helper'

class CrossReferenceParserTest < Minitest::Test
  def test_parses_simple_reference
    result = CrossReferenceParser.parse('@[Pizza Dough]')

    assert_equal 'Pizza Dough', result[:target_title]
    assert_in_delta 1.0, result[:multiplier]
    assert_nil result[:prep_note]
  end

  def test_parses_integer_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 2')

    assert_in_delta 2.0, result[:multiplier]
  end

  def test_parses_fraction_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 1/2')

    assert_in_delta 0.5, result[:multiplier]
  end

  def test_parses_decimal_multiplier
    result = CrossReferenceParser.parse('@[Pizza Dough], 0.5')

    assert_in_delta 0.5, result[:multiplier]
  end

  def test_parses_multiplier_and_prep_note
    result = CrossReferenceParser.parse('@[Pizza Dough], 2: Let rest 30 min.')

    assert_in_delta 2.0, result[:multiplier]
    assert_equal 'Let rest 30 min.', result[:prep_note]
  end

  def test_parses_trailing_period
    result = CrossReferenceParser.parse('@[Pizza Dough].')

    assert_equal 'Pizza Dough', result[:target_title]
  end

  def test_raises_on_missing_reference_syntax
    error = assert_raises(RuntimeError) { CrossReferenceParser.parse('Pizza Dough') }

    assert_match(/Invalid cross-reference/, error.message)
  end

  def test_raises_on_old_quantity_first_syntax
    error = assert_raises(RuntimeError) { CrossReferenceParser.parse('2 @[Pizza Dough]') }

    assert_match(/quantity/, error.message)
  end
end

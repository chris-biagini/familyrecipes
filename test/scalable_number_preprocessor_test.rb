# frozen_string_literal: true

require_relative 'test_helper'

class ScalableNumberPreprocessorTest < Minitest::Test
  # --- process_instructions tests ---

  def test_word_number_replacement
    result = ScalableNumberPreprocessor.process_instructions('Use two* sheet pans.')

    assert_includes result, 'data-base-value="2"'
    assert_includes result, 'data-original-text="two"'
    assert_includes result, '>two</span>'
    refute_includes result, 'two*'
  end

  def test_capitalized_word_number
    result = ScalableNumberPreprocessor.process_instructions('Three* eggs.')

    assert_includes result, 'data-base-value="3"'
    assert_includes result, 'data-original-text="Three"'
  end

  def test_numeral_replacement
    result = ScalableNumberPreprocessor.process_instructions('Add 15* grams.')

    assert_includes result, 'data-base-value="15.0"'
    assert_includes result, 'data-original-text="15"'
    refute_includes result, '15*'
  end

  def test_fraction_replacement
    result = ScalableNumberPreprocessor.process_instructions('Use 1/2* cup.')

    assert_includes result, 'data-base-value="0.5"'
    assert_includes result, 'data-original-text="1/2"'
  end

  def test_decimal_replacement
    result = ScalableNumberPreprocessor.process_instructions('Add 1.5* cups.')

    assert_includes result, 'data-base-value="1.5"'
    assert_includes result, 'data-original-text="1.5"'
  end

  def test_multiple_markers_in_same_text
    result = ScalableNumberPreprocessor.process_instructions('Use two* pans and three* bowls.')

    assert_includes result, 'data-base-value="2"'
    assert_includes result, 'data-base-value="3"'
  end

  def test_unmarked_numbers_left_alone
    result = ScalableNumberPreprocessor.process_instructions('Bake at 400 for 25 minutes.')

    refute_includes result, 'scalable'
    assert_equal 'Bake at 400 for 25 minutes.', result
  end

  def test_word_number_twelve
    result = ScalableNumberPreprocessor.process_instructions('Divide into twelve* portions.')

    assert_includes result, 'data-base-value="12"'
    assert_includes result, 'data-original-text="twelve"'
    assert_includes result, '>twelve</span>'
    refute_includes result, 'twelve*'
  end

  def test_unmarked_words_left_alone
    result = ScalableNumberPreprocessor.process_instructions('Let it cool for one hour.')

    refute_includes result, 'scalable'
    assert_equal 'Let it cool for one hour.', result
  end

  # --- process_yield_line tests ---

  def test_yield_line_wraps_first_numeral
    result = ScalableNumberPreprocessor.process_yield_line('Makes 30 gougères.')

    assert_includes result, 'data-base-value="30.0"'
    assert_includes result, 'data-original-text="30"'
    assert_includes result, '>30</span>'
  end

  def test_yield_line_wraps_first_word_number
    result = ScalableNumberPreprocessor.process_yield_line('Serves four.')

    assert_includes result, 'data-base-value="4"'
    assert_includes result, 'data-original-text="four"'
  end

  def test_yield_line_only_wraps_first_number
    result = ScalableNumberPreprocessor.process_yield_line('Makes 30 in 2 batches.')
    # First number (30) should be wrapped
    assert_includes result, 'data-base-value="30.0"'
    # Second number (2) should NOT be wrapped
    assert_includes result, ' 2 batches.'
    # Only one scalable span
    assert_equal 1, result.scan('scalable').length
  end

  def test_yield_line_with_no_number
    result = ScalableNumberPreprocessor.process_yield_line('Makes a bunch.')

    refute_includes result, 'scalable'
    assert_equal 'Makes a bunch.', result
  end

  def test_yield_line_empty_string
    result = ScalableNumberPreprocessor.process_yield_line('')

    assert_equal '', result
  end

  # --- process_yield_with_unit tests ---

  def test_yield_with_unit_wraps_number_and_noun
    result = ScalableNumberPreprocessor.process_yield_with_unit('12 pancakes', 'pancake', 'pancakes')

    assert_includes result, 'class="yield"'
    assert_includes result, 'data-base-value="12.0"'
    assert_includes result, 'data-unit-singular="pancake"'
    assert_includes result, 'data-unit-plural="pancakes"'
    assert_includes result, '<span class="scalable"'
    assert_includes result, '>12</span> pancakes'
  end

  def test_yield_with_unit_handles_word_numbers
    result = ScalableNumberPreprocessor.process_yield_with_unit('two loaves', 'loaf', 'loaves')

    assert_includes result, 'data-base-value="2"'
    assert_includes result, 'data-unit-singular="loaf"'
    assert_includes result, 'data-unit-plural="loaves"'
    assert_includes result, '>two</span> loaves'
  end

  def test_yield_with_unit_handles_single_item
    result = ScalableNumberPreprocessor.process_yield_with_unit('1 loaf', 'loaf', 'loaves')

    assert_includes result, 'data-base-value="1.0"'
    assert_includes result, '>1</span> loaf'
  end
end

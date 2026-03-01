# frozen_string_literal: true

require_relative 'test_helper'

class IngredientParserTest < Minitest::Test
  def test_parses_name_only
    result = IngredientParser.parse('Salt')

    assert_equal 'Salt', result[:name]
    assert_nil result[:quantity]
    assert_nil result[:prep_note]
  end

  def test_parses_name_and_quantity
    result = IngredientParser.parse('Flour, 250 g')

    assert_equal 'Flour', result[:name]
    assert_equal '250 g', result[:quantity]
    assert_nil result[:prep_note]
  end

  def test_parses_full_ingredient
    result = IngredientParser.parse('Walnuts, 75 g: Roughly chop.')

    assert_equal 'Walnuts', result[:name]
    assert_equal '75 g', result[:quantity]
    assert_equal 'Roughly chop.', result[:prep_note]
  end

  def test_parses_name_and_prep_note_without_quantity
    result = IngredientParser.parse('Garlic: Minced')

    assert_equal 'Garlic', result[:name]
    assert_nil result[:quantity]
    assert_equal 'Minced', result[:prep_note]
  end

  def test_handles_quantity_with_unit
    result = IngredientParser.parse('Butter, 2 tablespoons')

    assert_equal 'Butter', result[:name]
    assert_equal '2 tablespoons', result[:quantity]
  end

  def test_handles_numeric_quantity
    result = IngredientParser.parse('Eggs, 4')

    assert_equal 'Eggs', result[:name]
    assert_equal '4', result[:quantity]
  end

  def test_handles_parenthetical_name
    result = IngredientParser.parse('Sugar (brown), 150 g')

    assert_equal 'Sugar (brown)', result[:name]
    assert_equal '150 g', result[:quantity]
  end

  def test_handles_colon_in_prep_note
    result = IngredientParser.parse('Chocolate, 250 g: Use chips or bar: your choice.')

    assert_equal 'Chocolate', result[:name]
    assert_equal '250 g', result[:quantity]
    assert_equal 'Use chips or bar: your choice.', result[:prep_note]
  end

  def test_strips_whitespace
    result = IngredientParser.parse('  Flour  ,  250 g  :  Sifted  ')

    assert_equal 'Flour', result[:name]
    assert_equal '250 g', result[:quantity]
    assert_equal 'Sifted', result[:prep_note]
  end

  def test_handles_empty_quantity
    result = IngredientParser.parse('Salt, : to taste')

    assert_equal 'Salt', result[:name]
    assert_nil result[:quantity]
    assert_equal 'to taste', result[:prep_note]
  end

  def test_raises_on_cross_reference_syntax
    error = assert_raises(RuntimeError) { IngredientParser.parse('@[Pizza Dough]') }

    assert_match(/>>> syntax/, error.message)
  end
end

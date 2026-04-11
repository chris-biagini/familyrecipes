# frozen_string_literal: true

require_relative 'test_helper'

class MirepoixTest < Minitest::Test
  def test_slugify_simple_word
    assert_equal 'cookies', Mirepoix.slugify('Cookies')
  end

  def test_slugify_multiple_words
    assert_equal 'chocolate-chip-cookies', Mirepoix.slugify('Chocolate Chip Cookies')
  end

  def test_slugify_removes_special_characters
    assert_equal 'mac--cheese', Mirepoix.slugify('Mac & Cheese')
  end

  def test_slugify_handles_accented_characters
    # NFKD normalization decomposes e into e + combining accent, accent is removed
    assert_equal 'sauteed-asparagus', Mirepoix.slugify('Sauteed Asparagus')
  end

  def test_slugify_removes_parentheses
    assert_equal 'sugar-brown', Mirepoix.slugify('Sugar (brown)')
  end

  def test_slugify_collapses_multiple_spaces
    assert_equal 'red-beans-and-rice', Mirepoix.slugify('Red  Beans   and   Rice')
  end

  def test_parse_quick_bites_content_new_format
    content = <<~TXT
      ## Snacks
      - Peanut Butter on Bread: Peanut butter, Bread
      - Goldfish

      ## Breakfast
      - Cereal with Milk: Cereal, Milk
    TXT

    result = Mirepoix.parse_quick_bites_content(content)

    assert_equal 3, result.quick_bites.size
    assert_equal 'Peanut Butter on Bread', result.quick_bites[0].title
    assert_equal ['Peanut butter', 'Bread'], result.quick_bites[0].ingredients
    assert_equal 'Quick Bites: Snacks', result.quick_bites[0].category
    assert_equal 'Goldfish', result.quick_bites[1].title
    assert_equal ['Goldfish'], result.quick_bites[1].ingredients
    assert_equal 'Quick Bites: Breakfast', result.quick_bites[2].category
    assert_empty result.warnings
  end

  def test_parse_quick_bites_warns_on_unrecognized_lines
    content = <<~TXT
      ## Snacks
      - Goldfish
      this line is garbage
      - Dried fruit
    TXT

    result = Mirepoix.parse_quick_bites_content(content)

    assert_equal 2, result.quick_bites.size
    assert_equal 1, result.warnings.size
    assert_match(/line 3/i, result.warnings.first)
  end

  def test_parse_quick_bites_ignores_blank_lines
    content = <<~TXT
      ## Snacks

      - Goldfish

    TXT

    result = Mirepoix.parse_quick_bites_content(content)

    assert_equal 1, result.quick_bites.size
    assert_empty result.warnings
  end

  def test_parse_quick_bites_handles_empty_content
    result = Mirepoix.parse_quick_bites_content('')

    assert_empty result.quick_bites
    assert_empty result.warnings
  end

  def test_parse_quick_bites_category_with_apostrophe
    content = "## Kids' Lunches\n- RXBARs\n"
    result = Mirepoix.parse_quick_bites_content(content)

    assert_equal "Quick Bites: Kids' Lunches", result.quick_bites.first.category
  end

  def test_normalize_for_comparison_curly_single_quotes
    assert_equal "Grandma's Cookies", Mirepoix.normalize_for_comparison("Grandma\u2019s Cookies")
  end

  def test_normalize_for_comparison_left_single_quote
    assert_equal "'quoted'", Mirepoix.normalize_for_comparison("\u2018quoted\u2019")
  end

  def test_normalize_for_comparison_curly_double_quotes
    assert_equal '"hello"', Mirepoix.normalize_for_comparison("\u201Chello\u201D")
  end

  def test_normalize_for_comparison_mixed
    assert_equal "Baker's \"Best\" Rolls", Mirepoix.normalize_for_comparison("Baker\u2019s \u201CBest\u201D Rolls")
  end

  def test_normalize_for_comparison_no_change
    assert_equal 'plain text', Mirepoix.normalize_for_comparison('plain text')
  end

  def test_normalize_for_comparison_nil
    assert_equal '', Mirepoix.normalize_for_comparison(nil)
  end
end

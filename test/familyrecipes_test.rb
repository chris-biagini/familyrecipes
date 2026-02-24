# frozen_string_literal: true

require_relative 'test_helper'

class FamilyRecipesTest < Minitest::Test
  def test_slugify_simple_word
    assert_equal 'cookies', FamilyRecipes.slugify('Cookies')
  end

  def test_slugify_multiple_words
    assert_equal 'chocolate-chip-cookies', FamilyRecipes.slugify('Chocolate Chip Cookies')
  end

  def test_slugify_removes_special_characters
    assert_equal 'mac--cheese', FamilyRecipes.slugify('Mac & Cheese')
  end

  def test_slugify_handles_accented_characters
    # NFKD normalization decomposes e into e + combining accent, accent is removed
    assert_equal 'sauteed-asparagus', FamilyRecipes.slugify('Sauteed Asparagus')
  end

  def test_slugify_removes_parentheses
    assert_equal 'sugar-brown', FamilyRecipes.slugify('Sugar (brown)')
  end

  def test_slugify_collapses_multiple_spaces
    assert_equal 'red-beans-and-rice', FamilyRecipes.slugify('Red  Beans   and   Rice')
  end

  def test_parse_quick_bites_content
    content = <<~MD
      # Quick Bites

      ## Snacks
        - Peanut Butter on Bread: Peanut butter, Bread
        - Goldfish

      ## Breakfast
        - Cereal with Milk: Cereal, Milk
    MD

    result = FamilyRecipes.parse_quick_bites_content(content)

    assert_equal 3, result.size
    assert_equal 'Peanut Butter on Bread', result[0].title
    assert_equal ['Peanut butter', 'Bread'], result[0].ingredients
    assert_equal 'Quick Bites: Snacks', result[0].category
    assert_equal 'Goldfish', result[1].title
    assert_equal ['Goldfish'], result[1].ingredients
    assert_equal 'Quick Bites: Breakfast', result[2].category
  end
end

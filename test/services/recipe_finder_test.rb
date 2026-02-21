# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative '../../config/environment'
require 'minitest/autorun'

class RecipeFinderTest < Minitest::Test
  def test_finds_recipe_by_slug
    recipe = RecipeFinder.find_by_slug('focaccia')

    assert recipe
    assert_equal 'focaccia', recipe.id
    assert_equal 'Focaccia', recipe.title
  end

  def test_returns_nil_for_unknown_slug
    assert_nil RecipeFinder.find_by_slug('nonexistent-recipe')
  end

  def test_extracts_category_from_front_matter
    recipe = RecipeFinder.find_by_slug('focaccia')

    assert_equal 'Bread', recipe.category
  end

  def test_ignores_quick_bites_file
    assert_nil RecipeFinder.find_by_slug('quick-bites')
  end
end

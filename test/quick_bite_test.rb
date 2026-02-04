require_relative 'test_helper'

class QuickBiteTest < Minitest::Test
  def test_parses_title_from_text
    qb = QuickBite.new(text_source: "PB&J: Peanut butter, jelly, bread", category: "Sandwiches")

    assert_equal "PB&J", qb.title
  end

  def test_parses_category
    qb = QuickBite.new(text_source: "Toast: Bread, butter", category: "Breakfast")

    assert_equal "Breakfast", qb.category
  end

  def test_generates_id_from_title
    qb = QuickBite.new(text_source: "Grilled Cheese: Bread, cheese, butter", category: "Sandwiches")

    assert_equal "grilled-cheese", qb.id
  end

  def test_parses_ingredients_separated_by_commas
    qb = QuickBite.new(text_source: "Salad: Lettuce, tomato, cucumber", category: "Sides")

    assert_includes qb.ingredients, "Lettuce"
    assert_includes qb.ingredients, "tomato"
    assert_includes qb.ingredients, "cucumber"
  end

  def test_parses_ingredients_separated_by_and
    qb = QuickBite.new(text_source: "PB&J: Peanut butter and jelly and bread", category: "Sandwiches")

    assert_includes qb.ingredients, "Peanut butter"
    assert_includes qb.ingredients, "jelly"
    assert_includes qb.ingredients, "bread"
  end

  def test_parses_ingredients_separated_by_with
    qb = QuickBite.new(text_source: "Toast: Bread with butter", category: "Breakfast")

    assert_includes qb.ingredients, "Bread"
    assert_includes qb.ingredients, "butter"
  end

  def test_parses_ingredients_separated_by_on
    qb = QuickBite.new(text_source: "Eggs: Fried egg on toast", category: "Breakfast")

    assert_includes qb.ingredients, "Fried egg"
    assert_includes qb.ingredients, "toast"
  end

  def test_handles_mixed_separators
    qb = QuickBite.new(text_source: "Combo: Apple and cheese with crackers, grapes", category: "Snacks")

    assert_includes qb.ingredients, "Apple"
    assert_includes qb.ingredients, "cheese"
    assert_includes qb.ingredients, "crackers"
    assert_includes qb.ingredients, "grapes"
  end

  def test_handles_no_colon
    qb = QuickBite.new(text_source: "Fresh Fruit", category: "Snacks")

    assert_equal "Fresh Fruit", qb.title
    assert_includes qb.ingredients, "Fresh Fruit"
  end

  def test_all_ingredient_names_returns_unique
    qb = QuickBite.new(text_source: "Duplicate: Apple, apple, Apple", category: "Snacks")

    # Due to case sensitivity, these are different strings
    # But verifies the uniq behavior
    assert_equal qb.ingredients.uniq, qb.all_ingredient_names
  end

  def test_strips_whitespace_from_ingredients
    qb = QuickBite.new(text_source: "Test:   Item One  ,  Item Two  ", category: "Test")

    assert_includes qb.ingredients, "Item One"
    assert_includes qb.ingredients, "Item Two"
  end

  def test_stores_text_source
    text = "Original: Some ingredients"
    qb = QuickBite.new(text_source: text, category: "Test")

    assert_equal text, qb.text_source
  end
end

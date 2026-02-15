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

  def test_does_not_split_on_and
    # "and" in ingredient names should not cause splitting
    qb = QuickBite.new(text_source: "Snack: Salt and Vinegar Chips", category: "Snacks")

    assert_equal 1, qb.ingredients.length
    assert_equal "Salt and Vinegar Chips", qb.ingredients[0]
  end

  def test_does_not_split_on_with
    # "with" in ingredient names should not cause splitting
    qb = QuickBite.new(text_source: "Crackers: Crackers with Everything Seasoning", category: "Snacks")

    assert_equal 1, qb.ingredients.length
    assert_equal "Crackers with Everything Seasoning", qb.ingredients[0]
  end

  def test_explicit_comma_separated_ingredients
    qb = QuickBite.new(text_source: "Hummus with Pretzels: Hummus, Pretzels", category: "Snacks")

    assert_equal "Hummus with Pretzels", qb.title
    assert_includes qb.ingredients, "Hummus"
    assert_includes qb.ingredients, "Pretzels"
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

  def test_ingredients_with_quantities_returns_nil_amounts
    qb = QuickBite.new(text_source: "PB&J: Peanut butter, Jelly, Bread", category: "Sandwiches")
    iwq = qb.ingredients_with_quantities

    assert_equal 3, iwq.length
    iwq.each do |name, amounts|
      assert_equal [nil], amounts, "#{name} should have [nil] amounts"
    end
  end

  def test_ingredients_with_quantities_names_match_all_ingredient_names
    qb = QuickBite.new(text_source: "Salad: Lettuce, Tomato", category: "Sides")
    iwq = qb.ingredients_with_quantities
    names = iwq.map { |name, _| name }

    assert_equal qb.all_ingredient_names, names
  end
end

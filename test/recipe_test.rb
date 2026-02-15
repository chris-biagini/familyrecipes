require_relative 'test_helper'

class RecipeTest < Minitest::Test
  def make_recipe(markdown)
    Recipe.new(markdown_source: markdown, id: "test-recipe", category: "Test")
  end

  def test_ingredients_with_quantities_sums_same_unit_across_steps
    markdown = <<~MD
      # Chocolate Chip Cookies

      ## Step 1 (mix sugar)

      - Butter, 60 g

      Mix.

      ## Step 2 (brown butter)

      - Butter, 140 g

      Brown.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    butter = iwq.find { |name, _| name == "Butter" }

    refute_nil butter
    amounts = butter[1]
    assert_equal 1, amounts.length
    assert_equal 200.0, amounts[0][0]
    assert_equal "g", amounts[0][1]
  end

  def test_ingredients_with_quantities_mixed_quantified_and_unquantified
    markdown = <<~MD
      # Test Recipe

      ## Step 1 (prep)

      - Olive oil, 50 g

      Drizzle.

      ## Step 2 (finish)

      - Olive oil

      Drizzle more.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    oil = iwq.find { |name, _| name == "Olive oil" }

    refute_nil oil
    amounts = oil[1]
    # Should have [50.0, "g"] and nil
    numeric = amounts.find { |a| a.is_a?(Array) }
    assert_equal [50.0, "g"], numeric
    assert_includes amounts, nil
  end

  def test_ingredients_with_quantities_different_units_kept_separate
    markdown = <<~MD
      # Test Recipe

      ## Step 1 (prep)

      - Butter, 200 g

      Melt.

      ## Step 2 (finish)

      - Butter, 3 Tbsp

      Add.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    butter = iwq.find { |name, _| name == "Butter" }

    refute_nil butter
    amounts = butter[1]
    assert_equal 2, amounts.length
    units = amounts.map { |a| a[1] }.sort
    assert_includes units, "g"
    assert_includes units, "Tbsp"
  end

  def test_ingredients_with_quantities_all_unquantified
    markdown = <<~MD
      # Test Recipe

      ## Step 1 (cook)

      - Salt

      Season.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    salt = iwq.find { |name, _| name == "Salt" }

    refute_nil salt
    assert_equal [nil], salt[1]
  end

  def test_ingredients_with_quantities_preserves_order
    markdown = <<~MD
      # Test Recipe

      ## Step 1 (prep)

      - Flour, 250 g
      - Butter, 100 g
      - Salt

      Mix.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    names = iwq.map { |name, _| name }

    assert_equal ["Flour", "Butter", "Salt"], names
  end

  def test_ingredients_with_quantities_unitless_numeric
    markdown = <<~MD
      # Test Recipe

      ## Step 1 (prep)

      - Egg, 2
      - Egg, 1

      Crack.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    egg = iwq.find { |name, _| name == "Egg" }

    refute_nil egg
    amounts = egg[1]
    assert_equal 1, amounts.length
    assert_equal 3.0, amounts[0][0]
    assert_nil amounts[0][1]
  end
end

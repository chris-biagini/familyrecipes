# frozen_string_literal: true

require_relative 'test_helper'

class RecipeTest < Minitest::Test
  def make_recipe(markdown)
    Recipe.new(markdown_source: markdown, id: 'test-recipe', category: 'Test')
  end

  def test_ingredients_with_quantities_sums_same_unit_across_steps
    markdown = <<~MD
      # Chocolate Chip Cookies

      Category: Test

      ## Step 1 (mix sugar)

      - Butter, 60 g

      Mix.

      ## Step 2 (brown butter)

      - Butter, 140 g

      Brown.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    butter = iwq.find { |name, _| name == 'Butter' }

    refute_nil butter
    amounts = butter[1]

    assert_equal 1, amounts.length
    assert_in_delta 200.0, amounts[0].value
    assert_equal 'g', amounts[0].unit
  end

  def test_ingredients_with_quantities_mixed_quantified_and_unquantified
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (prep)

      - Olive oil, 50 g

      Drizzle.

      ## Step 2 (finish)

      - Olive oil

      Drizzle more.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    oil = iwq.find { |name, _| name == 'Olive oil' }

    refute_nil oil
    amounts = oil[1]
    # Should have [50.0, "g"] and nil
    numeric = amounts.find { |a| a.is_a?(Quantity) }

    assert_equal Quantity[50.0, 'g'], numeric
    assert_includes amounts, nil
  end

  def test_ingredients_with_quantities_different_units_kept_separate
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (prep)

      - Butter, 200 g

      Melt.

      ## Step 2 (finish)

      - Butter, 3 Tbsp

      Add.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    butter = iwq.find { |name, _| name == 'Butter' }

    refute_nil butter
    amounts = butter[1]

    assert_equal 2, amounts.length
    units = amounts.map(&:unit).sort

    assert_includes units, 'g'
    assert_includes units, 'tbsp'
  end

  def test_ingredients_with_quantities_all_unquantified
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (cook)

      - Salt

      Season.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    salt = iwq.find { |name, _| name == 'Salt' }

    refute_nil salt
    assert_equal [nil], salt[1]
  end

  def test_ingredients_with_quantities_preserves_order
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (prep)

      - Flour, 250 g
      - Butter, 100 g
      - Salt

      Mix.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    names = iwq.map { |name, _| name }

    assert_equal %w[Flour Butter Salt], names
  end

  def test_ingredients_with_quantities_unitless_numeric
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (prep)

      - Egg, 2
      - Egg, 1

      Crack.
    MD

    recipe = make_recipe(markdown)
    iwq = recipe.ingredients_with_quantities
    egg = iwq.find { |name, _| name == 'Egg' }

    refute_nil egg
    amounts = egg[1]

    assert_equal 1, amounts.length
    assert_in_delta 3.0, amounts[0].value
    assert_nil amounts[0].unit
  end

  # --- Full recipe parsing ---

  def full_recipe_markdown
    <<~MD
      # Hard-Boiled Eggs

      Protein!

      Category: Test

      ## Make ice bath.

      - Water
      - Ice

      Make ice bath in large bowl.

      ## Cook eggs.

      - Eggs

      Fill steamer pot with water and bring to a boil.

      ---

      Based on a recipe from Serious Eats.
    MD
  end

  def test_parses_title
    recipe = make_recipe(full_recipe_markdown)

    assert_equal 'Hard-Boiled Eggs', recipe.title
  end

  def test_parses_description
    recipe = make_recipe(full_recipe_markdown)

    assert_equal 'Protein!', recipe.description
  end

  def test_parses_steps
    recipe = make_recipe(full_recipe_markdown)

    assert_equal 2, recipe.steps.size
    assert_equal 'Make ice bath.', recipe.steps[0].tldr
    assert_equal 'Cook eggs.', recipe.steps[1].tldr
  end

  def test_parses_step_ingredients
    recipe = make_recipe(full_recipe_markdown)
    names = recipe.steps[0].ingredients.map(&:name)

    assert_equal %w[Water Ice], names
  end

  def test_parses_footer
    recipe = make_recipe(full_recipe_markdown)

    assert_match(/Serious Eats/, recipe.footer)
  end

  def test_all_ingredients_deduplicates
    markdown = <<~MD
      # Test Recipe

      Category: Test

      ## Step 1 (prep)

      - Salt
      - Butter, 50 g

      Mix.

      ## Step 2 (finish)

      - Salt

      Season.
    MD

    recipe = make_recipe(markdown)
    names = recipe.all_ingredients.map(&:name)

    assert_equal %w[Salt Butter], names
  end

  def test_all_ingredient_names
    recipe = make_recipe(full_recipe_markdown)
    names = recipe.all_ingredient_names

    assert_includes names, 'Water'
    assert_includes names, 'Ice'
    assert_includes names, 'Eggs'
    assert_equal 3, names.size
  end

  def test_relative_url_returns_id
    recipe = make_recipe(full_recipe_markdown)

    assert_equal 'test-recipe', recipe.relative_url
  end

  def test_version_hash_is_deterministic
    recipe_a = make_recipe(full_recipe_markdown)
    recipe_b = make_recipe(full_recipe_markdown)

    assert_equal recipe_a.version_hash, recipe_b.version_hash
  end

  def test_version_hash_changes_when_source_changes
    recipe_a = make_recipe(full_recipe_markdown)
    recipe_b = make_recipe(full_recipe_markdown.sub('Protein!', 'Healthy!'))

    refute_equal recipe_a.version_hash, recipe_b.version_hash
  end

  def test_raises_on_recipe_with_no_steps
    assert_raises(StandardError) do
      make_recipe("# Title\n\nCategory: Test\n\nJust a description, no steps.\n")
    end
  end

  def test_all_ingredients_with_quantities_merges_overlapping_sub_recipe
    dough_md = <<~MD
      # Pizza Dough

      Category: Test

      ## Mix (make dough)

      - Flour, 500 g
      - Salt, 10 g

      Knead.
    MD

    pizza_md = <<~MD
      # Test Pizza

      Category: Test

      ## Prep (prep toppings)

      - Flour, 50 g: For dusting.

      Dust the counter.

      ## Dough (make dough)

      - @[Pizza Dough]

      Stretch.
    MD

    dough = Recipe.new(markdown_source: dough_md, id: 'pizza-dough', category: 'Test')
    pizza = Recipe.new(markdown_source: pizza_md, id: 'test-pizza', category: 'Test')
    recipe_map = { 'pizza-dough' => dough, 'test-pizza' => pizza }

    iwq = pizza.all_ingredients_with_quantities({}, recipe_map)
    flour = iwq.find { |name, _| name == 'Flour' }

    refute_nil flour, 'Flour should appear in merged ingredients'
    amounts = flour[1]

    # 50g own + 500g from cross-reference = 550g
    g_amount = amounts.find { |a| a&.unit == 'g' }

    assert_in_delta 550.0, g_amount.value
  end

  # --- Front matter tests ---

  def test_parses_category_from_front_matter
    markdown = <<~MD
      # Hard-Boiled Eggs

      Protein!

      Category: Test

      ## Cook eggs.

      - Eggs

      Cook them.
    MD

    recipe = make_recipe(markdown)

    assert_equal 'Test', recipe.category
  end

  def test_parses_makes
    markdown = <<~MD
      # Cookies

      Category: Test
      Makes: 32 cookies

      ## Mix

      - Flour, 250 g

      Mix.
    MD

    recipe = make_recipe(markdown)

    assert_equal '32 cookies', recipe.makes
    assert_equal '32', recipe.makes_quantity
    assert_equal 'cookies', recipe.makes_unit_noun
  end

  def test_parses_serves
    markdown = <<~MD
      # Beans

      Category: Test
      Serves: 4

      ## Cook

      - Beans

      Cook.
    MD

    recipe = make_recipe(markdown)

    assert_equal '4', recipe.serves
  end

  def test_category_mismatch_raises_error
    markdown = <<~MD
      # Cookies

      Category: Dessert

      ## Mix

      - Flour

      Mix.
    MD

    error = assert_raises(StandardError) do
      make_recipe(markdown)
    end

    assert_includes error.message, 'Category'
  end

  def test_missing_category_raises_error
    markdown = <<~MD
      # Cookies

      ## Mix

      - Flour

      Mix.
    MD

    error = assert_raises(StandardError) do
      make_recipe(markdown)
    end

    assert_includes error.message, 'Category'
  end

  def test_makes_without_unit_noun_raises_error
    markdown = <<~MD
      # Cookies

      Category: Test
      Makes: 4

      ## Mix

      - Flour

      Mix.
    MD

    error = assert_raises(StandardError) do
      make_recipe(markdown)
    end

    assert_includes error.message, 'Makes'
  end
end

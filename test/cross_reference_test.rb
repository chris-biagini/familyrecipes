# frozen_string_literal: true

require_relative 'test_helper'

class CrossReferenceTest < Minitest::Test
  # --- IngredientParser cross-reference detection ---

  def test_parses_simple_cross_reference
    result = IngredientParser.parse('@[Pizza Dough]')

    assert result[:cross_reference]
    assert_equal 'Pizza Dough', result[:target_title]
    assert_in_delta(1.0, result[:multiplier])
    assert_nil result[:prep_note]
  end

  def test_parses_cross_reference_with_integer_multiplier
    result = IngredientParser.parse('@[Pizza Dough], 2')

    assert result[:cross_reference]
    assert_equal 'Pizza Dough', result[:target_title]
    assert_in_delta(2.0, result[:multiplier])
  end

  def test_parses_cross_reference_with_fraction_multiplier
    result = IngredientParser.parse('@[Pizza Dough], 1/2')

    assert result[:cross_reference]
    assert_in_delta(0.5, result[:multiplier])
  end

  def test_parses_cross_reference_with_decimal_multiplier
    result = IngredientParser.parse('@[Pizza Dough], 0.5')

    assert result[:cross_reference]
    assert_in_delta(0.5, result[:multiplier])
  end

  def test_parses_cross_reference_with_prep_note
    result = IngredientParser.parse('@[Pizza Dough], 2: Let rest 30 min.')

    assert result[:cross_reference]
    assert_in_delta(2.0, result[:multiplier])
    assert_equal 'Let rest 30 min.', result[:prep_note]
  end

  def test_parses_cross_reference_with_trailing_period
    result = IngredientParser.parse('@[Pizza Dough].')

    assert result[:cross_reference]
    assert_equal 'Pizza Dough', result[:target_title]
    assert_in_delta(1.0, result[:multiplier])
  end

  def test_parses_cross_reference_with_multiplier_and_trailing_period
    result = IngredientParser.parse('@[Pizza Dough]., 1')

    assert result[:cross_reference]
    assert_equal 'Pizza Dough', result[:target_title]
    assert_in_delta(1.0, result[:multiplier])
  end

  def test_old_syntax_quantity_before_reference_raises_error
    error = assert_raises(RuntimeError) do
      IngredientParser.parse('2 @[Pizza Dough]')
    end

    assert_match(/Invalid cross-reference syntax/, error.message)
  end

  def test_old_syntax_quantity_with_x_before_reference_raises_error
    error = assert_raises(RuntimeError) do
      IngredientParser.parse('2x @[Pizza Dough]')
    end

    assert_match(/Invalid cross-reference syntax/, error.message)
  end

  def test_regular_ingredient_not_detected_as_cross_reference
    result = IngredientParser.parse('Flour, 250 g')

    assert_nil result[:cross_reference]
    assert_equal 'Flour', result[:name]
  end

  # --- CrossReference object ---

  def test_cross_reference_slug_generation
    xref = FamilyRecipes::CrossReference.new(target_title: 'Pizza Dough')

    assert_equal 'pizza-dough', xref.target_slug
  end

  def test_cross_reference_default_multiplier
    xref = FamilyRecipes::CrossReference.new(target_title: 'Pizza Dough')

    assert_in_delta(1.0, xref.multiplier)
  end

  def test_cross_reference_expanded_ingredients
    md = "# Pizza Dough\n\nCategory: Test\n\n## Mix (make dough)\n\n- Flour, 500 g\n- Water, 325 g\n- Salt\n\nKnead."
    dough = make_recipe(md, id: 'pizza-dough')
    recipe_map = { 'pizza-dough' => dough }
    xref = FamilyRecipes::CrossReference.new(target_title: 'Pizza Dough', multiplier: 2.0)

    expanded = xref.expanded_ingredients(recipe_map)

    flour = expanded.find { |name, _| name == 'Flour' }

    refute_nil flour
    assert_in_delta 1000.0, flour[1].find { |a| a.is_a?(Quantity) }.value

    water = expanded.find { |name, _| name == 'Water' }

    refute_nil water
    assert_in_delta 650.0, water[1].find { |a| a.is_a?(Quantity) }.value

    # Unquantified ingredient (Salt) should have nil amount preserved
    salt = expanded.find { |name, _| name == 'Salt' }

    refute_nil salt
    assert_includes salt[1], nil
  end

  # --- Recipe integration ---

  def test_recipe_with_cross_reference_has_cross_references
    md = "# White Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n\nStretch."
    recipe = make_recipe(md)

    assert_equal 1, recipe.cross_references.size
    assert_equal 'Pizza Dough', recipe.cross_references.first.target_title
  end

  def test_recipe_cross_reference_not_in_own_ingredients
    md = "# White Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n- Olive oil\n\nStretch."
    recipe = make_recipe(md)

    names = recipe.all_ingredient_names

    assert_includes names, 'Olive oil'
    refute_includes names, 'Pizza Dough'
  end

  def test_recipe_all_ingredients_with_quantities_includes_sub_recipe
    dough_md = "# Pizza Dough\n\nCategory: Test\n\n## Mix (make dough)\n\n- Flour, 500 g\n- Salt\n\nKnead."
    dough = make_recipe(dough_md, id: 'pizza-dough')
    pizza_md = "# White Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n" \
               "- @[Pizza Dough]\n- Olive oil, 60 g\n\nStretch."
    pizza = make_recipe(pizza_md)
    recipe_map = { 'pizza-dough' => dough }

    expanded = pizza.all_ingredients_with_quantities({}, recipe_map)
    names = expanded.map(&:first)

    assert_includes names, 'Olive oil'
    assert_includes names, 'Flour'
    assert_includes names, 'Salt'
  end

  def test_recipe_all_ingredients_with_quantities_scales_sub_recipe
    dough_md = "# Pizza Dough\n\nCategory: Test\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead."
    dough = make_recipe(dough_md, id: 'pizza-dough')
    pizza_md = "# White Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n- @[Pizza Dough], 2\n\nStretch."
    pizza = make_recipe(pizza_md)
    recipe_map = { 'pizza-dough' => dough }

    expanded = pizza.all_ingredients_with_quantities({}, recipe_map)
    flour = expanded.find { |name, _| name == 'Flour' }

    refute_nil flour
    assert_in_delta 1000.0, flour[1].find { |a| a.is_a?(Quantity) }.value
  end

  def test_step_ingredient_list_items_preserves_order
    md = "# Test\n\nCategory: Test\n\n## Cook (mix)\n\n- Olive oil, 60 g\n- @[Pizza Dough]\n- Salt\n\nMix."
    recipe = make_recipe(md)

    items = recipe.steps.first.ingredient_list_items

    assert_equal 3, items.size
    assert_instance_of FamilyRecipes::Ingredient, items[0]
    assert_instance_of FamilyRecipes::CrossReference, items[1]
    assert_instance_of FamilyRecipes::Ingredient, items[2]
  end

  private

  def make_recipe(markdown, id: 'test-recipe')
    FamilyRecipes::Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end
end

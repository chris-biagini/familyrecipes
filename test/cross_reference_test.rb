# frozen_string_literal: true

require_relative 'test_helper'

class CrossReferenceTest < Minitest::Test
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

  # --- Recipe integration (>>> syntax) ---

  def test_recipe_with_cross_reference_has_cross_references
    recipe = make_recipe(<<~MD)
      # Pizza
      Category: Test
      ## Make dough.
      >>> @[Pizza Dough]
      ## Top.
      - Cheese
      Add cheese.
    MD

    assert_equal 1, recipe.cross_references.size
    assert_equal 'Pizza Dough', recipe.cross_references.first.target_title
  end

  def test_recipe_cross_reference_not_in_own_ingredients
    recipe = make_recipe(<<~MD)
      # Pizza
      Category: Test
      ## Make dough.
      >>> @[Pizza Dough]
      ## Top.
      - Cheese
      Add cheese.
    MD

    assert_equal ['Cheese'], recipe.all_ingredient_names
  end

  def test_recipe_all_ingredients_with_quantities_includes_sub_recipe
    dough = make_recipe(<<~MD, id: 'pizza-dough')
      # Pizza Dough
      Category: Test
      ## Mix (make dough)
      - Flour, 500 g
      - Water, 325 g
      Knead.
    MD

    pizza = make_recipe(<<~MD)
      # Pizza
      Category: Test
      ## Make dough.
      >>> @[Pizza Dough]
      ## Top.
      - Cheese, 200 g
      Add cheese.
    MD

    recipe_map = { 'pizza-dough' => dough }
    all = pizza.all_ingredients_with_quantities(recipe_map)

    flour = all.find { |name, _| name == 'Flour' }

    refute_nil flour
    assert_in_delta 500.0, flour[1].first.value
  end

  def test_recipe_all_ingredients_with_quantities_scales_sub_recipe
    dough = make_recipe(<<~MD, id: 'pizza-dough')
      # Pizza Dough
      Category: Test
      ## Mix (make dough)
      - Flour, 500 g
      Knead.
    MD

    pizza = make_recipe(<<~MD)
      # Pizza
      Category: Test
      ## Make dough.
      >>> @[Pizza Dough], 2
      ## Top.
      - Cheese
      Add cheese.
    MD

    recipe_map = { 'pizza-dough' => dough }
    all = pizza.all_ingredients_with_quantities(recipe_map)

    flour = all.find { |name, _| name == 'Flour' }

    refute_nil flour
    assert_in_delta 1000.0, flour[1].first.value
  end

  def test_step_cross_reference_accessible_on_step
    recipe = make_recipe(<<~MD)
      # Pizza
      Category: Test
      ## Make dough.
      >>> @[Pizza Dough]
      ## Top.
      - Cheese
      Add cheese.
    MD

    dough_step = recipe.steps.first

    refute_nil dough_step.cross_reference
    assert_equal 'Pizza Dough', dough_step.cross_reference.target_title
    assert_nil recipe.steps.last.cross_reference
  end

  private

  def make_recipe(markdown, id: 'test-recipe')
    FamilyRecipes::Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end
end

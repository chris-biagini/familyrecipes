require_relative 'test_helper'

class CrossReferenceTest < Minitest::Test
  # --- IngredientParser cross-reference detection ---

  def test_parses_simple_cross_reference
    result = IngredientParser.parse("@[Pizza Dough]")

    assert result[:cross_reference]
    assert_equal "Pizza Dough", result[:target_title]
    assert_equal 1.0, result[:multiplier]
    assert_nil result[:prep_note]
  end

  def test_parses_cross_reference_with_integer_multiplier
    result = IngredientParser.parse("@[Pizza Dough], 2")

    assert result[:cross_reference]
    assert_equal "Pizza Dough", result[:target_title]
    assert_equal 2.0, result[:multiplier]
  end

  def test_parses_cross_reference_with_fraction_multiplier
    result = IngredientParser.parse("@[Pizza Dough], 1/2")

    assert result[:cross_reference]
    assert_equal 0.5, result[:multiplier]
  end

  def test_parses_cross_reference_with_decimal_multiplier
    result = IngredientParser.parse("@[Pizza Dough], 0.5")

    assert result[:cross_reference]
    assert_equal 0.5, result[:multiplier]
  end

  def test_parses_cross_reference_with_prep_note
    result = IngredientParser.parse("@[Pizza Dough], 2: Let rest 30 min.")

    assert result[:cross_reference]
    assert_equal 2.0, result[:multiplier]
    assert_equal "Let rest 30 min.", result[:prep_note]
  end

  def test_parses_cross_reference_with_trailing_period
    result = IngredientParser.parse("@[Pizza Dough].")

    assert result[:cross_reference]
    assert_equal "Pizza Dough", result[:target_title]
    assert_equal 1.0, result[:multiplier]
  end

  def test_parses_cross_reference_with_multiplier_and_trailing_period
    result = IngredientParser.parse("@[Pizza Dough]., 1")

    assert result[:cross_reference]
    assert_equal "Pizza Dough", result[:target_title]
    assert_equal 1.0, result[:multiplier]
  end

  def test_old_syntax_quantity_before_reference_raises_error
    error = assert_raises(RuntimeError) do
      IngredientParser.parse("2 @[Pizza Dough]")
    end

    assert_match(/Invalid cross-reference syntax/, error.message)
  end

  def test_old_syntax_quantity_with_x_before_reference_raises_error
    error = assert_raises(RuntimeError) do
      IngredientParser.parse("2x @[Pizza Dough]")
    end

    assert_match(/Invalid cross-reference syntax/, error.message)
  end

  def test_regular_ingredient_not_detected_as_cross_reference
    result = IngredientParser.parse("Flour, 250 g")

    assert_nil result[:cross_reference]
    assert_equal "Flour", result[:name]
  end

  # --- CrossReference object ---

  def test_cross_reference_slug_generation
    xref = CrossReference.new(target_title: "Pizza Dough")

    assert_equal "pizza-dough", xref.target_slug
  end

  def test_cross_reference_default_multiplier
    xref = CrossReference.new(target_title: "Pizza Dough")

    assert_equal 1.0, xref.multiplier
  end

  def test_cross_reference_expanded_ingredients
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n- Water, 325 g\n- Salt\n\nKnead.", id: "pizza-dough")
    recipe_map = { "pizza-dough" => dough }
    xref = CrossReference.new(target_title: "Pizza Dough", multiplier: 2.0)

    expanded = xref.expanded_ingredients(recipe_map)

    flour = expanded.find { |name, _| name == "Flour" }
    refute_nil flour
    assert_equal 1000.0, flour[1].find { |a| a&.first }&.first

    water = expanded.find { |name, _| name == "Water" }
    refute_nil water
    assert_equal 650.0, water[1].find { |a| a&.first }&.first

    # Unquantified ingredient (Salt) should have nil amount preserved
    salt = expanded.find { |name, _| name == "Salt" }
    refute_nil salt
    assert_includes salt[1], nil
  end

  # --- Recipe integration ---

  def test_recipe_with_cross_reference_has_cross_references
    recipe = make_recipe("# White Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n\nStretch.")

    assert_equal 1, recipe.cross_references.size
    assert_equal "Pizza Dough", recipe.cross_references.first.target_title
  end

  def test_recipe_cross_reference_not_in_own_ingredients
    recipe = make_recipe("# White Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n- Olive oil\n\nStretch.")

    names = recipe.all_ingredient_names
    assert_includes names, "Olive oil"
    refute_includes names, "Pizza Dough"
  end

  def test_recipe_all_ingredients_with_quantities_includes_sub_recipe
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n- Salt\n\nKnead.", id: "pizza-dough")
    pizza = make_recipe("# White Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n- Olive oil, 60 g\n\nStretch.")
    recipe_map = { "pizza-dough" => dough }

    expanded = pizza.all_ingredients_with_quantities({}, recipe_map)
    names = expanded.map(&:first)

    assert_includes names, "Olive oil"
    assert_includes names, "Flour"
    assert_includes names, "Salt"
  end

  def test_recipe_all_ingredients_with_quantities_scales_sub_recipe
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead.", id: "pizza-dough")
    pizza = make_recipe("# White Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough], 2\n\nStretch.")
    recipe_map = { "pizza-dough" => dough }

    expanded = pizza.all_ingredients_with_quantities({}, recipe_map)
    flour = expanded.find { |name, _| name == "Flour" }

    refute_nil flour
    assert_equal 1000.0, flour[1].find { |a| a&.first }&.first
  end

  def test_step_ingredient_list_items_preserves_order
    recipe = make_recipe("# Test\n\n## Cook (mix)\n\n- Olive oil, 60 g\n- @[Pizza Dough]\n- Salt\n\nMix.")

    items = recipe.steps.first.ingredient_list_items
    assert_equal 3, items.size
    assert_instance_of Ingredient, items[0]
    assert_instance_of CrossReference, items[1]
    assert_instance_of Ingredient, items[2]
  end

  # --- Validation ---

  def test_site_generator_detects_unresolved_cross_reference
    dough_md = "# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead."
    pizza_md = "# Test Pizza\n\n## Dough (make dough)\n\n- @[Nonexistent Recipe]\n\nStretch."

    dough = Recipe.new(markdown_source: dough_md, id: "pizza-dough", category: "Pizza")
    pizza = Recipe.new(markdown_source: pizza_md, id: "test-pizza", category: "Pizza")

    error = assert_raises(StandardError) do
      generator = FamilyRecipes::SiteGenerator.new(
        File.expand_path('..', __dir__),
        recipes: [dough, pizza],
        quick_bites: []
      )
      generator.generate
    end

    assert_match(/Unresolved cross-reference/, error.message)
    assert_match(/Nonexistent Recipe/, error.message)
  end

  def test_site_generator_detects_circular_reference
    a_md = "# Recipe A\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo."
    b_md = "# Recipe B\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo."

    a = Recipe.new(markdown_source: a_md, id: "recipe-a", category: "Test")
    b = Recipe.new(markdown_source: b_md, id: "recipe-b", category: "Test")

    error = assert_raises(StandardError) do
      generator = FamilyRecipes::SiteGenerator.new(
        File.expand_path('..', __dir__),
        recipes: [a, b],
        quick_bites: []
      )
      generator.generate
    end

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_site_generator_detects_title_filename_mismatch
    md = "# Actual Title\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix."
    recipe = Recipe.new(markdown_source: md, id: "wrong-slug", category: "Test")

    error = assert_raises(StandardError) do
      generator = FamilyRecipes::SiteGenerator.new(
        File.expand_path('..', __dir__),
        recipes: [recipe],
        quick_bites: []
      )
      generator.generate
    end

    assert_match(/Title\/filename mismatch/, error.message)
  end

  private

  def make_recipe(markdown, id: "test-recipe")
    Recipe.new(markdown_source: markdown, id: id, category: "Test")
  end
end

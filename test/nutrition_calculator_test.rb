require_relative 'test_helper'

class NutritionCalculatorTest < Minitest::Test
  def setup
    @nutrition_data = {
      'Flour (all-purpose)' => {
        'fdc_id' => 169761,
        'per_100g' => {
          'calories' => 364,
          'protein' => 10.33,
          'fat' => 0.98,
          'carbs' => 76.31,
          'fiber' => 2.7,
          'sodium' => 2
        },
        'portions' => {
          'cup' => 125,
          'Tbsp' => 8
        }
      },
      'Eggs' => {
        'fdc_id' => 171287,
        'per_100g' => {
          'calories' => 143,
          'protein' => 12.56,
          'fat' => 9.51,
          'carbs' => 0.72,
          'fiber' => 0,
          'sodium' => 142
        },
        'portions' => {
          '~unitless' => 50
        }
      },
      'Butter' => {
        'fdc_id' => 173410,
        'per_100g' => {
          'calories' => 717,
          'protein' => 0.85,
          'fat' => 81.11,
          'carbs' => 0.06,
          'fiber' => 0,
          'sodium' => 643
        },
        'portions' => {
          'Tbsp' => 14.2,
          'cup' => 227
        }
      },
      'Olive oil' => {
        'fdc_id' => 171413,
        'per_100g' => {
          'calories' => 884,
          'protein' => 0,
          'fat' => 100,
          'carbs' => 0,
          'fiber' => 0,
          'sodium' => 2
        },
        'portions' => {
          'Tbsp' => 13.5
        }
      },
      'Sugar (white)' => {
        'fdc_id' => 169655,
        'per_100g' => {
          'calories' => 387,
          'protein' => 0,
          'fat' => 0,
          'carbs' => 100,
          'fiber' => 0,
          'sodium' => 1
        },
        'portions' => {
          'cup' => 200
        }
      }
    }

    @omit_set = Set.new(['water', 'ice', 'poolish', 'sourdough starter'])
    @calculator = FamilyRecipes::NutritionCalculator.new(@nutrition_data, omit_set: @omit_set)
    @alias_map = {
      'flour (all-purpose)' => 'Flour (all-purpose)',
      'flour (all purpose)' => 'Flour (all-purpose)',
      'eggs' => 'Eggs',
      'egg' => 'Eggs',
      'butter' => 'Butter',
      'olive oil' => 'Olive oil',
      'sugar (white)' => 'Sugar (white)',
      'water' => 'Water'
    }
    @recipe_map = {}
  end

  def make_recipe(markdown, id: 'test-recipe')
    Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  # --- Basic calculations ---

  def test_gram_based_calculation
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 500 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 500g flour: 364 * 5 = 1820 cal
    assert_in_delta 1820, result.totals[:calories], 1
    assert_in_delta 51.65, result.totals[:protein], 0.1
    assert_in_delta 4.9, result.totals[:fat], 0.1
    assert_in_delta 381.55, result.totals[:carbs], 0.1
    assert_in_delta 13.5, result.totals[:fiber], 0.1
    assert_in_delta 10, result.totals[:sodium], 1
  end

  def test_unitless_count_calculation
    recipe = make_recipe(<<~MD)
      # Test

      ## Prep (crack eggs)

      - Eggs, 3

      Crack.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 3 eggs * 50g each = 150g; 143 * 1.5 = 214.5 cal
    assert_in_delta 214.5, result.totals[:calories], 1
    assert_in_delta 18.84, result.totals[:protein], 0.1
  end

  def test_portion_unit_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 2 Tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 2 Tbsp * 14.2g = 28.4g; 717 * 0.284 = 203.6 cal
    assert_in_delta 203.6, result.totals[:calories], 1
  end

  # --- Aggregation across steps ---

  def test_aggregation_across_steps
    recipe = make_recipe(<<~MD)
      # Test

      ## Step 1 (first)

      - Butter, 50 g

      First.

      ## Step 2 (second)

      - Butter, 100 g

      Second.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 150g butter: 717 * 1.5 = 1075.5 cal
    assert_in_delta 1075.5, result.totals[:calories], 1
  end

  # --- Missing and partial ingredients ---

  def test_missing_ingredient_reported
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Unicorn dust, 50 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_includes result.missing_ingredients, 'Unicorn dust'
    refute result.complete?
  end

  def test_unknown_unit_reported_as_partial
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 2 bushels

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_includes result.partial_ingredients, 'Flour (all-purpose)'
    refute result.complete?
  end

  # --- Omit_From_List ingredients ---

  def test_omit_from_list_silently_skipped
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Water, 500 g
      - Flour (all-purpose), 100 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # Only flour should contribute (100g: 364 cal)
    assert_in_delta 364, result.totals[:calories], 1
    refute_includes result.missing_ingredients, 'Water'
  end

  # --- Unquantified ingredients ---

  def test_unquantified_ingredients_silently_skipped
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 200 g
      - Olive oil

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # Only flour contributes (200g: 364 * 2 = 728 cal)
    assert_in_delta 728, result.totals[:calories], 1
    refute_includes result.missing_ingredients, 'Olive oil'
  end

  # --- Yield line parsing ---

  def test_yield_line_serves
    recipe = make_recipe(<<~MD)
      # Test

      Serves 4.

      ## Mix (combine)

      - Flour (all-purpose), 400 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 4, result.serving_count
    # 400g flour = 1456 cal total, 364 per serving
    assert_in_delta 364, result.per_serving[:calories], 1
  end

  def test_yield_line_makes_count
    recipe = make_recipe(<<~MD)
      # Test

      Makes 30 gougeres.

      ## Mix (combine)

      - Eggs, 3

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 30, result.serving_count
    refute_nil result.per_serving
  end

  def test_yield_line_makes_about
    recipe = make_recipe(<<~MD)
      # Test

      Makes about 32 cookies.

      ## Mix (combine)

      - Eggs, 2

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)
    assert_equal 32, result.serving_count
  end

  def test_yield_line_makes_enough_for
    recipe = make_recipe(<<~MD)
      # Test

      Makes enough for 2 pizzas.

      ## Mix (combine)

      - Flour (all-purpose), 500 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)
    assert_equal 2, result.serving_count
  end

  def test_no_yield_line_returns_nil_serving_count
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 500 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_nil result.serving_count
    assert_nil result.per_serving
  end

  # --- Cross-references ---

  def test_cross_reference_ingredients_included
    dough_recipe = make_recipe(<<~MD, id: 'pizza-dough')
      # Pizza Dough

      ## Dough (make dough)

      - Flour (all-purpose), 500 g

      Knead.
    MD

    pizza_recipe = make_recipe(<<~MD, id: 'pizza')
      # Pizza

      ## Assemble (put together)

      - @[Pizza Dough]
      - Olive oil, 2 Tbsp

      Bake.
    MD

    recipe_map = {
      'pizza-dough' => dough_recipe,
      'pizza' => pizza_recipe
    }

    result = @calculator.calculate(pizza_recipe, @alias_map, recipe_map)

    # Flour: 500g = 1820 cal, Olive oil: 2 Tbsp = 27g = 238.7 cal
    assert_in_delta 2058.7, result.totals[:calories], 2
  end

  def test_cross_reference_with_multiplier
    dough_recipe = make_recipe(<<~MD, id: 'pizza-dough')
      # Pizza Dough

      ## Dough (make dough)

      - Flour (all-purpose), 250 g

      Knead.
    MD

    pizza_recipe = make_recipe(<<~MD, id: 'pizza')
      # Pizza

      ## Assemble (put together)

      - @[Pizza Dough], 2

      Bake.
    MD

    recipe_map = {
      'pizza-dough' => dough_recipe,
      'pizza' => pizza_recipe
    }

    result = @calculator.calculate(pizza_recipe, @alias_map, recipe_map)

    # Flour: 250g * 2 = 500g = 1820 cal
    assert_in_delta 1820, result.totals[:calories], 1
  end

  # --- Alias map ---

  def test_alias_map_resolves_alternate_names
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (All purpose), 200 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # "Flour (All purpose)" aliases to "Flour (all-purpose)"
    assert_in_delta 728, result.totals[:calories], 1
    assert result.missing_ingredients.empty?
  end

  # --- Complete? ---

  def test_complete_when_all_resolved
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 200 g
      - Eggs, 2

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert result.complete?
  end

  # --- Standard conversions (oz, lbs, ml, l) ---

  def test_oz_uses_standard_conversion_without_portions_entry
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 4 oz

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 4 oz * 28.35 g/oz = 113.4g; 717 * 1.134 = 813.1 cal
    assert_in_delta 813.1, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end

  def test_lbs_uses_standard_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 1 lbs

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 lbs * 453.59 g/lbs = 453.59g; 364 * 4.5359 = 1650.7 cal
    assert_in_delta 1650.7, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end

  def test_ml_uses_standard_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Olive oil, 30 ml

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 30 ml * 1 g/ml = 30g; 884 * 0.3 = 265.2 cal
    assert_in_delta 265.2, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end

  def test_l_uses_standard_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Olive oil, 0.5 l

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 0.5 l * 1000 g/l = 500g; 884 * 5 = 4420 cal
    assert_in_delta 4420, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end

  def test_case_insensitive_unit_lookup
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 1 tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 Tbsp butter = 14.2g; 717 * 0.142 = 101.8 cal
    assert_in_delta 101.8, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end
end

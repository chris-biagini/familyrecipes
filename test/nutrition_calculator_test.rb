require_relative 'test_helper'

class NutritionCalculatorTest < Minitest::Test
  def setup
    @nutrition_data = {
      'Flour (all-purpose)' => {
        'serving' => { 'grams' => 30 },
        'per_serving' => {
          'calories' => 109.2,
          'protein' => 3.099,
          'fat' => 0.294,
          'saturated_fat' => 0.05,
          'carbs' => 22.893,
          'fiber' => 0.81,
          'sodium' => 0.6
        },
        'portions' => {
          'cup' => 125,
          'tbsp' => 8
        }
      },
      'Eggs' => {
        'serving' => { 'grams' => 50 },
        'per_serving' => {
          'calories' => 71.5,
          'protein' => 6.28,
          'fat' => 4.755,
          'saturated_fat' => 1.6,
          'carbs' => 0.36,
          'fiber' => 0,
          'sodium' => 71
        },
        'portions' => {
          '~unitless' => 50
        }
      },
      'Butter' => {
        'serving' => {
          'grams' => 14,
          'volume_amount' => 1,
          'volume_unit' => 'tbsp'
        },
        'per_serving' => {
          'calories' => 100.38,
          'protein' => 0.119,
          'fat' => 11.3554,
          'saturated_fat' => 7.17,
          'carbs' => 0.0084,
          'fiber' => 0,
          'sodium' => 90.02
        },
        'portions' => {
          'tbsp' => 14.2,
          'cup' => 227
        }
      },
      'Olive oil' => {
        'serving' => {
          'grams' => 14,
          'volume_amount' => 1,
          'volume_unit' => 'tbsp'
        },
        'per_serving' => {
          'calories' => 123.76,
          'protein' => 0,
          'fat' => 14,
          'saturated_fat' => 1.9,
          'carbs' => 0,
          'fiber' => 0,
          'sodium' => 0.28
        },
        'portions' => {
          'tbsp' => 13.5
        }
      },
      'Sugar (white)' => {
        'serving' => { 'grams' => 4 },
        'per_serving' => {
          'calories' => 15.48,
          'protein' => 0,
          'fat' => 0,
          'saturated_fat' => 0,
          'carbs' => 4,
          'fiber' => 0,
          'sodium' => 0.04
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

    # 500g flour: (109.2/30)*500 = 1820 cal
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

    # 3 eggs * 50g each = 150g; (71.5/50)*150 = 214.5 cal
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

    # 2 Tbsp * 14.2g = 28.4g; (100.38/14)*28.4 = 203.6 cal
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

    # 150g butter: (100.38/14)*150 = 1075.5 cal
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

    # Only flour should contribute (100g: (109.2/30)*100 = 364 cal)
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

    # Only flour contributes (200g: (109.2/30)*200 = 728 cal)
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

  # --- Weight conversions (oz, lb, kg) ---

  def test_oz_uses_weight_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 4 oz

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 4 oz * 28.3495 g/oz = 113.398g; (100.38/14)*113.398 = 813.1 cal
    assert_in_delta 813.1, result.totals[:calories], 2
    assert result.partial_ingredients.empty?
  end

  def test_lb_uses_weight_conversion
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Flour (all-purpose), 1 lbs

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 lbs → normalized to lb → 453.592g; (109.2/30)*453.592 = 1651 cal
    assert_in_delta 1651, result.totals[:calories], 2
    assert result.partial_ingredients.empty?
  end

  # --- Volumetric with density fallback ---

  def test_density_derived_volume_conversion
    # Olive oil has volume_amount/volume_unit in serving but NO cup portion
    # Density: 14g / (1 * 14.787ml) = 0.9468 g/ml
    # 1 cup = 236.588ml * 0.9468 = 224.0g
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Olive oil, 1 cup

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # (123.76/14) * (236.588 * 14/14.787) = 8.84 * 224.0 = 1980 cal approx
    expected_grams = 236.588 * (14.0 / 14.787)
    expected_cal = (123.76 / 14.0) * expected_grams
    assert_in_delta expected_cal, result.totals[:calories], 2
    assert result.partial_ingredients.empty?
  end

  def test_portion_takes_priority_over_density
    # Butter has both a tbsp portion (14.2) and density info.
    # The explicit portion should be used.
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 1 Tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # Uses portion: 1 * 14.2g, NOT density-derived
    expected_cal = (100.38 / 14.0) * 14.2
    assert_in_delta expected_cal, result.totals[:calories], 1
  end

  # --- Saturated fat tracking ---

  def test_saturated_fat_tracked
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 100 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # (7.17/14)*100 = 51.21g sat fat
    expected = (7.17 / 14.0) * 100
    assert_in_delta expected, result.totals[:saturated_fat], 0.5
  end

  # --- Resolvable? API ---

  def test_resolvable_with_known_unit
    entry = @nutrition_data['Flour (all-purpose)']
    assert @calculator.resolvable?(1, 'cup', entry)
    assert @calculator.resolvable?(1, 'g', entry)
    assert @calculator.resolvable?(1, nil, entry)  # bare count
  end

  def test_not_resolvable_with_unknown_unit
    entry = @nutrition_data['Flour (all-purpose)']
    refute @calculator.resolvable?(1, 'bushel', entry)
  end

  def test_resolvable_with_density
    entry = @nutrition_data['Olive oil']
    # Olive oil has no 'cup' portion but has density info → resolvable via density
    assert @calculator.resolvable?(1, 'cup', entry)
  end

  # --- Case insensitive unit lookup ---

  def test_case_insensitive_unit_lookup
    recipe = make_recipe(<<~MD)
      # Test

      ## Mix (combine)

      - Butter, 1 tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 tbsp butter = 14.2g; (100.38/14)*14.2 = 101.8 cal
    assert_in_delta 101.8, result.totals[:calories], 1
    assert result.partial_ingredients.empty?
  end
end

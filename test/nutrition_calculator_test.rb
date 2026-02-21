# frozen_string_literal: true

require_relative 'test_helper'

class NutritionCalculatorTest < Minitest::Test
  def setup
    @nutrition_data = {
      'Flour (all-purpose)' => {
        'nutrients' => {
          'basis_grams' => 30,
          'calories' => 109.2, 'protein' => 3.099, 'fat' => 0.294,
          'saturated_fat' => 0.05, 'carbs' => 22.893, 'fiber' => 0.81, 'sodium' => 0.6
        },
        'density' => { 'grams' => 125, 'volume' => 1, 'unit' => 'cup' }
      },
      'Eggs' => {
        'nutrients' => {
          'basis_grams' => 50,
          'calories' => 71.5, 'protein' => 6.28, 'fat' => 4.755,
          'saturated_fat' => 1.6, 'carbs' => 0.36, 'fiber' => 0, 'sodium' => 71
        },
        'portions' => { '~unitless' => 50 }
      },
      'Butter' => {
        'nutrients' => {
          'basis_grams' => 14,
          'calories' => 100.38, 'protein' => 0.119, 'fat' => 11.3554,
          'saturated_fat' => 7.17, 'carbs' => 0.0084, 'fiber' => 0, 'sodium' => 90.02
        },
        'density' => { 'grams' => 227, 'volume' => 1, 'unit' => 'cup' },
        'portions' => { 'stick' => 113.0 }
      },
      'Olive oil' => {
        'nutrients' => {
          'basis_grams' => 14,
          'calories' => 123.76, 'protein' => 0, 'fat' => 14,
          'saturated_fat' => 1.9, 'carbs' => 0, 'fiber' => 0, 'sodium' => 0.28
        },
        'density' => { 'grams' => 14, 'volume' => 1, 'unit' => 'tbsp' }
      },
      'Sugar (white)' => {
        'nutrients' => {
          'basis_grams' => 4,
          'calories' => 15.48, 'protein' => 0, 'fat' => 0,
          'saturated_fat' => 0, 'carbs' => 4, 'fiber' => 0, 'sodium' => 0.04
        },
        'density' => { 'grams' => 200, 'volume' => 1, 'unit' => 'cup' }
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
    FamilyRecipes::Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  # --- Basic calculations ---

  def test_gram_based_calculation
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

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

      Category: Test

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

      Category: Test

      ## Mix (combine)

      - Butter, 2 Tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 2 Tbsp via density: 227g/cup, 1 cup = 236.588ml, 1 tbsp = 14.787ml
    # 2 * 14.787ml * (227/236.588) g/ml = 28.37g; (100.38/14)*28.37 = 203.3 cal
    expected_grams = 2 * 14.787 * (227.0 / 236.588)
    expected_cal = (100.38 / 14.0) * expected_grams

    assert_in_delta expected_cal, result.totals[:calories], 1
  end

  # --- Aggregation across steps ---

  def test_aggregation_across_steps
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

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

      Category: Test

      ## Mix (combine)

      - Unicorn dust, 50 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_includes result.missing_ingredients, 'Unicorn dust'
    refute_predicate result, :complete?
  end

  def test_unknown_unit_reported_as_partial
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Flour (all-purpose), 2 bushels

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_includes result.partial_ingredients, 'Flour (all-purpose)'
    refute_predicate result, :complete?
  end

  # --- Omit_From_List ingredients ---

  def test_omit_from_list_silently_skipped
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

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

      Category: Test

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

  # --- Serving count from front matter ---

  def test_serves_field
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Serves: 4

      ## Mix (combine)

      - Flour (all-purpose), 400 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 4, result.serving_count
    assert_in_delta 364, result.per_serving[:calories], 1
  end

  def test_makes_field
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 30 gougeres

      ## Mix (combine)

      - Eggs, 3

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 30, result.serving_count
    refute_nil result.per_serving
  end

  def test_serves_preferred_over_makes_for_serving_count
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 12 cookies
      Serves: 6

      ## Mix (combine)

      - Eggs, 2

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 6, result.serving_count
  end

  def test_no_serves_or_makes_returns_nil_serving_count
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

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

      Category: Test

      ## Dough (make dough)

      - Flour (all-purpose), 500 g

      Knead.
    MD

    pizza_recipe = make_recipe(<<~MD, id: 'pizza')
      # Pizza

      Category: Test

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

    # Flour: 500g = 1820 cal, Olive oil: 2 Tbsp via density (14g/tbsp) = 28g = 247.5 cal
    flour_cal = (109.2 / 30.0) * 500
    oil_grams = 2 * 14.787 * (14.0 / 14.787) # density: 14g per 1 tbsp
    oil_cal = (123.76 / 14.0) * oil_grams

    assert_in_delta flour_cal + oil_cal, result.totals[:calories], 2
  end

  def test_cross_reference_with_multiplier
    dough_recipe = make_recipe(<<~MD, id: 'pizza-dough')
      # Pizza Dough

      Category: Test

      ## Dough (make dough)

      - Flour (all-purpose), 250 g

      Knead.
    MD

    pizza_recipe = make_recipe(<<~MD, id: 'pizza')
      # Pizza

      Category: Test

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

      Category: Test

      ## Mix (combine)

      - Flour (All purpose), 200 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # "Flour (All purpose)" aliases to "Flour (all-purpose)"
    assert_in_delta 728, result.totals[:calories], 1
    assert_empty result.missing_ingredients
  end

  # --- Complete? ---

  def test_complete_when_all_resolved
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Flour (all-purpose), 200 g
      - Eggs, 2

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_predicate result, :complete?
  end

  # --- Weight conversions (oz, lb, kg) ---

  def test_oz_uses_weight_conversion
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Butter, 4 oz

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 4 oz * 28.3495 g/oz = 113.398g; (100.38/14)*113.398 = 813.1 cal
    assert_in_delta 813.1, result.totals[:calories], 2
    assert_empty result.partial_ingredients
  end

  def test_lb_uses_weight_conversion
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Flour (all-purpose), 1 lbs

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 lbs → normalized to lb → 453.592g; (109.2/30)*453.592 = 1651 cal
    assert_in_delta 1651, result.totals[:calories], 2
    assert_empty result.partial_ingredients
  end

  # --- Volumetric with density fallback ---

  def test_density_derived_volume_conversion
    # Olive oil has density hash (14g per 1 tbsp) but no cup portion
    # Density: 14g / (1 * 14.787ml) = 0.9468 g/ml
    # 1 cup = 236.588ml * 0.9468 = 224.0g
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Olive oil, 1 cup

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # (123.76/14) * (236.588 * 14/14.787) = 8.84 * 224.0 = 1980 cal approx
    expected_grams = 236.588 * (14.0 / 14.787)
    expected_cal = (123.76 / 14.0) * expected_grams

    assert_in_delta expected_cal, result.totals[:calories], 2
    assert_empty result.partial_ingredients
  end

  def test_named_portion_resolves
    # Butter has a 'stick' portion (113g) — resolves via named portion
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Butter, 1 stick

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 stick = 113g; (100.38/14)*113 = 810.2 cal
    expected_cal = (100.38 / 14.0) * 113.0

    assert_in_delta expected_cal, result.totals[:calories], 1
  end

  # --- Saturated fat tracking ---

  def test_saturated_fat_tracked
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

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
  end

  def test_resolvable_bare_count_with_unitless
    entry = @nutrition_data['Eggs']

    assert @calculator.resolvable?(1, nil, entry)
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

      Category: Test

      ## Mix (combine)

      - Butter, 1 tbsp

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # 1 tbsp butter via density: 14.787ml * (227/236.588) g/ml = 14.19g
    # (100.38/14)*14.19 = 101.7 cal
    expected_grams = 14.787 * (227.0 / 236.588)
    expected_cal = (100.38 / 14.0) * expected_grams

    assert_in_delta expected_cal, result.totals[:calories], 1
    assert_empty result.partial_ingredients
  end

  # --- Bare count without ~unitless (#2 fix) ---

  def test_bare_count_without_unitless_reported_as_partial
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Flour (all-purpose), 4

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    # Flour has no ~unitless portion, so bare "4" should be partial
    assert_includes result.partial_ingredients, 'Flour (all-purpose)'
    refute_predicate result, :complete?
  end

  def test_bare_count_not_resolvable_without_unitless
    entry = @nutrition_data['Flour (all-purpose)']

    refute @calculator.resolvable?(1, nil, entry)
  end

  # --- New nutrients (#9) ---

  def test_new_nutrients_calculated
    nutrition_data = {
      'Butter' => {
        'nutrients' => {
          'basis_grams' => 14,
          'calories' => 100, 'fat' => 11, 'saturated_fat' => 7, 'trans_fat' => 0.5,
          'cholesterol' => 30, 'sodium' => 90, 'carbs' => 0, 'fiber' => 0,
          'total_sugars' => 0, 'added_sugars' => 0, 'protein' => 0.1
        },
        'portions' => { 'stick' => 113 }
      }
    }
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)

    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Butter, 28 g

      Mix.
    MD

    result = calculator.calculate(recipe, @alias_map, @recipe_map)

    # 28g = 2 servings worth
    assert_in_delta 1.0, result.totals[:trans_fat], 0.01
    assert_in_delta 60, result.totals[:cholesterol], 0.1
    assert_in_delta 0, result.totals[:total_sugars], 0.01
    assert_in_delta 0, result.totals[:added_sugars], 0.01
  end

  def test_missing_new_nutrient_keys_default_to_zero
    # Entry without new nutrients (trans_fat, cholesterol, etc.)
    nutrition_data = {
      'Flour (all-purpose)' => {
        'nutrients' => {
          'basis_grams' => 30,
          'calories' => 109.2, 'protein' => 3.0, 'fat' => 0.3,
          'saturated_fat' => 0.05, 'carbs' => 22.9, 'fiber' => 0.8, 'sodium' => 0.6
        },
        'density' => { 'grams' => 125, 'volume' => 1, 'unit' => 'cup' }
      }
    }
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)

    recipe = make_recipe(<<~MD)
      # Test

      Category: Test

      ## Mix (combine)

      - Flour (all-purpose), 100 g

      Mix.
    MD

    result = calculator.calculate(recipe, @alias_map, @recipe_map)

    # New keys missing from YAML → default to 0
    assert_equal 0, result.totals[:trans_fat]
    assert_equal 0, result.totals[:cholesterol]
    assert_equal 0, result.totals[:total_sugars]
    assert_equal 0, result.totals[:added_sugars]
    # Old keys still work
    assert_predicate result.totals[:calories], :positive?
  end

  # --- Schema validation (#11) ---

  def test_malformed_entry_missing_basis_grams
    nutrition_data = {
      'Good' => {
        'nutrients' => { 'basis_grams' => 30, 'calories' => 100 }
      },
      'Bad' => {
        'nutrients' => { 'calories' => 100 }
      }
    }

    _out, err = capture_io do
      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)

      assert calculator.nutrition_data.key?('Good')
      refute calculator.nutrition_data.key?('Bad')
    end

    assert_match(/Bad/, err)
  end

  def test_malformed_entry_invalid_nutrients
    nutrition_data = {
      'Bad2' => {
        'nutrients' => 'not a hash'
      }
    }

    _out, err = capture_io do
      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)

      refute calculator.nutrition_data.key?('Bad2')
    end

    assert_match(/Bad2/, err)
  end

  def test_zero_basis_grams_skipped
    nutrition_data = {
      'ZeroGrams' => {
        'nutrients' => { 'basis_grams' => 0, 'calories' => 100 }
      }
    }

    _out, err = capture_io do
      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)

      refute calculator.nutrition_data.key?('ZeroGrams')
    end

    assert_match(/ZeroGrams/, err)
  end

  # --- Per-unit nutrition ---

  def test_per_unit_with_makes
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 24 cookies

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 24, result.makes_quantity
    assert_equal 'cookie', result.makes_unit_singular
    assert_equal 'cookies', result.makes_unit_plural
    assert_in_delta 1820.0 * 480 / 500 / 24, result.per_unit[:calories], 1
  end

  def test_per_unit_nil_without_makes
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Serves: 4

      ## Mix (combine)

      - Flour (all-purpose), 400 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_nil result.per_unit
    assert_nil result.makes_quantity
  end

  def test_units_per_serving_with_both
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 24 cookies
      Serves: 4

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_in_delta 6.0, result.units_per_serving, 0.01
  end

  def test_units_per_serving_nil_without_both
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 12 bagels

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_nil result.units_per_serving
  end

  def test_per_unit_with_irregular_plural
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 2 loaves

      ## Mix (combine)

      - Flour (all-purpose), 500 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 'loaf', result.makes_unit_singular
    assert_equal 'loaves', result.makes_unit_plural
  end
end

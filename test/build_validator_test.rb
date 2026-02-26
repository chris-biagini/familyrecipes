# frozen_string_literal: true

require_relative 'test_helper'

class BuildValidatorTest < ActiveSupport::TestCase
  def test_detects_unresolved_cross_reference
    dough_md = "# Pizza Dough\n\nCategory: Test\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead."
    dough = make_recipe(dough_md, id: 'pizza-dough')
    pizza_md = "# Test Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n- @[Nonexistent Recipe]\n\nStretch."
    pizza = make_recipe(pizza_md, id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Unresolved cross-reference/, error.message)
    assert_match(/Nonexistent Recipe/, error.message)
  end

  def test_detects_circular_reference
    a = make_recipe("# Recipe A\n\nCategory: Test\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo.", id: 'recipe-a')
    b = make_recipe("# Recipe B\n\nCategory: Test\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo.", id: 'recipe-b')
    validator = build_validator(recipes: [a, b])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_detects_title_filename_mismatch
    md = "# Actual Title\n\nCategory: Test\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix."
    recipe = make_recipe(md, id: 'wrong-slug')
    validator = build_validator(recipes: [recipe])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(%r{Title/filename mismatch}, error.message)
  end

  def test_valid_cross_references_pass
    dough_md = "# Pizza Dough\n\nCategory: Test\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead."
    dough = make_recipe(dough_md, id: 'pizza-dough')
    pizza_md = "# Test Pizza\n\nCategory: Test\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n\nStretch."
    pizza = make_recipe(pizza_md, id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    output = capture_io { validator.validate_cross_references }

    assert_match(/Validating cross-references\.\.\.done!/, output.first)
  end

  def test_self_referential_cross_reference
    recipe = make_recipe("# Loopy\n\nCategory: Test\n\n## Step (do it)\n\n- @[Loopy]\n\nDo.", id: 'loopy')
    validator = build_validator(recipes: [recipe])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_three_way_circular_reference
    a = make_recipe("# Recipe A\n\nCategory: Test\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo.", id: 'recipe-a')
    b = make_recipe("# Recipe B\n\nCategory: Test\n\n## Step (do it)\n\n- @[Recipe C]\n\nDo.", id: 'recipe-b')
    c = make_recipe("# Recipe C\n\nCategory: Test\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo.", id: 'recipe-c')
    validator = build_validator(recipes: [a, b, c])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_validate_ingredients_warns_on_unknown
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Flour, 500 g\n- Unicorn dust\n\nMix."
    recipe = make_recipe(md, id: 'test-recipe')
    IngredientCatalog.find_or_create_by!(ingredient_name: 'Flour', kitchen_id: nil) do |p|
      p.basis_grams = 30
      p.calories = 110
    end
    validator = build_validator(recipes: [recipe])

    output = capture_io { validator.validate_ingredients }

    assert_match(/Unicorn dust/, output.first)
  end

  def test_validate_ingredients_passes_when_all_known
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Flour, 500 g\n- Salt\n\nMix."
    recipe = make_recipe(md, id: 'test-recipe')
    IngredientCatalog.find_or_create_by!(ingredient_name: 'Flour', kitchen_id: nil) do |p|
      p.basis_grams = 30
      p.calories = 110
    end
    IngredientCatalog.find_or_create_by!(ingredient_name: 'Salt', kitchen_id: nil) do |p|
      p.basis_grams = 6
      p.calories = 0
    end
    validator = build_validator(recipes: [recipe])

    output = capture_io { validator.validate_ingredients }

    assert_match(/All ingredients validated/, output.first)
  end

  def test_validate_nutrition_warns_on_missing_data
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix."
    recipe = make_recipe(md, id: 'test-recipe')
    nutrition_data = {}
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
    validator = build_validator(recipes: [recipe], nutrition_calculator: calculator)

    output = capture_io { validator.validate_nutrition }

    assert_match(/Missing nutrition data/, output.first)
    assert_match(/Flour/, output.first)
  end

  def test_validate_nutrition_passes_when_complete
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix."
    recipe = make_recipe(md, id: 'test-recipe')
    nutrition_data = {
      'Flour' => {
        'nutrients' => { 'basis_grams' => 30.0, 'calories' => 110.0 },
        'density' => { 'grams' => 30.0, 'volume' => 0.25, 'unit' => 'cup' }
      }
    }
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
    validator = build_validator(recipes: [recipe], nutrition_calculator: calculator)

    output = capture_io { validator.validate_nutrition }

    assert_match(/All ingredients have nutrition data/, output.first)
  end

  def test_validate_ingredients_matches_plural_variant
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Egg, 2\n\nScramble."
    recipe = make_recipe(md, id: 'test-recipe')
    IngredientCatalog.find_or_create_by!(ingredient_name: 'Eggs', kitchen_id: nil) do |p|
      p.basis_grams = 50
      p.calories = 70
    end
    validator = build_validator(recipes: [recipe])

    output = capture_io { validator.validate_ingredients }

    assert_match(/All ingredients validated/, output.first)
  end

  def test_validate_ingredients_matches_singular_variant
    md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Carrots, 3\n\nChop."
    recipe = make_recipe(md, id: 'test-recipe')
    IngredientCatalog.find_or_create_by!(ingredient_name: 'Carrot', kitchen_id: nil) do |p|
      p.basis_grams = 50
      p.calories = 25
    end
    validator = build_validator(recipes: [recipe])

    output = capture_io { validator.validate_ingredients }

    assert_match(/All ingredients validated/, output.first)
  end

  private

  def make_recipe(markdown, id: 'test-recipe')
    FamilyRecipes::Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  def build_validator(recipes: [], quick_bites: [], nutrition_calculator: nil)
    recipe_map = recipes.index_by(&:id)
    FamilyRecipes::BuildValidator.new(
      recipes: recipes,
      quick_bites: quick_bites,
      recipe_map: recipe_map,
      nutrition_calculator: nutrition_calculator
    )
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

class BuildValidatorTest < Minitest::Test
  def test_detects_unresolved_cross_reference
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead.", id: 'pizza-dough')
    pizza_md = "# Test Pizza\n\n## Dough (make dough)\n\n- @[Nonexistent Recipe]\n\nStretch."
    pizza = make_recipe(pizza_md, id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Unresolved cross-reference/, error.message)
    assert_match(/Nonexistent Recipe/, error.message)
  end

  def test_detects_circular_reference
    a = make_recipe("# Recipe A\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo.", id: 'recipe-a')
    b = make_recipe("# Recipe B\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo.", id: 'recipe-b')
    validator = build_validator(recipes: [a, b])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_detects_title_filename_mismatch
    recipe = make_recipe("# Actual Title\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix.", id: 'wrong-slug')
    validator = build_validator(recipes: [recipe])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(%r{Title/filename mismatch}, error.message)
  end

  def test_valid_cross_references_pass
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead.", id: 'pizza-dough')
    pizza = make_recipe("# Test Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n\nStretch.", id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    validator.validate_cross_references
  end

  def test_self_referential_cross_reference
    recipe = make_recipe("# Loopy\n\n## Step (do it)\n\n- @[Loopy]\n\nDo.", id: 'loopy')
    validator = build_validator(recipes: [recipe])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_three_way_circular_reference
    a = make_recipe("# Recipe A\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo.", id: 'recipe-a')
    b = make_recipe("# Recipe B\n\n## Step (do it)\n\n- @[Recipe C]\n\nDo.", id: 'recipe-b')
    c = make_recipe("# Recipe C\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo.", id: 'recipe-c')
    validator = build_validator(recipes: [a, b, c])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_validate_ingredients_warns_on_unknown
    md = "# Test Recipe\n\n## Step (do it)\n\n- Flour, 500 g\n- Unicorn dust\n\nMix."
    recipe = make_recipe(md, id: 'test-recipe')
    validator = build_validator(recipes: [recipe], known_ingredients: Set.new(%w[flour]))

    output = capture_io { validator.validate_ingredients }

    assert_match(/Unicorn dust/, output.first)
  end

  def test_validate_ingredients_passes_when_all_known
    recipe = make_recipe("# Test Recipe\n\n## Step (do it)\n\n- Flour, 500 g\n- Salt\n\nMix.", id: 'test-recipe')
    validator = build_validator(recipes: [recipe], known_ingredients: Set.new(%w[flour salt]))

    output = capture_io { validator.validate_ingredients }

    assert_match(/All ingredients validated/, output.first)
  end

  def test_validate_nutrition_warns_on_missing_data
    recipe = make_recipe("# Test Recipe\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix.", id: 'test-recipe')
    nutrition_data = {}
    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
    validator = build_validator(recipes: [recipe], nutrition_calculator: calculator)

    output = capture_io { validator.validate_nutrition }

    assert_match(/Missing nutrition data/, output.first)
    assert_match(/Flour/, output.first)
  end

  def test_validate_nutrition_passes_when_complete
    recipe = make_recipe("# Test Recipe\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix.", id: 'test-recipe')
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

  private

  def make_recipe(markdown, id: 'test-recipe')
    Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  def build_validator(recipes: [], quick_bites: [], known_ingredients: Set.new,
                      nutrition_calculator: nil)
    recipe_map = recipes.to_h { |r| [r.id, r] }
    FamilyRecipes::BuildValidator.new(
      recipes: recipes,
      quick_bites: quick_bites,
      recipe_map: recipe_map,
      alias_map: {},
      known_ingredients: known_ingredients,
      omit_set: Set.new,
      nutrition_calculator: nutrition_calculator
    )
  end
end

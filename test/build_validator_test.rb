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

  private

  def make_recipe(markdown, id: 'test-recipe')
    Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  def build_validator(recipes: [], quick_bites: [])
    recipe_map = recipes.to_h { |r| [r.id, r] }
    FamilyRecipes::BuildValidator.new(
      recipes: recipes,
      quick_bites: quick_bites,
      recipe_map: recipe_map,
      alias_map: {},
      known_ingredients: Set.new,
      omit_set: Set.new,
      nutrition_calculator: nil
    )
  end
end

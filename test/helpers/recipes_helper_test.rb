# frozen_string_literal: true

require 'test_helper'

class RecipesHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    setup_test_kitchen
  end

  test 'format_makes returns formatted string with whole quantity' do
    recipe = Recipe.new(makes_quantity: 30.0, makes_unit_noun: 'cookies')

    assert_equal '30 cookies', format_makes(recipe)
  end

  test 'format_makes returns formatted string with decimal quantity' do
    recipe = Recipe.new(makes_quantity: 1.5, makes_unit_noun: 'loaves')

    assert_equal '1.5 loaves', format_makes(recipe)
  end

  test 'format_makes returns nil when makes_quantity is nil' do
    recipe = Recipe.new(makes_quantity: nil)

    assert_nil format_makes(recipe)
  end

  test 'serving_size_text with makes and serves' do
    nutrition = {
      'serving_count' => 4, 'makes_quantity' => 8,
      'makes_unit_singular' => 'taco', 'makes_unit_plural' => 'tacos',
      'units_per_serving' => 2.0, 'total_weight_grams' => 592.0
    }

    assert_equal '2 tacos (148 g)', serving_size_text(nutrition)
  end

  test 'serving_size_text with makes only (no serves)' do
    nutrition = {
      'serving_count' => 12, 'makes_quantity' => 12,
      'makes_unit_singular' => 'pancake', 'makes_unit_plural' => 'pancakes',
      'units_per_serving' => nil, 'total_weight_grams' => 600.0
    }

    assert_equal '1 pancake (50 g)', serving_size_text(nutrition)
  end

  test 'serving_size_text with serves only (no makes)' do
    nutrition = {
      'serving_count' => 4, 'makes_quantity' => nil,
      'total_weight_grams' => 400.0
    }

    result = serving_size_text(nutrition)

    assert_includes result, '100 g'
  end

  test 'serving_size_text with neither makes nor serves' do
    nutrition = {
      'serving_count' => nil, 'makes_quantity' => nil,
      'total_weight_grams' => 300.0
    }

    result = serving_size_text(nutrition)

    assert_includes result, '300 g'
  end

  test 'servings_per_recipe_text with serving count' do
    assert_equal '4 servings per recipe', servings_per_recipe_text({ 'serving_count' => 4 })
  end

  test 'servings_per_recipe_text without serving count' do
    assert_equal '1 serving per recipe', servings_per_recipe_text({ 'serving_count' => nil })
  end

  test 'serving_size_text without weight shows unit only' do
    nutrition = {
      'serving_count' => 4, 'makes_quantity' => 8,
      'makes_unit_singular' => 'taco', 'makes_unit_plural' => 'tacos',
      'units_per_serving' => 2.0, 'total_weight_grams' => nil
    }

    assert_equal '2 tacos', serving_size_text(nutrition)
  end

  test 'percent_daily_value for fat' do
    assert_equal 13, percent_daily_value(:fat, 10.0)
  end

  test 'percent_daily_value for nutrient with no daily value' do
    assert_nil percent_daily_value(:trans_fat, 5.0)
  end

  test 'percent_daily_value rounds to nearest integer' do
    assert_equal 100, percent_daily_value(:sodium, 2300.0)
  end

  test 'scaled_quantity_display does not scale freeform quantity' do
    item = Ingredient.new(name: 'Basil', quantity: 'a few', unit: 'leaves', position: 0)

    result = scaled_quantity_display(item, 2.0)

    assert_equal 'a few leaves', result
  end

  test 'linkify_recipe_references converts @[Title] to link' do
    html = '<p>Try the @[Simple Tomato Sauce] next.</p>'
    result = linkify_recipe_references(html)

    assert_includes result, '<a href='
    assert_includes result, 'simple-tomato-sauce'
    assert_includes result, '>Simple Tomato Sauce</a>'
  end

  test 'linkify_recipe_references handles multiple references' do
    html = '<p>See @[Pizza Dough] and @[Tomato Sauce].</p>'
    result = linkify_recipe_references(html)

    assert_includes result, 'pizza-dough'
    assert_includes result, 'tomato-sauce'
  end

  test 'linkify_recipe_references ignores @[Title] inside code tags' do
    html = '<p>Use <code>@[Recipe Title]</code> syntax.</p>'
    result = linkify_recipe_references(html)

    assert_not_includes result, '<a href='
  end

  test 'linkify_recipe_references with no references returns unchanged html' do
    html = '<p>Just regular text.</p>'

    assert_equal html, linkify_recipe_references(html)
  end

  test 'linkify_recipe_references uses non-greedy match for brackets' do
    html = '<p>@[First] and @[Second]</p>'
    result = linkify_recipe_references(html)

    assert_includes result, '>First</a>'
    assert_includes result, '>Second</a>'
  end

  test 'render_markdown linkifies recipe references in footer text' do
    text = 'See also @[Pizza Dough].'
    result = render_markdown(text)

    assert_includes result, 'pizza-dough'
    assert_includes result, '>Pizza Dough</a>'
  end

  test 'scalable_instructions linkifies recipe references in prose' do
    text = 'Use the @[Simple Tomato Sauce] from yesterday.'
    result = scalable_instructions(text)

    assert_includes result, 'simple-tomato-sauce'
    assert_includes result, '>Simple Tomato Sauce</a>'
  end

  test 'ingredient_data_attrs emits quantity-low for non-range' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
    attrs = ingredient_data_attrs(ingredient)

    assert_includes attrs, 'data-quantity-low'
    assert_not_includes attrs, 'data-quantity-high'
  end

  test 'ingredient_data_attrs emits both low and high for range' do
    ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)
    attrs = ingredient_data_attrs(ingredient)

    assert_includes attrs, 'data-quantity-low'
    assert_includes attrs, 'data-quantity-high'
  end

  test 'ingredient_data_attrs pre-multiplies by scale_factor' do
    ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)
    attrs = ingredient_data_attrs(ingredient, scale_factor: 2.0)

    assert_includes attrs, '4.0'
    assert_includes attrs, '6.0'
  end

  test 'ingredient_data_attrs returns empty for non-numeric' do
    ingredient = Ingredient.new(name: 'Salt', quantity: 'a pinch')
    attrs = ingredient_data_attrs(ingredient)

    assert_not_includes attrs, 'data-quantity-low'
  end

  test 'scaled_quantity_display for range at 1x shows quantity_display' do
    ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)

    assert_equal ingredient.quantity_display, scaled_quantity_display(ingredient, 1.0)
  end

  test 'scaled_quantity_display for range at 2x' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, quantity_high: 3.0, unit: 'cup')
    display = scaled_quantity_display(ingredient, 2.0)

    assert_equal "4\u20136 cups", display
  end

  test 'scaled_quantity_display for non-range at 2x' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
    display = scaled_quantity_display(ingredient, 2.0)

    assert_equal '4 cups', display
  end

  test 'scaled_quantity_display for non-numeric returns quantity_display' do
    ingredient = Ingredient.new(name: 'Salt', quantity: 'a pinch')
    display = scaled_quantity_display(ingredient, 2.0)

    assert_equal 'a pinch', display
  end

  test 'ingredient_data_attrs includes title for resolved ingredient' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
    info = {
      'ingredient_details' => {
        'flour' => {
          'nutrients_per_gram' => {
            'calories' => 3.64, 'protein' => 0.1033, 'fat' => 0.0098,
            'carbs' => 0.7631, 'sodium' => 0.02, 'fiber' => 0.027
          },
          'grams_per_unit' => { 'cup' => 125.0 }
        }
      },
      'missing_ingredients' => [],
      'partial_ingredients' => []
    }
    attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

    assert_includes attrs, 'title='
    assert_includes attrs, '250g'
    assert_includes attrs, 'Cal 910'
    assert_includes attrs, 'based on original quantities'
  end

  test 'ingredient_data_attrs title for missing ingredient' do
    ingredient = Ingredient.new(name: 'Unicorn dust', quantity_low: 1.0, unit: 'cup')
    info = {
      'ingredient_details' => {},
      'missing_ingredients' => ['Unicorn dust'],
      'partial_ingredients' => []
    }
    attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

    assert_includes attrs, 'Not in ingredient catalog'
  end

  test 'ingredient_data_attrs title for partial ingredient' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'bushel')
    info = {
      'ingredient_details' => {},
      'missing_ingredients' => [],
      'partial_ingredients' => ['Flour']
    }
    attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

    assert_includes attrs, 'can&#39;t convert this unit'
  end

  test 'ingredient_data_attrs omits title when ingredient_info is nil' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
    attrs = ingredient_data_attrs(ingredient)

    assert_not_includes attrs, 'title='
  end

  test 'ingredient_data_attrs omits title for skipped ingredient' do
    ingredient = Ingredient.new(name: 'Olive oil', quantity: nil)
    info = {
      'ingredient_details' => {},
      'missing_ingredients' => [],
      'partial_ingredients' => []
    }
    attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

    assert_not_includes attrs, 'title='
  end

  test 'ingredient_data_attrs title omits conversion line when unit is grams' do
    ingredient = Ingredient.new(name: 'Flour', quantity_low: 500.0, unit: 'g')
    info = {
      'ingredient_details' => {
        'flour' => {
          'nutrients_per_gram' => {
            'calories' => 3.64, 'protein' => 0.1033, 'fat' => 0.0098,
            'carbs' => 0.7631, 'sodium' => 0.02, 'fiber' => 0.027
          },
          'grams_per_unit' => { 'g' => 1.0 }
        }
      },
      'missing_ingredients' => [],
      'partial_ingredients' => []
    }
    attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

    assert_not_includes attrs, "\u2192"
    assert_includes attrs, 'Cal 1820'
    assert_includes attrs, 'based on original quantities'
  end
end

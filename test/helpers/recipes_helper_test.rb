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

  test 'format_quantity_display shows freeform quantity verbatim' do
    item = Ingredient.new(name: 'Basil', quantity: 'a few', unit: 'leaves', position: 0)

    result = format_quantity_display(item)

    assert_equal 'a few leaves', result
  end

  test 'scaled_quantity_display does not scale freeform quantity' do
    item = Ingredient.new(name: 'Basil', quantity: 'a few', unit: 'leaves', position: 0)

    result = scaled_quantity_display(item, 2.0)

    assert_equal 'a few leaves', result
  end
end

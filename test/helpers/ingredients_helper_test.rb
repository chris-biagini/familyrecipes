# frozen_string_literal: true

require 'test_helper'

class IngredientsHelperTest < ActionView::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'nutrition_summary formats key macros from entry' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110, fat: 0.5, carbs: 23, protein: 3,
      saturated_fat: 0, trans_fat: 0, cholesterol: 0, sodium: 5,
      fiber: 1, total_sugars: 0, added_sugars: 0
    )

    assert_equal '110 cal · 0.5g fat · 23g carbs · 3g protein', nutrition_summary(entry)
  end

  test 'nutrition_summary returns nil for nil entry' do
    assert_nil nutrition_summary(nil)
  end

  test 'nutrition_summary returns nil when basis_grams is nil' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: @kitchen,
      basis_grams: nil, aisle: 'Baking'
    )

    assert_nil nutrition_summary(entry)
  end

  test 'density_summary formats volume-to-weight relationship' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110,
      density_grams: 120, density_volume: 1, density_unit: 'cup'
    )

    assert_equal '1 cup = 120g', density_summary(entry)
  end

  test 'density_summary returns nil when no density data' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Salt', kitchen: nil,
      basis_grams: 6, calories: 0
    )

    assert_nil density_summary(entry)
  end

  test 'portions_summary formats portions including each for unitless' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Eggs', kitchen: nil,
      basis_grams: 50, calories: 70,
      portions: { '~unitless' => 50, 'stick' => 113 }
    )

    result = portions_summary(entry)

    assert_includes result, '1 each = 50g'
    assert_includes result, '1 stick = 113g'
  end

  test 'portions_summary returns nil when no portions' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Salt', kitchen: nil,
      basis_grams: 6, calories: 0, portions: {}
    )

    assert_nil portions_summary(entry)
  end

  test 'ingredient_status returns complete when nutrition and density present' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110,
      density_grams: 120, density_volume: 1, density_unit: 'cup'
    )

    assert_equal :complete, ingredient_status(entry)
  end

  test 'ingredient_status returns missing when entry nil' do
    assert_equal :missing, ingredient_status(nil)
  end

  test 'ingredient_status returns needs_nutrition when no basis_grams' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: @kitchen,
      basis_grams: nil, aisle: 'Baking'
    )

    assert_equal :needs_nutrition, ingredient_status(entry)
  end

  test 'ingredient_status returns needs_density when nutrition but no density' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110
    )

    assert_equal :needs_density, ingredient_status(entry)
  end

  test 'format_nutrient_value omits trailing zeros' do
    assert_equal '110', format_nutrient_value(110.0)
    assert_equal '0.5', format_nutrient_value(0.5)
    assert_equal '0', format_nutrient_value(0.0)
  end
end

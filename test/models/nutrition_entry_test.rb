# frozen_string_literal: true

require 'test_helper'

class NutritionEntryTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'stores nutrient data for an ingredient' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      calories: 110.0,
      fat: 0.5,
      saturated_fat: 0.0,
      trans_fat: 0.0,
      cholesterol: 0.0,
      sodium: 0.0,
      carbs: 23.0,
      fiber: 1.0,
      total_sugars: 0.0,
      added_sugars: 0.0,
      protein: 3.0
    )

    entry.reload

    assert_equal 'Flour (all-purpose)', entry.ingredient_name
    assert_in_delta 30.0, entry.basis_grams.to_f
    assert_in_delta 110.0, entry.calories.to_f
    assert_in_delta 0.5, entry.fat.to_f
    assert_in_delta 23.0, entry.carbs.to_f
    assert_in_delta 1.0, entry.fiber.to_f
    assert_in_delta 3.0, entry.protein.to_f
  end

  test 'stores zero-value nutrients correctly' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      saturated_fat: 0.0,
      trans_fat: 0.0,
      cholesterol: 0.0,
      sodium: 0.0,
      total_sugars: 0.0,
      added_sugars: 0.0
    )

    entry.reload

    assert_in_delta 0.0, entry.saturated_fat.to_f
    assert_in_delta 0.0, entry.trans_fat.to_f
    assert_in_delta 0.0, entry.cholesterol.to_f
    assert_in_delta 0.0, entry.sodium.to_f
    assert_in_delta 0.0, entry.total_sugars.to_f
    assert_in_delta 0.0, entry.added_sugars.to_f
  end

  test 'enforces unique ingredient_name per kitchen' do
    NutritionEntry.create!(
      ingredient_name: 'Salt',
      basis_grams: 6.0,
      sodium: 2360.0
    )

    duplicate = NutritionEntry.new(
      ingredient_name: 'Salt',
      basis_grams: 6.0,
      sodium: 2360.0
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ingredient_name], 'has already been taken'
  end

  test 'stores density data' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      density_grams: 30.0,
      density_volume: 0.25,
      density_unit: 'cup'
    )

    entry.reload

    assert_in_delta 30.0, entry.density_grams.to_f
    assert_in_delta 0.25, entry.density_volume.to_f
    assert_equal 'cup', entry.density_unit
  end

  test 'stores portions as JSON' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Butter',
      basis_grams: 14.0,
      portions: { 'stick' => 113.0 }
    )

    entry.reload

    assert_equal({ 'stick' => 113.0 }, entry.portions)
  end

  test 'stores sources as JSON array' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Cream cheese',
      basis_grams: 28.0,
      sources: [{ 'type' => 'usda', 'fdc_id' => 173_530 }]
    )

    entry.reload

    assert_equal [{ 'type' => 'usda', 'fdc_id' => 173_530 }], entry.sources
  end

  test 'requires ingredient_name' do
    entry = NutritionEntry.new(basis_grams: 30.0)

    assert_not entry.valid?
    assert_includes entry.errors[:ingredient_name], "can't be blank"
  end

  test 'requires basis_grams' do
    entry = NutritionEntry.new(ingredient_name: 'Flour')

    assert_not entry.valid?
    assert_includes entry.errors[:basis_grams], "can't be blank"
  end

  test 'requires basis_grams to be greater than zero' do
    entry = NutritionEntry.new(ingredient_name: 'Flour', basis_grams: 0)

    assert_not entry.valid?
    assert_includes entry.errors[:basis_grams], 'must be greater than 0'
  end

  test 'belongs to kitchen' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Sugar',
      basis_grams: 4.0
    )

    assert_equal @kitchen, entry.kitchen
  end
end

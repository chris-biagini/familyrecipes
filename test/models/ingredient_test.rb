# frozen_string_literal: true

require 'test_helper'

class IngredientModelTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.find_or_create_by!(name: 'Test', slug: 'test')
    @recipe = Recipe.find_or_create_by!(
      title: 'Test Recipe', slug: 'test-recipe',
      category: @category, markdown_source: "# Test\n\nCategory: Test\n\n## Step\n\n- Flour\n\nMix."
    )
    @step = @recipe.steps.find_or_create_by!(title: 'Step', position: 1)
  end

  # --- validations ---

  test 'requires name' do
    ingredient = Ingredient.new(step: @step, position: 1)

    assert_not ingredient.valid?
    assert_includes ingredient.errors[:name], "can't be blank"
  end

  test 'requires position' do
    ingredient = Ingredient.new(step: @step, name: 'Flour')

    assert_not ingredient.valid?
    assert_includes ingredient.errors[:position], "can't be blank"
  end

  test 'valid with name and position' do
    ingredient = Ingredient.new(step: @step, name: 'Flour', position: 1)

    assert_predicate ingredient, :valid?
  end

  # --- quantity_display ---

  test 'quantity_display joins quantity and unit' do
    ingredient = Ingredient.new(step: @step, name: 'Flour', quantity: '2', unit: 'cups', position: 1)

    assert_equal '2 cups', ingredient.quantity_display
  end

  test 'quantity_display with quantity only' do
    ingredient = Ingredient.new(step: @step, name: 'Eggs', quantity: '4', position: 1)

    assert_equal '4', ingredient.quantity_display
  end

  test 'quantity_display with unit only' do
    ingredient = Ingredient.new(step: @step, name: 'Salt', unit: 'pinch', position: 1)

    assert_equal 'pinch', ingredient.quantity_display
  end

  test 'quantity_display returns nil when both are blank' do
    ingredient = Ingredient.new(step: @step, name: 'Salt', position: 1)

    assert_nil ingredient.quantity_display
  end

  # --- quantity_value ---

  test 'quantity_value for simple integer' do
    ingredient = Ingredient.new(step: @step, name: 'Eggs', quantity: '4', position: 1)

    assert_equal '4', ingredient.quantity_value
  end

  test 'quantity_value for decimal' do
    ingredient = Ingredient.new(step: @step, name: 'Salt', quantity: '3.5', unit: 'g', position: 1)

    assert_equal '3.5', ingredient.quantity_value
  end

  test 'quantity_value for fraction' do
    ingredient = Ingredient.new(step: @step, name: 'Butter', quantity: '1/2', unit: 'cup', position: 1)

    assert_equal '0.5', ingredient.quantity_value
  end

  test 'quantity_value returns nil when quantity is nil' do
    ingredient = Ingredient.new(step: @step, name: 'Salt', position: 1)

    assert_nil ingredient.quantity_value
  end

  # --- quantity_unit ---

  test 'quantity_unit normalizes unit' do
    ingredient = Ingredient.new(step: @step, name: 'Flour', quantity: '2', unit: 'cups', position: 1)

    assert_equal 'cup', ingredient.quantity_unit
  end

  test 'quantity_unit normalizes tablespoons' do
    ingredient = Ingredient.new(step: @step, name: 'Oil', quantity: '2', unit: 'tablespoons', position: 1)

    assert_equal 'tbsp', ingredient.quantity_unit
  end

  test 'quantity_unit returns nil when unit is nil' do
    ingredient = Ingredient.new(step: @step, name: 'Eggs', quantity: '4', position: 1)

    assert_nil ingredient.quantity_unit
  end

  # --- prep_note ---

  test 'stores optional prep_note' do
    ingredient = Ingredient.create!(
      step: @step, name: 'Garlic', quantity: '3', unit: 'cloves',
      prep_note: 'minced', position: 1
    )

    assert_equal 'minced', ingredient.reload.prep_note
  end
end

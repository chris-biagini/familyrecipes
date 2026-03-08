# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class CatalogWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  VALID_NUTRIENTS = { basis_grams: '30', calories: '110', fat: '0.5', saturated_fat: '0',
                      trans_fat: '0', cholesterol: '0', sodium: '5', carbs: '23',
                      fiber: '1', total_sugars: '0', added_sugars: '0', protein: '3' }.freeze

  setup do
    setup_test_kitchen
    setup_test_category
    IngredientCatalog.where(kitchen: @kitchen).delete_all
  end

  # --- upsert creates ---

  test 'upsert creates kitchen-scoped entry and returns persisted result' do
    result = upsert_entry('flour', nutrients: VALID_NUTRIENTS, aisle: 'Baking')

    assert_instance_of CatalogWriteService::Result, result
    assert_predicate result, :persisted

    entry = result.entry

    assert_equal @kitchen, entry.kitchen
    assert_equal 'flour', entry.ingredient_name
    assert_in_delta 30.0, entry.basis_grams
    assert_in_delta 110.0, entry.calories
    assert_equal 'Baking', entry.aisle
  end

  test 'upsert updates existing entry' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour',
                              basis_grams: 100, calories: 364)

    result = upsert_entry('flour', nutrients: VALID_NUTRIENTS, aisle: 'Baking')

    assert_predicate result, :persisted
    assert_in_delta 30.0, result.entry.basis_grams
    assert_in_delta 110.0, result.entry.calories
    assert_equal 1, IngredientCatalog.where(kitchen: @kitchen, ingredient_name: 'flour').size
  end

  test 'upsert returns non-persisted result on validation failure' do
    bad_nutrients = { basis_grams: '0', calories: '100' }

    result = upsert_entry('flour', nutrients: bad_nutrients)

    assert_not result.persisted
    assert_predicate result.entry.errors, :any?
  end

  # --- upsert aisle sync ---

  test 'upsert syncs new aisle to kitchen aisle_order' do
    @kitchen.update!(aisle_order: 'Produce')

    upsert_entry('flour', nutrients: {}, aisle: 'Baking')

    assert_includes @kitchen.reload.parsed_aisle_order, 'Baking'
  end

  test 'upsert does not sync omit aisle' do
    @kitchen.update!(aisle_order: 'Produce')

    upsert_entry('flour', nutrients: {}, aisle: 'omit')

    assert_not_includes @kitchen.reload.parsed_aisle_order, 'omit'
  end

  test 'upsert does not duplicate existing aisle' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    upsert_entry('flour', nutrients: {}, aisle: 'Baking')

    assert_equal 1, @kitchen.reload.parsed_aisle_order.count('Baking')
  end

  test 'upsert does not add case-duplicate aisle' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    upsert_entry('flour', nutrients: {}, aisle: 'baking')

    assert_equal %w[Produce Baking], @kitchen.reload.parsed_aisle_order
  end

  # --- upsert nutrition recalculation ---

  test 'upsert recalculates affected recipes when nutrition present' do
    create_catalog_entry('flour', basis_grams: 100, calories: 364, aisle: 'Baking')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bread


      ## Mix (combine)

      - flour, 200 g

      Stir together.
    MD

    recipe = @kitchen.recipes.find_by!(slug: 'bread')
    recipe.update_column(:nutrition_data, nil) # rubocop:disable Rails/SkipsModelValidations

    upsert_entry('flour', nutrients: VALID_NUTRIENTS, aisle: 'Baking')

    assert_not_nil recipe.reload.nutrition_data
  end

  test 'upsert recalculates recipes using inflector variants of ingredient name' do
    create_catalog_entry('Eggs', basis_grams: 50, calories: 78, aisle: 'Dairy')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Omelette


      ## Cook (combine)

      - Egg, 3

      Cook gently.
    MD

    recipe = @kitchen.recipes.find_by!(slug: 'omelette')
    recipe.update_column(:nutrition_data, nil) # rubocop:disable Rails/SkipsModelValidations

    upsert_entry('Eggs', nutrients: VALID_NUTRIENTS, aisle: 'Dairy')

    assert_not_nil recipe.reload.nutrition_data
  end

  # --- upsert broadcasting ---

  test 'upsert broadcasts meal plan refresh when aisle present' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      upsert_entry('flour', nutrients: {}, aisle: 'Baking')
    end
  end

  # --- alias collision validation ---

  test 'upsert rejects alias that matches another canonical name' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

    result = upsert_entry('Ghee', aliases: ['Butter'])

    assert_not result.persisted
    assert(result.entry.errors.full_messages.any? { |m| m.include?('Butter') })
  end

  test 'upsert rejects alias that matches another canonical name case-insensitively' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

    result = upsert_entry('Ghee', aliases: ['butter'])

    assert_not result.persisted
    assert(result.entry.errors.full_messages.any? { |m| m.include?('butter') })
  end

  test 'upsert rejects alias that collides with another entry alias' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Salt (Table)',
                              aisle: 'Baking', aliases: ['Kosher salt'])

    result = upsert_entry('Salt (Kosher)', aliases: ['Kosher salt'])

    assert_not result.persisted
    assert(result.entry.errors.full_messages.any? { |m| m.include?('Kosher salt') })
  end

  test 'upsert allows non-colliding aliases' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Butter', aisle: 'Dairy')

    result = upsert_entry('Ghee', aliases: ['Clarified butter'])

    assert_predicate result, :persisted
    assert_equal ['Clarified butter'], result.entry.aliases
  end

  # --- destroy ---

  test 'destroy deletes kitchen entry' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour',
                              basis_grams: 100, calories: 364)

    result = CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')

    assert_predicate result, :persisted
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')
  end

  test 'destroy recalculates affected recipes using global fallback' do
    IngredientCatalog.where(ingredient_name: 'flour').delete_all
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'flour',
                              basis_grams: 100, calories: 364, aisle: 'Baking')
    override = IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour',
                                         basis_grams: 50, calories: 180)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bread


      ## Mix (combine)

      - flour, 200 g

      Stir together.
    MD

    recipe = @kitchen.recipes.find_by!(slug: 'bread')

    CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')

    assert_nil IngredientCatalog.find_by(id: override.id)
    nutrition = recipe.reload.nutrition_data

    assert_not_nil nutrition
    # Global entry (364 cal per 100g) should be used after override is deleted
    assert_in_delta 728.0, nutrition['totals']['calories']
  end

  test 'destroy broadcasts meal plan refresh' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour',
                              basis_grams: 100, calories: 364)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')
    end
  end

  test 'destroy raises RecordNotFound for missing entry' do
    assert_raises(ActiveRecord::RecordNotFound) do
      CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'nonexistent')
    end
  end

  private

  def upsert_entry(name, nutrients: {}, density: {}, portions: {}, aisle: nil, aliases: nil) # rubocop:disable Metrics/ParameterLists
    CatalogWriteService.upsert( # rubocop:disable Rails/SkipsModelValidations
      kitchen: @kitchen, ingredient_name: name,
      params: { nutrients:, density:, portions:, aisle:, aliases: }
    )
  end
end

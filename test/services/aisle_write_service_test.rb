# frozen_string_literal: true

require 'test_helper'

class AisleWriteServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen: @kitchen).delete_all
  end

  # --- update_order: validation ---

  test 'update_order returns errors for too many aisles' do
    order = (1..51).map { |i| "Aisle #{i}" }.join("\n")

    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: order, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('Too many') })
  end

  test 'update_order returns errors for aisle name too long' do
    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: 'a' * 51, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('too long') })
  end

  test 'update_order returns errors for case-insensitive duplicates' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Produce\nproduce", renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('more than once') })
  end

  # --- update_order: saves and normalizes ---

  test 'update_order saves normalized aisle_order' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Produce\n  Baking\nProduce\n\nFrozen", renames: {}, deletes: []
    )

    assert result.success
    assert_equal "Produce\nBaking\nFrozen", @kitchen.reload.aisle_order
  end

  test 'update_order clears aisle_order when empty' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: '', renames: {}, deletes: [])

    assert result.success
    assert_nil @kitchen.reload.aisle_order
  end

  # --- update_order: cascade renames ---

  test 'update_order cascades renames to catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Fruits\nDairy",
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_order cascades renames case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: cascade deletes ---

  test 'update_order clears aisle from catalog entries on delete' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Dairy',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_order cascades deletes case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: '',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: renames + deletes together ---

  test 'update_order handles renames and deletes in one call' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bread', aisle: 'Bakery')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: ['Bakery']
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bread').aisle
  end

  # --- update_order: tenant isolation ---

  test 'update_order does not affect other kitchens' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: other_kitchen, ingredient_name: 'Apples', aisle: 'Produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Produce', IngredientCatalog.find_by(kitchen: other_kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: ignores nil/non-hash renames and non-array deletes ---

  test 'update_order tolerates nil renames and deletes' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Produce', renames: nil, deletes: nil
    )

    assert result.success
    assert_equal 'Produce', @kitchen.reload.aisle_order
  end
end

# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class AisleWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen: @kitchen).delete_all
  end

  # --- update: validation ---

  test 'update returns errors for too many aisles' do
    order = (1..51).map { |i| "Aisle #{i}" }.join("\n")

    result = AisleWriteService.update(kitchen: @kitchen, aisle_order: order, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('Too many') })
  end

  test 'update returns errors for aisle name too long' do
    result = AisleWriteService.update(kitchen: @kitchen, aisle_order: 'a' * 51, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('too long') })
  end

  test 'update returns errors for case-insensitive duplicates' do
    result = AisleWriteService.update(
      kitchen: @kitchen, aisle_order: "Produce\nproduce", renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('more than once') })
  end

  # --- update: saves and normalizes ---

  test 'update saves normalized aisle_order' do
    result = AisleWriteService.update(
      kitchen: @kitchen, aisle_order: "Produce\n  Baking\nProduce\n\nFrozen", renames: {}, deletes: []
    )

    assert result.success
    assert_equal "Produce\nBaking\nFrozen", @kitchen.reload.aisle_order
  end

  test 'update clears aisle_order when empty' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    result = AisleWriteService.update(kitchen: @kitchen, aisle_order: '', renames: {}, deletes: [])

    assert result.success
    assert_nil @kitchen.reload.aisle_order
  end

  # --- update: cascade renames ---

  test 'update cascades renames to catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: "Fruits\nDairy",
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update cascades renames case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update: cascade rename length validation ---

  test 'update rejects rename target exceeding MAX_AISLE_NAME_LENGTH' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    long_name = 'a' * (Mirepoix::NutritionConstraints::AISLE_MAX_LENGTH + 1)

    result = AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Produce',
      renames: { 'Produce' => long_name }, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('exceeds maximum length') })
  end

  # --- update: cascade deletes ---

  test 'update clears aisle from catalog entries on delete' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Dairy',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update cascades deletes case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: '',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update: renames + deletes together ---

  test 'update handles renames and deletes in one call' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bread', aisle: 'Bakery')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: ['Bakery']
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bread').aisle
  end

  # --- update: tenant isolation ---

  test 'update does not affect other kitchens' do
    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: other_kitchen, ingredient_name: 'Apples', aisle: 'Produce')

    AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Produce', IngredientCatalog.find_by(kitchen: other_kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update: ignores nil/non-hash renames and non-array deletes ---

  test 'update tolerates nil renames and deletes' do
    result = AisleWriteService.update(
      kitchen: @kitchen, aisle_order: 'Produce', renames: nil, deletes: nil
    )

    assert result.success
    assert_equal 'Produce', @kitchen.reload.aisle_order
  end

  # --- update: broadcasts ---

  test 'update broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      AisleWriteService.update(
        kitchen: @kitchen, aisle_order: 'Produce', renames: {}, deletes: []
      )
    end
  end

  test 'update does not broadcast on validation failure' do
    assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
      AisleWriteService.update(
        kitchen: @kitchen, aisle_order: 'a' * 51, renames: {}, deletes: []
      )
    end
  end

  # --- sync_new_aisles ---

  test 'sync_new_aisles appends single aisle to kitchen aisle_order' do
    @kitchen.update!(aisle_order: 'Produce')

    AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: ['Baking'])

    assert_includes @kitchen.reload.parsed_aisle_order, 'Baking'
  end

  test 'sync_new_aisles does not duplicate existing aisle' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: ['Baking'])

    assert_equal 1, @kitchen.reload.parsed_aisle_order.count('Baking')
  end

  test 'sync_new_aisles skips case-duplicate aisle' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: ['baking'])

    assert_equal %w[Produce Baking], @kitchen.reload.parsed_aisle_order
  end

  test 'sync_new_aisles appends multiple new aisles in one pass' do
    @kitchen.update!(aisle_order: 'Produce')

    AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: %w[Baking Dairy])

    order = @kitchen.reload.parsed_aisle_order

    assert_includes order, 'Baking'
    assert_includes order, 'Dairy'
    assert_includes order, 'Produce'
  end

  test 'sync_new_aisles skips duplicates' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: %w[Baking Dairy Dairy])

    order = @kitchen.reload.parsed_aisle_order

    assert_equal 1, order.count('Baking')
    assert_equal 1, order.count('Dairy')
    assert_includes order, 'Dairy'
  end
end

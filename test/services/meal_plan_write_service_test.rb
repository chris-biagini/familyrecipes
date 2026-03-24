# frozen_string_literal: true

require 'test_helper'

class MealPlanWriteServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category
    CustomGroceryItem.where(kitchen: @kitchen).delete_all
    OnHandEntry.where(kitchen: @kitchen).delete_all
    MealPlanSelection.where(kitchen: @kitchen).delete_all
    CookHistoryEntry.where(kitchen: @kitchen).delete_all
  end

  # --- select action ---

  test 'selecting a recipe creates a MealPlanSelection' do
    recipe = create_focaccia_recipe

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: true
    )

    assert_predicate result, :success
    assert MealPlanSelection.exists?(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: recipe.slug)
  end

  test 'deselecting a recipe destroys the MealPlanSelection' do
    recipe = create_focaccia_recipe
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: true
    )

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: false
    )

    assert_not MealPlanSelection.exists?(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: recipe.slug)
  end

  test 'deselecting a recipe records cook history' do
    recipe = create_focaccia_recipe
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: true
    )

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: false
    )

    entry = CookHistoryEntry.find_by(kitchen: @kitchen, recipe_slug: recipe.slug)

    assert_not_nil entry
    assert_in_delta Time.current, entry.cooked_at, 2
  end

  test 'selecting does not record cook history' do
    recipe = create_focaccia_recipe

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: recipe.slug, selected: true
    )

    assert_equal 0, CookHistoryEntry.where(kitchen: @kitchen).count
  end

  test 'deselecting a quick bite does not record cook history' do
    MealPlanSelection.toggle(kitchen: @kitchen, type: 'QuickBite', id: 'lunch-box', selected: true)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'quick_bite', slug: 'lunch-box', selected: false
    )

    assert_equal 0, CookHistoryEntry.where(kitchen: @kitchen).count
  end

  test 'apply_action calls finalize_writes' do
    finalized = false
    Kitchen.stub(:finalize_writes, ->(_k) { finalized = true }) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'check',
        item: 'flour', checked: true
      )
    end

    assert finalized
  end

  test 'apply_action defers finalization when batching' do
    broadcast_pending_during_batch = nil

    Kitchen.batch_writes(@kitchen) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'check',
        item: 'flour', checked: true
      )
      broadcast_pending_during_batch = Current.broadcast_pending
    end

    # During the batch, finalize_writes short-circuits so no broadcast is queued
    assert_nil broadcast_pending_during_batch
  end

  # --- check action ---

  test 'check creates OnHandEntry with starting values' do
    select_recipe_with_flour

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Flour', checked: true
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry
    assert_equal OnHandEntry::STARTING_INTERVAL, entry.interval
    assert_equal Date.current, entry.confirmed_at
    assert_nil entry.depleted_at
  end

  test 'check canonicalizes item name via IngredientResolver' do
    create_catalog_entry('Flour', aisle: 'Baking')
    select_recipe_with_flour

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'flour', checked: true
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry
    assert_equal 'Flour', entry.ingredient_name
  end

  test 'check sets null interval for custom items' do
    CustomGroceryItem.create!(kitchen: @kitchen, name: 'Birthday candles',
                              aisle: 'Miscellaneous', last_used_at: Date.current)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Birthday candles', checked: true
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Birthday candles')

    assert_nil entry.interval
  end

  test 'check detects custom items case-insensitively' do
    CustomGroceryItem.create!(kitchen: @kitchen, name: 'Paper Towels',
                              aisle: 'Miscellaneous', last_used_at: Date.current)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'paper towels', checked: true
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Paper Towels')

    assert_not_nil entry
    assert_nil entry.interval
  end

  test 'uncheck destroys OnHandEntry for custom items' do
    custom = CustomGroceryItem.create!(kitchen: @kitchen, name: 'Paper Towels',
                                       aisle: 'Miscellaneous', last_used_at: Date.current)
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Paper Towels',
                        confirmed_at: Date.current, interval: nil, ease: nil)
    custom.update!(on_hand_at: Date.current)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Paper Towels', checked: false
    )

    assert_not OnHandEntry.exists?(kitchen: @kitchen, ingredient_name: 'Paper Towels')
  end

  test 'uncheck depletes OnHandEntry for recipe items' do
    select_recipe_with_flour
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: 5.days.ago.to_date, interval: 7,
                        ease: OnHandEntry::STARTING_EASE)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'Flour', checked: false
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry.depleted_at
  end

  # --- custom items action ---

  test 'add custom item creates CustomGroceryItem' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'Paper Towels', action: 'add', aisle: 'Household'
    )

    assert_predicate result, :success

    item = CustomGroceryItem.find_by(kitchen: @kitchen, name: 'Paper Towels')

    assert_not_nil item
    assert_equal 'Household', item.aisle
    assert_equal Date.current, item.last_used_at
  end

  test 'remove custom item destroys CustomGroceryItem' do
    CustomGroceryItem.create!(kitchen: @kitchen, name: 'Paper Towels',
                              aisle: 'Household', last_used_at: Date.current)

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'Paper Towels', action: 'remove'
    )

    assert_predicate result, :success
    assert_not CustomGroceryItem.exists?(kitchen: @kitchen, name: 'Paper Towels')
  end

  test 'validates custom item length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 101, action: 'add'
    )

    assert_not_predicate result, :success
    assert_includes result.errors.first, 'too long'
    assert_equal 0, CustomGroceryItem.where(kitchen: @kitchen).count
  end

  test 'accepts custom item at max length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'custom_items',
      item: 'a' * 100, action: 'add'
    )

    assert_predicate result, :success
    assert CustomGroceryItem.exists?(kitchen: @kitchen, name: 'a' * 100)
  end

  # --- have_it action ---

  test 'have_it confirms item using canonical name' do
    create_catalog_entry('Flour', aisle: 'Baking')
    select_recipe_with_flour

    # Sentinel entry in Inventory Check — orphaned but not depleted
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.parse(OnHandEntry::ORPHAN_SENTINEL),
                        interval: 7, ease: OnHandEntry::STARTING_EASE,
                        orphaned_at: 1.day.ago.to_date)

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'have_it', item: 'flour'
    )

    assert_predicate result, :success

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry
    assert_equal Date.current, entry.confirmed_at
    assert_nil entry.orphaned_at
    assert_equal 'Flour', entry.ingredient_name
  end

  test 'have_it grows interval on confirmation' do
    create_catalog_entry('Flour', aisle: 'Baking')
    select_recipe_with_flour

    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.parse(OnHandEntry::ORPHAN_SENTINEL),
                        interval: 7, ease: OnHandEntry::STARTING_EASE)

    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'have_it', item: 'Flour'
    )

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_operator entry.interval, :>, 7
  end

  # --- need_it action ---

  test 'need_it puts item in depleted state using canonical name' do
    create_catalog_entry('Flour', aisle: 'Baking')
    select_recipe_with_flour

    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.current, interval: 7,
                        ease: OnHandEntry::STARTING_EASE)

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'need_it', item: 'flour'
    )

    assert_predicate result, :success

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry.depleted_at
    assert_equal 'Flour', entry.ingredient_name
  end

  # --- quick_add action ---

  test 'quick_add creates custom item for unrecognized ingredient' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'quick_add',
      item: 'Parchment paper', aisle: 'Household'
    )

    assert_predicate result, :success?
    assert_equal :added, result.status

    item = CustomGroceryItem.find_by(kitchen: @kitchen, name: 'Parchment paper')

    assert_not_nil item
    assert_equal 'Household', item.aisle
  end

  test 'quick_add moves active on-hand item to needed' do
    select_recipe_with_flour
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.current, interval: 7,
                        ease: OnHandEntry::STARTING_EASE)

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'quick_add', item: 'Flour'
    )

    assert_equal :moved_to_buy, result.status

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry.depleted_at
  end

  test 'quick_add returns already_needed for depleted visible items' do
    select_recipe_with_flour
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.parse(OnHandEntry::ORPHAN_SENTINEL),
                        depleted_at: 1.day.ago.to_date,
                        interval: 7, ease: OnHandEntry::STARTING_EASE)

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'quick_add', item: 'Flour'
    )

    assert_equal :already_needed, result.status
  end

  test 'quick_add marks visible non-on-hand item as depleted' do
    select_recipe_with_flour

    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'quick_add', item: 'Flour'
    )

    assert_equal :moved_to_buy, result.status

    entry = OnHandEntry.find_by(kitchen: @kitchen, ingredient_name: 'Flour')

    assert_not_nil entry
    assert_not_nil entry.depleted_at
  end

  test 'quick_add validates item length' do
    result = MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'quick_add',
      item: 'a' * 101
    )

    assert_not result.success
    assert_includes result.errors.first, 'too long'
  end

  test 'quick_add does not use recursive self-calls' do
    calls = []
    original = MealPlanWriteService.method(:new)

    MealPlanWriteService.stub(:new, lambda { |**kwargs|
      calls << true
      original.call(**kwargs)
    }) do
      MealPlanWriteService.apply_action(
        kitchen: @kitchen, action_type: 'quick_add',
        item: 'New thing', aisle: 'Miscellaneous'
      )
    end

    assert_equal 1, calls.size
  end

  private

  def select_recipe_with_flour
    create_focaccia_recipe
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'select',
      type: 'recipe', slug: 'focaccia', selected: true
    )
  end

  def create_focaccia_recipe
    create_recipe(<<~MD)
      # Focaccia

      ## Mix

      - Flour, 3 cups

      Mix well.
    MD
  end
end

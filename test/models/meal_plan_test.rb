# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
  end

  def reconcile_plan!(plan)
    visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end

  test 'belongs to kitchen' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal @kitchen, list.kitchen
  end

  test 'enforces one list per kitchen' do
    MealPlan.create!(kitchen: @kitchen)
    duplicate = MealPlan.new(kitchen: @kitchen)

    assert_not_predicate duplicate, :valid?
  end

  test 'defaults to version 0 and empty state' do
    list = MealPlan.create!(kitchen: @kitchen)

    assert_equal 0, list.lock_version
    assert_empty list.state
  end

  test 'for_kitchen finds or creates' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_predicate list, :persisted?
    assert_equal @kitchen, list.kitchen

    assert_equal list, MealPlan.for_kitchen(@kitchen)
  end

  test 'apply_action adds recipe to selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)

    assert_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action removes recipe from selected_recipes' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: false)

    assert_not_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action adds quick bite to selected_quick_bites' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)

    assert_includes list.state['selected_quick_bites'], 'nachos'
  end

  test 'apply_action checks off item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)

    assert_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action unchecks item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    list.apply_action('check', item: 'milk', checked: false)

    assert_not_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action adds custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    assert_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action removes custom item' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('custom_items', item: 'birthday candles', action: 'remove')

    assert_not_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action bumps version' do
    list = MealPlan.for_kitchen(@kitchen)
    old_version = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_operator list.lock_version, :>, old_version
  end

  test 'operations are idempotent' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    version_after_first = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_equal version_after_first, list.lock_version
  end

  test 'raises on unknown action types' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_raises(ArgumentError) { list.apply_action('bogus', foo: 'bar') }
  end

  test 'with_optimistic_retry retries on StaleObjectError' do
    list = MealPlan.for_kitchen(@kitchen)
    attempts = 0

    list.with_optimistic_retry do
      attempts += 1
      raise ActiveRecord::StaleObjectError, list if attempts == 1
    end

    assert_equal 2, attempts
  end

  test 'with_optimistic_retry raises after max attempts' do
    list = MealPlan.for_kitchen(@kitchen)

    assert_raises(ActiveRecord::StaleObjectError) do
      list.with_optimistic_retry(max_attempts: 2) do
        raise ActiveRecord::StaleObjectError, list
      end
    end
  end

  # --- reconcile! ---

  test 'reconcile! removes checked-off items not on shopping list' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Phantom Item', checked: true)

    reconcile_plan!(plan)
    plan.reload

    assert_empty plan.state['checked_off']
  end

  test 'reconcile! preserves checked-off items on shopping list' do
    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)
    plan.apply_action('check', item: 'Phantom', checked: true)

    reconcile_plan!(plan)
    plan.reload

    assert_includes plan.state['checked_off'], 'Flour'
    assert_not_includes plan.state['checked_off'], 'Phantom'
  end

  test 'reconcile! preserves custom items even when not in visible names' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
    plan.apply_action('check', item: 'birthday candles', checked: true)

    reconcile_plan!(plan)
    plan.reload

    assert_includes plan.state['checked_off'], 'birthday candles'
  end

  test 'reconcile! preserves custom items case-insensitively' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    plan.apply_action('check', item: 'birthday candles', checked: true)

    reconcile_plan!(plan)
    plan.reload

    assert_includes plan.state['checked_off'], 'birthday candles'
  end

  test 'reconcile! removes deleted recipe slugs from selections' do
    category = Category.find_or_create_by!(name: 'Test', slug: 'test', kitchen: @kitchen)
    MarkdownImporter.import("# Exists\n\n## Step (do it)\n\n- Flour, 1 cup\n\nDo it.\n", kitchen: @kitchen, category:)

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'exists', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'gone', selected: true)

    reconcile_plan!(plan)

    assert_includes plan.state['selected_recipes'], 'exists'
    assert_not_includes plan.state['selected_recipes'], 'gone'
  end

  test 'reconcile! removes deleted quick bite IDs from selections' do
    @kitchen.update!(quick_bites_content: "## Snacks\n- Nachos: Chips\n")

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'gone-bite', selected: true)

    reconcile_plan!(plan)

    assert_includes plan.state['selected_quick_bites'], 'nachos'
    assert_not_includes plan.state['selected_quick_bites'], 'gone-bite'
  end

  test 'reconcile! is idempotent when nothing to prune' do
    plan = MealPlan.for_kitchen(@kitchen)
    version_before = plan.lock_version

    reconcile_plan!(plan)

    assert_equal version_before, plan.reload.lock_version
  end

  test 'reconcile! saves when items are pruned' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('check', item: 'Phantom', checked: true)
    version_before = plan.lock_version

    reconcile_plan!(plan)

    assert_operator plan.lock_version, :>, version_before
  end

  # --- Case-insensitive custom items (issue #156) ---

  test 'adding custom item ignores case-insensitive duplicate' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Butter', action: 'add')
    list.apply_action('custom_items', item: 'butter', action: 'add')

    assert_equal ['Butter'], list.state['custom_items']
  end

  test 'removing custom item is case-insensitive' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Butter', action: 'add')
    list.apply_action('custom_items', item: 'butter', action: 'remove')

    assert_empty list.state['custom_items']
  end

  test 'checking off item is case-insensitive' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Milk', checked: true)
    list.apply_action('check', item: 'milk', checked: true)

    assert_equal ['Milk'], list.state['checked_off']
  end

  test 'unchecking item is case-insensitive' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Milk', checked: true)
    list.apply_action('check', item: 'milk', checked: false)

    assert_empty list.state['checked_off']
  end

  test 'removing custom item and reconciling cleans up checked-off entry' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    list.apply_action('check', item: 'Birthday Candles', checked: true)
    list.apply_action('custom_items', item: 'Birthday Candles', action: 'remove')
    reconcile_plan!(list)

    list.reload

    assert_empty list.state['custom_items']
    assert_empty list.state['checked_off']
  end

  test 'removing custom item and reconciling cleans up case-mismatched checked-off entry' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Test', action: 'add')
    list.apply_action('check', item: 'Test', checked: true)
    list.apply_action('custom_items', item: 'test', action: 'remove')
    reconcile_plan!(list)

    list.reload

    assert_empty list.state['custom_items']
    assert_empty list.state['checked_off']
  end
end

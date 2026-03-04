# frozen_string_literal: true

require 'test_helper'

class MealPlanTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    MealPlan.where(kitchen: @kitchen).delete_all
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

  test 'apply_action handles string selected param' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'true')

    assert_includes list.state['selected_recipes'], 'pizza-dough'

    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'false')

    assert_not_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action handles string checked param' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: 'true')

    assert_includes list.state['checked_off'], 'milk'

    list.apply_action('check', item: 'milk', checked: 'false')

    assert_not_includes list.state['checked_off'], 'milk'
  end

  test 'clear resets state and bumps version' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    old_version = list.lock_version

    list.clear!

    assert_empty list.state
    assert_operator list.lock_version, :>, old_version
  end

  test 'select_all sets all recipes and quick bites while preserving custom items' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'milk', checked: true)

    list.select_all!(%w[focaccia bagels], %w[goldfish nachos])

    assert_equal %w[focaccia bagels], list.state['selected_recipes']
    assert_equal %w[goldfish nachos], list.state['selected_quick_bites']
    assert_includes list.state['custom_items'], 'birthday candles'
    assert_includes list.state['checked_off'], 'milk'
  end

  test 'clear_selections resets selections and checked off but preserves custom items' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'milk', checked: true)

    list.clear_selections!

    assert_empty list.state['selected_recipes']
    assert_empty list.state['selected_quick_bites']
    assert_includes list.state['custom_items'], 'birthday candles'
    assert_empty list.state['checked_off']
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

  test 'prune_checked_off removes items not in visible names' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Flour', checked: true)
    list.apply_action('check', item: 'Salt', checked: true)

    list.prune_checked_off(visible_names: Set.new(['Flour']))

    assert_includes list.state['checked_off'], 'Flour'
    assert_not_includes list.state['checked_off'], 'Salt'
  end

  test 'prune_checked_off removes all when visible set is empty' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Flour', checked: true)
    list.apply_action('check', item: 'Salt', checked: true)

    list.prune_checked_off(visible_names: Set.new)

    assert_empty list.state['checked_off']
  end

  test 'prune_checked_off preserves custom items even when not in visible names' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('check', item: 'birthday candles', checked: true)
    list.apply_action('check', item: 'Flour', checked: true)

    list.prune_checked_off(visible_names: Set.new)

    assert_includes list.state['checked_off'], 'birthday candles'
    assert_not_includes list.state['checked_off'], 'Flour'
  end

  test 'prune_checked_off is idempotent when nothing to prune' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Flour', checked: true)
    version_before = list.lock_version

    list.prune_checked_off(visible_names: Set.new(['Flour']))

    assert_equal version_before, list.lock_version
  end

  test 'prune_checked_off saves when items are pruned' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('check', item: 'Flour', checked: true)
    version_before = list.lock_version

    list.prune_checked_off(visible_names: Set.new)

    assert_operator list.lock_version, :>, version_before
  end

  test 'pruning removes checked items not on shopping list' do
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('check', item: 'Flour', checked: true)
    plan.apply_action('check', item: 'Phantom Item', checked: true)

    shopping_list = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).build
    visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
    plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }

    plan.reload

    assert_includes plan.state['checked_off'], 'Flour'
    assert_not_includes plan.state['checked_off'], 'Phantom Item'
  end

  test 'pruning preserves custom items' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
    plan.apply_action('check', item: 'birthday candles', checked: true)

    shopping_list = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).build
    visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
    plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }

    plan.reload

    assert_includes plan.state['checked_off'], 'birthday candles'
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

  test 'removing custom item cleans up checked-off entry' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    list.apply_action('check', item: 'Birthday Candles', checked: true)
    list.apply_action('custom_items', item: 'Birthday Candles', action: 'remove')

    list.reload

    assert_empty list.state['custom_items']
    assert_empty list.state['checked_off']
  end

  test 'removing custom item cleans up case-mismatched checked-off entry' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Test', action: 'add')
    list.apply_action('check', item: 'Test', checked: true)
    list.apply_action('custom_items', item: 'test', action: 'remove')

    list.reload

    assert_empty list.state['custom_items']
    assert_empty list.state['checked_off']
  end

  test 'prune_checked_off preserves custom items case-insensitively' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
    list.apply_action('check', item: 'birthday candles', checked: true)

    list.prune_checked_off(visible_names: Set.new)

    assert_includes list.state['checked_off'], 'birthday candles'
  end

  test 'truthy? class method recognizes true and string true' do
    assert MealPlan.truthy?(true)
    assert MealPlan.truthy?('true')
    assert_not MealPlan.truthy?(false)
    assert_not MealPlan.truthy?('false')
    assert_not MealPlan.truthy?(nil)
  end

  test 'pruning is no-op when nothing to prune' do
    plan = MealPlan.for_kitchen(@kitchen)
    version_before = plan.lock_version

    shopping_list = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).build
    visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
    plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }

    assert_equal version_before, plan.reload.lock_version
  end
end

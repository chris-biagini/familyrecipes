# frozen_string_literal: true

require 'test_helper'

class GroceryListTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    GroceryList.where(kitchen: @kitchen).delete_all
  end

  test 'belongs to kitchen' do
    list = GroceryList.create!(kitchen: @kitchen)

    assert_equal @kitchen, list.kitchen
  end

  test 'enforces one list per kitchen' do
    GroceryList.create!(kitchen: @kitchen)
    duplicate = GroceryList.new(kitchen: @kitchen)

    refute_predicate duplicate, :valid?
  end

  test 'defaults to version 0 and empty state' do
    list = GroceryList.create!(kitchen: @kitchen)

    assert_equal 0, list.lock_version
    assert_empty list.state
  end

  test 'for_kitchen finds or creates' do
    list = GroceryList.for_kitchen(@kitchen)

    assert_predicate list, :persisted?
    assert_equal @kitchen, list.kitchen

    assert_equal list, GroceryList.for_kitchen(@kitchen)
  end

  test 'apply_action adds recipe to selected_recipes' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)

    assert_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action removes recipe from selected_recipes' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: false)

    refute_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action adds quick bite to selected_quick_bites' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)

    assert_includes list.state['selected_quick_bites'], 'nachos'
  end

  test 'apply_action checks off item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)

    assert_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action unchecks item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    list.apply_action('check', item: 'milk', checked: false)

    refute_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action adds custom item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    assert_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action removes custom item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('custom_items', item: 'birthday candles', action: 'remove')

    refute_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action handles string selected param' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'true')

    assert_includes list.state['selected_recipes'], 'pizza-dough'

    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: 'false')

    refute_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action handles string checked param' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: 'true')

    assert_includes list.state['checked_off'], 'milk'

    list.apply_action('check', item: 'milk', checked: 'false')

    refute_includes list.state['checked_off'], 'milk'
  end

  test 'clear resets state and bumps version' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    old_version = list.lock_version

    list.clear!

    assert_empty list.state
    assert_operator list.lock_version, :>, old_version
  end

  test 'apply_action bumps version' do
    list = GroceryList.for_kitchen(@kitchen)
    old_version = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_operator list.lock_version, :>, old_version
  end

  test 'operations are idempotent' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    version_after_first = list.lock_version

    list.apply_action('check', item: 'milk', checked: true)

    assert_equal version_after_first, list.lock_version
  end

  test 'ignores unknown action types' do
    list = GroceryList.for_kitchen(@kitchen)
    old_version = list.lock_version

    list.apply_action('bogus', foo: 'bar')

    assert_equal old_version, list.lock_version
  end

  test 'with_optimistic_retry retries on StaleObjectError' do
    list = GroceryList.for_kitchen(@kitchen)
    attempts = 0

    list.with_optimistic_retry do
      attempts += 1
      raise ActiveRecord::StaleObjectError, list if attempts == 1
    end

    assert_equal 2, attempts
  end

  test 'with_optimistic_retry raises after max attempts' do
    list = GroceryList.for_kitchen(@kitchen)

    assert_raises(ActiveRecord::StaleObjectError) do
      list.with_optimistic_retry(max_attempts: 2) do
        raise ActiveRecord::StaleObjectError, list
      end
    end
  end
end

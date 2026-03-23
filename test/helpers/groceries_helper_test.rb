# frozen_string_literal: true

require 'test_helper'

class GroceriesHelperTest < ActionView::TestCase
  test 'format_amounts with single amount and unit' do
    assert_equal "(3\u00a0cups)", format_amounts([[3.0, 'cups']])
  end

  test 'format_amounts with multiple amounts' do
    assert_equal "(3\u00a0cups + 1\u00a0tsp)", format_amounts([[3.0, 'cups'], [1.0, 'tsp']])
  end

  test 'format_amounts with unitless amount' do
    assert_equal '(2)', format_amounts([[2.0, nil]])
  end

  test 'format_amounts strips trailing zeros' do
    assert_equal "(3\u00a0cups)", format_amounts([[3.0, 'cups']])
  end

  test 'format_amounts preserves decimals when needed' do
    assert_equal "(1.5\u00a0cups)", format_amounts([[1.5, 'cups']])
  end

  test 'format_amounts returns empty string for empty array' do
    assert_equal '', format_amounts([])
  end

  test 'format_amounts returns empty string for nil' do
    assert_equal '', format_amounts(nil)
  end

  test 'shopping_list_count_text with no items returns empty string' do
    assert_equal '', shopping_list_count_text({}, Set.new)
  end

  test 'shopping_list_count_text with no checked items shows total to buy' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }
    on_hand_data = { 'Milk' => { 'depleted_at' => '2026-03-20' }, 'Eggs' => { 'depleted_at' => '2026-03-20' } }

    assert_equal '2 items to buy', shopping_list_count_text(shopping_list, Set.new, on_hand_data:)
  end

  test 'shopping_list_count_text with some checked shows unchecked count' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }
    on_hand_data = { 'Eggs' => { 'depleted_at' => '2026-03-20' } }

    assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new(%w[Milk]), on_hand_data:)
  end

  test 'shopping_list_count_text with all checked shows done' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }] }

    assert_equal "\u2713 All done!", shopping_list_count_text(shopping_list, Set.new(%w[Milk]))
  end

  test 'shopping_list_count_text with single item uses singular' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }] }
    on_hand_data = { 'Milk' => { 'depleted_at' => '2026-03-20' } }

    assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new, on_hand_data:)
  end

  test 'format_amounts with uncounted appends +N more' do
    assert_equal "(1 + 1\u00a0more)", format_amounts([[1.0, nil]], uncounted: 1)
  end

  test 'format_amounts with multiple uncounted appends +N more' do
    assert_equal "(3\u00a0Tbsp + 2\u00a0more)", format_amounts([[3.0, 'Tbsp']], uncounted: 2)
  end

  test 'format_amounts all uncounted with multiple uses shows count' do
    assert_equal "(3\u00a0uses)", format_amounts([], uncounted: 3)
  end

  test 'format_amounts single uncounted returns empty string' do
    assert_equal '', format_amounts([], uncounted: 1)
  end

  test 'format_amounts zero uncounted preserves existing behavior' do
    assert_equal '(2)', format_amounts([[2.0, nil]], uncounted: 0)
  end

  test 'format_amounts defaults uncounted to zero' do
    assert_equal '(2)', format_amounts([[2.0, nil]])
  end

  test 'restock_tooltip shows days remaining for on-hand items' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-15', 'interval' => 10, 'ease' => 1.1 } }
    on_hand_names = Set.new(['Milk'])
    result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

    assert_equal 'Estimated restock in ~4 days', result
  end

  test 'restock_tooltip shows cycle length for to-buy items with history' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 10, 'ease' => 1.1 } }
    on_hand_names = Set.new
    result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

    assert_equal 'Restocks every ~9 days', result
  end

  test 'restock_tooltip returns nil for custom items' do
    on_hand_data = { 'Candles' => { 'confirmed_at' => '2026-03-15', 'interval' => nil, 'ease' => nil } }
    on_hand_names = Set.new(['Candles'])

    assert_nil restock_tooltip('Candles', on_hand_data, on_hand_names)
  end

  test 'restock_tooltip returns nil for fresh items with no history' do
    on_hand_data = { 'Flour' => { 'confirmed_at' => '2026-03-15', 'interval' => 7,
                                  'ease' => MealPlan::STARTING_EASE } }
    on_hand_names = Set.new
    result = restock_tooltip('Flour', on_hand_data, on_hand_names, now: Date.new(2026, 3, 25))

    assert_nil result
  end

  test 'item_zone returns :on_hand for items in on_hand_names' do
    result = item_zone(name: 'Milk', on_hand_names: Set.new(%w[Milk]), on_hand_data: {}, custom_items: [])

    assert_equal :on_hand, result
  end

  test 'item_zone returns :to_buy for items with depleted_at entry' do
    on_hand_data = { 'Milk' => { 'depleted_at' => '2026-03-20' } }

    result = item_zone(name: 'Milk', on_hand_names: Set.new, on_hand_data:, custom_items: [])

    assert_equal :to_buy, result
  end

  test 'item_zone returns :inventory_check for items with no entry' do
    result = item_zone(name: 'Eggs', on_hand_names: Set.new, on_hand_data: {}, custom_items: [])

    assert_equal :inventory_check, result
  end

  test 'item_zone returns :inventory_check for expired non-depleted items' do
    # Expired items have an entry but no depleted_at (interval expired, not manually depleted)
    on_hand_data = { 'Butter' => { 'confirmed_at' => '2026-01-01', 'interval' => 7 } }

    result = item_zone(name: 'Butter', on_hand_names: Set.new, on_hand_data:, custom_items: [])

    assert_equal :inventory_check, result
  end

  test 'item_zone returns :on_hand for custom items that are on_hand' do
    # Custom items with null interval can still be checked on-hand
    result = item_zone(name: 'Candles', on_hand_names: Set.new(%w[Candles]),
                       on_hand_data: {}, custom_items: %w[Candles])

    assert_equal :on_hand, result
  end

  test 'item_zone returns :to_buy for unchecked custom items' do
    # Custom items never go to Inventory Check — always :to_buy when not on hand
    result = item_zone(name: 'Shaving cream', on_hand_names: Set.new, on_hand_data: {}, custom_items: ['Shaving cream'])

    assert_equal :to_buy, result
  end

  test 'item_zone matching is case-insensitive for on_hand_data lookup' do
    on_hand_data = { 'milk' => { 'depleted_at' => '2026-03-20' } }

    result = item_zone(name: 'Milk', on_hand_names: Set.new, on_hand_data:, custom_items: [])

    assert_equal :to_buy, result
  end

  test 'confirmed_today? returns true when confirmed_at matches today' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => Date.current.iso8601 } }

    assert confirmed_today?('Milk', on_hand_data)
  end

  test 'confirmed_today? returns false for past confirmed_at' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-01-01' } }

    assert_not confirmed_today?('Milk', on_hand_data)
  end

  test 'confirmed_today? returns false for missing entry' do
    assert_not confirmed_today?('Eggs', {})
  end

  test 'confirmed_today? returns false for orphan sentinel' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => MealPlan::ORPHAN_SENTINEL } }

    assert_not confirmed_today?('Milk', on_hand_data)
  end

  test 'confirmed_today? matches case-insensitively' do
    on_hand_data = { 'milk' => { 'confirmed_at' => Date.current.iso8601 } }

    assert confirmed_today?('Milk', on_hand_data)
  end

  test 'confirmed_today? returns false when confirmed_at is nil' do
    on_hand_data = { 'Milk' => { 'interval' => nil } }

    assert_not confirmed_today?('Milk', on_hand_data)
  end

  test 'shopping_list_count_text counts only :to_buy items, not :inventory_check' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }
    # Milk is depleted (:to_buy), Eggs has no entry (:inventory_check)
    on_hand_data = { 'Milk' => { 'depleted_at' => '2026-03-20' } }

    result = shopping_list_count_text(shopping_list, Set.new, on_hand_data:, custom_items: [])

    assert_equal '1 item to buy', result
  end

  test 'on_hand_freshness_class returns on-hand-fresh for early progress' do
    entry = { 'confirmed_at' => '2026-03-21', 'interval' => 10 }

    assert_equal 'on-hand-fresh', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class returns on-hand-mid for middle progress' do
    entry = { 'confirmed_at' => '2026-03-19', 'interval' => 10 }

    assert_equal 'on-hand-mid', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class returns on-hand-aging for late progress' do
    entry = { 'confirmed_at' => '2026-03-16', 'interval' => 10 }

    assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class returns on-hand-fresh for nil interval' do
    entry = { 'confirmed_at' => '2026-03-01', 'interval' => nil }

    assert_equal 'on-hand-fresh', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class boundary at 0.33 returns mid' do
    entry = { 'confirmed_at' => '2026-03-20', 'interval' => 10 }

    assert_equal 'on-hand-mid', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class boundary at 0.66 returns aging' do
    entry = { 'confirmed_at' => '2026-03-17', 'interval' => 10 }

    assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_freshness_class clamps progress above 1.0 to aging' do
    entry = { 'confirmed_at' => '2026-03-08', 'interval' => 10 }

    assert_equal 'on-hand-aging', on_hand_freshness_class(entry, now: Date.new(2026, 3, 23))
  end

  test 'on_hand_sort_key orders by days until restock descending' do
    now = Date.new(2026, 3, 23)
    on_hand_data = {
      'Eggs' => { 'confirmed_at' => '2026-03-16', 'interval' => 10 },
      'Butter' => { 'confirmed_at' => '2026-03-22', 'interval' => 10 },
      'Milk' => { 'confirmed_at' => now.iso8601, 'interval' => 10 }
    }
    names = %w[Eggs Butter Milk]
    sorted = names.sort_by { |n| on_hand_sort_key(n, on_hand_data, now:) }

    assert_equal %w[Milk Butter Eggs], sorted
  end

  test 'on_hand_sort_key puts custom items after today' do
    now = Date.new(2026, 3, 23)
    on_hand_data = {
      'Eggs' => { 'confirmed_at' => '2026-03-20', 'interval' => 10 },
      'Candles' => { 'confirmed_at' => '2026-03-15', 'interval' => nil }
    }
    sorted = %w[Eggs Candles].sort_by { |n| on_hand_sort_key(n, on_hand_data, now:) }

    assert_equal %w[Candles Eggs], sorted
  end
end

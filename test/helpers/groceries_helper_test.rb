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
    assert_equal "(1 +1\u00a0more)", format_amounts([[1.0, nil]], uncounted: 1)
  end

  test 'format_amounts with multiple uncounted appends +N more' do
    assert_equal "(3\u00a0Tbsp +2\u00a0more)", format_amounts([[3.0, 'Tbsp']], uncounted: 2)
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

  test 'parse_custom_item splits on last @' do
    name, aisle = parse_custom_item('Shaving cream @ Personal care')

    assert_equal 'Shaving cream', name
    assert_equal 'Personal care', aisle
  end

  test 'parse_custom_item returns nil aisle when no @' do
    name, aisle = parse_custom_item('Just milk')

    assert_equal 'Just milk', name
    assert_nil aisle
  end

  test 'parse_custom_item strips whitespace from both parts' do
    name, aisle = parse_custom_item('  soap  @  Health  ')

    assert_equal 'soap', name
    assert_equal 'Health', aisle
  end

  test 'parse_custom_item handles no spaces around @' do
    name, aisle = parse_custom_item('foo@bar')

    assert_equal 'foo', name
    assert_equal 'bar', aisle
  end

  test 'parse_custom_item with multiple @ uses last' do
    name, aisle = parse_custom_item('foo @ bar @ Baz')

    assert_equal 'foo @ bar', name
    assert_equal 'Baz', aisle
  end

  test 'parse_custom_item with trailing @ returns nil aisle' do
    name, aisle = parse_custom_item('foo @ ')

    assert_equal 'foo', name
    assert_nil aisle
  end

  test 'restock_tooltip shows days remaining for on-hand items' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-15', 'interval' => 10, 'ease' => 1.1 } }
    on_hand_names = Set.new(['Milk'])
    result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

    assert_equal 'Estimated restock in ~5 days', result
  end

  test 'restock_tooltip shows cycle length for to-buy items with history' do
    on_hand_data = { 'Milk' => { 'confirmed_at' => '2026-03-01', 'interval' => 10, 'ease' => 1.1 } }
    on_hand_names = Set.new
    result = restock_tooltip('Milk', on_hand_data, on_hand_names, now: Date.new(2026, 3, 20))

    assert_equal 'Restocks every ~10 days', result
  end

  test 'restock_tooltip returns nil for custom items' do
    on_hand_data = { 'Candles' => { 'confirmed_at' => '2026-03-15', 'interval' => nil, 'ease' => nil } }
    on_hand_names = Set.new(['Candles'])

    assert_nil restock_tooltip('Candles', on_hand_data, on_hand_names)
  end

  test 'restock_tooltip returns nil for fresh items with no history' do
    on_hand_data = { 'Flour' => { 'confirmed_at' => '2026-03-15', 'interval' => 7, 'ease' => 2.0 } }
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

  test 'shopping_list_count_text counts only :to_buy items, not :inventory_check' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }
    # Milk is depleted (:to_buy), Eggs has no entry (:inventory_check)
    on_hand_data = { 'Milk' => { 'depleted_at' => '2026-03-20' } }

    result = shopping_list_count_text(shopping_list, Set.new, on_hand_data:, custom_items: [])

    assert_equal '1 item to buy', result
  end
end

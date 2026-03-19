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

    assert_equal '2 items to buy', shopping_list_count_text(shopping_list, Set.new)
  end

  test 'shopping_list_count_text with some checked shows unchecked count' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }, { name: 'Eggs' }] }

    assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new(%w[Milk]))
  end

  test 'shopping_list_count_text with all checked shows done' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }] }

    assert_equal "\u2713 All done!", shopping_list_count_text(shopping_list, Set.new(%w[Milk]))
  end

  test 'shopping_list_count_text with single item uses singular' do
    shopping_list = { 'Dairy' => [{ name: 'Milk' }] }

    assert_equal '1 item to buy', shopping_list_count_text(shopping_list, Set.new)
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
end

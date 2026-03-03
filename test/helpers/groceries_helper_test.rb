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

  test 'aisle_count_tag shows remaining count when some unchecked' do
    items = [{ name: 'Milk' }, { name: 'Eggs' }]
    result = aisle_count_tag(items, Set.new(%w[Milk]))

    assert_equal '<span class="aisle-count">(1)</span>', result
  end

  test 'aisle_count_tag shows checkmark when all checked off' do
    items = [{ name: 'Milk' }, { name: 'Eggs' }]
    result = aisle_count_tag(items, Set.new(%w[Milk Eggs]))

    assert_equal "<span class=\"aisle-count aisle-done\">\u2713</span>", result
  end

  test 'aisle_count_tag shows total when none checked' do
    items = [{ name: 'Milk' }, { name: 'Eggs' }]
    result = aisle_count_tag(items, Set.new)

    assert_equal '<span class="aisle-count">(2)</span>', result
  end

  test 'aisle_count_tag shows zero for empty aisle' do
    result = aisle_count_tag([], Set.new)

    assert_equal '<span class="aisle-count">(0)</span>', result
  end
end

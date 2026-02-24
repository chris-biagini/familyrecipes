# frozen_string_literal: true

require 'test_helper'

class KitchenAisleOrderTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test', slug: 'test')
  end

  test 'parsed_aisle_order returns empty array when nil' do
    @kitchen.update!(aisle_order: nil)

    assert_empty @kitchen.parsed_aisle_order
  end

  test 'parsed_aisle_order splits lines and strips whitespace' do
    @kitchen.update!(aisle_order: "Produce\n  Baking \nFrozen\n")

    assert_equal %w[Produce Baking Frozen], @kitchen.parsed_aisle_order
  end

  test 'parsed_aisle_order skips blank lines' do
    @kitchen.update!(aisle_order: "Produce\n\n\nBaking\n")

    assert_equal %w[Produce Baking], @kitchen.parsed_aisle_order
  end

  test 'normalize_aisle_order! deduplicates and strips' do
    @kitchen.aisle_order = "Produce\nBaking\n  Produce \nFrozen"
    @kitchen.normalize_aisle_order!

    assert_equal "Produce\nBaking\nFrozen", @kitchen.aisle_order
  end

  test 'normalize_aisle_order! sets nil for empty input' do
    @kitchen.aisle_order = "  \n  \n"
    @kitchen.normalize_aisle_order!

    assert_nil @kitchen.aisle_order
  end
end

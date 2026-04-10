# frozen_string_literal: true

require 'test_helper'

class KitchenJoinCodeTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  test 'join code is generated on create' do
    kitchen = Kitchen.create!(name: 'New Kitchen', slug: 'new-kitchen')

    assert_predicate kitchen.join_code, :present?
    assert_equal 4, kitchen.join_code.split.size
  end

  test 'join code is unique across kitchens' do
    k1 = Kitchen.create!(name: 'Kitchen A', slug: 'kitchen-a')
    k2 = Kitchen.create!(name: 'Kitchen B', slug: 'kitchen-b')

    assert_not_equal k1.join_code, k2.join_code
  end

  test 'regenerate_join_code! produces a new code' do
    old_code = @kitchen.join_code
    @kitchen.regenerate_join_code!

    assert_not_equal old_code, @kitchen.join_code
  end

  test 'find_by_join_code normalizes input' do
    code = @kitchen.join_code
    upcased = code.upcase
    padded = "  #{code}  "

    assert_equal @kitchen, Kitchen.find_by_join_code(upcased)
    assert_equal @kitchen, Kitchen.find_by_join_code(padded)
  end

  test 'find_by_join_code returns nil for invalid code' do
    assert_nil Kitchen.find_by_join_code('invalid code here now')
  end
end

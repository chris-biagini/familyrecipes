# frozen_string_literal: true

require 'test_helper'

class GroceryListChannelTest < ActionCable::Channel::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
  end

  test 'subscribes to kitchen grocery list' do
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :confirmed?
  end

  test 'rejects subscription for unknown kitchen' do
    subscribe kitchen_slug: 'nonexistent'

    assert_predicate subscription, :rejected?
  end

  test 'broadcasts version to kitchen' do
    assert_broadcast_on(
      GroceryListChannel.broadcasting_for(@kitchen),
      version: 42
    ) do
      GroceryListChannel.broadcast_version(@kitchen, 42)
    end
  end
end

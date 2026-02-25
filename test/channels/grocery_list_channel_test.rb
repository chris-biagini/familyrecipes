# frozen_string_literal: true

require 'test_helper'

class GroceryListChannelTest < ActionCable::Channel::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    @user = User.create!(name: 'Member', email: 'member@example.com')
    ActsAsTenant.with_tenant(@kitchen) do
      Membership.create!(kitchen: @kitchen, user: @user)
    end
  end

  test 'subscribes when user is kitchen member' do
    stub_connection current_user: @user
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :confirmed?
  end

  test 'rejects subscription for unknown kitchen' do
    stub_connection current_user: @user
    subscribe kitchen_slug: 'nonexistent'

    assert_predicate subscription, :rejected?
  end

  test 'rejects subscription when user is not a member' do
    outsider = User.create!(name: 'Outsider', email: 'outsider@example.com')

    stub_connection current_user: outsider
    subscribe kitchen_slug: @kitchen.slug

    assert_predicate subscription, :rejected?
  end

  test 'rejects subscription when no user' do
    stub_connection current_user: nil
    subscribe kitchen_slug: @kitchen.slug

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

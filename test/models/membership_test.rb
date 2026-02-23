# frozen_string_literal: true

require 'test_helper'

class MembershipTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'enforces unique user per kitchen' do
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    Membership.create!(kitchen: @kitchen, user: user)

    dup = Membership.new(kitchen: @kitchen, user: user)

    assert_not dup.valid?
    assert_includes dup.errors[:user_id], 'has already been taken'
  end

  test 'default role is member' do
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    membership = Membership.create!(kitchen: @kitchen, user: user)

    assert_equal 'member', membership.role
  end
end

# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'requires name' do
    user = User.new

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test 'allows nil email' do
    user = User.new(name: 'Alice')

    assert_predicate user, :valid?
  end

  test 'enforces email uniqueness when present' do
    User.create!(name: 'Alice', email: 'alice@example.com')
    dup = User.new(name: 'Bob', email: 'alice@example.com')

    assert_not dup.valid?
    assert_includes dup.errors[:email], 'has already been taken'
  end

  test 'allows multiple nil emails' do
    User.create!(name: 'Alice')
    user = User.new(name: 'Bob')

    assert_predicate user, :valid?
  end

  test 'accesses kitchens through memberships' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    user = User.create!(name: 'Alice')
    ActsAsTenant.current_tenant = kitchen
    Membership.create!(kitchen: kitchen, user: user)

    assert_includes user.kitchens, kitchen
  end
end

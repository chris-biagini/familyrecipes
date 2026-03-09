# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'requires name' do
    user = User.new(email: 'test@example.com')

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test 'requires email' do
    user = User.new(name: 'Alice')

    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test 'enforces email uniqueness' do
    User.create!(name: 'Alice', email: 'alice@example.com')
    dup = User.new(name: 'Bob', email: 'alice@example.com')

    assert_not dup.valid?
    assert_includes dup.errors[:email], 'has already been taken'
  end

  test 'accesses kitchens through memberships' do
    setup_test_kitchen
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    Membership.create!(kitchen: @kitchen, user: user)

    assert_includes user.kitchens, @kitchen
  end
end

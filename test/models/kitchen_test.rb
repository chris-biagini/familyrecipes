# frozen_string_literal: true

require 'test_helper'

class KitchenTest < ActiveSupport::TestCase
  test 'requires name' do
    kitchen = Kitchen.new(slug: 'test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:name], "can't be blank"
  end

  test 'requires slug' do
    kitchen = Kitchen.new(name: 'Test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:slug], "can't be blank"
  end

  test 'enforces unique slug' do
    Kitchen.create!(name: 'First', slug: 'first')
    dup = Kitchen.new(name: 'Second', slug: 'first')

    assert_not dup.valid?
    assert_includes dup.errors[:slug], 'has already been taken'
  end

  test 'member? returns true for kitchen members' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    user = User.create!(name: 'Alice')
    ActsAsTenant.current_tenant = kitchen
    Membership.create!(kitchen: kitchen, user: user)

    assert kitchen.member?(user)
  end

  test 'member? returns false for non-members' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    user = User.create!(name: 'Alice')
    ActsAsTenant.current_tenant = kitchen

    assert_not kitchen.member?(user)
  end

  test 'member? returns false for nil user' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = kitchen

    assert_not kitchen.member?(nil)
  end
end

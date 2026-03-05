# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class KitchenTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

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
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    ActsAsTenant.current_tenant = kitchen
    Membership.create!(kitchen: kitchen, user: user)

    assert kitchen.member?(user)
  end

  test 'member? returns false for non-members' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    user = User.create!(name: 'Alice', email: 'alice@example.com')
    ActsAsTenant.current_tenant = kitchen

    assert_not kitchen.member?(user)
  end

  test 'member? returns false for nil user' do
    kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = kitchen

    assert_not kitchen.member?(nil)
  end

  test 'all_aisles returns empty array when no aisles exist' do
    kitchen = Kitchen.create!(name: 'Empty', slug: 'empty')

    assert_empty kitchen.all_aisles
  end

  test 'all_aisles returns aisle_order entries' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-aisles', aisle_order: "Produce\nBaking")

    assert_equal %w[Produce Baking], kitchen.all_aisles
  end

  test 'all_aisles merges catalog aisles not in order' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-merge', aisle_order: 'Produce')
    IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
    IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Salt', aisle: 'Spices', basis_grams: 6)

    aisles = kitchen.all_aisles

    assert_equal 'Produce', aisles.first
    assert_includes aisles, 'Baking'
    assert_includes aisles, 'Spices'
  end

  test 'all_aisles excludes omit sentinel' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-omit')
    IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Bay leaves', aisle: 'omit', basis_grams: 1)

    assert_not_includes kitchen.all_aisles, 'omit'
  end

  test 'all_aisles deduplicates across sources' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-dedup', aisle_order: 'Baking')
    IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)

    assert_equal ['Baking'], kitchen.all_aisles
  end

  test 'quick_bites_by_subsection groups parsed quick bites by stripped category' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-qb',
                              quick_bites_content: "## Snacks\n- Chips\n- Pretzels\n\n## Drinks\n- Juice\n")

    result = kitchen.quick_bites_by_subsection

    assert_kind_of Hash, result
    assert_includes result.keys, 'Snacks'
    assert_includes result.keys, 'Drinks'
    assert_equal 2, result['Snacks'].size
    assert_equal 1, result['Drinks'].size
  end

  test 'broadcast_update sends refresh to kitchen updates stream' do
    kitchen = Kitchen.create!(name: 'Broadcast', slug: 'broadcast')

    assert_turbo_stream_broadcasts [kitchen, :updates] do
      kitchen.broadcast_update
    end
  end

  test 'quick_bites_by_subsection returns empty hash when no content' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-qb-empty')

    assert_empty kitchen.quick_bites_by_subsection
  end

  test 'parsed_quick_bites returns quick bites from new format' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-parsed-qb',
                              quick_bites_content: "Snacks:\n- Goldfish\n- Dried fruit\n")
    qbs = kitchen.parsed_quick_bites

    assert_equal 2, qbs.size
    assert_equal 'Goldfish', qbs.first.title
  end

  test 'all_aisles prefers kitchen catalog entries over global' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test-overlay')
    IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
    IngredientCatalog.create!(kitchen: kitchen, ingredient_name: 'Flour', aisle: 'Pantry', basis_grams: 30)

    aisles = kitchen.all_aisles

    assert_includes aisles, 'Pantry'
    assert_not_includes aisles, 'Baking'
  end
end

# frozen_string_literal: true

require 'test_helper'

class CustomGroceryItemTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    CustomGroceryItem.where(kitchen_id: @kitchen.id).delete_all
  end

  # --- constants ---

  test 'MAX_NAME_LENGTH is 100' do
    assert_equal 100, CustomGroceryItem::MAX_NAME_LENGTH
  end

  test 'RETENTION is 45' do
    assert_equal 45, CustomGroceryItem::RETENTION
  end

  # --- validations ---

  test 'valid with name and last_used_at' do
    item = CustomGroceryItem.new(name: 'Paper Towels', last_used_at: Date.current)

    assert_predicate item, :valid?
  end

  test 'requires name' do
    item = CustomGroceryItem.new(name: '', last_used_at: Date.current)

    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
  end

  test 'rejects name longer than MAX_NAME_LENGTH' do
    item = CustomGroceryItem.new(name: 'x' * 101, last_used_at: Date.current)

    assert_not item.valid?
    assert item.errors[:name].any? { |msg| msg.include?('too long') }
  end

  test 'accepts name at MAX_NAME_LENGTH' do
    item = CustomGroceryItem.new(name: 'x' * 100, last_used_at: Date.current)

    assert_predicate item, :valid?
  end

  test 'enforces kitchen-scoped uniqueness' do
    CustomGroceryItem.create!(name: 'Paper Towels', last_used_at: Date.current)
    dup = CustomGroceryItem.new(name: 'Paper Towels', last_used_at: Date.current)

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end

  test 'enforces case-insensitive uniqueness' do
    CustomGroceryItem.create!(name: 'Paper Towels', last_used_at: Date.current)
    dup = CustomGroceryItem.new(name: 'paper towels', last_used_at: Date.current)

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end

  # --- acts_as_tenant ---

  test 'scoped to current kitchen via acts_as_tenant' do
    CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.current)

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen

    assert_empty CustomGroceryItem.all
  end

  # --- visible scope ---

  test 'visible includes items with nil on_hand_at' do
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.current, on_hand_at: nil)

    assert_includes CustomGroceryItem.visible(now: Date.current), item
  end

  test 'visible includes items with on_hand_at in the future' do
    tomorrow = Date.current + 1
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.current, on_hand_at: tomorrow)

    assert_includes CustomGroceryItem.visible(now: Date.current), item
  end

  test 'visible includes items with on_hand_at equal to now' do
    today = Date.current
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: today, on_hand_at: today)

    assert_includes CustomGroceryItem.visible(now: today), item
  end

  test 'visible excludes items with on_hand_at in the past' do
    yesterday = Date.current - 1
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: yesterday, on_hand_at: yesterday)

    assert_not_includes CustomGroceryItem.visible(now: Date.current), item
  end

  # --- stale scope ---

  test 'stale includes items with last_used_at before cutoff' do
    old = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.new(2026, 1, 1))

    assert_includes CustomGroceryItem.stale(cutoff: Date.new(2026, 2, 1)), old
  end

  test 'stale excludes items with last_used_at at cutoff' do
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.new(2026, 2, 1))

    assert_not_includes CustomGroceryItem.stale(cutoff: Date.new(2026, 2, 1)), item
  end

  test 'stale excludes items with last_used_at after cutoff' do
    item = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.new(2026, 3, 1))

    assert_not_includes CustomGroceryItem.stale(cutoff: Date.new(2026, 2, 1)), item
  end
end

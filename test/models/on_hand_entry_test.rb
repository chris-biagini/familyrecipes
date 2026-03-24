# frozen_string_literal: true

require 'test_helper'

class OnHandEntryTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    OnHandEntry.where(kitchen_id: @kitchen.id).delete_all
    CustomGroceryItem.where(kitchen_id: @kitchen.id).delete_all
  end

  # --- Constants ---

  test 'constants match SM-2 tuning values' do
    assert_equal 7, OnHandEntry::STARTING_INTERVAL
    assert_equal 180, OnHandEntry::MAX_INTERVAL
    assert_equal 180, OnHandEntry::ORPHAN_RETENTION
    assert_equal '1970-01-01', OnHandEntry::ORPHAN_SENTINEL
    assert_in_delta 1.5, OnHandEntry::STARTING_EASE
    assert_in_delta 1.1, OnHandEntry::MIN_EASE
    assert_in_delta 2.5, OnHandEntry::MAX_EASE
    assert_in_delta 0.05, OnHandEntry::EASE_BONUS
    assert_in_delta 0.15, OnHandEntry::EASE_PENALTY
    assert_in_delta 0.9, OnHandEntry::SAFETY_MARGIN
  end

  # --- Tenant scoping ---

  test 'scoped to current kitchen via acts_as_tenant' do
    OnHandEntry.create!(ingredient_name: 'Eggs', confirmed_at: Date.current,
                        interval: 7, ease: 1.5)

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen

    assert_empty OnHandEntry.all
  end

  # --- NOCASE uniqueness ---

  test 'enforces case-insensitive uniqueness on ingredient_name' do
    OnHandEntry.create!(ingredient_name: 'Eggs', confirmed_at: Date.current)
    dup = OnHandEntry.new(ingredient_name: 'eggs', confirmed_at: Date.current)

    assert_not dup.valid?
    assert_includes dup.errors[:ingredient_name], 'has already been taken'
  end

  # --- Active scope ---

  test 'active includes entry with nil interval and no depleted_at' do
    entry = OnHandEntry.create!(ingredient_name: 'Paper Towels',
                                confirmed_at: Date.current, interval: nil, ease: nil)

    assert_includes OnHandEntry.active(now: Date.current), entry
  end

  test 'active includes entry within safety margin window' do
    today = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: today, interval: 10.0, ease: 1.5)

    # 10 * 0.9 = 9 days effective. Day 9 should still be active.
    assert_includes OnHandEntry.active(now: today + 9), entry
  end

  test 'active excludes entry past safety margin window' do
    today = Date.new(2026, 3, 1)
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: today, interval: 10.0, ease: 1.5)

    # 10 * 0.9 = 9 days. Day 10 should be expired.
    assert_empty OnHandEntry.active(now: today + 10)
  end

  test 'active excludes depleted entries' do
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 30.0, ease: 1.5,
                        depleted_at: Date.current)

    assert_empty OnHandEntry.active(now: Date.current)
  end

  test 'active safety margin truncates fractional days' do
    today = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Milk',
                                confirmed_at: today, interval: 7.0, ease: 1.5)

    # 7 * 0.9 = 6.3, CAST to INT = 6. Day 6 active, day 7 expired.
    assert_includes OnHandEntry.active(now: today + 6), entry
    assert_empty OnHandEntry.active(now: today + 7)
  end

  # --- Depleted scope ---

  test 'depleted includes entries with depleted_at' do
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 7.0, ease: 1.5, depleted_at: Date.current)

    assert_includes OnHandEntry.depleted, entry
  end

  test 'depleted excludes entries without depleted_at' do
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 7.0, ease: 1.5)

    assert_empty OnHandEntry.depleted
  end

  # --- Orphaned scope ---

  test 'orphaned includes entries with orphaned_at' do
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 7.0, ease: 1.5, orphaned_at: Date.current)

    assert_includes OnHandEntry.orphaned, entry
  end

  test 'orphaned excludes entries without orphaned_at' do
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 7.0, ease: 1.5)

    assert_empty OnHandEntry.orphaned
  end

  # --- have_it! ---

  test 'have_it! with sentinel grows standard: resets confirmed_at, grows interval' do
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 10.0, ease: 1.5, orphaned_at: Date.new(2026, 1, 1))
    now = Date.new(2026, 3, 15)

    entry.have_it!(now:)
    entry.reload

    new_ease = 1.5 + 0.05
    expected_interval = 10.0 * new_ease

    assert_equal now, entry.confirmed_at
    assert_in_delta new_ease, entry.ease
    assert_in_delta expected_interval, entry.interval
    assert_nil entry.orphaned_at
  end

  test 'have_it! with real confirmed_at grows anchored, keeps confirmed_at when anchor covers today' do
    today = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Butter',
                                confirmed_at: today, interval: 14.0, ease: 1.5)

    # Entry expires at: Mar 1 + (14*0.9).to_i = Mar 1 + 12 = Mar 13.
    # Call have_it! on Mar 14 → not on hand, triggers anchored growth.
    # Anchored growth: 14 * 1.55 = 21.7 → Mar 1 + 21 = Mar 22 >= Mar 14 → anchor holds.
    entry.have_it!(now: today + 13)
    entry.reload

    assert_equal today, entry.confirmed_at
    assert_in_delta 1.55, entry.ease
    assert_in_delta 14.0 * 1.55, entry.interval
  end

  test 'have_it! with real confirmed_at resets confirmed_at when anchor cannot cover today' do
    start = Date.new(2026, 1, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Flour',
                                confirmed_at: start, interval: 7.0, ease: 1.5)

    # Anchored growth: 7 * 1.55 = 10.85 → start + 10 = Jan 11.
    # Checking on Jan 20 can't cover → reset confirmed_at, no ease bump.
    now = Date.new(2026, 1, 20)
    entry.have_it!(now:)
    entry.reload

    assert_equal now, entry.confirmed_at
    assert_in_delta 1.5, entry.ease
    assert_in_delta 7.0 * 1.55, entry.interval
  end

  test 'have_it! is a no-op when already on hand' do
    today = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Sugar',
                                confirmed_at: today, interval: 30.0, ease: 1.5)

    entry.have_it!(now: today + 5)
    entry.reload

    assert_equal today, entry.confirmed_at
    assert_in_delta 30.0, entry.interval
    assert_in_delta 1.5, entry.ease
  end

  test 'have_it! caps ease at MAX_EASE' do
    entry = OnHandEntry.create!(ingredient_name: 'Rice',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 10.0, ease: 2.48)

    entry.have_it!(now: Date.new(2026, 3, 1))
    entry.reload

    assert_in_delta OnHandEntry::MAX_EASE, entry.ease
  end

  test 'have_it! caps interval at MAX_INTERVAL' do
    entry = OnHandEntry.create!(ingredient_name: 'Salt',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 170.0, ease: 2.0)

    entry.have_it!(now: Date.new(2026, 3, 1))
    entry.reload

    assert_in_delta OnHandEntry::MAX_INTERVAL, entry.interval
  end

  # --- need_it! ---

  test 'need_it! with sentinel penalizes ease only, marks depleted' do
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 10.0, ease: 1.5, orphaned_at: Date.new(2026, 1, 1))
    now = Date.new(2026, 3, 15)

    entry.need_it!(now:)
    entry.reload

    assert_in_delta 1.5 * (1 - 0.15), entry.ease
    assert_in_delta 10.0, entry.interval
    assert_equal now, entry.depleted_at
    assert_nil entry.orphaned_at
  end

  test 'need_it! with real confirmed_at blends observed with interval' do
    start = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Milk',
                                confirmed_at: start, interval: 14.0, ease: 1.5)
    now = start + 10

    entry.need_it!(now:)
    entry.reload

    observed = 10
    blended = (observed + 14.0) / 2.0

    assert_in_delta blended, entry.interval
    assert_in_delta 1.5 * (1 - 0.15), entry.ease
    assert_equal Date.parse('1970-01-01'), entry.confirmed_at
    assert_equal now, entry.depleted_at
  end

  test 'need_it! enforces minimum interval of STARTING_INTERVAL after depletion' do
    start = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Cream',
                                confirmed_at: start, interval: 7.0, ease: 1.5)

    # observed=2, blended=(2+7)/2=4.5, clamped to STARTING_INTERVAL=7
    entry.need_it!(now: start + 2)
    entry.reload

    assert_in_delta OnHandEntry::STARTING_INTERVAL, entry.interval
  end

  test 'need_it! ease never falls below MIN_EASE' do
    entry = OnHandEntry.create!(ingredient_name: 'Vinegar',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 10.0, ease: 1.1)

    entry.need_it!(now: Date.new(2026, 3, 1))
    entry.reload

    assert_in_delta OnHandEntry::MIN_EASE, entry.ease
  end

  # --- check! ---

  test 'check! creates new entry with starting values' do
    entry = OnHandEntry.new(ingredient_name: 'Eggs', kitchen: @kitchen)
    now = Date.new(2026, 3, 1)

    entry.check!(now:)

    assert_predicate entry, :persisted?
    assert_equal now, entry.confirmed_at
    assert_in_delta OnHandEntry::STARTING_INTERVAL, entry.interval
    assert_in_delta OnHandEntry::STARTING_EASE, entry.ease
    assert_nil entry.depleted_at
  end

  test 'check! creates custom entry with nil interval and ease' do
    custom = CustomGroceryItem.create!(name: 'Paper Towels', last_used_at: Date.current)
    entry = OnHandEntry.new(ingredient_name: 'Paper Towels', kitchen: @kitchen)
    now = Date.new(2026, 3, 1)

    entry.check!(now:, custom_item: custom)

    assert_predicate entry, :persisted?
    assert_nil entry.interval
    assert_nil entry.ease
    assert_equal now, custom.reload.on_hand_at
  end

  test 'check! rechecks depleted entry' do
    now = Date.new(2026, 3, 15)
    entry = OnHandEntry.create!(ingredient_name: 'Butter',
                                confirmed_at: Date.parse('1970-01-01'),
                                interval: 12.0, ease: 1.4,
                                depleted_at: Date.new(2026, 3, 10))

    entry.check!(now:)
    entry.reload

    assert_equal now, entry.confirmed_at
    assert_nil entry.depleted_at
    assert_in_delta 12.0, entry.interval
    assert_in_delta 1.4, entry.ease
  end

  test 'check! is a no-op when confirmed same day' do
    now = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Sugar',
                                confirmed_at: now, interval: 7.0, ease: 1.5)

    entry.check!(now:)
    entry.reload

    assert_in_delta 7.0, entry.interval
    assert_in_delta 1.5, entry.ease
  end

  test 'check! is a no-op when still active' do
    start = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Flour',
                                confirmed_at: start, interval: 30.0, ease: 1.5)

    entry.check!(now: start + 5)
    entry.reload

    assert_equal start, entry.confirmed_at
    assert_in_delta 30.0, entry.interval
  end

  # --- uncheck! ---

  test 'uncheck! destroys custom entry and clears on_hand_at' do
    custom = CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.current,
                                       on_hand_at: Date.current)
    entry = OnHandEntry.create!(ingredient_name: 'Foil',
                                confirmed_at: Date.current, interval: nil, ease: nil)

    entry.uncheck!(now: Date.current, custom_item: custom)

    assert_predicate entry, :destroyed?
    assert_nil custom.reload.on_hand_at
  end

  test 'uncheck! destroys entry with nil interval (custom-sourced)' do
    entry = OnHandEntry.create!(ingredient_name: 'Wipes',
                                confirmed_at: Date.current, interval: nil, ease: nil)

    entry.uncheck!(now: Date.current)

    assert_predicate entry, :destroyed?
  end

  test 'uncheck! same-day with default values depletes to To Buy' do
    now = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: now, interval: 7.0, ease: 1.5)

    entry.uncheck!(now:)
    entry.reload

    assert_equal Date.parse('1970-01-01'), entry.confirmed_at
    assert_equal now, entry.depleted_at
    assert_in_delta 7.0, entry.interval
    assert_in_delta 1.5, entry.ease
  end

  test 'uncheck! same-day with learned values marks depleted without penalty' do
    now = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Eggs',
                                confirmed_at: now, interval: 14.0, ease: 1.8)

    entry.uncheck!(now:)
    entry.reload

    assert_equal Date.parse('1970-01-01'), entry.confirmed_at
    assert_equal now, entry.depleted_at
    assert_in_delta 14.0, entry.interval
    assert_in_delta 1.8, entry.ease
  end

  test 'uncheck! on different day performs full depletion' do
    start = Date.new(2026, 3, 1)
    entry = OnHandEntry.create!(ingredient_name: 'Milk',
                                confirmed_at: start, interval: 14.0, ease: 1.5)
    now = start + 10

    entry.uncheck!(now:)
    entry.reload

    blended = (10 + 14.0) / 2.0

    assert_in_delta blended, entry.interval
    assert_in_delta 1.5 * (1 - 0.15), entry.ease
    assert_equal Date.parse('1970-01-01'), entry.confirmed_at
    assert_equal now, entry.depleted_at
  end

  # --- reconcile! ---

  test 'reconcile! re-canonicalizes names via resolver' do
    OnHandEntry.create!(ingredient_name: 'egg',
                        confirmed_at: Date.current, interval: 10.0, ease: 1.5)

    resolver = build_mock_resolver('egg' => 'Eggs')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: %w[Eggs], resolver:)

    assert_equal 1, OnHandEntry.count
    assert_equal 'Eggs', OnHandEntry.first.ingredient_name
  end

  test 'reconcile! merge conflict keeps longer interval' do
    OnHandEntry.create!(ingredient_name: 'egg',
                        confirmed_at: Date.current, interval: 20.0, ease: 1.5)
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 10.0, ease: 1.5)

    resolver = build_mock_resolver('egg' => 'Eggs', 'Eggs' => 'Eggs')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: %w[Eggs], resolver:)

    assert_equal 1, OnHandEntry.count

    winner = OnHandEntry.first

    assert_equal 'Eggs', winner.ingredient_name
    assert_in_delta 20.0, winner.interval
  end

  test 'reconcile! merge conflict keeps non-sentinel over sentinel' do
    OnHandEntry.create!(ingredient_name: 'egg',
                        confirmed_at: Date.parse('1970-01-01'), interval: 30.0, ease: 1.5)
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 10.0, ease: 1.5)

    resolver = build_mock_resolver('egg' => 'Eggs', 'Eggs' => 'Eggs')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: %w[Eggs], resolver:)

    assert_equal 1, OnHandEntry.count

    winner = OnHandEntry.first

    assert_equal Date.current, winner.confirmed_at
    assert_in_delta 10.0, winner.interval
  end

  test 'reconcile! expires entries not in visible names' do
    now = Date.new(2026, 3, 15)
    OnHandEntry.create!(ingredient_name: 'Old Spice',
                        confirmed_at: now, interval: 10.0, ease: 1.5)

    resolver = build_mock_resolver('Old Spice' => 'Old Spice')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:, now:)

    entry = OnHandEntry.first

    assert_equal Date.parse('1970-01-01'), entry.confirmed_at
    assert_equal now, entry.orphaned_at
  end

  test 'reconcile! does not expire already depleted entries' do
    now = Date.new(2026, 3, 15)
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.parse('1970-01-01'),
                        interval: 10.0, ease: 1.5,
                        depleted_at: Date.new(2026, 3, 10))

    resolver = build_mock_resolver('Eggs' => 'Eggs')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:, now:)

    entry = OnHandEntry.first

    assert_nil entry.orphaned_at
    assert_equal Date.new(2026, 3, 10), entry.depleted_at
  end

  test 'reconcile! does not expire entries backed by custom grocery items' do
    now = Date.new(2026, 3, 15)
    CustomGroceryItem.create!(name: 'Paper Towels', last_used_at: now)
    OnHandEntry.create!(ingredient_name: 'Paper Towels',
                        confirmed_at: now, interval: nil, ease: nil)

    resolver = build_mock_resolver('Paper Towels' => 'Paper Towels')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:, now:)

    entry = OnHandEntry.first

    assert_equal now, entry.confirmed_at
    assert_nil entry.orphaned_at
  end

  test 'reconcile! fixes null intervals not backed by custom items' do
    OnHandEntry.create!(ingredient_name: 'Mystery',
                        confirmed_at: Date.current, interval: nil, ease: nil)

    resolver = build_mock_resolver('Mystery' => 'Mystery')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: %w[Mystery], resolver:)

    entry = OnHandEntry.first

    assert_in_delta OnHandEntry::STARTING_INTERVAL, entry.interval
    assert_in_delta OnHandEntry::STARTING_EASE, entry.ease
  end

  test 'reconcile! leaves null intervals for custom-backed items' do
    CustomGroceryItem.create!(name: 'Foil', last_used_at: Date.current)
    OnHandEntry.create!(ingredient_name: 'Foil',
                        confirmed_at: Date.current, interval: nil, ease: nil)

    resolver = build_mock_resolver('Foil' => 'Foil')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: %w[Foil], resolver:)

    assert_nil OnHandEntry.first.interval
  end

  test 'reconcile! purges stale orphans past ORPHAN_RETENTION' do
    stale_date = Date.current - OnHandEntry::ORPHAN_RETENTION - 1
    OnHandEntry.create!(ingredient_name: 'Ancient',
                        confirmed_at: Date.parse('1970-01-01'),
                        interval: 10.0, ease: 1.5,
                        orphaned_at: stale_date)

    resolver = build_mock_resolver('Ancient' => 'Ancient')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:)

    assert_equal 0, OnHandEntry.count
  end

  test 'reconcile! does not purge orphans that are also depleted' do
    stale_date = Date.current - OnHandEntry::ORPHAN_RETENTION - 1
    OnHandEntry.create!(ingredient_name: 'Depleted Orphan',
                        confirmed_at: Date.parse('1970-01-01'),
                        interval: 10.0, ease: 1.5,
                        orphaned_at: stale_date,
                        depleted_at: Date.current)

    resolver = build_mock_resolver('Depleted Orphan' => 'Depleted Orphan')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:)

    assert_equal 1, OnHandEntry.count
  end

  test 'reconcile! does not purge recent orphans' do
    OnHandEntry.create!(ingredient_name: 'Recent Orphan',
                        confirmed_at: Date.parse('1970-01-01'),
                        interval: 10.0, ease: 1.5,
                        orphaned_at: Date.current)

    resolver = build_mock_resolver('Recent Orphan' => 'Recent Orphan')

    OnHandEntry.reconcile!(kitchen: @kitchen, visible_names: [], resolver:)

    assert_equal 1, OnHandEntry.count
  end

  # --- Kitchen association ---

  test 'kitchen has_many on_hand_entries' do
    OnHandEntry.create!(ingredient_name: 'Eggs',
                        confirmed_at: Date.current, interval: 7.0, ease: 1.5)

    assert_equal 1, @kitchen.on_hand_entries.size
  end

  private

  def build_mock_resolver(mapping)
    resolver = Object.new
    resolver.define_singleton_method(:resolve) { |name| mapping.fetch(name, name) }
    resolver
  end
end

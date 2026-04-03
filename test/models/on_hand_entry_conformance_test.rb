# frozen_string_literal: true

require 'test_helper'
require_relative '../sim/grocery_audit'

# Proves that GroceryAudit::Entry mirrors OnHandEntry's exact math.
# Runs identical sequences through both and asserts field-level equality.
#
# Usage: ruby -Itest test/models/on_hand_entry_conformance_test.rb
class OnHandEntryConformanceTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
  end

  test 'constants match' do
    assert_equal OnHandEntry::STARTING_INTERVAL, GroceryAudit::STARTING_INTERVAL
    assert_equal OnHandEntry::MAX_INTERVAL, GroceryAudit::MAX_INTERVAL
    assert_equal OnHandEntry::STARTING_EASE, GroceryAudit::STARTING_EASE
    assert_equal OnHandEntry::MIN_EASE, GroceryAudit::MIN_EASE
    assert_equal OnHandEntry::MAX_EASE, GroceryAudit::MAX_EASE
    assert_equal OnHandEntry::EASE_BONUS, GroceryAudit::EASE_BONUS
    assert_equal OnHandEntry::EASE_PENALTY, GroceryAudit::EASE_PENALTY
    assert_equal OnHandEntry::SAFETY_MARGIN, GroceryAudit::SAFETY_MARGIN
    assert_equal OnHandEntry::BLEND_WEIGHT, GroceryAudit::BLEND_WEIGHT
    assert_equal OnHandEntry::MAX_GROWTH_FACTOR, GroceryAudit::MAX_GROWTH_FACTOR
    assert_equal OnHandEntry::BURST_THRESHOLD, GroceryAudit::BURST_THRESHOLD
    assert_equal OnHandEntry::MIN_ESTABLISHED_INTERVAL, GroceryAudit::MIN_ESTABLISHED_INTERVAL
  end

  test 'check creates matching starting values' do
    ar = build_ar_entry('flour')
    sim = GroceryAudit::Entry.new(confirmed_at: 0)

    now = Date.new(2026, 4, 1)
    ar.check!(now:)
    sim.check!(0)

    assert_entries_match(ar, sim, now, 0)
  end

  test 'have_it with sentinel matches grow_standard' do
    now = Date.new(2026, 4, 1)
    ar = build_ar_entry('flour', confirmed_at: sentinel_date, interval: 7.0,
                                 ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: GroceryAudit::SENTINEL,
                                  interval: 7.0, ease: 1.5)

    ar.have_it!(now:)
    sim.have_it!(0)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
  end

  test 'have_it with anchor holding' do
    now = Date.new(2026, 4, 14)
    base = Date.new(2026, 4, 1)
    ar = build_ar_entry('flour', confirmed_at: base, interval: 14.0,
                                 ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 14.0, ease: 1.5)

    ar.have_it!(now:)
    sim.have_it!(13) # day 13 relative to base=day 0

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
    assert_equal base, ar.confirmed_at
    assert_equal 0, sim.confirmed_at
  end

  test 'have_it with anchor broken' do
    now = Date.new(2026, 4, 20)
    base = Date.new(2026, 4, 1)
    ar = build_ar_entry('flour', confirmed_at: base, interval: 7.0,
                                 ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)

    ar.have_it!(now:)
    sim.have_it!(19)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
    assert_equal now, ar.confirmed_at
    assert_equal 19, sim.confirmed_at
  end

  test 'need_it with real confirmed_at matches deplete_observed' do
    now = Date.new(2026, 4, 15)
    base = Date.new(2026, 4, 1)
    ar = build_ar_entry('flour', confirmed_at: base, interval: 7.0,
                                 ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)

    ar.need_it!(now:)
    sim.need_it!(14)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
    assert_equal now, ar.depleted_at
    assert_equal 14, sim.depleted_at
  end

  test 'need_it with sentinel matches deplete_sentinel' do
    now = Date.new(2026, 4, 10)
    ar = build_ar_entry('flour', confirmed_at: sentinel_date, interval: 7.0,
                                 ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: GroceryAudit::SENTINEL,
                                  interval: 7.0, ease: 1.5)

    ar.need_it!(now:)
    sim.need_it!(0)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
  end

  test 'uncheck same-day matches undo_same_day' do
    now = Date.new(2026, 4, 10)
    ar = build_ar_entry('flour', confirmed_at: now, interval: 28.0,
                                 ease: 2.0, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 28.0, ease: 2.0)

    ar.uncheck!(now:)
    sim.uncheck!(0)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
  end

  test 'uncheck different-day matches deplete_observed' do
    now = Date.new(2026, 4, 15)
    base = Date.new(2026, 4, 1)
    ar = build_ar_entry('flour', confirmed_at: base, interval: 14.0,
                                 ease: 1.8, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 14.0, ease: 1.8)

    ar.uncheck!(now:)
    sim.uncheck!(14)

    assert_in_delta ar.interval, sim.interval, 0.001
    assert_in_delta ar.ease, sim.ease, 0.001
  end

  test 'multi-step sequence produces matching state' do
    base = Date.new(2026, 4, 1)

    ar = build_ar_entry('eggs', confirmed_at: base, interval: 7.0,
                                ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)

    # Step 1: have_it on day 8 (anchor should hold: 0 + (7*1.55).to_i = 10 >= 8)
    ar.have_it!(now: base + 8)
    sim.have_it!(8)

    assert_in_delta ar.interval, sim.interval, 0.001, 'Step 1 interval'
    assert_in_delta ar.ease, sim.ease, 0.001, 'Step 1 ease'

    # Step 2: need_it on day 20
    ar.need_it!(now: base + 20)
    sim.need_it!(20)

    assert_in_delta ar.interval, sim.interval, 0.001, 'Step 2 interval'
    assert_in_delta ar.ease, sim.ease, 0.001, 'Step 2 ease'

    # Step 3: recheck on day 21
    ar.check!(now: base + 21)
    sim.check!(21)

    assert_in_delta ar.interval, sim.interval, 0.001, 'Step 3 interval'
    assert_in_delta ar.ease, sim.ease, 0.001, 'Step 3 ease'

    # Step 4: have_it on day 28
    ar.have_it!(now: base + 28)
    sim.have_it!(28)

    assert_in_delta ar.interval, sim.interval, 0.001, 'Step 4 interval'
    assert_in_delta ar.ease, sim.ease, 0.001, 'Step 4 ease'
  end

  test 'deplete_observed blend vs floor matches production' do
    base = Date.new(2026, 4, 1)
    ar = build_ar_entry('eggs', confirmed_at: base, interval: 7.0,
                                ease: 1.5, depleted_at: nil)
    ar.save!
    sim = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)

    ar.need_it!(now: base + 2)
    sim.need_it!(2)

    assert_in_delta ar.interval, sim.interval, 0.001, 'Short obs floor'
    assert_in_delta 7.0, sim.interval, 0.001, 'Should floor at STARTING_INTERVAL'
  end

  private

  def build_ar_entry(name, confirmed_at: Date.current, interval: 7.0, ease: 1.5, depleted_at: nil)
    OnHandEntry.new(
      kitchen: @kitchen,
      ingredient_name: name,
      confirmed_at:,
      interval:,
      ease:,
      depleted_at:
    )
  end

  def sentinel_date = Date.parse(OnHandEntry::ORPHAN_SENTINEL)

  def assert_entries_match(record, sim, ar_base, sim_base)
    assert_in_delta record.interval, sim.interval, 0.001, 'interval mismatch'
    assert_in_delta record.ease, sim.ease, 0.001, 'ease mismatch'
    ar_offset = record.confirmed_at == sentinel_date ? :sentinel : (record.confirmed_at - ar_base).to_i
    sim_offset = sim.confirmed_at == GroceryAudit::SENTINEL ? :sentinel : (sim.confirmed_at - sim_base)

    assert_equal ar_offset, sim_offset, 'confirmed_at offset mismatch'
  end
end

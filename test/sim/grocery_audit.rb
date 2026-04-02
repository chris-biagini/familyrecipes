#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive audit of the SM-2-inspired grocery interval algorithm.
# Replaces grocery_convergence.rb, grocery_delayed_signals.rb, and
# grocery_real_world.rb with a single authoritative tool that mirrors
# OnHandEntry's exact math and measures user-experience metrics.
#
# Design: docs/superpowers/specs/2026-04-02-grocery-algorithm-audit-design.md
# Usage:  ruby test/sim/grocery_audit.rb

module GroceryAudit
  STARTING_INTERVAL = 7
  MAX_INTERVAL      = 180
  STARTING_EASE     = 1.5
  MIN_EASE          = 1.1
  MAX_EASE          = 2.5
  EASE_BONUS        = 0.05
  EASE_PENALTY      = 0.15
  SAFETY_MARGIN     = 0.9
  SENTINEL          = -999_999
  SIM_DAYS          = 365

  DEFAULT_ITEMS = { 'Eggs' => 7, 'Milk' => 10, 'Butter' => 14,
                    'Flour' => 30, 'Pepper' => 60, 'Salt' => 90 }.freeze

  # Mirrors OnHandEntry's per-ingredient adaptive interval state.
  # Uses integer day numbers: SENTINEL (-999_999) maps to production's
  # Date.parse('1970-01-01'). Every method below matches the corresponding
  # OnHandEntry private method line-for-line.
  class Entry
    attr_accessor :confirmed_at, :interval, :ease, :depleted_at

    def initialize(confirmed_at:, interval: STARTING_INTERVAL.to_f, ease: STARTING_EASE)
      @confirmed_at = confirmed_at
      @interval     = interval.to_f
      @ease         = ease.to_f
      @depleted_at  = nil
    end

    def sentinel? = confirmed_at == SENTINEL

    def on_hand?(day)
      return false if depleted_at
      confirmed_at + (interval * SAFETY_MARGIN).to_i >= day
    end

    def depleted? = !depleted_at.nil?

    # First day the item appears in Inventory Check (on_hand? returns false).
    def ic_fires_on
      return nil if sentinel? || depleted?

      confirmed_at + (interval * SAFETY_MARGIN).to_i + 1
    end

    # --- Public actions (match OnHandEntry's public interface) ---

    def have_it!(day)
      return if on_hand?(day)

      sentinel? ? grow_standard(day) : grow_anchored(day)
    end

    def need_it!(day)
      sentinel? ? deplete_sentinel(day) : deplete_observed(day)
    end

    def check!(day)
      depleted_at ? recheck(day) : assign_starting_values(day)
    end

    def uncheck!(day)
      confirmed_at == day ? undo_same_day(day) : deplete_observed(day)
    end

    private

    # Resets confirmed_at to now, grows interval by ease.
    # NOTE: ease is bumped FIRST, then interval uses the new ease.
    def grow_standard(day)
      @ease         = [ease + EASE_BONUS, MAX_EASE].min
      @interval     = [interval * ease, MAX_INTERVAL].min
      @confirmed_at = day
    end

    # One-step anchored growth. Grows interval by tentative new_ease.
    # Anchor check uses interval.to_i (NOT safety margin).
    # Ease only committed if anchor holds.
    def grow_anchored(day)
      new_ease  = [ease + EASE_BONUS, MAX_EASE].min
      @interval = [interval * new_ease, MAX_INTERVAL].min

      if confirmed_at + interval.to_i >= day
        @ease = new_ease
      else
        @confirmed_at = day
      end
    end

    # Blends observed period with current interval, then floors at
    # STARTING_INTERVAL. Production does max(blend, 7), NOT max(obs, 7)
    # before blending — this is where the old sims diverged.
    def deplete_observed(day)
      observed      = day - confirmed_at
      blended       = (observed + interval) / 2.0
      @interval     = [blended, STARTING_INTERVAL.to_f].max
      @ease         = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
      @confirmed_at = SENTINEL
      @depleted_at  = day
    end

    # Sentinel confirmed_at means no real observed period — penalize ease only.
    def deplete_sentinel(day)
      @ease        = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
      @depleted_at = day
    end

    # Recheck from depleted: reset confirmed_at, clear depleted_at.
    # Interval and ease are preserved.
    def recheck(day)
      @confirmed_at = day
      @depleted_at  = nil
    end

    def assign_starting_values(day)
      @confirmed_at = day
      @interval     = STARTING_INTERVAL.to_f
      @ease         = STARTING_EASE
      @depleted_at  = nil
    end

    # Same-day undo: mark depleted without penalizing — the learned
    # interval and ease survive the accidental tap.
    def undo_same_day(day)
      @confirmed_at = SENTINEL
      @depleted_at  = day
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  puts 'Entry smoke test...'

  e = GroceryAudit::Entry.new(confirmed_at: 0)
  abort 'FAIL: initial interval' unless e.interval == 7.0
  abort 'FAIL: initial ease' unless e.ease == 1.5
  abort 'FAIL: on_hand?(0)' unless e.on_hand?(0)
  abort 'FAIL: on_hand?(6)' unless e.on_hand?(6)
  abort 'FAIL: should be expired day 7' if e.on_hand?(7)
  abort 'FAIL: ic_fires_on' unless e.ic_fires_on == 7

  # grow_standard: ease bumps first, then interval uses new ease
  e2 = GroceryAudit::Entry.new(confirmed_at: GroceryAudit::SENTINEL)
  e2.have_it!(10)
  expected_ease = 1.5 + 0.05 # 1.55
  expected_interval = 7.0 * 1.55 # 10.85
  abort 'FAIL: grow_standard ease' unless (e2.ease - expected_ease).abs < 0.001
  abort 'FAIL: grow_standard interval' unless (e2.interval - expected_interval).abs < 0.001
  abort 'FAIL: grow_standard confirmed_at' unless e2.confirmed_at == 10

  # grow_anchored: anchor holds (item expires day 13, so day 14 triggers grow_anchored)
  e3 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 14.0, ease: 1.5)
  e3.have_it!(14) # 0 + (14*1.55).to_i = 0 + 21 = 21 >= 14 → anchor holds
  abort 'FAIL: anchored ease' unless (e3.ease - 1.55).abs < 0.001
  abort 'FAIL: anchored confirmed_at' unless e3.confirmed_at == 0

  # grow_anchored: anchor breaks
  e4 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e4.have_it!(20) # 0 + (7*1.55).to_i = 0 + 10 = 10 < 20 → anchor breaks
  abort 'FAIL: broken anchor ease' unless (e4.ease - 1.5).abs < 0.001
  abort 'FAIL: broken anchor confirmed_at' unless e4.confirmed_at == 20

  # deplete_observed: blend then floor
  e5 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e5.need_it!(14) # observed=14, blended=(14+7)/2=10.5, ease=1.5*0.85=1.275
  abort 'FAIL: deplete interval' unless (e5.interval - 10.5).abs < 0.001
  abort 'FAIL: deplete ease' unless (e5.ease - 1.275).abs < 0.001
  abort 'FAIL: deplete sentinel' unless e5.sentinel?
  abort 'FAIL: deplete depleted_at' unless e5.depleted_at == 14

  # deplete_observed: floor kicks in for short observations
  e6 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e6.need_it!(2) # observed=2, blended=(2+7)/2=4.5, floored to 7
  abort 'FAIL: deplete floor' unless (e6.interval - 7.0).abs < 0.001

  # undo_same_day: no penalty
  e7 = GroceryAudit::Entry.new(confirmed_at: 10, interval: 28.0, ease: 2.0)
  e7.uncheck!(10) # same day → undo
  abort 'FAIL: same-day interval' unless (e7.interval - 28.0).abs < 0.001
  abort 'FAIL: same-day ease' unless (e7.ease - 2.0).abs < 0.001
  abort 'FAIL: same-day sentinel' unless e7.sentinel?

  puts 'Entry: all checks passed'
end

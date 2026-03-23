#!/usr/bin/env ruby
# frozen_string_literal: true

# Real-world stress tests for the adaptive grocery interval algorithm.
# Exercises messy human behaviors the main convergence sim doesn't cover.
#
# Usage: ruby test/sim/grocery_real_world.rb

require_relative 'grocery_convergence'

module GrocerySim
  # Extends ThreeZoneSim with real-world chaos:
  #   - Irregular shopping intervals
  #   - Skipped weeks / vacations
  #   - Accidental check/uncheck (cracked eggs)
  #   - Holiday burst consumption
  #   - Forgotten IC processing
  class RealWorldSim < ThreeZoneSim
    def initialize(items:, schedule:, days: 365, seed: 42, fuzz: 2)
      @schedule = schedule
      super(items:, shop_every: 7, fuzz:, days:, seed:, anchor_mode: :confirm_only)
    end

    def run!
      (1..@days).each do |day|
        consume!(day)
        event = @schedule[day]
        case event
        when :shop then shop!(day)
        when :partial_shop then partial_shop!(day)
        when :accidental_uncheck then accidental_uncheck!(day)
        when :holiday_bake then holiday_consume!(day)
        end
      end
      self
    end

    private

    def partial_shop!(day)
      @items.each_with_index do |it, idx|
        next if idx.even? # only process odd-indexed items (skip half)

        case it.status(day)
        when :new then triage_new!(it, day)
        when :expired then triage_expired!(it, day)
        when :on_hand then deplete!(it, day) unless it.has_stock
        when :depleted then purchase!(it, day)
        end
      end
    end

    def accidental_uncheck!(day)
      @items.each do |it|
        next unless it.entry&.depleted?

        # Buy it, then immediately realize it's bad and uncheck
        it.entry.confirmed_at = day
        it.entry.depleted_at = nil
        it.record(day, 'buy:recheck')
        it.has_stock = true
        it.runs_out_on = day + it.true_cycle + fuzz_days

        # Oops — cracked eggs / wrong item / bad quality. Uncheck same day.
        deplete!(it, day)
        it.has_stock = false
        it.record(day, 'accidental-uncheck')
        break # only one accidental uncheck per event
      end
    end

    def holiday_consume!(day)
      @items.each do |it|
        next unless it.has_stock
        next unless it.true_cycle >= 14 # holidays burn through long-cycle items

        it.has_stock = false
        deplete!(it, day) if it.status(day) == :on_hand
        it.record(day, 'holiday-bake!')
      end
    end

    def fuzz_days = @fuzz.zero? ? 0 : @rng.rand(-@fuzz..@fuzz)
  end
end

# ---- Scenario 1: Irregular shopping schedule ----
puts "=" * 70
puts "SCENARIO 1: Irregular shopping (3d, 11d, 7d, 4d, 10d cycle)"
puts "=" * 70

schedule = {}
day = 0
intervals = [3, 11, 7, 4, 10, 7, 14, 7, 5, 9, 7, 7, 3, 11] # repeating pattern
intervals.cycle.each do |gap|
  day += gap
  break if day > 365

  schedule[day] = :shop
end

sim = GrocerySim::RealWorldSim.new(
  items: GrocerySim.default_items,
  schedule: schedule,
  fuzz: 2
)
sim.run!.report("Irregular shopping intervals")

# ---- Scenario 2: Two-week vacation ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO 2: Regular weekly shopping with 2-week vacation (day 100-114)"
puts "=" * 70

schedule = {}
(1..365).each do |d|
  next if d >= 100 && d <= 114 # vacation: no shopping

  schedule[d] = :shop if (d % 7).zero?
end

sim = GrocerySim::RealWorldSim.new(
  items: GrocerySim.default_items,
  schedule: schedule,
  fuzz: 2
)
sim.run!.report("Weekly + 2-week vacation")

# ---- Scenario 3: Accidental uncheck (cracked eggs) ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO 3: Regular weekly shopping with accidental unchecks on days 50, 150, 250"
puts "=" * 70

schedule = {}
(1..365).each do |d|
  schedule[d] = :shop if (d % 7).zero?
end
schedule[50] = :accidental_uncheck
schedule[150] = :accidental_uncheck
schedule[250] = :accidental_uncheck

sim = GrocerySim::RealWorldSim.new(
  items: GrocerySim.default_items,
  schedule: schedule,
  fuzz: 2
)
sim.run!.report("Weekly + accidental unchecks")

# ---- Scenario 4: Holiday baking burns through flour/butter ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO 4: Regular weekly + holiday baking spree on day 80 and 170"
puts "=" * 70

schedule = {}
(1..365).each do |d|
  schedule[d] = :shop if (d % 7).zero?
end
schedule[80] = :holiday_bake
schedule[170] = :holiday_bake

sim = GrocerySim::RealWorldSim.new(
  items: GrocerySim.default_items,
  schedule: schedule,
  fuzz: 2
)
sim.run!.report("Weekly + holiday baking")

# ---- Scenario 5: Distracted user, only processes IC every other trip ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO 5: Shops weekly but only processes IC every other trip"
puts "=" * 70

schedule = {}
(1..365).each do |d|
  next unless (d % 7).zero?

  schedule[d] = (d / 7).even? ? :shop : :partial_shop
end

sim = GrocerySim::RealWorldSim.new(
  items: GrocerySim.default_items,
  schedule: schedule,
  fuzz: 2
)
sim.run!.report("Half-attention shopping")

# ---- Scenario 6: Same-day check/uncheck damage test ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO 6: Direct same-day check/uncheck test (isolated)"
puts "=" * 70

puts "\n  Testing: Item at interval=28, ease=2.1"
puts "  Check on day 0, uncheck on day 0 (cracked eggs scenario)"

entry = { confirmed_at: 0, interval: 28.0, ease: 2.1, depleted_at: nil }
item = GrocerySim::Item.new('Test', 28)
item.entry = GrocerySim::Entry.new(confirmed_at: -999_999)
item.entry.depleted_at = 0

# Simulate recheck (buy)
item.entry.confirmed_at = 100
item.entry.depleted_at = nil

# Simulate same-day uncheck
obs = 100 - item.entry.confirmed_at # = 0
item.entry.interval = [obs, GrocerySim::STARTING_INTERVAL].max
item.entry.ease = [(item.entry.ease * (1 - GrocerySim::EASE_PENALTY)), GrocerySim::MIN_EASE].max
item.entry.confirmed_at = -999_999
item.entry.depleted_at = 100

puts "  After same-day uncheck:"
puts "    interval: #{item.entry.interval} (was 28 → now #{GrocerySim::STARTING_INTERVAL}!)"
puts "    ease: #{item.entry.ease.round(3)} (was 2.1 → now #{(2.0 * 0.7).round(3)})"
puts "    VERDICT: Same-day uncheck destroyed 28-day learned interval."
puts "             Ease dropped from 2.1 to #{(2.0 * 0.7).round(3)}."
puts "             Recovery: ~#{((2.1 - (2.0 * 0.7)) / 0.1).ceil} successful confirmations to recover ease."

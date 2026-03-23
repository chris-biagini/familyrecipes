#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests delayed-signal scenarios: what happens when users don't act promptly?
#
# Scenario A: "Need It" → item sits in To Buy for days before purchase
# Scenario B: "Have It" → item depletes quickly (before interval expires)
# Scenario C: IC items ignored for 1-2 weeks before user responds
# Scenario D: Full lifecycle with realistic delays throughout
#
# Usage: ruby test/sim/grocery_delayed_signals.rb

require_relative 'grocery_convergence'

module GrocerySim
  class DelayedSignalSim < ThreeZoneSim
    # purchase_delay: days between "Need It"/"deplete" and actual purchase
    # ic_response_delay: days an IC item sits before user responds
    # depletion_report_delay: days between running out and reporting it
    def initialize(items:, shop_every: 7, fuzz: 0, days: 365, seed: 42,
                   purchase_delay: 0, ic_response_delay: 0,
                   depletion_report_delay: 0)
      @purchase_delay = purchase_delay
      @ic_response_delay = ic_response_delay
      @depletion_report_delay = depletion_report_delay
      @pending_purchases = {} # item_name => day_available_to_buy
      @pending_depletions = {} # item_name => day_ran_out
      @pending_ic = {} # item_name => day_first_seen_in_ic
      super(items:, shop_every:, fuzz:, days:, seed:, anchor_mode: :confirm_only)
    end

    private

    def shop!(day)
      @items.each do |it|
        case it.status(day)
        when :new
          triage_new_delayed!(it, day)
        when :expired
          triage_expired_delayed!(it, day)
        when :on_hand
          handle_on_hand_delayed!(it, day)
        when :depleted
          purchase_delayed!(it, day)
        end
      end
    end

    def triage_new_delayed!(it, day)
      if it.has_stock
        # User sees new item in IC, responds with Have It
        # (no delay on first encounter — it's right there in the kitchen)
        it.entry = Entry.new(confirmed_at: day)
        it.record(day, 'have_it:new')
      else
        it.entry = Entry.new(confirmed_at: -999_999)
        it.entry.depleted_at = day
        it.record(day, 'need_it:new')
        @pending_purchases[it.name] = day + @purchase_delay
        purchase_delayed!(it, day) # try immediate buy
      end
    end

    def triage_expired_delayed!(it, day)
      first_seen = @pending_ic[it.name] ||= day

      if day - first_seen < @ic_response_delay
        # User sees IC but hasn't responded yet — skip this item
        return
      end

      @pending_ic.delete(it.name)

      if it.has_stock
        anchor_confirm!(it, day, label: "have_it:confirm(waited #{day - first_seen}d)")
      else
        deplete!(it, day)
        @pending_purchases[it.name] = day + @purchase_delay
        purchase_delayed!(it, day)
      end
    end

    def handle_on_hand_delayed!(it, day)
      return if it.has_stock

      ran_out = @pending_depletions[it.name]
      unless ran_out
        # Item ran out but user hasn't noticed/reported yet — track it
        @pending_depletions[it.name] = day
        return if @depletion_report_delay > 0
      end

      if ran_out && day - ran_out < @depletion_report_delay
        return # user hasn't reported yet
      end

      @pending_depletions.delete(it.name)
      deplete!(it, day)
    end

    def purchase_delayed!(it, day)
      return unless it.entry&.depleted?

      available = @pending_purchases[it.name] || day
      return if day < available # not ready to buy yet

      @pending_purchases.delete(it.name)
      it.entry.confirmed_at = day
      it.entry.depleted_at = nil
      it.record(day, "buy(delayed #{day - (available - @purchase_delay)}d)")
      it.has_stock = true
      it.runs_out_on = day + it.true_cycle + fuzz_days
    end

    def fuzz_days = @fuzz.zero? ? 0 : @rng.rand(-@fuzz..@fuzz)
  end

  # Variant: "Have It" on day N, item depletes on day N+1..N+3
  # Tests anchored observation inflation
  class QuickDepletionSim < ThreeZoneSim
    # early_depletion_chance: probability that an item depletes much faster
    # than its true cycle (simulating unusual consumption like holiday baking)
    def initialize(items:, shop_every: 7, fuzz: 0, days: 365, seed: 42,
                   quick_depletion_days: [])
      @quick_depletion_days = quick_depletion_days.to_set
      super(items:, shop_every:, fuzz:, days:, seed:, anchor_mode: :confirm_only)
    end

    private

    def shop!(day)
      @items.each do |it|
        # Force immediate depletion of recently-confirmed items on trigger days
        if @quick_depletion_days.include?(day) && it.has_stock && it.entry &&
           !it.entry.depleted? && it.true_cycle >= 14
          it.has_stock = false
          it.runs_out_on = day
        end

        case it.status(day)
        when :new then triage_new!(it, day)
        when :expired then triage_expired!(it, day)
        when :on_hand then deplete!(it, day) unless it.has_stock
        when :depleted then purchase!(it, day)
        end
      end
    end
  end
end

# ---- Scenario A: Delayed purchase after Need It ----
puts "=" * 70
puts "SCENARIO A: Need It → purchase delayed 0, 3, 7, 14 days"
puts "=" * 70

[0, 3, 7, 14].each do |delay|
  items = [GrocerySim::Item.new('Milk', 10), GrocerySim::Item.new('Flour', 30)]
  sim = GrocerySim::DelayedSignalSim.new(
    items: items, purchase_delay: delay, fuzz: 2
  )
  sim.run!
  puts "\n  Purchase delay: #{delay} days"
  items.each do |it|
    ev = it.events.last
    err = ((ev[:interval] - it.true_cycle).to_f / it.true_cycle * 100).round(0)
    puts "    #{it.name} (true: #{it.true_cycle}d) → interval: #{ev[:interval]}, ease: #{ev[:ease]}, err: #{err}%"
  end
end

# ---- Scenario B: IC response delayed 0, 7, 14 days ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO B: IC items sit unprocessed for 0, 7, 14 days"
puts "=" * 70

[0, 7, 14].each do |delay|
  items = [GrocerySim::Item.new('Milk', 10), GrocerySim::Item.new('Flour', 30)]
  sim = GrocerySim::DelayedSignalSim.new(
    items: items, ic_response_delay: delay, fuzz: 2
  )
  sim.run!
  puts "\n  IC response delay: #{delay} days"
  items.each do |it|
    ev = it.events.last
    next unless ev

    err = ((ev[:interval] - it.true_cycle).to_f / it.true_cycle * 100).round(0)
    puts "    #{it.name} (true: #{it.true_cycle}d) → interval: #{ev[:interval]}, ease: #{ev[:ease]}, err: #{err}%"
  end
end

# ---- Scenario C: Have It → immediate depletion ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO C: Have It on day N, then item depletes 1-2 days later"
puts "=" * 70
puts "  (Flour: true 30d. Quick depletion forced on days 45, 150, 250)"

items = [GrocerySim::Item.new('Flour', 30), GrocerySim::Item.new('Butter', 14)]
sim = GrocerySim::QuickDepletionSim.new(
  items: items,
  quick_depletion_days: [45, 150, 250],
  fuzz: 2
)
sim.run!.report("Have It → quick depletion")

# ---- Scenario D: Combined delays (realistic user) ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO D: Realistic user — 3d purchase delay, 7d IC delay, 3d depletion report delay"
puts "=" * 70

items = GrocerySim.default_items
sim = GrocerySim::DelayedSignalSim.new(
  items: items,
  purchase_delay: 3,
  ic_response_delay: 7,
  depletion_report_delay: 3,
  fuzz: 2
)
sim.run!.report("Realistic delayed user")

# ---- Scenario E: Trace a single item through Have It → quick depletion ----
puts "\n\n#{"=" * 70}"
puts "SCENARIO E: Detailed trace — Flour (30d cycle)"
puts "  Day 0: buy flour (confirmed_at=0, interval=7)"
puts "  Day 7: IC → Have It (anchored: interval grows to 14.7, confirmed_at stays 0)"
puts "  Day 9: Baked cookies, used all flour!"
puts "=" * 70

e = GrocerySim::Entry.new(confirmed_at: 0)
puts "\n  After initial purchase:"
puts "    confirmed_at=#{e.confirmed_at}, interval=#{e.interval}, ease=#{e.ease}"

# Day 7: IC → Have It (anchored growth)
e.ease = [e.ease + GrocerySim::EASE_BONUS, GrocerySim::MAX_EASE].min
loop do
  e.interval = [e.interval * e.ease, GrocerySim::MAX_INTERVAL].min
  break if e.confirmed_at + e.interval >= 7 || e.interval >= GrocerySim::MAX_INTERVAL
end
puts "\n  Day 7: Have It (anchored):"
puts "    confirmed_at=#{e.confirmed_at}, interval=#{e.interval.round(1)}, ease=#{e.ease}"
puts "    Next expiry: day #{(e.confirmed_at + e.interval).round(1)}"

# Day 9: User runs out and reports it (unchecks or Need It on next shopping day)
# But item doesn't expire until day 14.7! So it's still "on hand"
# User must manually expand On Hand and uncheck, or wait until day 14.7
puts "\n  Day 9: Flour is gone, but system thinks it's on hand until day #{(e.confirmed_at + e.interval).round(1)}"
puts "  Option 1: User unchecks from On Hand immediately"
obs_a = 9 - e.confirmed_at
int_a = [obs_a, GrocerySim::STARTING_INTERVAL].max
ease_a = [(e.ease * (1 - GrocerySim::EASE_PENALTY)), GrocerySim::MIN_EASE].max
puts "    → observed=#{obs_a}d, interval=#{int_a}, ease=#{ease_a.round(2)}"
puts "    (Good! 9d is close to true cycle. But ease penalized from #{e.ease} to #{ease_a.round(2)})"

puts "\n  Option 2: User doesn't notice until next shopping trip (day 14)"
puts "    Item still 'on hand' (expiry day #{(e.confirmed_at + e.interval).round(1)} > 14)"
puts "    User must dig into On Hand section and uncheck manually"
obs_b = 14 - e.confirmed_at
int_b = [obs_b, GrocerySim::STARTING_INTERVAL].max
ease_b = [(e.ease * (1 - GrocerySim::EASE_PENALTY)), GrocerySim::MIN_EASE].max
puts "    → observed=#{obs_b}d, interval=#{int_b}, ease=#{ease_b.round(2)}"
puts "    (OK. 14d is close enough for 30d item. But user had to know to look in On Hand.)"

puts "\n  Option 3: User waits until natural IC expiry (day #{(e.confirmed_at + e.interval).round(0)}), presses Need It"
expiry = e.confirmed_at + e.interval.to_i
obs_c = expiry - e.confirmed_at
int_c = [obs_c.to_i, GrocerySim::STARTING_INTERVAL].max
ease_c = [(e.ease * (1 - GrocerySim::EASE_PENALTY)), GrocerySim::MIN_EASE].max
puts "    → observed=#{obs_c.round(0)}d, interval=#{int_c}, ease=#{ease_c.round(2)}"
puts "    (Bad! System thinks flour lasts #{int_c}d. True cycle is 30d but it was used in 9.)"

puts "\n  INSIGHT: The anchor fix inflates the observation when depletion happens"
puts "  soon after Have It. The system can't see that depletion was immediate"
puts "  because it measures from the anchored confirmed_at, not from the last"
puts "  Have It action."

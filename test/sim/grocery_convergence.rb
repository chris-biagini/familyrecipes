#!/usr/bin/env ruby
# frozen_string_literal: true

# Simulates the adaptive grocery interval algorithm against known consumption
# cycles. Exercises the exact math from MealPlan without Rails dependencies.
#
# Usage: ruby test/sim/grocery_convergence.rb

module GrocerySim
  STARTING_INTERVAL = 7
  MAX_INTERVAL = 180
  STARTING_EASE = 2.0
  MIN_EASE = 1.1
  MAX_EASE = 2.5
  EASE_BONUS = 0.1
  EASE_PENALTY = 0.3

  class Entry
    attr_accessor :confirmed_at, :interval, :ease, :depleted_at

    def initialize(confirmed_at:, interval: STARTING_INTERVAL.to_f, ease: STARTING_EASE)
      @confirmed_at = confirmed_at
      @interval = interval.to_f
      @ease = ease.to_f
      @depleted_at = nil
    end

    def on_hand?(day) = depleted_at.nil? && confirmed_at + interval >= day
    def depleted? = !depleted_at.nil?
  end

  class Item
    attr_reader :name, :true_cycle, :events
    attr_accessor :entry, :has_stock, :runs_out_on

    def initialize(name, true_cycle)
      @name = name
      @true_cycle = true_cycle
      @entry = nil
      @has_stock = false
      @runs_out_on = nil
      @events = []
    end

    def status(day)
      return :new unless entry
      return :depleted if entry.depleted?
      entry.on_hand?(day) ? :on_hand : :expired
    end

    def record(day, label)
      events << { day:, label:, interval: entry.interval.round(1), ease: entry.ease.round(3) }
    end
  end

  class Sim
    attr_reader :items

    # anchor_mode:
    #   :none           — current algorithm
    #   :confirm_only   — anchor on confirm; buy resets confirmed_at
    #   :all            — anchor on everything (what MealPlan would do, since it can't
    #                     distinguish confirm from buy)
    def initialize(items:, shop_every: 7, fuzz: 0, days: 365, seed: 42,
                   anchor_confirms: false, anchor_mode: nil)
      @items = items
      @shop_every = shop_every
      @fuzz = fuzz
      @days = days
      @rng = Random.new(seed)
      @mode = anchor_mode || (anchor_confirms ? :all : :none)
    end

    def run!
      @items.each { |it| purchase!(it, 0) }

      (1..@days).each do |day|
        consume!(day)
        shop!(day) if (day % @shop_every).zero?
      end
      self
    end

    def report(label)
      puts "\n#{'=' * 70}"
      puts label
      puts '=' * 70
      @items.each { |it| print_log(it) }
      print_summary
    end

    private

    def consume!(day)
      @items.each do |it|
        next unless it.has_stock && day >= it.runs_out_on

        it.has_stock = false
        deplete!(it, day) if it.status(day) == :on_hand
      end
    end

    def shop!(day)
      @items.each do |it|
        # Inventory: uncheck on-hand items we've run out of
        deplete!(it, day) if it.status(day) == :on_hand && !it.has_stock

        case it.status(day)
        when :expired
          it.has_stock ? confirm!(it, day) : purchase!(it, day)
        when :depleted, :new
          purchase!(it, day) unless it.has_stock
        end
      end
    end

    def purchase!(it, day)
      if it.entry&.depleted?
        it.entry.confirmed_at = day
        it.entry.depleted_at = nil
        it.record(day, 'buy:recheck')
      elsif it.entry
        if @mode == :all
          anchor_confirm!(it, day, label: 'buy:anchor')
        else
          grow_entry!(it.entry, day, anchor: false)
          it.record(day, 'buy:grow')
        end
      else
        it.entry = Entry.new(confirmed_at: day)
        it.record(day, 'buy:new')
      end
      it.has_stock = true
      it.runs_out_on = day + it.true_cycle + fuzz_days
    end

    def confirm!(it, day)
      if @mode != :none
        anchor_confirm!(it, day)
      else
        grow_entry!(it.entry, day, anchor: false)
        it.record(day, 'confirm')
      end
    end

    def deplete!(it, day)
      e = it.entry
      obs = day - e.confirmed_at
      e.interval = [obs, STARTING_INTERVAL].max.to_f
      e.ease = [(e.ease * (1 - EASE_PENALTY)), MIN_EASE].max
      e.confirmed_at = -999_999
      e.depleted_at = day
      it.record(day, "deplete(obs=#{obs})")
    end

    # Current algorithm: always reset confirmed_at to today
    def grow_entry!(entry, day, anchor:)
      entry.interval = [entry.interval * entry.ease, MAX_INTERVAL].min
      entry.ease = [entry.ease + EASE_BONUS, MAX_EASE].min
      return if anchor && entry.confirmed_at + entry.interval >= day

      entry.confirmed_at = day
    end

    # Proposed fix: keep confirmed_at anchored to purchase date.
    # Grow interval until the item is on_hand from the anchored date,
    # so depletion observations capture the full consumption period.
    def anchor_confirm!(it, day, label: 'confirm(anchor)')
      e = it.entry
      loop do
        e.interval = [e.interval * e.ease, MAX_INTERVAL].min
        e.ease = [e.ease + EASE_BONUS, MAX_EASE].min
        break if e.confirmed_at + e.interval >= day || e.interval >= MAX_INTERVAL
      end
      it.record(day, label)
    end

    def fuzz_days = @fuzz.zero? ? 0 : @rng.rand(-@fuzz..@fuzz)

    def print_log(it)
      puts "\n  #{it.name} (true: #{it.true_cycle}d)"
      puts format('  %4s  %-22s  %7s  %5s  %6s', 'Day', 'Event', 'Intrvl', 'Ease', 'Err%')

      last_interval = nil
      skipped = 0
      it.events.each do |ev|
        if ev[:interval] == last_interval
          skipped += 1
          next
        end
        puts format('  %38s', "(... #{skipped} repeats ...)") if skipped > 1
        skipped = 0
        last_interval = ev[:interval]
        err = ((ev[:interval] - it.true_cycle).to_f / it.true_cycle * 100).round(0)
        puts format('  %4d  %-22s  %7.1f  %5.2f  %+5d%%',
                     ev[:day], ev[:label], ev[:interval], ev[:ease], err)
      end
      puts format('  %38s', "(... #{skipped} repeats ...)") if skipped > 1
    end

    def print_summary
      puts "\n  Summary:"
      puts format('  %-10s  %5s  %8s  %5s  %6s', 'Item', 'True', 'Final', 'Ease', 'Err%')
      puts '  ' + ('-' * 40)
      @items.each do |it|
        ev = it.events.last
        err = ((ev[:interval] - it.true_cycle).to_f / it.true_cycle * 100).round(0)
        puts format('  %-10s  %5d  %8.1f  %5.2f  %+5d%%',
                     it.name, it.true_cycle, ev[:interval], ev[:ease], err)
      end
    end
  end

  # Models the three-zone grocery workflow explicitly:
  #   Inventory Check → "Have It" (anchor confirm) or "Need It" (deplete)
  #   To Buy → purchase (recheck depleted, reset confirmed_at)
  #   On Hand → timer expires → back to Inventory Check
  #   On Hand → user runs out → deplete → To Buy → purchase
  #
  # Uses anchor_mode: :confirm_only — the same algorithm MealPlan uses.
  class ThreeZoneSim < Sim
    def run!
      (1..@days).each do |day|
        consume!(day)
        shop!(day) if (day % @shop_every).zero?
      end
      self
    end

    private

    def shop!(day)
      @items.each do |it|
        case it.status(day)
        when :new
          triage_new!(it, day)
        when :expired
          triage_expired!(it, day)
        when :on_hand
          deplete!(it, day) unless it.has_stock
        when :depleted
          purchase!(it, day)
        end
      end
    end

    # First time seeing this item — user checks pantry
    def triage_new!(it, day)
      if it.has_stock
        it.entry = Entry.new(confirmed_at: day)
        it.record(day, 'have_it:new')
      else
        it.entry = Entry.new(confirmed_at: -999_999)
        it.entry.depleted_at = day
        it.record(day, 'need_it:new')
        purchase!(it, day)
      end
    end

    # Timer expired, item reappears in Inventory Check
    def triage_expired!(it, day)
      if it.has_stock
        anchor_confirm!(it, day, label: 'have_it:confirm')
      else
        deplete!(it, day)
        purchase!(it, day)
      end
    end
  end

  # ThreeZoneSim with resilience changes: lower starting ease, slower ease
  # growth, lighter depletion penalty, blended intervals on depletion,
  # one-step growth cap on anchor confirm, and safety margin on expiry.
  class ResilientThreeZoneSim < ThreeZoneSim
    RESILIENT_STARTING_EASE = 1.5
    RESILIENT_EASE_BONUS = 0.05
    RESILIENT_EASE_PENALTY = 0.15
    SAFETY_MARGIN = 0.9

    private

    def resilient_status(it, day)
      return :new unless it.entry
      return :depleted if it.entry.depleted?

      effective = it.entry.confirmed_at + (it.entry.interval * SAFETY_MARGIN)
      effective >= day ? :on_hand : :expired
    end

    def shop!(day)
      @items.each do |it|
        case resilient_status(it, day)
        when :new
          triage_new!(it, day)
        when :expired
          triage_expired!(it, day)
        when :on_hand
          deplete!(it, day) unless it.has_stock
        when :depleted
          purchase!(it, day)
        end
      end
    end

    def consume!(day)
      @items.each do |it|
        next unless it.has_stock && day >= it.runs_out_on

        it.has_stock = false
        deplete!(it, day) if resilient_status(it, day) == :on_hand
      end
    end

    def triage_new!(it, day)
      if it.has_stock
        it.entry = Entry.new(confirmed_at: day, ease: RESILIENT_STARTING_EASE)
        it.record(day, 'have_it:new')
      else
        it.entry = Entry.new(confirmed_at: -999_999, ease: RESILIENT_STARTING_EASE)
        it.entry.depleted_at = day
        it.record(day, 'need_it:new')
        purchase!(it, day)
      end
    end

    def deplete!(it, day)
      e = it.entry
      obs = day - e.confirmed_at
      e.interval = ((e.interval + [obs, STARTING_INTERVAL].max.to_f) / 2.0)
      e.ease = [(e.ease * (1 - RESILIENT_EASE_PENALTY)), MIN_EASE].max
      e.confirmed_at = -999_999
      e.depleted_at = day
      it.record(day, "deplete(obs=#{obs})")
    end

    def anchor_confirm!(it, day, label: 'confirm(anchor)')
      e = it.entry
      new_interval = [e.interval * e.ease, MAX_INTERVAL].min
      e.ease = [e.ease + RESILIENT_EASE_BONUS, MAX_EASE].min

      if e.confirmed_at + new_interval >= day
        e.interval = new_interval
      else
        e.interval = new_interval
        e.confirmed_at = day
      end

      it.record(day, label)
    end
  end

  def self.default_items
    { 'Eggs' => 7, 'Milk' => 10, 'Butter' => 14,
      'Flour' => 30, 'Pepper' => 60, 'Salt' => 90 }.map { |name, tc| Item.new(name, tc) }
  end
end

# ---- Scenarios ----

puts 'Grocery Interval Convergence Simulation'
puts 'Immediate uncheck, 365 days'

all_sims = []

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :none)
label = 'A) Current algorithm — weekly, no fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :confirm_only)
label = 'B) Anchor (confirm only) — weekly, no fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :none, shop_every: 3)
label = 'C) Current algorithm — shop every 3d, no fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :confirm_only, shop_every: 3)
label = 'D) Anchor (confirm only) — shop every 3d, no fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :confirm_only, fuzz: 2)
label = 'E) Anchor (confirm only) — weekly, ±2d fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::Sim.new(items: GrocerySim.default_items, anchor_mode: :all, fuzz: 2)
label = 'F) Anchor (all checks) — weekly, ±2d fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::ThreeZoneSim.new(items: GrocerySim.default_items, anchor_mode: :confirm_only, fuzz: 2)
label = 'G) Three-zone model — weekly shopping, ±2d fuzz'
sim.run!.report(label)
all_sims << [label, sim]

sim = GrocerySim::ResilientThreeZoneSim.new(items: GrocerySim.default_items, anchor_mode: :confirm_only, fuzz: 2)
label = 'H) Resilient three-zone — weekly shopping, ±2d fuzz'
sim.run!.report(label)
all_sims << [label, sim]

# ---- Side-by-side comparison ----

puts "\n\n#{'=' * 70}"
puts 'COMPARISON: Final intervals across all scenarios'
puts '=' * 70
item_names = all_sims.first.last.items.map(&:name)
header = format('  %-10s  %5s', 'Item', 'True')
all_sims.each_with_index { |(_, _), i| header += format('  %6s', (65 + i).chr) }
puts header
puts '  ' + ('-' * (18 + all_sims.size * 8))
item_names.each_with_index do |name, idx|
  true_cycle = all_sims.first.last.items[idx].true_cycle
  row = format('  %-10s  %5d', name, true_cycle)
  all_sims.each do |pair|
    ev = pair.last.items[idx].events.last
    err = ev ? ((ev[:interval] - true_cycle).to_f / true_cycle * 100).round(0) : 0
    row += format('  %+5d%%', err)
  end
  puts row
end
puts "\n  Legend:"
all_sims.each_with_index { |(lbl, _), i| puts "    #{(65 + i).chr}) #{lbl.sub(/^[A-H]\) /, '')}" }

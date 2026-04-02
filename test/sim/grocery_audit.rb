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

  Cycle = Struct.new(:item_name, :true_cycle, :purchased_on, :depleted_on,
                     :ic_fires_on, keyword_init: true)

  # Ground-truth stock tracking wrapper around Entry.
  # Tracks physical reality (has_stock, runs_out_on) separately from the
  # app's belief (entry state) to measure algorithm accuracy.
  class Item
    attr_reader :name, :true_cycle
    attr_accessor :entry, :has_stock, :runs_out_on

    def initialize(name, true_cycle)
      @name        = name
      @true_cycle  = true_cycle
      @entry       = nil
      @has_stock   = true
      @runs_out_on = true_cycle
    end

    def zone(day)
      return :new unless entry
      return :depleted if entry.depleted?

      entry.on_hand?(day) ? :on_hand : :expired
    end
  end

  # Records purchase-to-purchase cycles for scoring.
  # Collaborators: Item, FaithfulSim (calls start_cycle/record_depletion/update_ic).
  # record_depletion uses ||= so only the FIRST depletion per cycle is recorded.
  class CycleTracker
    attr_reader :completed

    def initialize
      @current   = {}
      @completed = []
    end

    def start_cycle(item, day)
      close_if_open(item)
      @current[item.name] = {
        purchased_on: day,
        depleted_on:  nil,
        ic_fires_on:  item.entry&.ic_fires_on,
        true_cycle:   item.true_cycle
      }
    end

    def record_depletion(item, day)
      c = @current[item.name]
      return unless c

      c[:depleted_on] ||= day
    end

    # Update IC fire date after entry state changes (have_it! grows interval).
    def update_ic(item)
      c = @current[item.name]
      return unless c && item.entry

      ic = item.entry.ic_fires_on
      c[:ic_fires_on] = ic if ic
    end

    def close_all(items)
      items.each { |item| close_if_open(item) }
    end

    private

    def close_if_open(item)
      c = @current.delete(item.name)
      return unless c && c[:depleted_on]

      @completed << Cycle.new(**c.merge(item_name: item.name))
    end
  end

  # Main simulation engine. Runs a day-by-day schedule through three-zone
  # triage matching MealPlanWriteService's orchestration.
  # Collaborators: Item, CycleTracker, Persona (behavioral parameters), Entry.
  # consume! runs every day; shopping events dispatch based on the schedule hash.
  class FaithfulSim
    attr_reader :items, :tracker, :ic_loads

    def initialize(items:, schedule:, persona:, rng:, days: SIM_DAYS)
      @items           = items
      @schedule        = schedule
      @persona         = persona
      @rng             = rng
      @days            = days
      @tracker         = CycleTracker.new
      @ic_loads        = []
      @pending_reports = {}
    end

    def run!
      (1..@days).each do |day|
        consume!(day)
        process_pending_reports!(day)
        process_event!(day) if @schedule[day]
      end
      @tracker.close_all(@items)
      self
    end

    private

    def consume!(day)
      @items.each do |item|
        next unless item.has_stock && day >= item.runs_out_on

        item.has_stock = false
        @tracker.record_depletion(item, day)
        maybe_schedule_report(item, day)
      end
    end

    def maybe_schedule_report(item, day)
      return unless @persona && @rng.rand < @persona.depletion_report_chance

      delay = gaussian_int(@persona.depletion_report_delay_mean,
                           @persona.depletion_report_delay_std)
      @pending_reports[item.name] = day + delay
    end

    def process_pending_reports!(day)
      due = @pending_reports.select { |_, report_day| day >= report_day }
      due.each_key do |name|
        @pending_reports.delete(name)
        item = @items.find { |i| i.name == name }
        next unless item&.entry && !item.has_stock && item.zone(day) == :on_hand

        item.entry.uncheck!(day)
        @tracker.update_ic(item)
      end
    end

    def process_event!(day)
      case @schedule[day]
      when :shop               then shop!(day, attention: 1.0)
      when :shop_partial       then shop!(day, attention: @persona&.ic_attention || 0.5)
      when :ghost_shop         then ghost_shop!(day)
      when :burst_consume      then burst_consume!(day)
      when :accidental_uncheck then accidental_uncheck_event!(day)
      end
    end

    # Schedule-driven accidental uncheck: buy the first depleted item,
    # then immediately uncheck it (cracked eggs scenario from raw schedules).
    def accidental_uncheck_event!(day)
      item = @items.find { |i| i.entry&.depleted? }
      return unless item

      item.entry.check!(day)
      @tracker.start_cycle(item, day)
      item.has_stock   = true
      fuzz             = @persona ? gaussian_int(0, @persona.fuzz_std) : 0
      item.runs_out_on = day + item.true_cycle + fuzz

      item.entry.uncheck!(day)
      item.has_stock = false
    end

    def shop!(day, attention:)
      @ic_loads << @items.count { |i| i.zone(day) == :expired }

      @items.each do |item|
        case item.zone(day)
        when :new
          triage_new!(item, day)
        when :expired
          next if attention < 1.0 && @rng.rand >= attention

          triage_expired!(item, day)
        when :on_hand
          triage_on_hand!(item, day)
        when :depleted
          purchase!(item, day)
        end

        maybe_accidental_uncheck!(item, day)
      end
    end

    def triage_new!(item, day)
      if item.has_stock
        item.entry = Entry.new(confirmed_at: day)
        @tracker.start_cycle(item, day)
      else
        item.entry = Entry.new(confirmed_at: SENTINEL)
        item.entry.instance_variable_set(:@depleted_at, day)
        purchase!(item, day)
      end
    end

    def triage_expired!(item, day)
      if item.has_stock
        item.entry.have_it!(day)
        @tracker.update_ic(item)
      else
        item.entry.need_it!(day)
        purchase!(item, day)
      end
    end

    def triage_on_hand!(item, day)
      return if item.has_stock

      item.entry.uncheck!(day)
      purchase!(item, day)
    end

    def purchase!(item, day)
      item.entry.check!(day) if item.entry.depleted?
      @tracker.start_cycle(item, day)
      item.has_stock   = true
      fuzz             = @persona ? gaussian_int(0, @persona.fuzz_std) : 0
      item.runs_out_on = day + item.true_cycle + fuzz
    end

    def ghost_shop!(day)
      @items.each do |item|
        next if item.has_stock

        item.has_stock   = true
        fuzz             = @persona ? gaussian_int(0, @persona.fuzz_std) : 0
        item.runs_out_on = day + item.true_cycle + fuzz
      end
    end

    def burst_consume!(day)
      @items.each do |item|
        next unless item.has_stock && item.true_cycle >= 14

        item.has_stock = false
        @tracker.record_depletion(item, day)
      end
    end

    def maybe_accidental_uncheck!(item, day)
      return unless @persona && @rng.rand < @persona.accident_rate
      return unless item.has_stock && item.entry && !item.entry.depleted?

      item.entry.uncheck!(day)
      item.has_stock = false
    end

    def gaussian_int(mean, std)
      return mean.to_i if std.zero?

      u1 = @rng.rand
      u2 = @rng.rand
      z  = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
      (mean + std * z).round.clamp(0..)
    end
  end

  # Stub for behavioral parameters. Full implementation added in Task 4.
  # Collaborators: FaithfulSim (reads all persona fields), ScheduleGenerator.
  Persona = Struct.new(
    :shop_interval_mean, :shop_interval_std,
    :ic_attention,
    :depletion_report_chance, :depletion_report_delay_mean, :depletion_report_delay_std,
    :vacation_gaps, :burst_days,
    :accident_rate, :ghost_shop_chance,
    :fuzz_std,
    keyword_init: true
  ) do
    def self.default
      new(
        shop_interval_mean: 7, shop_interval_std: 0,
        ic_attention: 1.0,
        depletion_report_chance: 0.0, depletion_report_delay_mean: 0,
        depletion_report_delay_std: 0,
        vacation_gaps: [], burst_days: [],
        accident_rate: 0.0, ghost_shop_chance: 0.0,
        fuzz_std: 0
      )
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  puts 'Entry smoke test...'

  e = GroceryAudit::Entry.new(confirmed_at: 0)
  abort 'FAIL: initial interval' unless e.interval == 7.0
  abort 'FAIL: initial ease' unless e.ease == 1.5
  abort 'FAIL: on_hand?(6)' unless e.on_hand?(6)
  abort 'FAIL: should be expired day 7' if e.on_hand?(7)
  abort 'FAIL: ic_fires_on' unless e.ic_fires_on == 7

  e2 = GroceryAudit::Entry.new(confirmed_at: GroceryAudit::SENTINEL)
  e2.have_it!(10)
  abort 'FAIL: grow_standard ease' unless (e2.ease - 1.55).abs < 0.001
  abort 'FAIL: grow_standard interval' unless (e2.interval - 10.85).abs < 0.001

  e3 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 14.0, ease: 1.5)
  e3.have_it!(14) # 0 + (14*1.55).to_i = 0 + 21 = 21 >= 14 → anchor holds
  abort 'FAIL: anchored ease' unless (e3.ease - 1.55).abs < 0.001
  abort 'FAIL: anchored confirmed_at stays' unless e3.confirmed_at == 0

  e4 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e4.have_it!(20) # 0 + (7*1.55).to_i = 0 + 10 = 10 < 20 → anchor breaks
  abort 'FAIL: broken anchor ease stays' unless (e4.ease - 1.5).abs < 0.001
  abort 'FAIL: broken anchor resets confirmed_at' unless e4.confirmed_at == 20

  e5 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e5.need_it!(14) # observed=14, blended=(14+7)/2=10.5, ease=1.5*0.85=1.275
  abort 'FAIL: deplete interval' unless (e5.interval - 10.5).abs < 0.001
  abort 'FAIL: deplete ease' unless (e5.ease - 1.275).abs < 0.001

  e6 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e6.need_it!(2) # observed=2, blended=(2+7)/2=4.5, floored to 7
  abort 'FAIL: deplete floor' unless (e6.interval - 7.0).abs < 0.001

  e7 = GroceryAudit::Entry.new(confirmed_at: 10, interval: 28.0, ease: 2.0)
  e7.uncheck!(10) # same day → undo
  abort 'FAIL: same-day interval preserved' unless (e7.interval - 28.0).abs < 0.001
  abort 'FAIL: same-day ease preserved' unless (e7.ease - 2.0).abs < 0.001

  puts 'Entry: all checks passed'

  puts "\nFaithfulSim smoke test..."

  persona = GroceryAudit::Persona.default
  schedule = {}
  (1..50).each { |d| schedule[d] = :shop if (d % 7).zero? }

  items = GroceryAudit::DEFAULT_ITEMS.map { |n, tc| GroceryAudit::Item.new(n, tc) }
  sim = GroceryAudit::FaithfulSim.new(
    items: items, schedule: schedule, persona: persona,
    rng: Random.new(42), days: 50
  )
  sim.run!

  cycles = sim.tracker.completed
  abort 'FAIL: no cycles recorded' if cycles.empty?

  egg_cycles = cycles.select { |c| c.item_name == 'Eggs' }
  abort 'FAIL: no egg cycles' if egg_cycles.empty?
  egg_cycles.each do |c|
    abort "FAIL: egg cycle missing depletion (#{c})" unless c.depleted_on
  end

  puts "FaithfulSim: #{cycles.size} cycles recorded across #{items.size} items"
  puts 'FaithfulSim: all checks passed'
end

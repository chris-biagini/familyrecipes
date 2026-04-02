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
  MIN_BUFFER        = 2
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
      confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i >= day
    end

    def depleted? = !depleted_at.nil?

    # First day the item appears in Inventory Check (on_hand? returns false).
    def ic_fires_on
      return nil if sentinel? || depleted?

      confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i + 1
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

  # Behavioral parameters controlling a simulated user's shopping habits.
  # Collaborators: FaithfulSim (reads all persona fields), ScheduleGenerator.
  # DEFAULTS uses fuzz_std: 2 to model realistic consumption variance.
  Persona = Struct.new(
    :shop_interval_mean, :shop_interval_std,
    :ic_attention,
    :depletion_report_chance, :depletion_report_delay_mean, :depletion_report_delay_std,
    :vacation_gaps, :burst_days,
    :accident_rate, :ghost_shop_chance,
    :fuzz_std,
    keyword_init: true
  ) do
    DEFAULTS = {
      shop_interval_mean: 7, shop_interval_std: 0,
      ic_attention: 1.0,
      depletion_report_chance: 0.0, depletion_report_delay_mean: 0,
      depletion_report_delay_std: 0,
      vacation_gaps: [], burst_days: [],
      accident_rate: 0.0, ghost_shop_chance: 0.0,
      fuzz_std: 2
    }.freeze

    def self.default = new(**DEFAULTS)
    def self.build(**overrides) = new(**DEFAULTS.merge(overrides))

    def disruption_days
      days = (vacation_gaps || []).map(&:first)
      days.concat(burst_days || [])
      days.sort
    end
  end

  # Generates a concrete schedule hash (day => event) from persona parameters.
  # Skips vacation days, applies ghost_shop_chance, uses :shop_partial when
  # ic_attention < 1.0. Overlays burst_days as :burst_consume.
  module ScheduleGenerator
    def self.generate(persona:, rng:, days: SIM_DAYS)
      require 'set'
      schedule     = {}
      vacation_set = build_vacation_set(persona.vacation_gaps || [])

      day = 0
      loop do
        gap = gaussian_int(persona.shop_interval_mean, persona.shop_interval_std, rng)
        gap = [gap, 1].max
        day += gap
        break if day > days
        next if vacation_set.include?(day)

        schedule[day] = if persona.ghost_shop_chance > 0 && rng.rand < persona.ghost_shop_chance
                          :ghost_shop
                        elsif persona.ic_attention < 1.0
                          :shop_partial
                        else
                          :shop
                        end
      end

      (persona.burst_days || []).each do |d|
        schedule[d] = :burst_consume if d <= days
      end

      schedule
    end

    def self.build_vacation_set(gaps)
      gaps.flat_map { |start, length| (start...start + length).to_a }.to_set
    end

    # Box-Muller gaussian, clamped to 1+ to avoid zero/negative intervals.
    def self.gaussian_int(mean, std, rng)
      return mean.to_i if std.zero?

      u1 = rng.rand
      u2 = rng.rand
      z  = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
      (mean + std * z).round.clamp(1..)
    end
  end

  # Classifies each cycle outcome and computes aggregate metrics.
  # Collaborators: CycleTracker (provides completed cycles), Cycle struct.
  # Timing classification compares IC fire date to actual depletion as a
  # fraction of true_cycle — earlier IC = more annoying false positives.
  class Scorer
    attr_reader :cycles

    def initialize(cycles, disruption_days: [])
      @cycles          = cycles
      @disruption_days = disruption_days
    end

    def classify(cycle)
      return :miss unless cycle.ic_fires_on
      return :miss if cycle.ic_fires_on > cycle.depleted_on

      earliness = (cycle.depleted_on - cycle.ic_fires_on).to_f / cycle.true_cycle
      if earliness <= 0.1 then :perfect
      elsif earliness <= 0.25 then :acceptable
      else :annoying
      end
    end

    def scorecard
      outcomes = @cycles.map { |c| classify(c) }
      n = outcomes.size
      return empty_scorecard if n.zero?

      {
        total_cycles:       n,
        perfect:            outcomes.count(:perfect),
        acceptable:         outcomes.count(:acceptable),
        annoying:           outcomes.count(:annoying),
        miss:               outcomes.count(:miss),
        hit_rate:           pct(outcomes.count(:perfect) + outcomes.count(:acceptable), n),
        miss_rate:          pct(outcomes.count(:miss), n),
        annoyance_rate:     pct(outcomes.count(:annoying), n),
        mean_ic_timing_pct: mean_ic_timing,
        avg_ic_load:        nil,
        recovery_cycles:    recovery_time
      }
    end

    def scorecard_with_ic_load(ic_loads)
      sc = scorecard
      sc[:avg_ic_load] = ic_loads.empty? ? 0.0 : ic_loads.sum.to_f / ic_loads.size
      sc
    end

    def per_item_breakdown
      @cycles.group_by(&:item_name).transform_values do |item_cycles|
        outcomes = item_cycles.map { |c| classify(c) }
        n = outcomes.size
        {
          cycles:         n,
          hit_rate:       pct(outcomes.count(:perfect) + outcomes.count(:acceptable), n),
          miss_rate:      pct(outcomes.count(:miss), n),
          annoyance_rate: pct(outcomes.count(:annoying), n)
        }
      end
    end

    private

    def pct(count, total) = total.zero? ? 0.0 : (count.to_f / total * 100)

    def mean_ic_timing
      with_ic = @cycles.select(&:ic_fires_on)
      return 0.0 if with_ic.empty?

      errors = with_ic.map { |c| (c.ic_fires_on - c.depleted_on).to_f / c.true_cycle * 100 }
      errors.sum / errors.size
    end

    def recovery_time
      return nil if @disruption_days.empty?

      recoveries = []
      by_item    = @cycles.group_by(&:item_name)

      @disruption_days.each do |dd|
        by_item.each_value do |item_cycles|
          sorted    = item_cycles.sort_by(&:purchased_on)
          start_idx = sorted.index { |c| c.purchased_on >= dd }
          next unless start_idx

          count = 0
          sorted[start_idx..].each do |c|
            outcome = classify(c)
            break if outcome == :perfect || outcome == :acceptable

            count += 1
          end
          recoveries << count
        end
      end

      recoveries.empty? ? nil : (recoveries.sum.to_f / recoveries.size).round(1)
    end

    def empty_scorecard
      { total_cycles: 0, perfect: 0, acceptable: 0, annoying: 0, miss: 0,
        hit_rate: 0.0, miss_rate: 0.0, annoyance_rate: 0.0,
        mean_ic_timing_pct: 0.0, avg_ic_load: nil, recovery_cycles: nil }
    end
  end

  # Formats scorecards and comparison tables for stdout output.
  # Collaborators: Scorer (scorecard/per_item_breakdown), run_scenario results.
  class Reporter
    def self.scenario_report(name, scorer, ic_loads)
      sc = scorer.scorecard_with_ic_load(ic_loads)
      puts "\n#{'=' * 70}"
      puts name
      puts '=' * 70
      puts format('  Cycles: %d | Hit: %.1f%% | Miss: %.1f%% | Annoying: %.1f%%',
                  sc[:total_cycles], sc[:hit_rate], sc[:miss_rate], sc[:annoyance_rate])
      puts format('  Avg IC timing: %+.1f%% of cycle | Avg IC load: %.1f items/trip',
                  sc[:mean_ic_timing_pct], sc[:avg_ic_load] || 0)
      puts format('  Recovery: %s cycles after disruption',
                  sc[:recovery_cycles] ? sc[:recovery_cycles].to_s : 'N/A')

      puts "\n  Per-item breakdown:"
      puts format('  %-10s  %5s  %6s  %6s  %6s', 'Item', 'Cycles', 'Hit%', 'Miss%', 'Annoy%')
      puts '  ' + ('-' * 40)
      scorer.per_item_breakdown.each do |name_str, data|
        puts format('  %-10s  %5d  %5.1f%%  %5.1f%%  %5.1f%%',
                    name_str, data[:cycles], data[:hit_rate], data[:miss_rate],
                    data[:annoyance_rate])
      end
    end

    def self.comparison_table(results)
      puts "\n\n#{'=' * 70}"
      puts 'COMPARISON: All scenarios'
      puts '=' * 70

      header = format('  %-30s  %5s  %5s  %5s  %5s  %5s',
                      'Scenario', 'Cyc', 'Hit%', 'Miss%', 'Ann%', 'IC/trip')
      puts header
      puts '  ' + ('-' * 62)

      results.each do |r|
        sc = r[:scorecard]
        puts format('  %-30s  %5d  %4.1f%%  %4.1f%%  %4.1f%%  %5.1f',
                    r[:name][0..29], sc[:total_cycles], sc[:hit_rate], sc[:miss_rate],
                    sc[:annoyance_rate], sc[:avg_ic_load] || 0)
      end
    end

    def self.sweep_report(ranked, count: 20)
      puts "\n\n#{'=' * 70}"
      puts "MONTE CARLO SWEEP: Top #{count} worst personas (of #{ranked.size})"
      puts '=' * 70

      ranked.first(count).each_with_index do |r, i|
        sc = r[:scorecard]
        p  = r[:persona]
        puts format("\n  #%d — Miss: %.1f%% | Annoy: %.1f%% | Hit: %.1f%%",
                    i + 1, sc[:miss_rate], sc[:annoyance_rate], sc[:hit_rate])
        puts format('    shop=%dd±%d, attn=%.0f%%, report=%.0f%%, delay=%dd, ' \
                    'acc=%.1f%%, ghost=%.0f%%, fuzz=%d',
                    p.shop_interval_mean, p.shop_interval_std,
                    p.ic_attention * 100, p.depletion_report_chance * 100,
                    p.depletion_report_delay_mean, p.accident_rate * 100,
                    p.ghost_shop_chance * 100, p.fuzz_std)
        puts format('    vac=%d gaps, bursts=%d', p.vacation_gaps.size, p.burst_days.size)

        r[:scorer].per_item_breakdown.each do |name_str, data|
          puts format('    %-10s  hit=%5.1f%%  miss=%5.1f%%  annoy=%5.1f%%',
                      name_str, data[:hit_rate], data[:miss_rate], data[:annoyance_rate])
        end

        dump_schedule(r[:schedule]) if i < 5
      end
    end

    def self.sweep_summary(ranked)
      puts "\n  Distribution across all #{ranked.size} personas:"
      %i[hit_rate miss_rate annoyance_rate].each do |metric|
        values = ranked.map { |r| r[:scorecard][metric] }.sort
        puts format('    %-15s  median=%5.1f%%  p90=%5.1f%%  p99=%5.1f%%  worst=%5.1f%%',
                    metric, percentile(values, 50), percentile(values, 90),
                    percentile(values, 99), values.last)
      end
    end

    def self.dump_schedule(schedule)
      return unless schedule

      puts '    Schedule:'
      schedule.sort.each do |day, event|
        puts format('      day %3d: %s', day, event)
      end
    end

    def self.percentile(sorted, pct)
      return 0 if sorted.empty?

      idx = (pct / 100.0 * (sorted.size - 1)).round
      sorted[idx]
    end
  end

  def self.run_scenario(name:, persona: nil, schedule: nil, seed: 42, days: SIM_DAYS)
    persona  ||= Persona.default
    rng      = Random.new(seed)
    schedule ||= ScheduleGenerator.generate(persona:, rng:, days:)
    items    = DEFAULT_ITEMS.map { |n, tc| Item.new(n, tc) }
    sim      = FaithfulSim.new(items:, schedule:, persona:, rng:, days:)
    sim.run!
    scorer = Scorer.new(sim.tracker.completed, disruption_days: persona.disruption_days)
    sc     = scorer.scorecard_with_ic_load(sim.ic_loads)
    { name:, scorer:, scorecard: sc, persona:, sim:, schedule: }
  end

  # The 15 handcrafted audit scenarios, covering baseline behavior, cadence
  # variation, life disruptions, inattentive users, and edge cases.
  # Each method returns a result hash from run_scenario.
  module Scenarios
    def self.all
      [s1_perfect_user, s2_frequent_shopper, s3_biweekly_shopper,
       s4_alternating_cadence, s5_gradual_drift, s6_random_intervals,
       s7_two_week_vacation, s8_repeated_vacations,
       s9_holiday_baker, s10_post_vacation_burst,
       s11_ic_ignorer, s12_delayed_reporter, s13_ghost_shopper,
       s14_butterfingers, s15_binge_and_forget]
    end

    # --- Baseline ---

    def self.s1_perfect_user
      GroceryAudit.run_scenario(name: 'S1: Perfect user (weekly, fuzz±2)',
                                persona: Persona.default)
    end

    def self.s2_frequent_shopper
      GroceryAudit.run_scenario(name: 'S2: Frequent shopper (every 3d)',
                                persona: Persona.build(shop_interval_mean: 3))
    end

    def self.s3_biweekly_shopper
      GroceryAudit.run_scenario(name: 'S3: Biweekly shopper (every 14d)',
                                persona: Persona.build(shop_interval_mean: 14))
    end

    # --- Inconsistent cadence ---

    def self.s4_alternating_cadence
      schedule = {}
      day = 0
      interval_toggle = [3, 14].cycle
      while day < SIM_DAYS
        day += interval_toggle.next
        schedule[day] = :shop if day <= SIM_DAYS
      end
      GroceryAudit.run_scenario(name: 'S4: Alternating cadence (3d/14d)',
                                persona: Persona.default,
                                schedule:)
    end

    def self.s5_gradual_drift
      schedule = {}
      day = 0
      (1..SIM_DAYS).each do |d|
        interval = if d <= 90 then 7
                   elsif d <= 150 then 7 + ((d - 90).to_f / 60 * 7).round
                   elsif d <= 240 then 14
                   elsif d <= 300 then 14 - ((d - 240).to_f / 60 * 7).round
                   else 7
                   end
        if d > day
          day = d
          schedule[day] = :shop
          day += interval - 1
        end
      end
      GroceryAudit.run_scenario(name: 'S5: Gradual drift (7d→14d→7d)',
                                persona: Persona.default,
                                schedule:)
    end

    def self.s6_random_intervals
      GroceryAudit.run_scenario(name: 'S6: Random intervals (mean=8d, std=4)',
                                persona: Persona.build(shop_interval_mean: 8, shop_interval_std: 4))
    end

    # --- Life disruptions ---

    def self.s7_two_week_vacation
      GroceryAudit.run_scenario(name: 'S7: Two-week vacation (day 100)',
                                persona: Persona.build(vacation_gaps: [[100, 14]]))
    end

    def self.s8_repeated_vacations
      GroceryAudit.run_scenario(name: 'S8: Repeated vacations (3×10d)',
                                persona: Persona.build(vacation_gaps: [[80, 10], [180, 10], [280, 10]]))
    end

    def self.s9_holiday_baker
      GroceryAudit.run_scenario(name: 'S9: Holiday baker (burst days 80, 170)',
                                persona: Persona.build(burst_days: [80, 170]))
    end

    def self.s10_post_vacation_burst
      GroceryAudit.run_scenario(name: 'S10: Post-vacation burst (vac day 100, burst day 115)',
                                persona: Persona.build(vacation_gaps: [[100, 14]], burst_days: [115]))
    end

    # --- Inattentive users ---

    def self.s11_ic_ignorer
      GroceryAudit.run_scenario(name: 'S11: IC ignorer (50% attention)',
                                persona: Persona.build(ic_attention: 0.5))
    end

    def self.s12_delayed_reporter
      GroceryAudit.run_scenario(name: 'S12: Delayed reporter (80% chance, 4d delay)',
                                persona: Persona.build(depletion_report_chance: 0.8,
                                                       depletion_report_delay_mean: 4,
                                                       depletion_report_delay_std: 1))
    end

    def self.s13_ghost_shopper
      GroceryAudit.run_scenario(name: 'S13: Ghost shopper (20% untracked trips)',
                                persona: Persona.build(ghost_shop_chance: 0.2))
    end

    # --- Mistakes and edge cases ---

    def self.s14_butterfingers
      GroceryAudit.run_scenario(name: 'S14: Butterfingers (5% accident rate)',
                                persona: Persona.build(accident_rate: 0.05))
    end

    def self.s15_binge_and_forget
      schedule = {}
      day = 0
      while day < 60
        day += 5
        schedule[day] = :shop
      end
      day = 90
      while day < SIM_DAYS
        day += 7
        schedule[day] = :shop if day <= SIM_DAYS
      end
      GroceryAudit.run_scenario(name: 'S15: Binge and forget (5d/60d, pause, weekly)',
                                persona: Persona.default,
                                schedule:)
    end
  end
  # Randomized parameter sweep over 5,000 synthetic personas to surface
  # edge cases that handcrafted scenarios miss. Seeds are derived from a
  # single master RNG so results are fully reproducible.
  # Collaborators: Persona.build, GroceryAudit.run_scenario, Reporter.
  module MonteCarlo
    SWEEP_SIZE  = 5_000
    MASTER_SEED = 12_345

    PARAM_RANGES = {
      shop_interval_mean:          2..21,
      shop_interval_std:           0..5,
      ic_attention:                0.3..1.0,
      depletion_report_chance:     0.0..1.0,
      depletion_report_delay_mean: 0..7,
      depletion_report_delay_std:  0..2,
      vacation_count:              0..3,
      vacation_length:             7..21,
      burst_count:                 0..4,
      accident_rate:               0.0..0.1,
      ghost_shop_chance:           0.0..0.3,
      fuzz_std:                    0..4
    }.freeze

    def self.run!(size: SWEEP_SIZE)
      master_rng = Random.new(MASTER_SEED)

      results = (1..size).map do |i|
        seed    = master_rng.rand(1..999_999)
        persona = random_persona(master_rng)
        result  = GroceryAudit.run_scenario(name: "MC-#{i}", persona:, seed:)
        result[:persona] = persona
        $stderr.print "\r  Sweep: #{i}/#{size}" if (i % 500).zero? || i == size
        result
      end
      $stderr.puts

      results.sort_by! { |r| [-r[:scorecard][:miss_rate], -r[:scorecard][:annoyance_rate]] }
      results
    end

    def self.random_persona(rng)
      vac_count = rng.rand(PARAM_RANGES[:vacation_count])
      vac_len   = PARAM_RANGES[:vacation_length]
      vacations = (1..vac_count).map do
        start  = rng.rand(30..300)
        length = rng.rand(vac_len)
        [start, length]
      end

      burst_count = rng.rand(PARAM_RANGES[:burst_count])
      bursts      = (1..burst_count).map { rng.rand(30..330) }

      Persona.build(
        shop_interval_mean:          rng.rand(PARAM_RANGES[:shop_interval_mean]),
        shop_interval_std:           rng.rand(PARAM_RANGES[:shop_interval_std]),
        ic_attention:                rand_float(rng, PARAM_RANGES[:ic_attention]),
        depletion_report_chance:     rand_float(rng, PARAM_RANGES[:depletion_report_chance]),
        depletion_report_delay_mean: rng.rand(PARAM_RANGES[:depletion_report_delay_mean]),
        depletion_report_delay_std:  rng.rand(PARAM_RANGES[:depletion_report_delay_std]),
        vacation_gaps:               vacations,
        burst_days:                  bursts,
        accident_rate:               rand_float(rng, PARAM_RANGES[:accident_rate]),
        ghost_shop_chance:           rand_float(rng, PARAM_RANGES[:ghost_shop_chance]),
        fuzz_std:                    rng.rand(PARAM_RANGES[:fuzz_std])
      )
    end

    def self.rand_float(rng, range)
      range.begin + rng.rand * (range.end - range.begin)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'set'

  puts 'Grocery Algorithm Audit'
  puts "#{GroceryAudit::SIM_DAYS} simulated days, #{GroceryAudit::DEFAULT_ITEMS.size} items"

  # ---- Handcrafted scenarios ----
  puts "\n--- HANDCRAFTED SCENARIOS ---"
  results = GroceryAudit::Scenarios.all
  results.each { |r| GroceryAudit::Reporter.scenario_report(r[:name], r[:scorer], r[:sim].ic_loads) }
  GroceryAudit::Reporter.comparison_table(results)

  # ---- Monte Carlo sweep ----
  puts "\n\n--- MONTE CARLO SWEEP ---"
  sweep = GroceryAudit::MonteCarlo.run!
  GroceryAudit::Reporter.sweep_report(sweep)
  GroceryAudit::Reporter.sweep_summary(sweep)
end

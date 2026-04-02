# Grocery Algorithm Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a comprehensive simulation audit that measures how often the SM-2-inspired grocery algorithm is helpful vs. annoying across 15 handcrafted scenarios and a 5,000-persona Monte Carlo sweep.

**Architecture:** A single standalone Ruby script (`test/sim/grocery_audit.rb`) with a `GroceryAudit` module containing: `Entry` (mirrors `OnHandEntry` math exactly), `Item` (ground truth tracking), `FaithfulSim` (three-zone triage loop), `CycleTracker` (per-cycle bookkeeping), `Scorer` (outcome classification and aggregation), `Persona`/`ScheduleGenerator` (behavioral parameters → concrete schedules), `Reporter` (formatted output). A separate Minitest conformance test proves the sim matches production.

**Tech Stack:** Ruby (standalone, no Rails dependency for sim). Minitest + Rails for conformance test.

**Design spec:** `docs/superpowers/specs/2026-04-02-grocery-algorithm-audit-design.md`

---

## File Structure

- **Create:** `test/sim/grocery_audit.rb` — the complete audit script
- **Create:** `test/models/on_hand_entry_conformance_test.rb` — proves sim matches production
- **Delete:** `test/sim/grocery_convergence.rb` — replaced by audit
- **Delete:** `test/sim/grocery_delayed_signals.rb` — replaced by audit
- **Delete:** `test/sim/grocery_real_world.rb` — replaced by audit

---

### Task 1: Module skeleton + Entry class

**Files:**
- Create: `test/sim/grocery_audit.rb`

The Entry class mirrors `OnHandEntry`'s exact math: same constants, same method names, same formulas. Uses integer day numbers instead of Date objects (SENTINEL = -999_999 maps to production's `Date.parse('1970-01-01')`).

Critical implementation details from `app/models/on_hand_entry.rb`:
- `grow_standard`: bumps ease FIRST, then multiplies interval by the ALREADY-BUMPED ease
- `grow_anchored`: computes tentative new_ease, multiplies interval, then checks anchor with `interval.to_i` (not `(interval * SAFETY_MARGIN).to_i`). Ease only committed if anchor holds.
- `deplete_observed`: blends `(observed + interval) / 2.0`, then floors at `STARTING_INTERVAL`. (Old sims did this in the wrong order — floored obs first, then blended.)
- `on_hand?`: uses `(interval * SAFETY_MARGIN).to_i` — truncation, not rounding
- IC fires on the first day `on_hand?` returns false: `confirmed_at + (interval * SAFETY_MARGIN).to_i + 1`

- [ ] **Step 1: Create the file with module, constants, and Entry class**

```ruby
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
```

- [ ] **Step 2: Add inline verification at the bottom of the file**

Append after the module closing `end`:

```ruby
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

  # grow_anchored: anchor holds
  e3 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 14.0, ease: 1.5)
  e3.have_it!(10) # 0 + (14*1.55).to_i = 0 + 21 = 21 >= 10 → anchor holds
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
```

- [ ] **Step 3: Run the smoke test**

Run: `ruby test/sim/grocery_audit.rb`
Expected: `Entry: all checks passed`

- [ ] **Step 4: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add GroceryAudit module with Entry class mirroring OnHandEntry"
```

---

### Task 2: Item class + CycleTracker + FaithfulSim

**Files:**
- Modify: `test/sim/grocery_audit.rb`

The simulation engine. `Item` wraps `Entry` with ground truth stock tracking. `CycleTracker` records purchase-to-purchase cycles for scoring. `FaithfulSim` processes a day-by-day schedule with three-zone triage matching `MealPlanWriteService`'s orchestration.

Key behaviors:
- `consume!` runs every day — ground truth stock depletion happens regardless of shopping
- `shop!` processes all items through three-zone triage (expired/depleted/on_hand/new)
- `shop_partial!` skips expired items with probability `1 - ic_attention`
- `ghost_shop!` restocks ground truth without any app interaction
- `burst_consume!` depletes all long-cycle on-hand items immediately
- `maybe_accidental_uncheck!` rolls per-item after each triage
- Pending mid-week depletion reports are tracked and fired with configurable delay

- [ ] **Step 1: Add Item and CycleTracker classes**

Insert inside the `GroceryAudit` module, after the `Entry` class:

```ruby
  Cycle = Struct.new(:item_name, :true_cycle, :purchased_on, :depleted_on,
                     :ic_fires_on, keyword_init: true)

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
```

- [ ] **Step 2: Add FaithfulSim class**

Insert inside the module, after `CycleTracker`:

```ruby
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
          if attention < 1.0 && @rng.rand >= attention
            next
          end
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
```

- [ ] **Step 3: Update the smoke test**

Replace the existing `if __FILE__` block with:

```ruby
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
  e3.have_it!(10)
  abort 'FAIL: anchored ease' unless (e3.ease - 1.55).abs < 0.001
  abort 'FAIL: anchored confirmed_at stays' unless e3.confirmed_at == 0

  e4 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e4.have_it!(20)
  abort 'FAIL: broken anchor ease stays' unless (e4.ease - 1.5).abs < 0.001
  abort 'FAIL: broken anchor resets confirmed_at' unless e4.confirmed_at == 20

  e5 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e5.need_it!(14)
  abort 'FAIL: deplete interval' unless (e5.interval - 10.5).abs < 0.001
  abort 'FAIL: deplete ease' unless (e5.ease - 1.275).abs < 0.001

  e6 = GroceryAudit::Entry.new(confirmed_at: 0, interval: 7.0, ease: 1.5)
  e6.need_it!(2)
  abort 'FAIL: deplete floor' unless (e6.interval - 7.0).abs < 0.001

  e7 = GroceryAudit::Entry.new(confirmed_at: 10, interval: 28.0, ease: 2.0)
  e7.uncheck!(10)
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
```

Note: This step references `Persona.default` which doesn't exist yet. It will be added in Task 4. For now, create a minimal placeholder so the smoke test runs:

Insert inside the module, after `FaithfulSim`:

```ruby
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
```

- [ ] **Step 4: Run the smoke test**

Run: `ruby test/sim/grocery_audit.rb`
Expected: Both "Entry: all checks passed" and "FaithfulSim: all checks passed"

- [ ] **Step 5: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add Item, CycleTracker, and FaithfulSim to grocery audit"
```

---

### Task 3: Scorer + Reporter

**Files:**
- Modify: `test/sim/grocery_audit.rb`

The `Scorer` classifies each cycle and computes aggregate metrics. The `Reporter` formats scorecards and comparison tables for stdout.

Outcome classification (comparing `ic_fires_on` to `depleted_on` as a fraction of `true_cycle`):
- `:perfect` — IC fires 0–10% of true cycle before depletion
- `:acceptable` — IC fires 10–25% early
- `:annoying` — IC fires 25%+ early
- `:miss` — IC fires after depletion, or never fires

- [ ] **Step 1: Add Scorer class**

Insert inside the module, after the `Persona` struct:

```ruby
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
        total_cycles:        n,
        perfect:             outcomes.count(:perfect),
        acceptable:          outcomes.count(:acceptable),
        annoying:            outcomes.count(:annoying),
        miss:                outcomes.count(:miss),
        hit_rate:            pct(outcomes.count(:perfect) + outcomes.count(:acceptable), n),
        miss_rate:           pct(outcomes.count(:miss), n),
        annoyance_rate:      pct(outcomes.count(:annoying), n),
        mean_ic_timing_pct:  mean_ic_timing,
        avg_ic_load:         nil,
        recovery_cycles:     recovery_time
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

      errors = with_ic.map do |c|
        (c.ic_fires_on - c.depleted_on).to_f / c.true_cycle * 100
      end
      errors.sum / errors.size
    end

    def recovery_time
      return nil if @disruption_days.empty?

      recoveries = []
      by_item = @cycles.group_by(&:item_name)

      @disruption_days.each do |dd|
        by_item.each_value do |item_cycles|
          sorted = item_cycles.sort_by(&:purchased_on)
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
```

- [ ] **Step 2: Add Reporter class**

Insert after `Scorer`:

```ruby
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
        p = r[:persona]
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

    def self.dump_schedule(schedule)
      return unless schedule

      puts '    Schedule:'
      schedule.sort.each do |day, event|
        puts format('      day %3d: %s', day, event)
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

    def self.percentile(sorted, pct)
      return 0 if sorted.empty?

      idx = (pct / 100.0 * (sorted.size - 1)).round
      sorted[idx]
    end
  end
```

- [ ] **Step 3: Update the smoke test to exercise Scorer**

Append to the `if __FILE__` block, before the final output:

```ruby
  puts "\nScorer smoke test..."

  scorer = GroceryAudit::Scorer.new(cycles)
  sc = scorer.scorecard_with_ic_load(sim.ic_loads)
  abort 'FAIL: scorecard missing hit_rate' unless sc[:hit_rate]
  abort 'FAIL: rates should sum to ~100' unless (sc[:hit_rate] + sc[:miss_rate] + sc[:annoyance_rate] - 100.0).abs < 1.0

  puts "Scorer: hit=#{sc[:hit_rate].round(1)}% miss=#{sc[:miss_rate].round(1)}% annoy=#{sc[:annoyance_rate].round(1)}%"
  puts 'Scorer: all checks passed'
```

- [ ] **Step 4: Run the smoke test**

Run: `ruby test/sim/grocery_audit.rb`
Expected: All three sections pass (Entry, FaithfulSim, Scorer)

- [ ] **Step 5: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add Scorer and Reporter to grocery audit"
```

---

### Task 4: Persona defaults + ScheduleGenerator + scenario runner

**Files:**
- Modify: `test/sim/grocery_audit.rb`

Extend the `Persona` struct with a `with` helper for creating variants, add `ScheduleGenerator` to turn personas into concrete schedules, and add a `run_scenario` module method that wires everything together.

- [ ] **Step 1: Extend Persona with helper methods**

Replace the existing `Persona` struct definition with:

```ruby
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
```

- [ ] **Step 2: Add ScheduleGenerator**

Insert after the `Persona` struct:

```ruby
  module ScheduleGenerator
    def self.generate(persona:, rng:, days: SIM_DAYS)
      schedule = {}
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

    def self.gaussian_int(mean, std, rng)
      return mean.to_i if std.zero?

      u1 = rng.rand
      u2 = rng.rand
      z  = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
      (mean + std * z).round.clamp(1..)
    end
  end
```

- [ ] **Step 3: Add run_scenario module method**

Insert after `ScheduleGenerator`:

```ruby
  def self.run_scenario(name:, persona: nil, schedule: nil, seed: 42, days: SIM_DAYS)
    persona ||= Persona.default
    rng = Random.new(seed)
    schedule ||= ScheduleGenerator.generate(persona:, rng:, days:)

    items = DEFAULT_ITEMS.map { |n, tc| Item.new(n, tc) }
    sim   = FaithfulSim.new(items:, schedule:, persona:, rng:, days:)
    sim.run!

    scorer = Scorer.new(sim.tracker.completed, disruption_days: persona.disruption_days)
    sc     = scorer.scorecard_with_ic_load(sim.ic_loads)

    { name:, scorer:, scorecard: sc, persona:, sim:, schedule: }
  end
```

- [ ] **Step 4: Update smoke test to use `run_scenario`**

Replace the FaithfulSim section of the smoke test with:

```ruby
  puts "\nFaithfulSim smoke test..."

  result = GroceryAudit.run_scenario(
    name: 'Smoke test',
    persona: GroceryAudit::Persona.build(fuzz_std: 0),
    days: 50
  )
  cycles = result[:scorer].cycles
  abort 'FAIL: no cycles recorded' if cycles.empty?

  egg_cycles = cycles.select { |c| c.item_name == 'Eggs' }
  abort 'FAIL: no egg cycles' if egg_cycles.empty?

  puts "FaithfulSim: #{cycles.size} cycles across #{GroceryAudit::DEFAULT_ITEMS.size} items"
  puts 'FaithfulSim: all checks passed'

  puts "\nScorer smoke test..."

  sc = result[:scorecard]
  abort 'FAIL: scorecard missing hit_rate' unless sc[:hit_rate]
  total = sc[:hit_rate] + sc[:miss_rate] + sc[:annoyance_rate]
  abort "FAIL: rates sum to #{total.round(1)}, expected ~100" unless (total - 100.0).abs < 1.0

  puts "Scorer: hit=#{sc[:hit_rate].round(1)}% miss=#{sc[:miss_rate].round(1)}% annoy=#{sc[:annoyance_rate].round(1)}%"
  puts 'Scorer: all checks passed'
```

- [ ] **Step 5: Run the smoke test**

Run: `ruby test/sim/grocery_audit.rb`
Expected: All checks pass

- [ ] **Step 6: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add Persona, ScheduleGenerator, and run_scenario to grocery audit"
```

---

### Task 5: Handcrafted scenarios 1–8

**Files:**
- Modify: `test/sim/grocery_audit.rb`

First eight scenarios: baseline (3), inconsistent cadence (3), life disruptions (2). Each scenario is a named method returning a result hash from `run_scenario`.

- [ ] **Step 1: Add scenario methods**

Insert inside the module, after `run_scenario`:

```ruby
  module Scenarios
    def self.all
      [s1_perfect_user, s2_frequent_shopper, s3_biweekly_shopper,
       s4_alternating_cadence, s5_gradual_drift, s6_random_intervals,
       s7_two_week_vacation, s8_repeated_vacations]
    end

    def self.s1_perfect_user
      GroceryAudit.run_scenario(
        name: '1. Perfect user (weekly, fuzz±2)',
        persona: Persona.default
      )
    end

    def self.s2_frequent_shopper
      GroceryAudit.run_scenario(
        name: '2. Frequent shopper (every 3d)',
        persona: Persona.build(shop_interval_mean: 3)
      )
    end

    def self.s3_biweekly_shopper
      GroceryAudit.run_scenario(
        name: '3. Biweekly shopper (every 14d)',
        persona: Persona.build(shop_interval_mean: 14)
      )
    end

    def self.s4_alternating_cadence
      schedule = {}
      day = 0
      intervals = [3, 14]
      idx = 0
      while day < SIM_DAYS
        day += intervals[idx]
        schedule[day] = :shop if day <= SIM_DAYS
        idx = (idx + 1) % 2
      end

      GroceryAudit.run_scenario(
        name: '4. Alternating cadence (3d/14d)',
        persona: Persona.default,
        schedule: schedule
      )
    end

    def self.s5_gradual_drift
      schedule = {}
      day = 0
      (1..SIM_DAYS).each do |d|
        interval = if d <= 90
                     7
                   elsif d <= 150
                     7 + ((d - 90).to_f / 60 * 7).round # 7 → 14 over 60 days
                   elsif d <= 240
                     14
                   elsif d <= 300
                     14 - ((d - 240).to_f / 60 * 7).round # 14 → 7 over 60 days
                   else
                     7
                   end
        if d > day
          day = d
          schedule[day] = :shop
          day += interval - 1
        end
      end

      GroceryAudit.run_scenario(
        name: '5. Gradual drift (7d→14d→7d)',
        persona: Persona.default,
        schedule: schedule
      )
    end

    def self.s6_random_intervals
      GroceryAudit.run_scenario(
        name: '6. Random intervals (8d±4)',
        persona: Persona.build(shop_interval_mean: 8, shop_interval_std: 4)
      )
    end

    def self.s7_two_week_vacation
      GroceryAudit.run_scenario(
        name: '7. Two-week vacation (day 100-114)',
        persona: Persona.build(vacation_gaps: [[100, 14]])
      )
    end

    def self.s8_repeated_vacations
      GroceryAudit.run_scenario(
        name: '8. Repeated vacations (3×10d)',
        persona: Persona.build(vacation_gaps: [[80, 10], [180, 10], [280, 10]])
      )
    end
  end
```

- [ ] **Step 2: Replace the smoke test with a real runner**

Replace the `if __FILE__` block with:

```ruby
if __FILE__ == $PROGRAM_NAME
  require 'set'

  puts 'Grocery Algorithm Audit'
  puts "#{SIM_DAYS} simulated days, #{DEFAULT_ITEMS.size} items"
  puts

  results = GroceryAudit::Scenarios.all
  results.each { |r| GroceryAudit::Reporter.scenario_report(r[:name], r[:scorer], r[:sim].ic_loads) }
  GroceryAudit::Reporter.comparison_table(results)
end
```

- [ ] **Step 3: Run the audit**

Run: `ruby test/sim/grocery_audit.rb`
Expected: Eight scenario reports with scorecards and a comparison table. Verify:
- Perfect user should have high hit rate (>60%)
- Alternating cadence should show higher annoyance or miss rate than perfect user

- [ ] **Step 4: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add handcrafted scenarios 1-8 to grocery audit"
```

---

### Task 6: Handcrafted scenarios 9–15

**Files:**
- Modify: `test/sim/grocery_audit.rb`

Remaining seven scenarios: life disruptions (2), inattentive users (3), mistakes and edge cases (2).

- [ ] **Step 1: Add scenario methods 9–15**

Add to the `Scenarios` module, updating the `all` method:

```ruby
    def self.all
      [s1_perfect_user, s2_frequent_shopper, s3_biweekly_shopper,
       s4_alternating_cadence, s5_gradual_drift, s6_random_intervals,
       s7_two_week_vacation, s8_repeated_vacations,
       s9_holiday_baker, s10_post_vacation_burst,
       s11_ic_ignorer, s12_delayed_reporter, s13_ghost_shopper,
       s14_butterfingers, s15_binge_and_forget]
    end

    def self.s9_holiday_baker
      GroceryAudit.run_scenario(
        name: '9. Holiday baker (bursts day 80, 170)',
        persona: Persona.build(burst_days: [80, 170])
      )
    end

    def self.s10_post_vacation_burst
      GroceryAudit.run_scenario(
        name: '10. Post-vacation burst',
        persona: Persona.build(vacation_gaps: [[100, 14]], burst_days: [115])
      )
    end

    def self.s11_ic_ignorer
      GroceryAudit.run_scenario(
        name: '11. IC ignorer (50% attention)',
        persona: Persona.build(ic_attention: 0.5)
      )
    end

    def self.s12_delayed_reporter
      GroceryAudit.run_scenario(
        name: '12. Delayed reporter (4d delay)',
        persona: Persona.build(
          depletion_report_chance: 0.8,
          depletion_report_delay_mean: 4,
          depletion_report_delay_std: 1
        )
      )
    end

    def self.s13_ghost_shopper
      GroceryAudit.run_scenario(
        name: '13. Ghost shopper (20% ghost)',
        persona: Persona.build(ghost_shop_chance: 0.2)
      )
    end

    def self.s14_butterfingers
      GroceryAudit.run_scenario(
        name: '14. Butterfingers (5% accidents)',
        persona: Persona.build(accident_rate: 0.05)
      )
    end

    def self.s15_binge_and_forget
      schedule = {}
      # Intense: shop every 5 days for 60 days
      day = 0
      while day < 60
        day += 5
        schedule[day] = :shop
      end
      # Dormant: no shopping for 30 days (day 60-90)
      # Resume: weekly for the rest
      day = 90
      while day < SIM_DAYS
        day += 7
        schedule[day] = :shop if day <= SIM_DAYS
      end

      GroceryAudit.run_scenario(
        name: '15. Binge and forget (60d on, 30d off)',
        persona: Persona.default,
        schedule: schedule
      )
    end
```

- [ ] **Step 2: Run the full handcrafted suite**

Run: `ruby test/sim/grocery_audit.rb`
Expected: All 15 scenario reports print. Verify:
- IC ignorer should show higher miss or annoyance rates
- Ghost shopper should show interval inflation effects
- Binge and forget should show recovery after the dormant period

- [ ] **Step 3: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add handcrafted scenarios 9-15 to grocery audit"
```

---

### Task 7: Monte Carlo sweep + main entry point

**Files:**
- Modify: `test/sim/grocery_audit.rb`

Generate 5,000 random personas, run each, rank by worst UX scores, print top-20 and distribution summary.

- [ ] **Step 1: Add MonteCarlo module**

Insert inside `GroceryAudit`, after the `Scenarios` module:

```ruby
  module MonteCarlo
    SWEEP_SIZE = 5_000
    MASTER_SEED = 12_345

    PARAM_RANGES = {
      shop_interval_mean: 2..21,
      shop_interval_std: 0..5,
      ic_attention: 0.3..1.0,
      depletion_report_chance: 0.0..1.0,
      depletion_report_delay_mean: 0..7,
      depletion_report_delay_std: 0..2,
      vacation_count: 0..3,
      vacation_length: 7..21,
      burst_count: 0..4,
      accident_rate: 0.0..0.1,
      ghost_shop_chance: 0.0..0.3,
      fuzz_std: 0..4
    }.freeze

    def self.run!(size: SWEEP_SIZE)
      master_rng = Random.new(MASTER_SEED)

      results = (1..size).map do |i|
        seed = master_rng.rand(1..999_999)
        persona = random_persona(master_rng)
        result = GroceryAudit.run_scenario(name: "MC-#{i}", persona:, seed:)
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
        start = rng.rand(30..300)
        length = rng.rand(vac_len)
        [start, length]
      end

      burst_count = rng.rand(PARAM_RANGES[:burst_count])
      bursts = (1..burst_count).map { rng.rand(30..330) }

      Persona.build(
        shop_interval_mean:        rng.rand(PARAM_RANGES[:shop_interval_mean]),
        shop_interval_std:         rng.rand(PARAM_RANGES[:shop_interval_std]),
        ic_attention:              rand_float(rng, PARAM_RANGES[:ic_attention]),
        depletion_report_chance:   rand_float(rng, PARAM_RANGES[:depletion_report_chance]),
        depletion_report_delay_mean: rng.rand(PARAM_RANGES[:depletion_report_delay_mean]),
        depletion_report_delay_std:  rng.rand(PARAM_RANGES[:depletion_report_delay_std]),
        vacation_gaps:             vacations,
        burst_days:                bursts,
        accident_rate:             rand_float(rng, PARAM_RANGES[:accident_rate]),
        ghost_shop_chance:         rand_float(rng, PARAM_RANGES[:ghost_shop_chance]),
        fuzz_std:                  rng.rand(PARAM_RANGES[:fuzz_std])
      )
    end

    def self.rand_float(rng, range)
      range.begin + rng.rand * (range.end - range.begin)
    end
  end
```

- [ ] **Step 2: Update the main runner**

Replace the `if __FILE__` block:

```ruby
if __FILE__ == $PROGRAM_NAME
  require 'set'

  puts 'Grocery Algorithm Audit'
  puts "#{SIM_DAYS} simulated days, #{DEFAULT_ITEMS.size} items"

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
```

- [ ] **Step 3: Run the full audit**

Run: `ruby test/sim/grocery_audit.rb`
Expected: 15 scenario reports, comparison table, then Monte Carlo sweep with top-20 worst personas and distribution summary. Should complete in under 30 seconds.

- [ ] **Step 4: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Add Monte Carlo sweep to grocery audit"
```

---

### Task 8: Delete old sims + conformance test

**Files:**
- Delete: `test/sim/grocery_convergence.rb`
- Delete: `test/sim/grocery_delayed_signals.rb`
- Delete: `test/sim/grocery_real_world.rb`
- Create: `test/models/on_hand_entry_conformance_test.rb`

The conformance test runs identical input sequences through both `GroceryAudit::Entry` and real `OnHandEntry` AR records, asserting that all fields match after each operation.

- [ ] **Step 1: Delete old sim scripts**

```bash
git rm test/sim/grocery_convergence.rb test/sim/grocery_delayed_signals.rb test/sim/grocery_real_world.rb
```

- [ ] **Step 2: Create conformance test**

```ruby
# frozen_string_literal: true

require 'test_helper'
require_relative '../sim/grocery_audit'

# Proves that GroceryAudit::Entry mirrors OnHandEntry's exact math.
# Runs identical sequences through both and asserts field-level equality.
# Not part of the regular test suite — run explicitly to verify sim fidelity.
#
# Usage: ruby -Itest test/models/on_hand_entry_conformance_test.rb
class OnHandEntryConformanceTest < ActiveSupport::TestCase
  setup do
    @kitchen = create_kitchen_and_user
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
    # Both should keep their original confirmed_at (anchor holds)
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
    # Both should reset confirmed_at (anchor broken)
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

    # Sentinel deplete: only ease changes, interval preserved
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

    # Same-day undo: interval and ease preserved
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
    # This is the specific divergence the old sims had:
    # observed=2, interval=7 → blended=(2+7)/2=4.5 → max(4.5, 7)=7
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

  def assert_entries_match(ar, sim, ar_base, sim_base)
    assert_in_delta ar.interval, sim.interval, 0.001, 'interval mismatch'
    assert_in_delta ar.ease, sim.ease, 0.001, 'ease mismatch'
    # confirmed_at: compare relative offset from base
    ar_offset = ar.confirmed_at == sentinel_date ? :sentinel : (ar.confirmed_at - ar_base).to_i
    sim_offset = sim.confirmed_at == GroceryAudit::SENTINEL ? :sentinel : (sim.confirmed_at - sim_base)
    assert_equal ar_offset, sim_offset, 'confirmed_at offset mismatch'
  end
end
```

- [ ] **Step 3: Run the conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: All tests pass. If any fail, the sim's Entry class needs to be fixed to match production.

- [ ] **Step 4: Run the full audit one final time**

Run: `ruby test/sim/grocery_audit.rb`
Expected: Complete output — 15 scenarios + Monte Carlo sweep. Save the output for review.

- [ ] **Step 5: Commit all changes**

```bash
git add test/sim/grocery_audit.rb test/models/on_hand_entry_conformance_test.rb
git commit -m "Complete grocery audit: delete old sims, add conformance test

Replaces grocery_convergence.rb, grocery_delayed_signals.rb, and
grocery_real_world.rb with a single audit script that mirrors
OnHandEntry exactly. 15 handcrafted scenarios + 5,000-persona
Monte Carlo sweep with UX-focused metrics (hit/miss/annoyance).
Conformance test proves sim matches production."
```

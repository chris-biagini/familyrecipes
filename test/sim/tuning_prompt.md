# Grocery Algorithm Tuning

You are tuning an SM-2-inspired grocery interval algorithm. The algorithm
predicts when a user will run out of each ingredient and prompts them to
check their inventory (Inventory Check / IC). Your goal is to make IC fire
at the right time — not too early (annoying), not too late (useless).

## Metrics

The audit at `test/sim/grocery_audit.rb` runs 15 scenarios + a 5,000-persona
Monte Carlo sweep and reports these metrics per scenario:

- **Hit rate** — % of cycles where IC fired 0–25% of the item's true cycle
  before depletion. Higher is better. This means the system caught it.
- **Miss rate** — % of cycles where IC fired AFTER the user ran out (or
  never fired). Lower is better. The system failed its promise.
- **Annoyance rate** — % of cycles where IC fired 25%+ of the cycle before
  depletion. Lower is better. The system asked way too early.

## Targets

Three "Core tier" scenarios must ALL meet these targets:

| Scenario | Name |
|----------|------|
| S1 | Perfect user (weekly shopping, ±2 day fuzz) |
| S7 | Two-week vacation (day 100-114) |
| S9 | Holiday baker (burst consumption days 80, 170) |

| Metric | Target |
|--------|--------|
| Hit rate | ≥50% |
| Miss rate | ≤40% |
| Annoyance rate | ≤15% |

**Guardrail:** No scenario (S1–S15) may have a miss rate exceeding 85%.

## What You Can Change

### Constants

Nine constants in `OnHandEntry` (file: `app/models/on_hand_entry.rb`):

```ruby
STARTING_INTERVAL = 7    # Initial interval for new items (days)
STARTING_EASE = 1.5      # Initial ease factor
MIN_EASE = 1.05          # Floor for ease factor
MAX_EASE = 2.5           # Ceiling for ease factor
EASE_BONUS = 0.03        # Ease bump on "Have It" confirmation
EASE_PENALTY = 0.20      # Ease penalty on "Need It" depletion
SAFETY_MARGIN = 0.78     # Proportional fraction for IC timing
BLEND_WEIGHT = 0.65      # Observation weight in depletion blending (0.5–0.8)
MAX_GROWTH_FACTOR = 1.3  # Max interval multiplier per have_it! cycle (1.2–1.5)
```

### Safety Margin Formula

The safety margin determines when IC fires. It appears in THREE places that
must stay in sync:

**1. Ruby `on_hand?` method** (on_hand_entry.rb, private method):
```ruby
def on_hand?(now)
  return false if depleted_at.present?
  return true if interval.nil?

  confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i.days >= now
end
```

**2. SQL `active` scope** (on_hand_entry.rb, class-level scope):
```ruby
scope :active, lambda { |now: Date.current|
  where(depleted_at: nil).where(
    'interval IS NULL OR date(confirmed_at, ' \
    "'+' || MIN(CAST(interval * #{SAFETY_MARGIN} AS INTEGER), " \
    "CAST(interval AS INTEGER) - #{MIN_BUFFER}) || ' days') >= date(?)",
    now.iso8601
  )
}
```

**3. Sim `on_hand?`** (test/sim/grocery_audit.rb, Entry class):
```ruby
def on_hand?(day)
  return false if depleted_at
  confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i >= day
end
```

You may change the formula (e.g., adjust MIN_BUFFER, use a different function
of interval, etc.). All three locations must produce identical results for the
same inputs.

If you change the formula, also update `ic_fires_on` in the sim's Entry
class — it must reflect the new formula:
```ruby
def ic_fires_on
  return nil if sentinel? || depleted?
  confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i + 1
end
```

### Blending Formula

The blending formula appears in TWO places that must stay in sync:

**1. Ruby `deplete_observed`** (on_hand_entry.rb):
```ruby
blended = (observed * BLEND_WEIGHT) + (interval * (1 - BLEND_WEIGHT))
```

**2. Sim `deplete_observed`** (test/sim/grocery_audit.rb, Entry class):
```ruby
blended = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
```

### Growth Cap

The growth cap appears in FOUR places that must stay in sync:

**1-2. Ruby `grow_standard` and `grow_anchored`** (on_hand_entry.rb):
```ruby
self.interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

**3-4. Sim `grow_standard` and `grow_anchored`** (grocery_audit.rb, Entry class):
```ruby
@interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

### What NOT to Change

Do not modify: `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions,
Monte Carlo sweep, the conformance test, or methods other than `deplete_observed`,
`grow_standard`, and `grow_anchored`.

Within those three methods, only change the blending formula and growth cap
formula. Do not restructure the methods or change their other behavior (ease
updates, sentinel handling, floor clamping, etc.).

Only change constants and the formulas documented above.

## Process (Each Iteration)

### Step 1: Read the tuning log

Read `test/sim/tuning_log.md`. If it has previous entries, read the last
entry's "Next" field for your starting hypothesis. If it's the first
iteration, start with the baseline and consider which constants need adjustment
now that blending and growth cap are in place.

### Step 2: Read current code

Read `app/models/on_hand_entry.rb` and the Entry class in
`test/sim/grocery_audit.rb` to see the current state of constants and formula.

### Step 3: Make changes

Modify constants and/or formulas in BOTH files. Keep them in sync. Remember
to update the SQL `active` scope if the safety margin formula changes.

### Step 4: Run conformance test

```bash
ruby -Itest test/models/on_hand_entry_conformance_test.rb
```

If any test fails, your changes made the sim diverge from production. Revert
and try a different approach. Note the failure in the tuning log.

### Step 5: Run the audit

```bash
ruby test/sim/grocery_audit.rb 2>/dev/null
```

Parse the output for the three Core tier scenarios (S1, S7, S9) and find the
worst miss rate across all 15 scenarios (for the guardrail check).

The comparison table at the end of the output has all the numbers you need:
```
COMPARISON: All scenarios
  Scenario                          Cyc   Hit%  Miss%   Ann%  IC/trip
  --------------------------------------------------------------
  S1: ...
```

### Step 6: Log results

Append an entry to `test/sim/tuning_log.md`:

```markdown
## Iteration N

**Hypothesis:** [What you tried and why]
**Changes:** [Exact constants/formula values]
**Results:**
- S1 (Perfect user): hit=X% miss=Y% annoy=Z%
- S7 (Vacation): hit=X% miss=Y% annoy=Z%
- S9 (Holiday baker): hit=X% miss=Y% annoy=Z%
- Guardrail worst: S___ at X% miss
**Assessment:** [What improved, what degraded, why]
**Next:** [What to try next iteration]
```

### Step 7: Commit

```bash
git add app/models/on_hand_entry.rb test/sim/grocery_audit.rb test/sim/tuning_log.md
git commit -m "Tuning iteration N: [brief description of change]"
```

### Step 8: Check completion

**If ALL of these are true, output `<promise>TUNING_COMPLETE</promise>` and stop:**
- S1 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- S7 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- S9 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- No scenario has miss rate >85%

**If the last 3 consecutive iterations showed no improvement on ANY Core
tier metric, output `<promise>TUNING_COMPLETE</promise>` and stop** (with a
note in the log that it stalled).

Otherwise, continue to the next iteration.

## Tips

- **BLEND_WEIGHT** controls convergence speed. Higher values (toward 0.8) make
  the interval track observations faster, reducing oscillation. But too high
  means the interval overreacts to fuzz-induced outliers.
- **MAX_GROWTH_FACTOR** caps per-cycle growth. Lower values (toward 1.2)
  prevent overshoot but slow convergence for long-cycle items (flour, pepper).
  Higher values (toward 1.5) converge faster but cause oscillation.
- **SAFETY_MARGIN** and **MIN_BUFFER** control the IC timing buffer. The
  formula `min(interval * SM, interval - MB)` gives a proportional buffer
  capped at a minimum absolute buffer.
- The previous tuning round (round 1) found SAFETY_MARGIN=0.78 and
  MIN_BUFFER=2 optimal for the safety margin formula. These may shift now
  that convergence is faster.
- STARTING_EASE=1.5 was previously problematic (55% first-cycle overshoot)
  but is now safe thanks to MAX_GROWTH_FACTOR capping growth.
- Small constant changes compound: EASE_BONUS and EASE_PENALTY control how
  fast the algorithm adapts. Faster adaptation means quicker convergence but
  more oscillation.
- The conformance test is your safety net. If it fails, you broke something.
  Don't skip it.

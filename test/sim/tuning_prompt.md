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

Seven constants in `OnHandEntry` (file: `app/models/on_hand_entry.rb`):

```ruby
STARTING_INTERVAL = 7    # Initial interval for new items (days)
STARTING_EASE = 1.5      # Initial ease factor
MIN_EASE = 1.1           # Floor for ease factor
MAX_EASE = 2.5           # Ceiling for ease factor
EASE_BONUS = 0.05        # Ease bump on "Have It" confirmation
EASE_PENALTY = 0.15      # Ease penalty on "Need It" depletion
SAFETY_MARGIN = 0.9      # Fraction of interval before IC fires
```

### Safety Margin Formula

The safety margin determines when IC fires. It appears in THREE places that
must stay in sync:

**1. Ruby `on_hand?` method** (on_hand_entry.rb, private method):
```ruby
def on_hand?(now)
  return false if depleted_at.present?
  return true if interval.nil?

  confirmed_at + (interval * SAFETY_MARGIN).to_i.days >= now
end
```

**2. SQL `active` scope** (on_hand_entry.rb, class-level scope):
```ruby
scope :active, lambda { |now: Date.current|
  where(depleted_at: nil).where(
    'interval IS NULL OR date(confirmed_at, ' \
    "'+' || CAST(interval * #{SAFETY_MARGIN} AS INTEGER) || ' days') >= date(?)",
    now.iso8601
  )
}
```

**3. Sim `on_hand?`** (test/sim/grocery_audit.rb, Entry class):
```ruby
def on_hand?(day)
  return false if depleted_at
  confirmed_at + (interval * SAFETY_MARGIN).to_i >= day
end
```

You may change the formula (e.g., add a minimum absolute buffer, use a
different function of interval, etc.). All three locations must produce
identical results for the same inputs.

If you change the formula, also update `ic_fires_on` in the sim's Entry
class — it must reflect the new formula:
```ruby
def ic_fires_on
  return nil if sentinel? || depleted?
  confirmed_at + (interval * SAFETY_MARGIN).to_i + 1
end
```

### What NOT to Change

Do not modify: `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions,
Monte Carlo sweep, the conformance test, or the structure of growth/depletion
methods (`grow_anchored`, `grow_standard`, `deplete_observed`, etc.).

Only change constants and the safety margin formula.

## Process (Each Iteration)

### Step 1: Read the tuning log

Read `test/sim/tuning_log.md`. If it has previous entries, read the last
entry's "Next" field for your starting hypothesis. If it's the first
iteration, start by addressing the safety margin formula — the audit showed
this is the primary bottleneck (1 day buffer for 7-day items is insufficient).

### Step 2: Read current code

Read `app/models/on_hand_entry.rb` and the Entry class in
`test/sim/grocery_audit.rb` to see the current state of constants and formula.

### Step 3: Make changes

Modify constants and/or the safety margin formula in BOTH files. Keep them
in sync. Remember to update the SQL `active` scope if the formula changes.

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

- The biggest lever is the safety margin. `floor(interval * 0.9)` gives only
  1 day of buffer for a 7-day item. Consider: a minimum absolute buffer
  (e.g., `interval - [interval * margin, interval - 2].min`), or a non-linear
  formula that gives more buffer to short intervals.
- Changing SAFETY_MARGIN from 0.9 to 0.8 would give 2 days buffer for 7-day
  items but 6 days for 30-day items — the annoyance rate for long-cycle items
  might spike.
- Small constant changes compound: EASE_BONUS and EASE_PENALTY control how
  fast the algorithm adapts. Faster adaptation means quicker convergence but
  more oscillation.
- The conformance test is your safety net. If it fails, you broke something.
  Don't skip it.

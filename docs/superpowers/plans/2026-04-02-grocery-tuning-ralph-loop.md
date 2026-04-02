# Grocery Algorithm Tuning — Ralph Loop Implementation Plan

> **For agentic workers:** This plan creates the prompt file and tuning log for a Ralph Wiggum loop. The actual algorithm tuning is done by the loop itself, not by this plan.

**Goal:** Create the self-contained Ralph loop prompt and empty tuning log so the user can invoke `/ralph-loop:ralph-loop` to iteratively tune the grocery algorithm.

**Architecture:** A single prompt file (`test/sim/tuning_prompt.md`) embeds all context the loop needs. An empty tuning log (`test/sim/tuning_log.md`) provides persistent memory across iterations. The loop modifies `OnHandEntry` and the sim's `Entry` class in tandem, verified by the conformance test.

**Tech Stack:** Ralph Wiggum plugin, Ruby, Minitest

**Design spec:** `docs/superpowers/specs/2026-04-02-grocery-tuning-ralph-loop-design.md`

---

## File Structure

- **Create:** `test/sim/tuning_prompt.md` — self-contained Ralph loop prompt
- **Create:** `test/sim/tuning_log.md` — empty log seeded with baseline scores

---

### Task 1: Create the tuning prompt

**Files:**
- Create: `test/sim/tuning_prompt.md`

The prompt must be entirely self-contained — a fresh Claude session with no conversation history reads only this file. It includes: what the algorithm is, what to change, where to change it, how to verify, what targets to hit, how to log results, and when to stop.

- [ ] **Step 1: Create the prompt file**

```markdown
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

**If ALL of these are true, output `TUNING_COMPLETE` and stop:**
- S1 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- S7 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- S9 hit rate ≥50% AND miss rate ≤40% AND annoyance rate ≤15%
- No scenario has miss rate >85%

**If the last 3 consecutive iterations showed no improvement on ANY Core
tier metric, output `TUNING_STALLED` and stop.**

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
```

- [ ] **Step 2: Run a quick sanity check**

Verify the prompt file is readable and the referenced paths exist:

```bash
wc -l test/sim/tuning_prompt.md
test -f app/models/on_hand_entry.rb && echo "on_hand_entry.rb exists"
test -f test/sim/grocery_audit.rb && echo "grocery_audit.rb exists"
test -f test/models/on_hand_entry_conformance_test.rb && echo "conformance test exists"
```

Expected: ~150 lines, all three files exist.

- [ ] **Step 3: Commit the prompt file**

```bash
git add test/sim/tuning_prompt.md
git commit -m "Add Ralph loop tuning prompt for grocery algorithm"
```

---

### Task 2: Seed the tuning log with baseline

**Files:**
- Create: `test/sim/tuning_log.md`

The log needs a baseline entry (iteration 0) with the current scores so the
loop has a starting reference point.

- [ ] **Step 1: Run the audit to capture current baseline scores**

```bash
ruby test/sim/grocery_audit.rb 2>/dev/null | grep -E 'S[0-9]+:'
```

Capture the S1, S7, S9 scores and the worst miss rate across all scenarios.

- [ ] **Step 2: Create the log with baseline entry**

Create `test/sim/tuning_log.md` with the baseline scores (fill in actual
numbers from the audit run):

```markdown
# Grocery Algorithm Tuning Log

## Iteration 0 (Baseline)

**Hypothesis:** N/A — recording current state before tuning.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.1, MAX_EASE = 2.5
- EASE_BONUS = 0.05, EASE_PENALTY = 0.15
- SAFETY_MARGIN = 0.9
- Formula: `confirmed_at + (interval * SAFETY_MARGIN).to_i`
**Results:**
- S1 (Perfect user): hit=X% miss=Y% annoy=Z%
- S7 (Vacation): hit=X% miss=Y% annoy=Z%
- S9 (Holiday baker): hit=X% miss=Y% annoy=Z%
- Guardrail worst: S___ at X% miss
**Assessment:** Safety margin provides only 1 day buffer for 7-day items.
Short-cycle items (eggs, milk) dominate the miss rate. Long-cycle items
(pepper, salt) perform better because the absolute buffer scales with
interval length.
**Next:** Address the safety margin formula — add a minimum absolute buffer
or use a non-linear function that gives more headroom to short intervals.
```

Fill in the actual X/Y/Z values from the audit output.

- [ ] **Step 3: Commit the log**

```bash
git add test/sim/tuning_log.md
git commit -m "Seed tuning log with baseline audit scores"
```

- [ ] **Step 4: Verify the Ralph loop can be invoked**

Print the invocation command for the user:

```bash
echo '/ralph-loop:ralph-loop "$(cat test/sim/tuning_prompt.md)" --max-iterations 15 --completion-promise "TUNING_COMPLETE"'
```

---

### Post-completion

After both tasks, the user clears context and runs:

```
/ralph-loop:ralph-loop "$(cat test/sim/tuning_prompt.md)" --max-iterations 15 --completion-promise "TUNING_COMPLETE"
```

The loop will iterate up to 15 times, modifying the algorithm and logging
results, until the targets are met or progress stalls.

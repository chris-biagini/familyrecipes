# Grocery Blending + Growth Cap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add weighted observation blending and per-cycle growth cap to the SM-2-inspired grocery interval algorithm, then re-tune constants via Ralph loop.

**Architecture:** Two isolated constant+formula changes to `OnHandEntry` and its sim mirror. The sim conformance test validates parity. After implementation, the tuning prompt is updated and a Ralph loop re-tunes all constants (including the two new ones).

**Tech Stack:** Ruby/Rails, Minitest, standalone Ruby sim (`grocery_audit.rb`)

---

### Task 1: Add BLEND_WEIGHT constant and update deplete_observed

**Files:**
- Modify: `app/models/on_hand_entry.rb:29` (constants block)
- Modify: `app/models/on_hand_entry.rb:137-145` (`deplete_observed`)
- Modify: `test/sim/grocery_audit.rb:12-22` (constants block)
- Modify: `test/sim/grocery_audit.rb:103-110` (`deplete_observed`)

- [ ] **Step 1: Add BLEND_WEIGHT constant to OnHandEntry**

In `app/models/on_hand_entry.rb`, after the `EASE_PENALTY` line (line 29), add the new constant:

```ruby
EASE_PENALTY = 0.20

BLEND_WEIGHT = 0.65
```

- [ ] **Step 2: Update deplete_observed in OnHandEntry**

In `app/models/on_hand_entry.rb`, change the `deplete_observed` method (line 138-139):

Old:
```ruby
  observed = (now - confirmed_at).to_i
  blended = (observed + interval) / 2.0
```

New:
```ruby
  observed = (now - confirmed_at).to_i
  blended = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
```

- [ ] **Step 3: Add BLEND_WEIGHT constant to sim**

In `test/sim/grocery_audit.rb`, after `EASE_PENALTY` in the module constants (line 19), add:

```ruby
EASE_PENALTY      = 0.20
BLEND_WEIGHT      = 0.65
```

- [ ] **Step 4: Update deplete_observed in sim Entry**

In `test/sim/grocery_audit.rb`, change the `deplete_observed` method in Entry (lines 105-106):

Old:
```ruby
    observed      = day - confirmed_at
    blended       = (observed + interval) / 2.0
```

New:
```ruby
    observed      = day - confirmed_at
    blended       = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
```

- [ ] **Step 5: Run conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: 11 runs, 41 assertions, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/models/on_hand_entry.rb test/sim/grocery_audit.rb
git commit -m "Add weighted blending to deplete_observed (BLEND_WEIGHT=0.65)"
```

### Task 2: Add MAX_GROWTH_FACTOR and update growth methods

**Files:**
- Modify: `app/models/on_hand_entry.rb:31` (constants, after BLEND_WEIGHT)
- Modify: `app/models/on_hand_entry.rb:114` (`grow_standard`)
- Modify: `app/models/on_hand_entry.rb:125` (`grow_anchored`)
- Modify: `test/sim/grocery_audit.rb:13` (constants)
- Modify: `test/sim/grocery_audit.rb:82` (sim `grow_standard`)
- Modify: `test/sim/grocery_audit.rb:91` (sim `grow_anchored`)

- [ ] **Step 1: Add MAX_GROWTH_FACTOR constant to OnHandEntry**

In `app/models/on_hand_entry.rb`, after the `BLEND_WEIGHT` line, add:

```ruby
BLEND_WEIGHT = 0.65
MAX_GROWTH_FACTOR = 1.3
```

- [ ] **Step 2: Update grow_standard in OnHandEntry**

In `app/models/on_hand_entry.rb`, change the interval line in `grow_standard`:

Old:
```ruby
  self.interval = [interval * ease, MAX_INTERVAL].min
```

New:
```ruby
  self.interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

- [ ] **Step 3: Update grow_anchored in OnHandEntry**

In `app/models/on_hand_entry.rb`, change the interval line in `grow_anchored`:

Old:
```ruby
  self.interval = [interval * new_ease, MAX_INTERVAL].min
```

New:
```ruby
  self.interval = [interval * [new_ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

- [ ] **Step 4: Add MAX_GROWTH_FACTOR constant to sim**

In `test/sim/grocery_audit.rb`, after `BLEND_WEIGHT` in the module constants, add:

```ruby
BLEND_WEIGHT      = 0.65
MAX_GROWTH_FACTOR = 1.3
```

- [ ] **Step 5: Update grow_standard in sim Entry**

In `test/sim/grocery_audit.rb`, change the interval line in sim's `grow_standard`:

Old:
```ruby
    @interval     = [interval * ease, MAX_INTERVAL].min
```

New:
```ruby
    @interval     = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

- [ ] **Step 6: Update grow_anchored in sim Entry**

In `test/sim/grocery_audit.rb`, change the interval line in sim's `grow_anchored`:

Old:
```ruby
    @interval = [interval * new_ease, MAX_INTERVAL].min
```

New:
```ruby
    @interval = [interval * [new_ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
```

- [ ] **Step 7: Run conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: 11 runs, 41 assertions, 0 failures

Note: The existing `have_it with sentinel` test uses ease=1.5+0.03=1.53, which
exceeds MAX_GROWTH_FACTOR=1.3. The test asserts interval and ease match between
AR and sim — both will now use 1.3 as the effective multiplier, so the test
passes with different values than before. This is correct behavior.

- [ ] **Step 8: Commit**

```bash
git add app/models/on_hand_entry.rb test/sim/grocery_audit.rb
git commit -m "Add MAX_GROWTH_FACTOR=1.3 to cap per-cycle interval growth"
```

### Task 3: Update conformance test constant assertions

**Files:**
- Modify: `test/models/on_hand_entry_conformance_test.rb:15-24`

- [ ] **Step 1: Add BLEND_WEIGHT and MAX_GROWTH_FACTOR to constant assertions**

In `test/models/on_hand_entry_conformance_test.rb`, add two lines after the
`SAFETY_MARGIN` assertion (line 23):

```ruby
    assert_equal OnHandEntry::SAFETY_MARGIN, GroceryAudit::SAFETY_MARGIN
    assert_equal OnHandEntry::BLEND_WEIGHT, GroceryAudit::BLEND_WEIGHT
    assert_equal OnHandEntry::MAX_GROWTH_FACTOR, GroceryAudit::MAX_GROWTH_FACTOR
  end
```

- [ ] **Step 2: Run conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: 11 runs, 43 assertions, 0 failures (2 more assertions than before)

- [ ] **Step 3: Commit**

```bash
git add test/models/on_hand_entry_conformance_test.rb
git commit -m "Add BLEND_WEIGHT and MAX_GROWTH_FACTOR to conformance assertions"
```

### Task 4: Run full test suite to verify no regressions

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass. No failures or errors.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 3: Run the audit to capture new baseline**

Run: `ruby test/sim/grocery_audit.rb 2>/dev/null | grep -E "^  S[0-9]"`

Record all 15 scenario results. These become the "post-algorithm-change baseline"
for the next tuning round.

- [ ] **Step 4: Commit if any lint fixes were needed**

### Task 5: Update tuning prompt for next Ralph loop

**Files:**
- Modify: `test/sim/tuning_prompt.md`
- Modify: `test/sim/tuning_log.md`

- [ ] **Step 1: Update the constants section in tuning_prompt.md**

Replace the constants block (lines 44-52) with:

```markdown
### Constants

Nine constants in `OnHandEntry` (file: `app/models/on_hand_entry.rb`):

\`\`\`ruby
STARTING_INTERVAL = 7    # Initial interval for new items (days)
STARTING_EASE = 1.5      # Initial ease factor
MIN_EASE = 1.05          # Floor for ease factor
MAX_EASE = 2.5           # Ceiling for ease factor
EASE_BONUS = 0.03        # Ease bump on "Have It" confirmation
EASE_PENALTY = 0.20      # Ease penalty on "Need It" depletion
SAFETY_MARGIN = 0.78     # Proportional fraction for IC timing
BLEND_WEIGHT = 0.65      # Observation weight in depletion blending (0.5–0.8)
MAX_GROWTH_FACTOR = 1.3  # Max interval multiplier per have_it! cycle (1.2–1.5)
\`\`\`
```

- [ ] **Step 2: Update the safety margin formula section**

The three safety margin sync points (lines 59-99) are unchanged — keep them
as-is. But add a new section after them documenting the two new formula sync
points:

```markdown
### Blending Formula

The blending formula appears in TWO places that must stay in sync:

**1. Ruby `deplete_observed`** (on_hand_entry.rb):
\`\`\`ruby
blended = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
\`\`\`

**2. Sim `deplete_observed`** (test/sim/grocery_audit.rb, Entry class):
\`\`\`ruby
blended = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
\`\`\`

### Growth Cap

The growth cap appears in FOUR places that must stay in sync:

**1-2. Ruby `grow_standard` and `grow_anchored`** (on_hand_entry.rb):
\`\`\`ruby
self.interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
\`\`\`

**3-4. Sim `grow_standard` and `grow_anchored`** (grocery_audit.rb, Entry class):
\`\`\`ruby
@interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
\`\`\`
```

- [ ] **Step 3: Update "What NOT to Change" section**

Replace lines 101-107 with:

```markdown
### What NOT to Change

Do not modify: `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions,
Monte Carlo sweep, the conformance test, or methods other than `deplete_observed`,
`grow_standard`, and `grow_anchored`.

Within those three methods, only change the blending formula and growth cap
formula. Do not restructure the methods or change their other behavior (ease
updates, sentinel handling, floor clamping, etc.).
```

- [ ] **Step 4: Reset tuning log for the new round**

Replace the entire contents of `test/sim/tuning_log.md` with a fresh baseline
entry. Run the audit first (Task 4 Step 3), then write:

```markdown
# Grocery Algorithm Tuning Log (Round 2)

Previous round: iterations 0–3 tuned safety margin formula and ease constants.
This round: re-tune all constants after adding weighted blending + growth cap.

## Iteration 0 (Baseline — post algorithm change)

**Hypothesis:** N/A — recording state after adding BLEND_WEIGHT and MAX_GROWTH_FACTOR.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.05, MAX_EASE = 2.5
- EASE_BONUS = 0.03, EASE_PENALTY = 0.20
- SAFETY_MARGIN = 0.78, MIN_BUFFER = 2
- BLEND_WEIGHT = 0.65, MAX_GROWTH_FACTOR = 1.3
- Safety margin formula: `min(interval * 0.78, interval - 2)`
- Blend formula: `observed * 0.65 + interval * 0.35`
- Growth cap: `interval * min(ease, 1.3)`
**Results:**
- S1 (Perfect user): hit=___% miss=___% annoy=___%
- S7 (Vacation): hit=___% miss=___% annoy=___%
- S9 (Holiday baker): hit=___% miss=___% annoy=___%
- Guardrail worst: S___ at ___% miss
**Assessment:** [Fill in after running audit]
**Next:** [Fill in after reviewing results]
```

Fill in the blanks from the audit output in Task 4 Step 3.

- [ ] **Step 5: Commit**

```bash
git add test/sim/tuning_prompt.md test/sim/tuning_log.md
git commit -m "Update tuning prompt and reset log for round 2"
```

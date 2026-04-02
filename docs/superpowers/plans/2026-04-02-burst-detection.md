# Burst Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add burst detection to `deplete_observed` so one-off consumption spikes don't corrupt learned intervals, then re-tune all constants.

**Architecture:** A `burst?` gate in `deplete_observed` skips blend+ease when an established item depletes suspiciously early. Two new tunable constants. Mirrored in the sim. Ralph loop re-tunes everything.

**Tech Stack:** Ruby/Rails, Minitest, standalone Ruby sim (`grocery_audit.rb`)

---

### Task 1: Add burst detection to OnHandEntry

**Files:**
- Modify: `app/models/on_hand_entry.rb:29` (constants)
- Modify: `app/models/on_hand_entry.rb:139-147` (`deplete_observed`)

- [ ] **Step 1: Add constants**

In `app/models/on_hand_entry.rb`, after the `MAX_GROWTH_FACTOR = 1.3` line (line 29), add:

```ruby
  MAX_GROWTH_FACTOR = 1.3
  BURST_THRESHOLD = 0.5
  MIN_ESTABLISHED_INTERVAL = 14
```

- [ ] **Step 2: Add burst? private method**

In `app/models/on_hand_entry.rb`, add a new private method directly before `deplete_observed` (before line 139):

```ruby
  def burst?(observed)
    interval >= MIN_ESTABLISHED_INTERVAL && observed < interval * BURST_THRESHOLD
  end
```

- [ ] **Step 3: Update deplete_observed**

In `app/models/on_hand_entry.rb`, replace the `deplete_observed` method (lines 139-147) with:

```ruby
  def deplete_observed(now)
    observed = (now - confirmed_at).to_i
    unless burst?(observed)
      blended = (observed * BLEND_WEIGHT) + (interval * (1 - BLEND_WEIGHT))
      self.interval = [blended, STARTING_INTERVAL].max
      self.ease = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    end
    self.confirmed_at = Date.parse(ORPHAN_SENTINEL)
    self.depleted_at = now
    self.orphaned_at = nil
  end
```

- [ ] **Step 4: Commit**

```bash
git add app/models/on_hand_entry.rb
git commit -m "Add burst detection to deplete_observed"
```

### Task 2: Mirror burst detection in sim Entry

**Files:**
- Modify: `test/sim/grocery_audit.rb:12-25` (constants)
- Modify: `test/sim/grocery_audit.rb:107-114` (`deplete_observed`)

- [ ] **Step 1: Add constants to sim**

In `test/sim/grocery_audit.rb`, after `MAX_GROWTH_FACTOR = 1.3` (line 21), add:

```ruby
  MAX_GROWTH_FACTOR = 1.3
  BURST_THRESHOLD         = 0.5
  MIN_ESTABLISHED_INTERVAL = 14
```

- [ ] **Step 2: Add burst? method to Entry**

In `test/sim/grocery_audit.rb`, add a private method to the Entry class, directly before `deplete_observed` (before line 107):

```ruby
    def burst?(observed)
      interval >= MIN_ESTABLISHED_INTERVAL && observed < interval * BURST_THRESHOLD
    end
```

- [ ] **Step 3: Update sim deplete_observed**

In `test/sim/grocery_audit.rb`, replace the Entry class `deplete_observed` method (lines 107-114) with:

```ruby
    def deplete_observed(day)
      observed = day - confirmed_at
      unless burst?(observed)
        blended       = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
        @interval     = [blended, STARTING_INTERVAL.to_f].max
        @ease         = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
      end
      @confirmed_at = SENTINEL
      @depleted_at  = day
    end
```

- [ ] **Step 4: Run conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: 11 runs, 43 assertions, 0 failures

- [ ] **Step 5: Commit**

```bash
git add test/sim/grocery_audit.rb
git commit -m "Mirror burst detection in sim Entry class"
```

### Task 3: Update conformance test constants

**Files:**
- Modify: `test/models/on_hand_entry_conformance_test.rb:24-26`

- [ ] **Step 1: Add constant assertions**

In `test/models/on_hand_entry_conformance_test.rb`, after the `MAX_GROWTH_FACTOR` assertion (line 25), add:

```ruby
    assert_equal OnHandEntry::MAX_GROWTH_FACTOR, GroceryAudit::MAX_GROWTH_FACTOR
    assert_equal OnHandEntry::BURST_THRESHOLD, GroceryAudit::BURST_THRESHOLD
    assert_equal OnHandEntry::MIN_ESTABLISHED_INTERVAL, GroceryAudit::MIN_ESTABLISHED_INTERVAL
  end
```

- [ ] **Step 2: Run conformance test**

Run: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
Expected: 11 runs, 45 assertions, 0 failures (2 more than before)

- [ ] **Step 3: Commit**

```bash
git add test/models/on_hand_entry_conformance_test.rb
git commit -m "Add burst detection constants to conformance assertions"
```

### Task 4: Full test suite + capture baseline

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests pass. The existing `deplete_observed` tests use interval=7
and interval=14. With MIN_ESTABLISHED_INTERVAL=14:
- interval=7: burst? returns false (7 < 14), normal path → existing tests unchanged
- interval=14 with observed=14 (test line 86-101): burst? checks 14 >= 14 AND 14 < 14*0.5=7 → false. Normal path.
- interval=14 with observed=2 (test line 184-196): burst? checks 14 >= 14 AND 2 < 7 → true! **This test may fail** because interval/ease won't be updated. Check the test and update the expected value if needed.

If any test fails, read the failing test, recalculate expected values with burst detection in mind, and update.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses. If offenses, fix and re-run.

- [ ] **Step 3: Capture new baseline**

Run: `ruby test/sim/grocery_audit.rb 2>/dev/null | grep -E "^  S[0-9]"`
Record all 15 scenario results for the tuning log.

- [ ] **Step 4: Commit any test fixes**

```bash
git add -u
git commit -m "Fix test expectations for burst detection"
```

### Task 5: Update tuning prompt and reset log

**Files:**
- Modify: `test/sim/tuning_prompt.md`
- Modify: `test/sim/tuning_log.md`

- [ ] **Step 1: Update constants section in tuning_prompt.md**

Replace the constants block (lines 42-54) with:

```markdown
Eleven constants in `OnHandEntry` (file: `app/models/on_hand_entry.rb`):

\`\`\`ruby
STARTING_INTERVAL = 7    # Initial interval for new items (days)
STARTING_EASE = 1.5      # Initial ease factor
MIN_EASE = 1.05          # Floor for ease factor
MAX_EASE = 2.5           # Ceiling for ease factor
EASE_BONUS = 0.05        # Ease bump on "Have It" confirmation
EASE_PENALTY = 0.20      # Ease penalty on "Need It" depletion
SAFETY_MARGIN = 0.78     # Proportional fraction for IC timing
BLEND_WEIGHT = 0.75      # Observation weight in depletion blending (0.5–0.8)
MAX_GROWTH_FACTOR = 1.3  # Max interval multiplier per have_it! cycle (1.2–1.5)
BURST_THRESHOLD = 0.5    # Ratio below which depletion is classified as burst (0.3–0.7)
MIN_ESTABLISHED_INTERVAL = 14  # Min interval before burst detection activates (10–21)
\`\`\`
```

- [ ] **Step 2: Add burst detection section after the Growth Cap section**

After the Growth Cap section (around line 131), add:

```markdown
### Burst Detection

The burst gate appears in TWO places that must stay in sync:

**1. Ruby `burst?`** (on_hand_entry.rb, private method):
\`\`\`ruby
def burst?(observed)
  interval >= MIN_ESTABLISHED_INTERVAL && observed < interval * BURST_THRESHOLD
end
\`\`\`

**2. Sim `burst?`** (test/sim/grocery_audit.rb, Entry class):
\`\`\`ruby
def burst?(observed)
  interval >= MIN_ESTABLISHED_INTERVAL && observed < interval * BURST_THRESHOLD
end
\`\`\`

When `burst?` returns true, `deplete_observed` skips the blend and ease penalty
entirely — the item is marked depleted but interval and ease are preserved.

You may adjust BURST_THRESHOLD and MIN_ESTABLISHED_INTERVAL. Do not change the
gate structure (the two conditions or the full-bypass behavior).
```

- [ ] **Step 3: Update the "What NOT to Change" section**

Replace lines 132-142 with:

```markdown
### What NOT to Change

Do not modify: `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions,
Monte Carlo sweep, the conformance test, or methods other than `deplete_observed`,
`grow_standard`, and `grow_anchored`.

Within those methods, only change formulas and constants. Do not restructure
the methods, change the burst gate structure, or alter behavior outside the
blend/ease/growth-cap/burst paths.

Only change constants and the formulas documented above.
```

- [ ] **Step 4: Update tips section**

Add to the tips section at the end of the file:

```markdown
- **BURST_THRESHOLD** controls outlier sensitivity. Lower values (0.3) only
  catch extreme bursts. Higher values (0.7) catch more but risk ignoring
  genuine lifestyle changes. If S9 annoyance is too high, raise the threshold.
  If other scenarios show slow adaptation, lower it.
- **MIN_ESTABLISHED_INTERVAL** gates burst detection on item maturity. Lower
  values (10) protect more items but risk suppressing learning for medium-cycle
  items. Higher values (21) only protect long-cycle pantry staples.
```

- [ ] **Step 5: Reset tuning log**

Replace `test/sim/tuning_log.md` entirely with a fresh round 3 baseline.
Fill in the audit results from Task 4 Step 3:

```markdown
# Grocery Algorithm Tuning Log (Round 3)

Previous rounds: round 1 tuned safety margin, round 2 added weighted blending +
growth cap. This round: re-tune all constants after adding burst detection.

## Iteration 0 (Baseline — post burst detection)

**Hypothesis:** N/A — recording state after adding burst detection.
**Changes:** None. Current constants:
- STARTING_INTERVAL = 7, STARTING_EASE = 1.5
- MIN_EASE = 1.05, MAX_EASE = 2.5
- EASE_BONUS = 0.05, EASE_PENALTY = 0.20
- SAFETY_MARGIN = 0.78, MIN_BUFFER = 2
- BLEND_WEIGHT = 0.75, MAX_GROWTH_FACTOR = 1.3
- BURST_THRESHOLD = 0.5, MIN_ESTABLISHED_INTERVAL = 14
**Results:**
- S1 (Perfect user): hit=___% miss=___% annoy=___%
- S7 (Vacation): hit=___% miss=___% annoy=___%
- S9 (Holiday baker): hit=___% miss=___% annoy=___%
- Guardrail worst: S___ at ___% miss
**Assessment:** [Fill after reviewing results]
**Next:** [Fill after reviewing — likely explore MIN_EASE=1.1 now that S9 burst
is handled, then adjust SM/BW if S1 miss improves]
```

Fill in the blanks from the audit output in Task 4 Step 3.

- [ ] **Step 6: Commit**

```bash
git add test/sim/tuning_prompt.md test/sim/tuning_log.md
git commit -m "Update tuning prompt and reset log for round 3"
```

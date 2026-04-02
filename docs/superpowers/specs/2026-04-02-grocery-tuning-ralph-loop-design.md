# Grocery Algorithm Tuning — Ralph Loop Design

Use the Ralph Wiggum technique to iteratively improve the SM-2-inspired
grocery interval algorithm based on findings from the comprehensive audit
(`test/sim/grocery_audit.rb`).

## Background

The audit revealed a structural limitation: the safety margin
(`floor(interval × 0.9)`) provides only 1 day of buffer for 7-day items,
which is swamped by ±2 day consumption fuzz. Even the "perfect user" scenario
shows a 65.7% miss rate. The algorithm is rarely annoying (8.8%) but misses
far more than it catches.

## User Tiers

Optimization targets the **Core tier** (attentive weekly-ish shoppers) with a
guardrail that the **Casual tier** (irregular, sometimes inattentive) does not
regress.

| Tier | Representative scenarios | Current hit rate |
|---|---|---|
| Core | S1 (perfect user), S7 (vacation), S9 (holiday baker) | 25–31% |
| Casual | S3, S6, S11, S14 | 13–32% |
| Peripheral | S13, S15 | 24–29% |

## Target Scores

Core tier scenarios (S1, S7, S9) must **all** meet:

| Metric | Current (S1) | Target |
|---|---|---|
| Hit rate | 25.5% | ≥50% |
| Miss rate | 65.7% | ≤40% |
| Annoyance rate | 8.8% | ≤15% |

**Guardrail:** No scenario's miss rate may exceed 85%.

## Search Space

Two categories of allowed changes. All changes go in both
`app/models/on_hand_entry.rb` AND `test/sim/grocery_audit.rb` (the sim must
stay in sync with production).

### Constants

The 7 tunable constants in `OnHandEntry`:

| Constant | Current | Role |
|---|---|---|
| `STARTING_INTERVAL` | 7 | Initial interval for new items |
| `STARTING_EASE` | 1.5 | Initial ease factor |
| `MIN_EASE` | 1.1 | Floor for ease factor |
| `MAX_EASE` | 2.5 | Ceiling for ease factor |
| `EASE_BONUS` | 0.05 | Ease bump on confirmation |
| `EASE_PENALTY` | 0.15 | Ease penalty on depletion |
| `SAFETY_MARGIN` | 0.9 | Fraction of interval before IC fires |

### Safety Margin Formula

The safety margin appears in three places:

1. **Ruby `on_hand?` method** — `confirmed_at + (interval * SAFETY_MARGIN).to_i.days >= now`
2. **SQL `active` scope** — `CAST(interval * #{SAFETY_MARGIN} AS INTEGER)`
3. **Sim `on_hand?`** — `confirmed_at + (interval * SAFETY_MARGIN).to_i >= day`

The loop may change how the margin is applied: different multiplier, a minimum
absolute buffer (e.g., `[floor(interval * margin), interval - 3].min`), or a
different formula entirely. All three locations must stay in sync.

### Off-Limits

The loop may NOT change: `FaithfulSim`, `CycleTracker`, `Scorer`, scenario
definitions, Monte Carlo sweep, the conformance test, or the growth/depletion
method structures (`grow_anchored`, `deplete_observed`, etc.). Only constants
and the safety margin formula.

## Ralph Loop Mechanics

### Prompt File

`test/sim/tuning_prompt.md` — a self-contained markdown document that the
Ralph loop feeds to a fresh Claude session. Contains all context needed
without relying on conversation history: target scores, search space, file
paths, verification commands, tuning log format, and metric definitions.

### Tuning Log

`test/sim/tuning_log.md` — persistent memory across iterations. Each entry:

```markdown
## Iteration N

**Hypothesis:** [What we're trying and why]
**Changes:** [Exact constants/formula modified]
**Results:**
- S1 (Perfect user): hit=X% miss=Y% annoy=Z%
- S7 (Vacation): hit=X% miss=Y% annoy=Z%
- S9 (Holiday baker): hit=X% miss=Y% annoy=Z%
- Guardrail worst: S___ at X% miss
**Assessment:** [Improved/degraded/mixed — what worked, what didn't]
**Next:** [What to try next iteration based on these results]
```

### Per-Iteration Process

1. Read `test/sim/tuning_log.md` (if it exists)
2. Read current state of `app/models/on_hand_entry.rb` and `test/sim/grocery_audit.rb`
3. Formulate hypothesis based on previous results (or start with safety margin if first iteration)
4. Modify constants/formula in `on_hand_entry.rb`
5. Mirror changes in `grocery_audit.rb`'s Entry class
6. Run conformance test: `ruby -Itest test/models/on_hand_entry_conformance_test.rb`
   - If fails → revert changes, note in log, try different approach
7. Run audit: `ruby test/sim/grocery_audit.rb 2>/dev/null`
8. Parse Core tier scores (S1, S7, S9) and guardrail (worst miss rate)
9. Append iteration entry to tuning log
10. Commit changes with message: `Tuning iteration N: [brief description]`
11. Check completion criteria

### Completion Criteria

- **`TUNING_COMPLETE`** — all three Core tier scenarios meet all three targets AND guardrail holds
- **`TUNING_STALLED`** — 3 consecutive iterations show no improvement on any Core metric
- **Max iterations:** 15

### Sync Safety

Every change to `OnHandEntry` must be mirrored in the sim's `Entry` class.
The conformance test (`on_hand_entry_conformance_test.rb`) catches drift. If
it fails, the iteration's changes must be reverted before continuing.

The `active` scope SQL uses `CAST(... AS INTEGER)` for truncation. If the
formula changes, the SQL must be updated to match the Ruby logic exactly.

## Invocation

```bash
/ralph-loop:ralph-loop "$(cat test/sim/tuning_prompt.md)" --max-iterations 15 --completion-promise "TUNING_COMPLETE"
```

## Deliverable

After the loop completes:
- `on_hand_entry.rb` with tuned constants/formula
- `grocery_audit.rb` with matching Entry class
- `test/sim/tuning_log.md` documenting the full search history
- All iterations committed individually for review
- Conformance test still passing

# Grocery Algorithm Audit Design

Comprehensive audit of the SM-2-inspired grocery interval algorithm. The goal
is to measure how often the system is *helpful* (surfacing items when truly
needed) vs. *annoying* (asking about items the user clearly still has), across
a wide range of realistic and adversarial usage patterns.

## Background

The algorithm lives in `OnHandEntry` and implements a three-zone grocery model
(Inventory Check / To Buy / On Hand) with adaptive intervals. Each ingredient
carries `confirmed_at`, `interval`, and `ease`. The interval grows on
confirmation ("Have It"), shrinks on depletion ("Need It"), and the ease factor
converges on the ingredient's natural restock cycle.

Three simulation scripts exist from the design phase (`test/sim/grocery_convergence.rb`,
`grocery_delayed_signals.rb`, `grocery_real_world.rb`) but they have drifted
from the production code. The convergence sim floors the observation before
blending (`(interval + max(obs, 7)) / 2.0`), while production floors after
blending (`max((observed + interval) / 2.0, 7)`). This audit replaces all
three with a single authoritative script.

## Simulation Engine

### FaithfulSim

A new `GroceryAudit::FaithfulSim` class mirrors `OnHandEntry`'s exact math.
Same constants, same method structure, same edge-case handling:

- **Constants:** `STARTING_INTERVAL=7`, `MAX_INTERVAL=180`, `STARTING_EASE=1.5`,
  `MIN_EASE=1.1`, `MAX_EASE=2.5`, `EASE_BONUS=0.05`, `EASE_PENALTY=0.15`,
  `SAFETY_MARGIN=0.9`
- **Entry struct:** `confirmed_at`, `interval`, `ease`, `depleted_at` (mirrors
  the AR columns)
- **Methods:** `grow_anchored`, `grow_standard`, `deplete_observed`,
  `deplete_sentinel`, `undo_same_day`, `recheck` — each matches the
  corresponding `OnHandEntry` private method line-for-line

No inheritance hierarchy. One sim class, one entry struct, one set of constants.

### Conformance Test

A Minitest integration test (`test/models/on_hand_entry_conformance_test.rb`)
runs identical input sequences through both `FaithfulSim` and real `OnHandEntry`
records. Asserts that `confirmed_at`, `interval`, `ease`, and `depleted_at`
match after each operation. Run once to prove fidelity; not part of the regular
test suite (tagged or in a separate file so `rake test` doesn't depend on the
sim script).

## Event Model and Schedule Generation

### Events

Each simulation runs against a **schedule** — a hash mapping day numbers to
events. Events represent user actions:

| Event | Behavior |
|---|---|
| `:shop` | Open grocery list, process all IC items (Have It / Need It based on ground truth), purchase everything in To Buy |
| `:shop_partial` | Same as `:shop` but only process a fraction of IC items (parameterized `ic_attention` rate) |
| `:deplete` | User runs out of a specific item and reports it mid-week |
| `:burst_consume` | Holiday bake / dinner party — all long-cycle on-hand items are consumed immediately |
| `:accidental_uncheck` | Buy an item then immediately uncheck it (cracked eggs) |

Days without events are implicit skips. Ground truth consumption ticks every
day regardless of whether the user interacts with the system.

### Shopping Trip Triage

On a `:shop` or `:shop_partial` event, the sim loops through all items and
performs three-zone triage:

1. **Expired items** (IC zone): if user has stock → `have_it!` (grow_anchored
   or grow_standard). If out of stock → `need_it!` (deplete_observed or
   deplete_sentinel), then purchase.
2. **Depleted items** (To Buy zone): purchase (recheck).
3. **On Hand items**: if user is actually out of stock → `uncheck!`
   (deplete_observed or undo_same_day).
4. **New items** (first encounter): if user has stock → `check!`. If not →
   create sentinel entry, deplete, purchase.

### Personas

A persona defines behavioral parameters that generate a concrete schedule:

| Parameter | Type | What it controls |
|---|---|---|
| `shop_interval` | `{mean:, std:}` | Days between shopping trips |
| `ic_attention` | Float 0–1 | Probability of processing each IC item per trip |
| `depletion_report_chance` | Float 0–1 | Probability of reporting mid-week depletion |
| `depletion_report_delay` | `{mean:, std:}` | Days between running out and reporting |
| `vacation_gaps` | Array of `{start:, length:}` | Periods with no shopping |
| `burst_days` | Array of integers | Days when long-cycle items get consumed suddenly |
| `accident_rate` | Float 0–1 | Per-item probability of accidental uncheck per trip |

The persona feeds parameters into a schedule generator that produces a
deterministic array of events (given a seed). Once generated, the schedule is
fixed — printable, replayable, debuggable.

Handcrafted scenarios can bypass personas and supply a raw schedule directly.

## Metrics and Scoring

### Per-Cycle Tracking

Each item tracks a log of **cycles** — the period from one purchase to the
next. For each cycle:

- `purchased_on` — day the item was bought
- `actually_depleted_on` — day ground truth stock hit zero
- `ic_fired_on` — day the item surfaced in IC (`confirmed_at + interval × 0.9`),
  or `nil` if the user ran out and self-reported first

### Outcome Classification

Comparing `ic_fired_on` to `actually_depleted_on`, expressed as a fraction of
the item's true consumption cycle:

| Outcome | Condition | Meaning |
|---|---|---|
| `:perfect` | IC fires 0–10% of true cycle before depletion | Safety margin doing its job |
| `:acceptable` | IC fires 10–25% early | Slightly eager, one tap to dismiss |
| `:annoying` | IC fires 25%+ early | User clearly still has it |
| `:miss` | IC fires after depletion or never fires | System failed its promise |

### Aggregate Scorecard

Reported per scenario:

- **Hit rate** — % of cycles that were `:perfect` or `:acceptable`
- **Miss rate** — % of cycles that were `:miss`
- **Annoyance rate** — % of cycles that were `:annoying`
- **Mean IC timing error** — average `(ic_fired_on − actually_depleted_on)` as
  % of true cycle. Negative = early, positive = late.
- **IC load per trip** — average number of items in IC at each shopping event
- **Recovery time** — after a disruption (vacation, burst consumption), number
  of cycles until the item returns to `:perfect` or `:acceptable`, averaged
  across all disruptions

Per-item breakdown also available to compare short-cycle items (eggs, milk)
against long-cycle items (salt, pepper).

No weighting between misses and annoyances — the raw rates tell the story.
Context determines severity (running out of pepper for steak au poivre ≠
running out of pepper for spaghetti).

## Handcrafted Scenarios

Fifteen named scenarios organized by theme.

### Baseline

| # | Name | Behavior | Probing |
|---|---|---|---|
| 1 | Perfect user | Shop every 7d, process all IC, report all depletion | Control case — does the algorithm converge? |
| 2 | Frequent shopper | Shop every 3d | Quantization: eggs alternate 7/14d observations |
| 3 | Biweekly shopper | Shop every 14d | Long gaps between feedback signals |

### Inconsistent Cadence

| # | Name | Behavior | Probing |
|---|---|---|---|
| 4 | Alternating cadence | Alternate 3d and 14d shopping intervals | Oscillation from contradictory signals |
| 5 | Gradual drift | Weekly → biweekly over 2 months → back | Lifestyle change adaptation |
| 6 | Random intervals | Shopping interval uniform(3, 14) | Pure noise resistance |

### Life Disruptions

| # | Name | Behavior | Probing |
|---|---|---|---|
| 7 | Two-week vacation | Weekly shopping, 14d gap at day 100, resume | Single disruption recovery |
| 8 | Repeated vacations | Three 10d gaps spread across the year | Repeated disruption accumulation |
| 9 | Holiday baker | Weekly + burst consumption on days 80 and 170 | Long-cycle items suddenly consumed |
| 10 | Post-vacation burst | 14d vacation then immediate dinner party | Compound disruption |

### Inattentive Users

| # | Name | Behavior | Probing |
|---|---|---|---|
| 11 | IC ignorer | Process IC items 50% of the time | Items languishing in IC |
| 12 | Delayed reporter | Never reports mid-week, waits for next trip | Observation inflation from delayed signals |
| 13 | Ghost shopper | Buys items without opening app for some cycles | Missing purchase signals |

### Mistakes and Edge Cases

| # | Name | Behavior | Probing |
|---|---|---|---|
| 14 | Butterfingers | 5% accidental uncheck rate per trip | Same-day undo grace under repeated stress |
| 15 | Binge and forget | Intense for 2 months, dormant 1 month, resume | Stale learned intervals after dormancy |

## Monte Carlo Sweep

### Parameter Ranges

| Parameter | Range | Distribution |
|---|---|---|
| `shop_interval` mean | 2–21 days | Uniform |
| `shop_interval` std | 0–5 days | Uniform |
| `ic_attention` | 0.3–1.0 | Uniform |
| `depletion_report_chance` | 0.0–1.0 | Uniform |
| `depletion_report_delay` mean | 0–7 days | Uniform |
| `vacation_count` | 0–3 | Uniform integer |
| `vacation_length` | 7–21 days | Uniform |
| `burst_count` | 0–4 | Uniform integer |
| `accident_rate` | 0.0–0.1 | Uniform |

### Execution

- **5,000 personas**, each run against the standard ingredient mix (eggs/7d,
  milk/10d, butter/14d, flour/30d, pepper/60d, salt/90d) for 365 simulated
  days.
- Seeded RNG (master seed generates per-persona seeds) for full reproducibility.
- Pure arithmetic, no I/O — should complete in seconds.

### Output

- Rank all 5,000 by worst metric: miss rate first, annoyance rate as
  tiebreaker.
- Print the **top 20 worst** with full parameter set and per-item breakdown.
- For the **top 5 worst**, dump the generated schedule for day-by-day tracing.
- Summary statistics across all 5,000: distribution of hit/miss/annoyance
  rates (median, p90, p99, worst).

### Distillation

After reviewing top failures, manually decide which reveal genuine algorithmic
weaknesses vs. pathological inputs (a user shopping every 21 days with 30% IC
attention has already given up). Genuine weaknesses become named scenarios in
the permanent suite.

## Deliverable

A single script `test/sim/grocery_audit.rb` containing:

1. `GroceryAudit::Entry` struct
2. `GroceryAudit::FaithfulSim` class
3. `GroceryAudit::Persona` and schedule generator
4. `GroceryAudit::Scorer` (cycle tracking and metric computation)
5. All 15 handcrafted scenarios
6. Monte Carlo sweep runner
7. Report printer (per-scenario scorecards, summary table, sweep results)

The three existing sim scripts (`grocery_convergence.rb`,
`grocery_delayed_signals.rb`, `grocery_real_world.rb`) are deleted.

A separate conformance test (`test/models/on_hand_entry_conformance_test.rb`)
verifies the sim matches production.

If the audit reveals tuning improvements or code fixes, those are follow-up
work — the audit's job is to produce the data, not to change the algorithm.

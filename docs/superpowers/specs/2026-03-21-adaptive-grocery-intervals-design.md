# Adaptive Grocery Intervals

**Date:** 2026-03-21
**Status:** Draft
**Companion spec:** `2026-03-21-grocery-backoff-design.md` (this spec refines its
algorithm)
**User docs:** `docs/help/groceries.md` (must be updated — see Help Doc section)

## Problem

The current spaced-repetition system uses fixed power-of-2 doubling
(7→14→28→56) with a hard cap at 56 days. This creates two problems:

1. **Oscillation.** Items whose true consumption cycle falls between two
   intervals oscillate forever. Milk with a ~10-day shelf life alternates
   between 7 and 14 because unchecking resets the interval to 7 (total
   amnesia), and the next confirmation doubles back to 14. The system can
   never learn "milk is a 10-day item."

2. **Granularity ceiling.** The only representable intervals are {7, 14, 28,
   56}. Black pepper (true cycle ~73 days) can never stabilize — 56 is too
   short, and there is no next step. The 56-day cap forces periodic false
   re-verification of stable pantry staples.

Both problems stem from the same root: the system has no per-item memory of
consumption rate. Every item follows the same doubling ladder, and failure
erases all learning.

## Design

### Core Change: Per-Item Adaptive Ease Factor

Inspired by the SM-2 algorithm (the engine behind Anki's spaced-repetition
system), each ingredient gains an `ease` factor — a per-item growth multiplier
that encodes how quickly the ingredient is consumed. Items the user always has
build high ease (intervals grow fast). Items the user frequently runs out of
settle to low ease (intervals grow slowly). Over time, each item converges to
its own natural restock cycle.

SM-2 uses a per-card ease factor to converge on each card's optimal review
interval. Our adaptation has one advantage SM-2 lacks: when the user runs out,
we observe the *exact* consumption period (days since last confirmation),
rather than just a binary pass/fail. This makes the failure signal much
richer.

### Algorithm

**Per-item data model** (stored in the `on_hand` hash within MealPlan state):

```json
{
  "Milk": {
    "confirmed_at": "2026-03-19",
    "interval": 10,
    "ease": 1.1
  }
}
```

**Constants:**

| Constant | Value | Rationale |
|----------|-------|-----------|
| `STARTING_INTERVAL` | 7 | One grocery cycle (unchanged) |
| `STARTING_EASE` | 2.0 | Matches current doubling behavior on first success |
| `MIN_EASE` | 1.1 | Floor prevents stagnation; 10% minimum growth |
| `MAX_EASE` | 2.5 | SM-2 ceiling; prevents runaway growth |
| `EASE_BONUS` | 0.1 | Additive reward on success; nudges ease up slowly |
| `EASE_PENALTY` | 0.3 | Multiplicative penalty on failure: `ease * 0.7` |
| `MAX_INTERVAL` | 180 | Up from 56; matches orphan retention period |

**Success path** — re-confirm after natural expiry ("I still have this"):

The interval was too short (user still had the item after it expired). Grow
the interval, reward the ease.

```ruby
entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
entry['ease'] = [entry['ease'] + EASE_BONUS, MAX_EASE].min
entry['confirmed_at'] = now
```

**Failure path** — uncheck ("I ran out"):

The interval was too long. Set interval to the actual observed consumption
period. Penalize the ease to slow future growth.

```ruby
observed = (now - Date.parse(entry['confirmed_at'])).to_i
entry['interval'] = [observed, STARTING_INTERVAL].max
entry['ease'] = [entry['ease'] * (1 - EASE_PENALTY), MIN_EASE].max
```

The observed period is floored at `STARTING_INTERVAL` (7 days) to prevent
sub-week intervals from rapid check/uncheck cycles.

**New item** (first check-off):

```ruby
{ 'confirmed_at' => now, 'interval' => STARTING_INTERVAL, 'ease' => STARTING_EASE }
```

**Custom items:** `{ interval: nil, ease: nil }` — exempt from all adaptive
logic, unchanged from current behavior. Custom items cannot be depleted —
unchecking a custom item toggles it off (removes from `on_hand`) as before.
The depleted state applies only to interval-bearing entries where the observed
consumption period is meaningful.

**Same-day idempotency:** unchanged — skip if `confirmed_at == today`.

### Convergence Behavior

The ease factor allows convergence to arbitrary intervals because failure
sets the interval to the observed period (direct measurement) while
simultaneously reducing the growth rate for that specific item. After a few
cycles, the ease factor drops to its floor (1.1), and the system oscillates
within a tight ~10% band around the true consumption period.

**Milk (true ~10-day cycle):**

| Day | Event | interval | ease |
|-----|-------|----------|------|
| 0 | Check off | 7 | 2.0 |
| 8 | Expired, confirm | 14 | 2.1 |
| 18 | Ran out (obs=10) | 10 | 1.47 |
| 18 | Re-check (bought) | 10 | 1.47 |
| 29 | Expired, confirm | 14.7 | 1.57 |
| 39 | Ran out (obs=10) | 10 | 1.1 |
| 39 | Re-check (bought) | 10 | 1.1 |
| 50 | Expired, confirm | 11 | 1.2 |
| 60 | Ran out (obs=10) | 10 | 1.1 |
| **Converged: 10 ↔ 11** ||||

**Salt (never runs out):** ease stays high, interval reaches 180, never
fails, stays parked. Periodic re-verification every ~6 months.

**Pepper (true ~73-day cycle):** converges to 73 ↔ 80 after ~4 failure
cycles. Takes longer (months of real use) because the cycles are long, but
converges reliably.

### Depleted State: Soft Failure

Currently, unchecking deletes the `on_hand` entry entirely (total amnesia).
The new system preserves the entry and marks it as **depleted** — parallel to
how pruning marks entries as **orphaned**.

When the user unchecks an item ("I ran out"), the entry is preserved with the
learned interval and ease, and marked with a sentinel confirmed_at date and a
`depleted_at` timestamp:

```json
{
  "Milk": {
    "confirmed_at": "1970-01-01",
    "interval": 10,
    "ease": 1.47,
    "depleted_at": "2026-03-21"
  }
}
```

The sentinel `confirmed_at` guarantees `effective_on_hand` filters the item
out (it reads as expired). The `depleted_at` field distinguishes depletion
from pruning.

**Re-check after depletion** (user bought more): uses the preserved interval
and ease *without growth*. Clears `depleted_at`, sets `confirmed_at` to today.
This is critical — the observed period just calibrated the interval, and
growing on re-check would immediately undo that calibration.

**Re-confirm after pruning** (recipe re-selected): *does* grow, same as
current behavior. Pruning means "we stopped asking," not "I ran out."

**Precedence:** if a depleted item is subsequently pruned (recipe deselected
while item is already depleted), the item stays depleted. Depletion is the
stronger signal. All reconciliation passes detect the depleted state by
checking for the presence of the `depleted_at` key (not by sentinel
coincidence):

- `expire_orphaned_on_hand`: skip entries with `depleted_at` — they are
  already in a terminal not-on-hand state.
- `fix_orphaned_null_intervals`: no interaction — depleted entries always
  have non-nil intervals (custom items cannot be depleted).
- `purge_stale_orphans`: skip entries with `depleted_at` — depleted entries
  are user-initiated state, not reconciliation artifacts. A user who stops
  buying milk for 6 months should not lose the learned interval. Depleted
  entries are retained indefinitely (they are small and bounded by the
  ingredient catalog).
- `recanon_on_hand_keys`: works as before — depleted entries participate in
  key re-canonicalization. If two entries merge, `pick_merge_winner` selects
  by interval (preserving the whole entry including ease), unchanged.

### On-Hand Entry Lifecycle

```
                     ┌──────────────────────────────────────┐
                     │              on_hand                  │
                     │                                       │
  check off ──►   ACTIVE  ──── natural expiry ────► TO BUY  │
                   │    ▲        (render-time)      (no entry│
                   │    │                            change)  │
                   │    │ re-check                            │
                   │    │ (no growth)                         │
                   │    │                                     │
           uncheck │    │                                     │
                   ▼    │                                     │
                DEPLETED                                     │
                (sentinel confirmed_at,                      │
                 depleted_at set)                             │
                                                             │
           prune   │                                         │
                   ▼                                         │
                ORPHANED ──── re-confirm ────► ACTIVE        │
                (sentinel confirmed_at,        (grows)       │
                 orphaned_at set)                             │
                     └──────────────────────────────────────┘
```

### Tooltip: Restock Estimate

On desktop, each grocery item's checkbox gets a restock hint appended to its
title attribute.

**Active on-hand items** (checked, not expired):
```
Estimated restock in ~X days
```
Where X = `confirmed_at + interval - today`, rounded to nearest integer.

**To Buy items** (unchecked or expired):
```
Restocks every ~X days
```
Where X = the learned `interval`, rounded to nearest integer. Shown only when
the item has been through at least one confirmation cycle (interval >
STARTING_INTERVAL or ease != STARTING_EASE).

**Custom items** (interval nil): no restock line.

Intervals are stored as floats internally for precision but rounded to
integers for all display purposes.

### Help Doc Updates

`docs/help/groceries.md` is the behavioral contract with the user. The
adaptive ease changes the behavior, so the doc must stay true.

**Changes:**

- **"How the System Learns Your Pantry" section:** rewrite to remove the fixed
  7→14→28→56 progression and "eight weeks is the longest." Replace with the
  concept that each item learns at its own pace. Frame the ease factor as
  "confidence" — the system builds confidence in items you always have and
  loses confidence in items you run out of.

- **User-friendly framing:** no mention of "ease," "SM-2," or internal
  mechanics. The explanation should read something like:

  > The system builds confidence in each ingredient independently. Items you
  > always have build confidence quickly — the system stops asking about them.
  > Items you sometimes run out of build confidence slowly, and running out
  > resets some of that confidence. Over time, each ingredient settles into
  > its own rhythm that matches your actual usage.

- **"Week 1 / Week 3 / Week 8" example:** make less specific about timelines.
  The adaptive system makes convergence per-item, not per-week-count.

- **Unchecking behavior:** update from "resets the schedule" to "adjusts the
  schedule based on how long the item lasted" — the system learns from the
  observation rather than starting from scratch.

- **Cap language:** remove "eight weeks is the longest the system will wait."
  Replace with softer language about periodic re-verification for even the
  most stable items.

**No changes needed to:**
- The weekly flow section
- "Checking Items Off" section
- "Staying Visible While Shopping" section
- Custom items section
- "What Happens When Recipes Change" section (pruning semantics unchanged)

### Existing Migration Update

Migration 012 (`convert_checked_off_to_on_hand`) has not shipped. Update it
to include `ease` when creating `on_hand` entries:

- Recipe ingredients: `{ confirmed_at: today, interval: 7, ease: 2.0 }`
- Custom items: `{ confirmed_at: today, interval: nil, ease: nil }`

No additional migration needed. The `ease` field lives inside the `state`
jsonb blob — no schema change.

### Affected Code

| Component | Change |
|-----------|--------|
| `MealPlan` model | Add `STARTING_EASE`, `MIN_EASE`, `MAX_EASE`, `EASE_BONUS`, `EASE_PENALTY` constants. Update `MAX_INTERVAL` from 56 to 180. Update `add_to_on_hand` to use ease-based growth (distinguish depleted re-check from success). Update `remove_from_on_hand` to mark depleted instead of deleting (custom items still delete — they cannot be depleted). Update `next_interval` with ease logic. Update `expire_orphaned_on_hand` to skip entries with `depleted_at`. Update `fix_orphaned_null_intervals` to also set `ease: STARTING_EASE` when converting null intervals (prevents nil ease from crashing the adaptive math). Update `purge_stale_orphans` to skip entries with `depleted_at`. `entry_on_hand?` unchanged — depleted entries have sentinel date, already filtered. |
| `MealPlanWriteService` | No changes. Depletion logic lives entirely in `MealPlan#remove_from_on_hand`. `enrich_check_params` only fires for `checked: true`; the uncheck path receives the item name and case-insensitive lookup handles the rest. |
| `GroceriesController` | Pass full `on_hand` hash (not just effective names) to view so tooltip can access interval data for both on-hand and to-buy items. |
| `GroceriesHelper` or view | Add restock tooltip text to checkbox title attributes. `_shopping_list.html.erb` updated to use on_hand entry data. |
| `Migration 012` | Add `ease` field to converted entries. |
| `docs/help/groceries.md` | Rewrite "How the System Learns" section per Help Doc Updates above. |
| `CLAUDE.md` | Update MealPlan description to mention ease-based growth and depleted state. |
| `meal_plan_test.rb` | Update/add tests for ease-based interval growth, depleted state, re-check-after-depletion semantics, convergence scenarios, custom-item-uncheck-still-deletes, tooltip values. |

### Out of Scope

- Distinguishing "I ran out" from "oops, I was wrong" on uncheck (future
  enhancement if premature check-offs become a problem)
- Visual distinction for items nearing expiry
- Per-aisle or per-category default intervals
- Exposing ease or interval to the user beyond the tooltip
- Shopping mode toggle
- Export/Import of on_hand state (learned intervals and ease are not included
  in kitchen exports — they are ephemeral user state, not portable data)

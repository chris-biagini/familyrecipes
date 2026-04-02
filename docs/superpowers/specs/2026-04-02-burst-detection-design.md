# Grocery Algorithm: Burst Detection

**Date:** 2026-04-02
**Status:** Design
**Motivation:** Tuning rounds 1–2 identified S9 (holiday baker / burst consumption)
as structurally resistant to constant tuning. When a burst event depletes long-cycle
items early, `deplete_observed` treats each depletion as a genuine consumption signal,
dragging intervals down and penalizing ease. Items that normally last 90 days get
52-day predicted intervals from one baking day, causing months of annoying IC prompts.

## Problem

A user buys flour every 90 days. On day 40, they bake 5 pies for Thanksgiving and
run out. They tap "Need It" from On Hand. `deplete_observed` sees observed=40,
interval=90, blends to 52.5, and penalizes ease. The algorithm now thinks flour
goes twice as fast as it does. Recovery takes multiple 90-day cycles — potentially
a year of too-early IC prompts.

The algorithm cannot distinguish a one-off burst from a genuine lifestyle change.
Both present as "observed << interval." The difference: a lifestyle change produces
consistently shorter observations; a burst is a single outlier followed by normal
consumption.

## Design

### Burst gate

Add a `burst?` check to `deplete_observed`. When the gate triggers, the item is
still marked depleted (lands in To Buy) but **interval and ease are preserved** —
the algorithm learns nothing from the outlier. On the next `check!`, the pre-burst
interval resumes.

```ruby
BURST_THRESHOLD = 0.5
MIN_ESTABLISHED_INTERVAL = 14

def burst?(observed)
  interval >= MIN_ESTABLISHED_INTERVAL && observed < interval * BURST_THRESHOLD
end
```

The gate has two conditions:
1. **Established item** (`interval >= MIN_ESTABLISHED_INTERVAL`): the algorithm has
   a real prediction worth protecting. New items (interval=7) still learn normally.
2. **Suspiciously short observation** (`observed < interval * BURST_THRESHOLD`):
   the depletion happened far earlier than predicted, suggesting a one-off event
   rather than a consumption pattern change.

### Updated deplete_observed

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

When `burst?` returns true, the method skips the blend and ease penalty but still
sets `confirmed_at` to sentinel, `depleted_at` to now, and clears `orphaned_at`.
The item transitions to depleted state normally — it just doesn't update its
learned interval or ease.

### Why full bypass, not dampening

A burst is noise, not signal. Clamping or dampening still shifts the interval
in the wrong direction, just less. Full bypass is simpler, more predictable,
and gives the Ralph loop a clean on/off boundary to tune rather than a
dampening curve.

If the user genuinely changes their consumption pattern, the *next* depletion
will have a normal observed/interval ratio (because the interval was preserved),
and the algorithm will learn normally from that observation.

## New constants

| Constant | Default | Tuning range | Purpose |
|----------|---------|-------------|---------|
| `BURST_THRESHOLD` | 0.5 | 0.3–0.7 | Ratio below which a depletion is classified as burst |
| `MIN_ESTABLISHED_INTERVAL` | 14 | 10–21 | Minimum interval before burst detection activates |

## What changes

| File | Change |
|------|--------|
| `app/models/on_hand_entry.rb` | Add constants, add `burst?` private method, update `deplete_observed` |
| `test/sim/grocery_audit.rb` | Mirror constants and method changes in Entry class |
| `test/models/on_hand_entry_conformance_test.rb` | Add constant assertions for new constants |
| `test/sim/tuning_prompt.md` | Document new constants and burst gate in "What You Can Change" |
| `test/sim/tuning_log.md` | Reset for round 3 with new baseline |

## What does NOT change

- Safety margin formula, growth methods, `deplete_sentinel`, `recheck`,
  `assign_starting_values`, `undo_same_day`
- `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions, Monte Carlo sweep
- The sim's `uncheck!` also calls `deplete_observed` — burst detection applies
  there too (same code path)

## Tuning strategy

The Ralph loop re-tunes ALL constants (existing + new):
- `BURST_THRESHOLD` (0.3–0.7)
- `MIN_ESTABLISHED_INTERVAL` (10–21)
- `SAFETY_MARGIN`, `MIN_BUFFER`, `BLEND_WEIGHT`, `MAX_GROWTH_FACTOR`
- `EASE_BONUS`, `EASE_PENALTY`, `MIN_EASE`, `STARTING_EASE`

Previous optimal constants (SM=0.78, BW=0.75, EB=0.05, ME=1.05, MGF=1.3) are
the starting point but may shift now that S9 is handled independently. In
particular, MIN_EASE may be able to move to 1.1 (which previously helped S9
annoyance but hurt S1 miss — a tradeoff that may no longer apply).

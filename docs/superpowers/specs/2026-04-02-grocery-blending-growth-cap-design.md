# Grocery Algorithm: Weighted Blending + Growth Cap

**Date:** 2026-04-02
**Status:** Design
**Motivation:** Tuning iterations 0–3 revealed two structural bottlenecks that
constants alone cannot fix: the 50/50 blending formula converges too slowly, and
the first-cycle growth overshoots by 55%. Both are genuine algorithm deficiencies,
not test-gaming.

## Problem

### Slow blending convergence

`deplete_observed` averages the observed period and the current interval equally:

```ruby
blended = (observed + interval) / 2.0
```

When eggs last 7 days but the interval has overshot to 10.85, the blend gives
8.93 — still 27% above reality. The interval oscillates between 8.5 and 10.8
across cycles, never settling close to the true value. This directly causes the
miss/annoyance tradeoff that blocked tuning: IC alternates between "just right"
(low interval) and "too late" (high interval).

### First-cycle growth overshoot

`grow_standard` (called on the first `have_it!` for sentinel entries) multiplies
the interval by `ease + EASE_BONUS`. With STARTING_EASE=1.5, the first call
produces `7 × 1.53 = 10.71` — a 53% jump from a single confirmation. This is
the seed of the oscillation above.

## Changes

### 1. Weighted blending in `deplete_observed`

Add a `BLEND_WEIGHT` constant (default 0.65) that controls how much weight the
observation gets versus the current prediction:

```ruby
BLEND_WEIGHT = 0.65

def deplete_observed(now)
  observed = (now - confirmed_at).to_i
  blended = observed * BLEND_WEIGHT + interval * (1 - BLEND_WEIGHT)
  self.interval = [blended, STARTING_INTERVAL].max
  # ... rest unchanged
end
```

Effect for eggs (observed=7, interval=10.85):
- Old (50/50): 8.93
- New (65/35): 8.35

The observation is ground truth; the interval is a prediction that already
overshot. Weighting toward the observation is standard in spaced-repetition
systems (SM-2, Anki). `BLEND_WEIGHT` is tunable during the Ralph loop.

### 2. Growth cap via MAX_GROWTH_FACTOR

Add a `MAX_GROWTH_FACTOR` constant (default 1.3) that caps the effective
multiplier in both growth methods:

```ruby
MAX_GROWTH_FACTOR = 1.3

def grow_standard(now)
  self.ease = [ease + EASE_BONUS, MAX_EASE].min
  self.interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
  self.confirmed_at = now
  self.orphaned_at = nil
end

def grow_anchored(now)
  new_ease = [ease + EASE_BONUS, MAX_EASE].min
  self.interval = [interval * [new_ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min

  if confirmed_at + interval.to_i >= now
    self.ease = new_ease
  else
    self.confirmed_at = now
  end
end
```

Effect: first `have_it!` gives `7 × 1.3 = 9.1` instead of `7 × 1.53 = 10.71`.
Later, once ease settles to 1.1–1.2, the cap does not fire. This is a universal
rate-of-change limiter — it constrains *how fast* the interval can grow per
cycle, not *where* it converges. Analogous to Anki's interval modifier cap.

## What does NOT change

- Safety margin formula (`on_hand?`, SQL `active` scope, sim `on_hand?` /
  `ic_fires_on`) — already tuned in iterations 0–3.
- `deplete_sentinel`, `recheck`, `assign_starting_values`, `undo_same_day` —
  no algorithmic changes.
- `FaithfulSim`, `CycleTracker`, `Scorer`, scenario definitions, Monte Carlo
  sweep — the audit harness stays fixed.
- No item-specific or interval-range-specific logic. Both changes are universal
  constants applied uniformly.

## Files changed

| File | Change |
|------|--------|
| `app/models/on_hand_entry.rb` | Add `BLEND_WEIGHT`, `MAX_GROWTH_FACTOR` constants. Update `deplete_observed`, `grow_standard`, `grow_anchored`. |
| `test/sim/grocery_audit.rb` | Mirror constant and method changes in the `Entry` class. |
| `test/sim/tuning_prompt.md` | Update "What You Can Change" to include `BLEND_WEIGHT`, `MAX_GROWTH_FACTOR`, and the two method formulas. Update "What NOT to Change" to reflect the relaxed scope. |
| `test/models/on_hand_entry_conformance_test.rb` | Add constant assertions for `BLEND_WEIGHT` and `MAX_GROWTH_FACTOR`. Existing method-level tests already cover `grow_standard`, `grow_anchored`, `deplete_observed` — they validate the new behavior automatically. |

## Tuning strategy

After implementing, re-run the Ralph loop with an updated tuning prompt that
allows adjustment of:

- `BLEND_WEIGHT` (0.5–0.8 range)
- `MAX_GROWTH_FACTOR` (1.2–1.5 range)
- All existing constants (`SAFETY_MARGIN`, `MIN_BUFFER`, `EASE_BONUS`,
  `EASE_PENALTY`, `MIN_EASE`, `STARTING_EASE`)

The previous best constants (SM=0.78, EB=0.03, ME=1.05) are a good starting
point but may shift now that convergence is faster. In particular, SAFETY_MARGIN
may be able to move back toward 0.80+ since the oscillation band will be tighter.

Previous tuning found STARTING_EASE mostly irrelevant once MAX_GROWTH_FACTOR
caps the first cycle. STARTING_EASE can likely revert to 1.5 (helps long-cycle
items) since the cap prevents the overshoot that made it problematic.

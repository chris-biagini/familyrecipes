# Grocery Interval Resilience — Design Spec

## Problem

The adaptive grocery interval system (SM-2-inspired, three-zone model) works
well in ideal conditions but is fragile under real-world messiness. An audit
of the algorithm against realistic user behavior revealed seven issues:

1. **Same-day uncheck destroys learned state.** Checking and unchecking an item
   on the same day (cracked eggs, wrong brand, accidental tap) fires
   `mark_depleted` with `observed=0`, nuking the interval to
   `STARTING_INTERVAL` and penalizing ease. Recovery takes 6-8 confirmations.

2. **Observation oscillation.** Items with cycles shorter than the shopping
   interval (eggs=7d, milk=10d with weekly shopping) produce observations that
   alternate between two values (7 and 14), never converging.

3. **IC delay inflation.** The anchored growth loop multiplies interval
   repeatedly when the user is slow to process Inventory Check. A 3-week
   absence can blow a 7-day item's interval to 65 days.

4. **Optimistic bias under delay.** Every type of user delay (slow IC response,
   delayed depletion reporting, forgotten updates) pushes intervals upward.
   A realistic distracted user sees +40-50% overestimates on medium-cycle
   items — the opposite of "better to ask and not need it."

5. **STARTING_EASE overshoot.** Ease of 2.0 means the first "Have It" always
   doubles the interval (7→14.7), immediately overshooting for any item with
   a true cycle under ~14 days.

6. **Harsh ease penalty.** `ease *= 0.7` requires 6-8 successful confirmations
   to recover from a single anomalous depletion (holiday baking, guests).

7. **Post-vacation friction.** No bulk action for Inventory Check; users must
   individually tap "Have It" on every expired staple.

## Philosophy

Err on the side of asking. The cost asymmetry is stark:

- Unnecessary IC question: one tap, mild annoyance
- Missing a depleted staple: failed recipe, wasted trip, real frustration

The system should be slightly pessimistic about shelf life. A 10% undershoot
(checking in a day or two early) is dramatically better than a 10% overshoot
(not asking until after the item ran out).

## Changes

### 1. Same-Day Uncheck Grace

When `remove_from_on_hand` fires and `confirmed_at == today`:

- **New entry (created today, no depleted_at history):** Delete from on_hand
  entirely. Treat as undo — the check never happened.
- **Rechecked depleted entry (came through recheck_depleted today):** Restore
  to depleted state — set confirmed_at back to sentinel, set depleted_at to
  today. Interval and ease are unchanged. The learned state survives.

Detection: add a `rechecked_today` flag (or check whether the entry had
`depleted_at` before the recheck cleared it). Simplest: track in a transient
instance variable or check if the entry's interval > STARTING_INTERVAL and
ease < STARTING_EASE (heuristic for "this was previously depleted").

Actually, simplest approach: in `recheck_depleted`, stash the original
depleted entry's interval and ease. In `remove_from_on_hand`, if
`confirmed_at == today`, restore from stash. No — too stateful across calls.

Cleanest: in `remove_from_on_hand`, when `confirmed_at == today`:
- If the entry has `interval == STARTING_INTERVAL` and
  `ease == STARTING_EASE` (brand-new): delete it.
- Otherwise (was rechecked from depletion or had prior history): restore to
  depleted state with the existing interval and ease. Don't penalize ease.
  Set confirmed_at to sentinel, depleted_at to today.

This avoids any extra state tracking. Brand-new entries look like defaults;
everything else has learned values that differ from defaults.

### 2. Blended Intervals on Depletion

Replace:
```ruby
entry['interval'] = [observed, STARTING_INTERVAL].max
```

With:
```ruby
blended = (observed + old_interval) / 2.0
entry['interval'] = [blended, STARTING_INTERVAL].max
```

Where `old_interval` is the entry's interval before this depletion event.
For brand-new items (no prior interval), use `observed` directly since
there's nothing to blend with.

Blending is an exponential moving average. Each observation pulls the interval
halfway toward truth. For oscillating items (eggs with observations of 7 and
14), the interval converges toward the mean (~10.5) instead of ping-ponging.
For delay-inflated observations, blending halves the damage.

`mark_depleted_sentinel` is unchanged — it already preserves the interval
and only penalizes ease, which is correct when there's no real observation.

### 3. One-Step Growth Cap

Replace the loop in `grow_anchored`:

```ruby
# Before: loop until interval covers gap (can multiply many times)
loop do
  entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
  break if confirmed + entry['interval'].to_i >= now
  break if entry['interval'] >= MAX_INTERVAL
end
```

With a single multiplication:

```ruby
entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
# If one step doesn't bridge the gap, reset confirmed_at — the gap is
# too large to trust the anchor (user was absent, not consuming).
if confirmed + entry['interval'].to_i < now
  entry['confirmed_at'] = now.iso8601
end
```

One "Have It" = one growth step. If the gap is too large, the system honestly
admits it doesn't know and starts a fresh observation from today. The learned
interval and ease are preserved.

### 4. Constant Tuning

| Constant       | Current | Proposed | Rationale                                   |
|----------------|---------|----------|---------------------------------------------|
| STARTING_EASE  | 2.0     | 1.5      | First "Have It" grows 50% not 110%          |
| EASE_BONUS     | 0.1     | 0.05     | Slower confidence growth; stays cautious     |
| EASE_PENALTY   | 0.3     | 0.15     | ×0.85 not ×0.7; recover in 2-3 cycles       |
| SAFETY_MARGIN  | (none)  | 0.9      | Items surface for IC 10% before predicted    |

**Safety margin implementation:** Applied in `entry_on_hand?` only:

```ruby
def entry_on_hand?(entry, now)
  # ...existing checks...
  effective = entry['interval'] * SAFETY_MARGIN
  Date.parse(entry['confirmed_at']) + effective.to_i.days >= now
end
```

The stored interval is the true learned estimate. The margin only affects
when items surface in Inventory Check. This keeps learned state clean and
makes the conservatism tunable without touching stored data.

### 5. "All Stocked" Bulk IC Action

When Inventory Check contains 5 or more items, render an "All Stocked"
button at the top of the IC section. One tap fires `have_it` for every
IC item.

**Controller:** New `confirm_all` action on `GroceriesController`. Accepts
the list of item names (embedded as a data attribute on the button, sourced
from the server-rendered IC items). Loops through items, calling
`apply_action('have_it', ...)` for each. Single save via
`Kitchen.batch_writes`.

**Route:** `PATCH /groceries/confirm_all`

**Stimulus:** Button handler in `grocery_ui_controller` that collects IC
item names and posts to the endpoint. Animates the IC section closed.

**Threshold:** Hardcoded at 5. Below that, the individual buttons are fast
enough that bulk action adds clutter without saving meaningful time.

### 6. `check` Action On-Hand Guard

Add to `add_to_on_hand`, after the depleted-recheck early return:

```ruby
return if existing && entry_on_hand?(existing, now)
```

This matches the guard in `apply_have_it` and prevents stale-page or
multi-device race conditions from accidentally growing an on-hand item.

### 7. Help Doc Updates

Light touch — behavior is mostly the same, system just does it better:

- Add a sentence about same-day corrections: "If you check something off by
  mistake, just uncheck it — the system treats same-day corrections as an
  undo, not as running out."
- Mention "All Stocked" in the Inventory Check section.
- Soften "confidence grows faster" language to match the slower EASE_BONUS.

### 8. Simulation Updates

Merge the real-world scenarios into the permanent simulation file:

- Irregular shopping intervals (3d, 11d, 7d, 4d, 10d cycle)
- 2-week vacation
- Accidental same-day uncheck
- Holiday baking burst
- Distracted user (half-attention IC processing)
- Delayed signals (purchase delay, IC delay, depletion report delay)

Add a parallel run of each scenario using the proposed constants and
blending, so the sim output includes before/after comparison.

## What's NOT Changing

- Three-zone model (IC / To Buy / On Hand) — unchanged
- Anchor fix concept — preserved but capped to one step
- Orphan/pruning system — unchanged
- Custom items — unchanged (still exempt from intervals)
- Data schema — no new fields; same on_hand hash structure
- Reconciliation passes — unchanged

## Expected Outcomes

Validated by simulation (numbers are approximate, depend on fuzz seed):

| Scenario              | Current worst | Expected after |
|-----------------------|---------------|----------------|
| Weekly, ideal         | Milk -20%     | Milk ~-10%     |
| Irregular shopping    | Salt +9%      | Similar        |
| 2-week vacation       | Milk +40%     | ~+15-20%       |
| Accidental uncheck    | Eggs +100%    | ~0% (grace)    |
| Holiday baking        | Butter +50%   | ~+20-25%       |
| Distracted user       | Butter +50%   | ~+20-25%       |
| Realistic delays      | Flour +40%    | ~+15-20%       |

The safety margin means the system checks in ~10% early across the board.
A slight negative bias (asking a day or two before predicted depletion) is
the intended behavior.

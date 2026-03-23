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

When `remove_from_on_hand` fires on a non-custom entry and the entry's
`confirmed_at` matches the `now` parameter (same calendar day), intercept
before `deplete_existing` runs:

- **Default-valued entry** (`interval == STARTING_INTERVAL` and
  `ease == STARTING_EASE`): Delete from on_hand entirely. The check never
  happened — item returns to Inventory Check on next render.
- **Entry with learned values** (anything else): Restore to depleted state
  without penalizing ease. Set confirmed_at to sentinel, depleted_at to now.
  Preserve interval and ease unchanged.

This avoids any extra state tracking. Brand-new entries match defaults;
everything else has learned values that differ.

**Edge case — rechecked-depleted entry with default values.** An item
depleted before any learning (created via `create_depleted_entry`, then
purchased same day via `recheck_depleted`) has STARTING_INTERVAL and
STARTING_EASE. The heuristic would delete it instead of restoring to
depleted state. This is acceptable: deletion puts the item back in
Inventory Check, which is the conservative choice. The item was never
learned — there's no state worth preserving.

**Edge case — old entries with pre-change defaults.** Entries created before
these changes may have `ease == 2.0` (the old STARTING_EASE). They won't
match the new defaults and will take the "restore to depleted" path, which
preserves their learned state. This is correct behavior.

**Insertion point:** In `remove_from_on_hand`, after the `return unless entry`
guard and before the `custom || entry['interval'].nil?` branch. Only applies
to the `else` (non-custom) branch.

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
Every entry reaching `mark_depleted` has an interval (from `build_on_hand_entry`
or prior learning), so `old_interval` is always present — no nil guard needed.

Blending is an exponential moving average. Each observation pulls the interval
halfway toward truth. For oscillating items (eggs with observations of 7 and
14), the interval converges toward the mean (~10.5) instead of ping-ponging.
For delay-inflated observations, blending halves the damage.

`mark_depleted_sentinel` is unchanged — it already preserves the interval
and only penalizes ease, which is correct when there's no real observation.
It will automatically use the softer EASE_PENALTY (0.15) from Change 4.

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

With a single multiplication, and ease bumped only on success:

```ruby
new_ease = [entry['ease'] + EASE_BONUS, MAX_EASE].min
entry['interval'] = [entry['interval'] * new_ease, MAX_INTERVAL].min

if confirmed + entry['interval'].to_i >= now
  # Success: one step bridges the gap. Commit the ease bump.
  entry['ease'] = new_ease
else
  # Gap too large to trust the anchor. Reset confirmed_at to now.
  # Don't bump ease — we can't tell if the item lasted or the user
  # was just absent.
  entry['confirmed_at'] = now.iso8601
end
```

One "Have It" = one growth step. If the gap is too large, the system honestly
admits it doesn't know and starts a fresh observation from today. Ease is
only rewarded when anchored growth succeeds — a long absence doesn't build
false confidence.

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

**Controller:** New `confirm_all` action on `GroceriesController`. Receives
a list of item names and calls `apply_action('have_it', ...)` for each.
Single save via `Kitchen.batch_writes`.

**Route:** `PATCH /groceries/confirm_all`

**Stimulus:** Button handler in `grocery_ui_controller` that collects IC
item names from the DOM at click time (from `data-item` attributes on
`.inventory-check-items li` elements — same pattern the Have It / Need It
buttons already use). Posts the collected names to the endpoint. Animates
the IC section closed.

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

**Restock tooltip:** `restock_tooltip` in `groceries_helper.rb` computes
days remaining from the raw interval. With the safety margin, an item can
appear in IC while the tooltip would show "Estimated restock in ~2 days."
Update the tooltip to use the safety-margined effective interval so the
numbers are consistent with the IC trigger.

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

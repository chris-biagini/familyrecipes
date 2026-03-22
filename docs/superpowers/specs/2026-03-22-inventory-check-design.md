# Inventory Check: Three-Zone Grocery Model

**Date:** 2026-03-22
**Status:** Draft
**Supersedes:** `2026-03-21-adaptive-grocery-intervals-design.md` (algorithm
section only — the adaptive ease system remains, this spec changes how user
actions map to algorithm events)
**User docs:** `docs/help/groceries.md` (already updated)

## Problem

The adaptive grocery interval algorithm (SM-2-inspired ease factor with
per-item growth rates) has a convergence trap: when an item's timer expires,
the user checks it off, and the system cannot distinguish **"I still have
this"** from **"I'm buying this."** Both arrive as `checked: true` on an
expired entry.

These are fundamentally different events:

- **"I still have this"** — the timer was too short. The consumption clock has
  been running since the last purchase. Resetting `confirmed_at` erases the
  purchase date and clips the observation window.
- **"I'm buying this"** — the user is starting a new consumption cycle.
  `confirmed_at` should reset to today.

Simulation confirms the impact: with weekly shopping, items with 60-day and
90-day cycles never converge (stuck at 12–13 days, -80% to -86% error). With
more frequent shopping, even 10-day and 14-day cycles get stuck at 7 days.
When the system can distinguish the two events, all items converge to within
2% of their true cycle.

See `test/sim/grocery_convergence.rb` for the simulation and results.

## Design

### Three Zones

The grocery page has three zones:

| Zone | What it means | Items shown |
|------|---------------|-------------|
| **Inventory Check** | The system is asking: do you have this? | No `on_hand` entry (new ingredient), or entry exists and expired (`confirmed_at + interval < today`, no `depleted_at`) |
| **To Buy** | You need to purchase this | Entry has `depleted_at` (user said "Need It" or unchecked from On Hand) |
| **On Hand** | You have this (collapsed) | Entry exists, no `depleted_at`, not expired |

**Layout.** Inventory Check appears at the top of the page, before the
aisle-grouped To Buy sections. It is a flat list (not grouped by aisle) sorted
by descending recipe usage count — ingredients used by many selected recipes
appear first. To Buy and On Hand remain grouped by aisle as they are today.

**New items start in Inventory Check.** An ingredient with no `on_hand` entry
is an unknown — the system's honest question is "do you have this?", not "buy
this." On day one, Inventory Check contains every ingredient; To Buy is empty.
As the user taps "Have It" or "Need It", items flow into On Hand or To Buy.

The zones are **views of existing state** — no new data fields. "Need It" on
a new item (no entry) creates a depleted entry so it appears in To Buy.

### Interactions

| Action | Zone | UI element | Algorithm effect |
|--------|------|------------|------------------|
| **Have It** (new item) | Inventory Check | Button | **First check**: create entry with `confirmed_at = today`, `interval = 7`, `ease = 2.0`. Move to On Hand. |
| **Have It** (expired item) | Inventory Check | Button | **Confirm**: bump `ease += 0.1`, grow `interval` via loop. **Keep `confirmed_at` unchanged** (anchor fix). Move to On Hand. |
| **Need It** (new item) | Inventory Check | Button | Create depleted entry (`confirmed_at = sentinel`, `interval = 7`, `ease = 2.0`, `depleted_at = today`). Move to To Buy. |
| **Need It** (expired item) | Inventory Check | Button | **Deplete**: `interval = max(now - confirmed_at, 7)`, `ease *= 0.7`, mark depleted. Move to To Buy. |
| **Check off** | To Buy | Checkbox | **Purchase**: depleted items recheck (`confirmed_at = today`, preserve interval/ease, clear `depleted_at`). Move to On Hand. |
| **Uncheck** | On Hand | Checkbox | **Deplete**: same as "Need It" on expired item. Move to To Buy. |
| **In-cart check** | To Buy (while shopping) | Checkbox | Same as Check off, plus client-side strikethrough via sessionStorage. |

### The Anchor Fix

"Have It" is the key algorithmic change. By keeping `confirmed_at` at the
original purchase date, the system preserves the full observation window.
When the user eventually runs out (via "Need It" or unchecking from On Hand),
`observed = now - confirmed_at` captures the entire consumption period from
purchase to depletion — not just the tail end after the last confirmation.

**Growth loop.** A single `interval * ease` growth may not push the expiry
(`confirmed_at + interval`) past today, since `confirmed_at` is anchored to a
potentially old date. Ease is bumped once (one user action = one confidence
signal), then the interval grows iteratively until the item is on-hand:

```ruby
entry['ease'] = [entry['ease'] + EASE_BONUS, MAX_EASE].min
loop do
  entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
  break if Date.parse(entry['confirmed_at']) + entry['interval'].to_i >= now
  break if entry['interval'] >= MAX_INTERVAL
end
```

**Fallback when MAX_INTERVAL can't reach today.** If `confirmed_at` is so old
that even `MAX_INTERVAL` (180 days) cannot push the expiry past today, the
system falls back to resetting `confirmed_at = today`. This prevents an item
from being stuck in Inventory Check permanently. In practice, this only fires
for entries that have been dormant for 6+ months.

**Sentinel guard.** Pruned/orphaned entries have `confirmed_at` set to
`ORPHAN_SENTINEL` (`1970-01-01`). Anchoring to 1970 would produce nonsensical
observations. When "Have It" is pressed on an entry with sentinel
`confirmed_at`, the system resets `confirmed_at` to today and grows once
(standard behavior, not anchored). This means pruned items resume their
learned interval but start a fresh observation window — matching the help
doc's description: "the schedule resumes from where it left off."

**Idempotency.** After "Have It" succeeds, the item is on-hand — the button
is no longer visible. As a safety net (race conditions, slow networks), the
method skips processing if `entry_on_hand?(now)` is already true.

### "Need It" Observation Semantics

**Normal case (anchored `confirmed_at`).** The entry's `confirmed_at` is the
purchase date (preserved by previous "Have It" anchoring). The observation =
`now - confirmed_at` ≈ the actual consumption period. This is the correct
signal.

If the user delays responding to Inventory Check (e.g., the item expired on
day 30, user responds on day 35), the observation slightly overestimates. This
self-corrects on the next cycle — the interval will be 35 instead of 30, and
the user will deplete sooner, giving a tighter observation.

**Sentinel case (pruned/orphaned entry).** If `confirmed_at` is the sentinel
(`1970-01-01`), the observation would be ~20,000 days — meaningless. In this
case, the system preserves the existing interval unchanged and only penalizes
ease. The item moves to To Buy with its learned interval intact, ready for
the next purchase to start a fresh observation window.

### Edge Cases

**Day one.** All ingredients are new (no `on_hand` entry). They appear in
Inventory Check, sorted by recipe usage count. To Buy is empty. The user
works through the list: "Have It" for things in the pantry, "Need It" for
things to buy. After one week, confirmed items begin expiring back into
Inventory Check. The system starts learning.

**Buying without the app.** User grabs milk on the way home without checking
the app. Next Saturday, milk's timer has expired — it appears in Inventory
Check. User taps "Have It" (they DO have it now). The system grows the
interval. Slightly wrong (they didn't have it continuously), but the mild
overestimate self-corrects on the next depletion. Much better than the
current stuck-at-7 trap.

**Pruned items re-appearing.** When a deselected recipe is re-selected, its
pruned ingredients reappear. They have sentinel `confirmed_at`, so they show
in Inventory Check (expired). "Have It" resets `confirmed_at` to today
(sentinel guard) and grows the interval from its preserved value. "Need It"
preserves the interval and penalizes ease (sentinel case — see "Need It"
Observation Semantics above).

**Custom items.** `interval: null` — never expire, never appear in Inventory
Check. They stay in To Buy or On Hand based on the user's last action.
Unchanged from current behavior.

**Rapid "Have It" / "Need It".** After "Have It", the item is on-hand and the
button is no longer visible. The `entry_on_hand?` guard prevents re-processing
in race conditions. For the sentinel-guard path (where `confirmed_at` resets
to today), the existing same-day idempotency check also applies.

### Convergence (Simulation Results)

With the three-zone model (equivalent to "anchor confirm only" in the
simulation), all tested consumption cycles converge:

| True cycle | Final interval | Error | Converges by day |
|------------|---------------|-------|-----------------|
| 7 days | 7.0 | 0% | Immediately |
| 10 days | 10.0 | 0% | ~24 |
| 14 days | 14.0 | 0% | ~28 |
| 30 days | 30.0 | 0% | ~100 |
| 60 days | 60.0 | 0% | ~60 |
| 90 days | 90.0 | 0% | ~90 |

With ±2 day fuzz, all items converge within 7% except short-cycle items
(milk at -20%), which oscillate in a tight band around the true value.

## Data Model

**No changes.** The `on_hand` hash entries retain the same fields:
`confirmed_at`, `interval`, `ease`, `depleted_at`, `orphaned_at`. The three
zones are derived from these fields at render time.

## Affected Components

| Component | Change |
|-----------|--------|
| `MealPlan` model | New `confirm_on_hand` method (anchor + growth loop + sentinel guard). Rename current `add_to_on_hand` to clarify it's the purchase path. |
| `MealPlanWriteService` | Accept new action types (`have_it`, `need_it`) alongside existing `check`. Route to appropriate MealPlan methods. |
| `GroceriesController` | Accept `have_it` / `need_it` actions from Inventory Check buttons. |
| `_shopping_list.html.erb` | Three-zone rendering: partition items into To Buy, Inventory Check, On Hand. |
| `grocery_ui_controller.js` | Handle "Have It" / "Need It" button clicks. Send appropriate action to controller. In-cart behavior unchanged (To Buy only). |
| `groceries.css` | Styles for Inventory Check section and Have It / Need It buttons. |
| `docs/help/groceries.md` | Already updated. |
| `meal_plan_test.rb` | Tests for anchor behavior, sentinel guard, growth loop, Need It depletion. |
| `config/routes.rb` | Routes for `have_it` / `need_it` actions. |
| `GroceriesHelper` | Three-zone partitioning logic. Item count text updated to reflect To Buy only (Inventory Check items are not "to buy"). |
| `groceries_controller_test.rb` | Tests for new action types. |
| `test/sim/grocery_convergence.rb` | Update to model three-zone interactions explicitly. |

## Out of Scope

- Distinguishing "I had it all along" from "I bought it without the app" on
  "Have It" (both produce the same anchor behavior — acceptable overestimate)
- Aisle grouping within Inventory Check (flat list sorted by recipe count;
  aisle grouping can be added later if the list gets long)
- Swipe gestures for Have It / Need It (buttons first, gestures later if
  warranted)
- Exposing interval/ease data to the user beyond existing tooltips

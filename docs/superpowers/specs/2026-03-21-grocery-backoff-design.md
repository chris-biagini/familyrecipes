# Grocery Backoff: Anki for Groceries

**Date:** 2026-03-21
**Status:** Draft
**Companion spec:** `2026-03-19-grocery-list-need-have-design.md` (UI layout —
this spec supersedes its "Data Model: No Changes" section)
**User docs:** `docs/help/groceries.md` (behavioral contract)

## Problem

The grocery page tracks ingredient availability as a binary: checked off (on
hand) or not (to buy). This creates three problems:

1. **No re-verification.** An item marked "on hand" stays that way until its
   recipes are deselected and it's pruned. If the same recipes stay selected
   for weeks, perishable items like milk and fresh herbs remain "on hand" long
   after they've been consumed.

2. **Inventory fatigue.** When the user takes inventory before shopping, they
   scan a long list of items and confirm which they have. Staples like salt
   and olive oil appear every week, consuming attention without providing
   value. The user falls into "yep, got it, got it, got it" mode and
   misses items they actually need.

3. **No "in cart" distinction.** During shopping, checking an item immediately
   moves it to the collapsed "On Hand" section. If the user makes a mistake
   (checked off milk but doesn't actually have it), the item is buried among
   pre-existing on-hand items and hard to find.

## Design

### Core Model: Invisible Spaced Repetition

Each on-hand ingredient carries a hidden verification schedule. When the
schedule expires, the item silently moves from "On Hand" back to "To Buy."
The user treats it the same as any new item — check the pantry, check the
box. Behind the scenes, confirming an item doubles its verification interval.

There is no visible "verify" state, no confirmation prompt, no third category.
Items are either To Buy or On Hand. The backoff is invisible. The user just
notices the list getting shorter over time as the system learns their pantry.

Items due for re-verification are NOT visually distinguished from genuinely
new items. This is deliberate: the user's job is the same in both cases (check
the kitchen), and visual hints would invite mindless bulk-confirmation.

### Backoff Parameters

| Parameter        | Value   | Rationale                                         |
|------------------|---------|---------------------------------------------------|
| Starting interval| 7 days  | One grocery cycle. Re-verified next week.         |
| Growth factor    | 2x      | Doubles on each confirmation.                     |
| Max interval     | 56 days | ~8 weeks. Even reliable staples get periodic checks.|
| Reset trigger    | Uncheck or prune | Unchecking resets interval to 7. Pruning deletes the entry. |

### Data Model: `on_hand` Hash

The `checked_off` string array is replaced by an `on_hand` hash keyed by
canonical ingredient name. This eliminates the risk of name-variant drift
between separate structures.

**Before:**
```json
{
  "checked_off": ["Flour", "Salt", "Milk"]
}
```

**After:**
```json
{
  "on_hand": {
    "Flour": { "confirmed_at": "2026-03-15", "interval": 14 },
    "Salt":  { "confirmed_at": "2026-02-20", "interval": 56 },
    "Milk":  { "confirmed_at": "2026-03-19", "interval": 7 }
  }
}
```

`on_hand` replaces `checked_off` in the `STATE_KEYS` constant and in
`CASE_INSENSITIVE_KEYS`. All code that reads or writes `checked_off` is
updated to use the hash. `confirmed_at` stores an ISO 8601 date string (date
only, no time). `interval` is an integer number of days, or `null` for custom
items (exempt from expiration).

**Note on `CASE_INSENSITIVE_KEYS`:** The current `toggle_array` / `list_include?`
/ `list_remove` utility methods operate on arrays with case-insensitive
comparison. These cannot be reused for the `on_hand` hash. New hash-aware
methods are needed: case-insensitive key lookup, case-insensitive key deletion.
All `on_hand` keys must be canonical names from `IngredientResolver`.

**Note on `ensure_state_keys`:** The current `ensure_state_keys` initializes
all `STATE_KEYS` to `[]`. Replace with a `STATE_DEFAULTS` hash that maps each
key to its empty value (`[]` for arrays, `{}` for `on_hand`). The
`ensure_state_keys` method iterates `STATE_DEFAULTS` and assigns
`state[key] ||= default.dup` (`.dup` prevents mutation of the frozen
defaults).

**`effective_on_hand` method:** To avoid reimplementing the expiration filter
in multiple callers (view helper, `RecipeAvailabilityCalculator`, reconciliation),
`MealPlan` should expose `effective_on_hand(now: Date.current)` — returns only
non-expired entries from `on_hand`. This is the single source of truth for
"what's actually on hand right now?" All display and availability code should
call this method rather than reading `on_hand` directly.

### Item Lifecycle

1. **Item checked off** → Create or update entry in `on_hand`:
   - New item: `{ confirmed_at: today, interval: 7 }`
   - Existing item already confirmed today: no change (idempotent). This
     prevents optimistic-locking retries and accidental double-taps from
     prematurely advancing the interval.
   - Existing item (not expired, confirmed on a previous day):
     `{ confirmed_at: today, interval: min(interval * 2, 56) }`
   - Expired item re-confirmed: `{ confirmed_at: today, interval: min(interval * 2, 56) }`
     (Interval still doubles. Expiration is a timeout, not a failure — the
     user is confirming they still have it. This differs from unchecking,
     which signals the item is genuinely absent.)
   - Custom item: `{ confirmed_at: today, interval: null }` (never expires)

   **Custom item detection:** `MealPlanWriteService` determines whether a
   checked item is custom by testing membership in `plan.custom_items`
   (case-insensitive). Items in `custom_items` get `interval: null`; all
   others get recipe-style intervals (7 or doubling). When a custom item
   shares a canonical name with a recipe ingredient, `ShoppingListBuilder`
   deduplicates them — the user sees one entry, and the check-off path sees
   the item in `custom_items`, so it gets `null`. Reconciliation corrects
   this if the custom item is later removed (see Reconciliation below).

2. **Item due for re-verification** (`interval` is not null and
   `confirmed_at + interval < today`) → Treated as "To Buy" at render time.
   Removed from `on_hand` during reconciliation on the next write. Note:
   `on_hand` may contain expired entries at rest between writes — any code
   reading `on_hand` for non-display purposes (e.g., `RecipeAvailabilityCalculator`)
   must also apply the expiration filter.

3. **Item unchecked by user** → Delete from `on_hand`. When re-checked, starts
   with `interval: 7` (fresh start, since unchecking signals unreliability).

4. **Item pruned** (no selected recipe needs it) → Entry stays in `on_hand`
   but `confirmed_at` is set to a sentinel (`1970-01-01`) that guarantees
   expiration. The learned `interval` is preserved. When the ingredient
   reappears from a newly selected recipe, it shows as "To Buy" (expired),
   and re-confirmation doubles the interval from its previous value rather
   than resetting to 7. This differs from unchecking, which deletes the
   entry and resets to 7 — pruning is "we stopped asking," not "I'm out."
   Custom items (`interval: null`) are never pruned by this mechanism.

5. **Item reappears after pruning** → `on_hand` entry exists with sentinel
   `confirmed_at`. Shows as "To Buy" (expired). Re-confirmation picks up
   where the interval left off.

### Expiration Check: Render-Time + Reconciliation

The expiration check runs in two places:

- **Render time (view/helper layer).** When building the shopping list for
  display, items whose `confirmed_at + interval` has passed are rendered as
  "To Buy" regardless of their presence in `on_hand`. This ensures the page
  is always accurate without requiring a background scheduler.

- **Reconciliation (write path).** `prune_checked_off` (renamed to
  `prune_on_hand`) runs three cleanup passes on the `on_hand` hash:

  1. **Prune orphans.** Remove entries whose key is not in `visible_names`
     and not in `custom_items` (case-insensitive). Same logic as the current
     `prune_checked_off`, adapted for hash keys.

  2. **Prune expired entries.** Remove entries where `interval` is not null
     and `confirmed_at + interval < today`. This keeps stored state clean.

  3. **Fix orphaned null intervals.** For each remaining entry with
     `interval: null`, check whether the key is still in `custom_items`
     (case-insensitive). If not, the item was formerly custom but the custom
     entry was removed while a recipe still uses it. Convert its interval to
     7 (starting interval) so it participates in the backoff system. Without
     this pass, a formerly-custom ingredient would silently stay on hand
     forever.

  4. **Re-canonicalize keys.** Resolve each `on_hand` key through the
     current `IngredientResolver`. If the canonical name differs from the
     stored key (e.g., a catalog edit changed "flour" → "Flour"), rename the
     key. If two keys collapse to the same canonical name, keep the one with
     the longer interval. This prevents pruning of valid entries when
     canonical names drift due to catalog changes.

  All four passes are idempotent. Running them on every write is safe.

### Interaction with Pruning

Pruning preserves the learned interval. When an item is pruned:
- Its `confirmed_at` is set to a sentinel date (`1970-01-01`), ensuring
  `effective_on_hand` filters it out (it's expired)
- The `interval` is preserved
- If the item later reappears (recipe re-selected), re-confirmation doubles
  the interval from its previous value

This differs from unchecking, which deletes the entry entirely. Pruning means
"no recipe needs this right now" — not "I don't have it." The system
shouldn't discard what it learned about the user's pantry just because recipe
selections changed temporarily.

Pruning remains the primary staleness mechanism for ingredients with high
recipe coverage (salt, olive oil). These are rarely pruned, so their intervals
grow long. The time-based backoff catches the gap: ingredients that stay on
the list for weeks without recipe changes still get periodic re-verification.

### Custom Items

Custom items are exempt from the backoff system but stored in the same
`on_hand` hash with `interval: null` as a sentinel meaning "never expires."
This avoids a separate `custom_checked` structure that would reintroduce the
dual-structure name-variant drift problem the `on_hand` hash was designed to
eliminate.

```json
{
  "on_hand": {
    "Flour":           { "confirmed_at": "2026-03-15", "interval": 14 },
    "Birthday candles": { "confirmed_at": "2026-03-19", "interval": null }
  }
}
```

The expiration check skips entries with `interval: null`. Pruning also skips
them — custom items are pruned only when the user removes them from
`custom_items`. One hash, one code path for "is this item on hand?", one
reconciliation pass.

### Shopping Trip: "In Cart" Boundary

During shopping, items checked off stay visible in the main list (strikethrough
but not collapsed into On Hand) until the user navigates away from the
groceries page.

**Implementation:** The Stimulus controller maintains a `Set` of item names
checked during this visit, backed by `sessionStorage`. Items in this set are
rendered in the main "To Buy" zone with a checked/strikethrough treatment
rather than in the collapsed "On Hand" zone.

**`sessionStorage`** is used (not a JS-only `Set`) so the "in cart" state
survives mid-shopping navigation to a recipe page and back. It clears when
the browser tab closes or the PWA is terminated by the OS. The key is
`grocery-in-cart-{kitchenSlug}` (scoped to kitchen to prevent cross-kitchen
leakage). The value is a JSON array of item names.

**Turbo morph handling:** When a morph arrives (e.g., another device triggers
a broadcast), the controller re-applies "in cart" treatment to items in the
`sessionStorage` set after the morph settles.

**Server-side, no changes.** Checking an item updates `on_hand` as usual. The
"in cart" visual treatment is purely client-side.

### Preemptive Flagging

Users can uncheck an item from "On Hand" at any time to move it back to "To
Buy." This is the mechanism for "we ran out of flour on Tuesday." Unchecking
deletes the item's `on_hand` entry, resetting its interval.

The UX for this is the existing uncheck mechanism (expand the On Hand section,
find the item, tap to uncheck). A future enhancement could add a quick-toggle
search at the top of the page, but that is out of scope for this effort.

### Migration

A data migration converts existing `checked_off` arrays to the new format:
- Each recipe ingredient in `checked_off` becomes an `on_hand` entry with
  `confirmed_at: today` and `interval: 7` (cold start)
- Custom items in `checked_off` become `on_hand` entries with
  `confirmed_at: today` and `interval: null` (exempt from expiration)
- The `checked_off` key is removed from the state hash
- Distinguish custom vs. recipe items by checking membership in
  `custom_items` (case-insensitive)
- Stale entries in `checked_off` (items not in `visible_names` and not
  custom) are migrated as recipe items with `interval: 7` — the next
  reconciliation will prune them naturally

### Testing Strategy

The backoff logic must be testable without waiting for real time to pass:

- **Time injection.** The backoff check accepts a `now:` parameter (defaulting
  to `Date.current`). Tests pass synthetic dates to simulate weeks of grocery
  runs in a single test.
- **Unit tests on interval math.** Pure function tests: confirm at day 0 with
  interval 7, confirm again, assert interval is 14, etc. Test the cap at 56.
  Test reset on uncheck. Test deletion on prune.
- **Multi-week scenario tests.** Integration tests that simulate a full month:
  select recipes, confirm items, advance time, assert which items surface as
  "To Buy" and which remain "On Hand."
- **Name variant tests.** Verify that the canonical name from
  `IngredientResolver` is always used as the `on_hand` key. Test with
  variant inputs ("Onion" vs "Onions") and assert they resolve to the same
  entry.
- **Pruning + backoff interaction tests.** Verify that pruning deletes the
  `on_hand` entry and that re-appearance starts fresh.
- **Expired re-confirmation tests.** Item expires, user re-confirms. Verify
  interval doubles from its previous value (not reset to 7).
- **RecipeAvailabilityCalculator tests.** Menu page availability badges must
  apply the expiration filter — an expired `on_hand` entry should count as
  "to buy" for availability purposes.
- **Custom item sentinel tests.** Verify `interval: null` items are never
  expired or pruned. Verify they participate correctly in "is on hand?" checks.
- **Same-day idempotency tests.** Check off an item, then check it off again
  on the same day. Verify the interval does not double. Verify `confirmed_at`
  stays the same. This covers both intentional double-taps and
  optimistic-locking retry scenarios.
- **Custom-to-recipe transition tests.** Add a custom item, check it off
  (`interval: null`), then remove the custom item while a recipe still uses
  the same ingredient. Verify reconciliation converts the interval from null
  to 7.
- **Key re-canonicalization tests.** Check off an item, then change the
  ingredient catalog so the canonical name changes. Verify reconciliation
  renames the `on_hand` key rather than pruning it. Verify that two keys
  collapsing to the same canonical name keeps the longer interval.
- **Import/Export roundtrip tests.** Export a kitchen with `on_hand` data,
  import into a fresh kitchen, verify backoff state is preserved. Test
  importing a legacy export with `checked_off` array and verify conversion.

### Affected Code

| Component | Change |
|-----------|--------|
| `MealPlan` model | Replace `checked_off` with `on_hand` hash in `STATE_KEYS`. Replace `STATE_KEYS` array with `STATE_DEFAULTS` hash for mixed-type defaults. New hash-aware methods for case-insensitive key ops (replaces `toggle_array`). Update `apply_action` with same-day idempotency guard. `prune_on_hand` (renamed) runs four passes: prune orphans, prune expired, fix orphaned null intervals, re-canonicalize keys. Add `effective_on_hand(now:)` as single source of truth for on-hand status. |
| `ShoppingListBuilder` | Verify it does not read `checked_off`. No changes expected. |
| `GroceriesController` | Pass `effective_on_hand` to views instead of `checked_off` set. |
| `GroceriesHelper` | Update `shopping_list_count_text` and checked-state logic to use `on_hand` hash. Expiration filter via `effective_on_hand`, not reimplemented. |
| `show.html.erb` | Update render call that passes `checked_off:` to `_shopping_list` partial. |
| `_shopping_list.html.erb` | Update checked-state logic to use `on_hand` hash. |
| `grocery_ui_controller.js` | Add `sessionStorage`-backed "in cart" set. Re-apply after Turbo morphs. On morph, find items in the `sessionStorage` set that the server rendered in the "On Hand" zone and reposition them to the "To Buy" zone with strikethrough. |
| `MealPlanWriteService` | Resolve item names to canonical form via `IngredientResolver` before passing to `MealPlan#apply_action`. This is the canonicalization boundary — `MealPlan` trusts that keys are already canonical. |
| `MenuController` | Reads `plan.checked_off` and passes to `RecipeAvailabilityCalculator`. Update to pass `plan.effective_on_hand.keys` — pre-filtered set of on-hand names. |
| `RecipeAvailabilityCalculator` | Takes `checked_off:` array. Interface unchanged — still receives a list of on-hand names. Only the data source changes (caller passes `effective_on_hand.keys` instead of `plan.checked_off`). Expiration filtering stays in `effective_on_hand`, not reimplemented here. |
| `meal_plan_test.rb` | Rewrite checked-off tests for `on_hand` hash semantics. Add backoff math tests. |
| `recipe_availability_calculator_test.rb` | Update to pass `on_hand` hash instead of `checked_off` arrays. |
| `groceries_controller_test.rb` | Update tests that reference `checked_off` state. |
| `catalog_write_service_test.rb` | Update references to `checked_off`. |
| `ingredient_resolver_regression_test.rb` | Update references to `checked_off`. |
| Data migration | Convert `checked_off` → `on_hand` hash. Recipe ingredients get `interval: 7`, custom items get `interval: null`. Remove `checked_off` key. |
| `docs/help/groceries.md` | Already written (behavioral contract). |
| Companion UI spec | Update `2026-03-19-grocery-list-need-have-design.md` data model section to reference this spec. |

### Out of Scope

- Quick-toggle search for preemptive flagging (future enhancement)
- Visual distinction between "due for re-verification" and "genuinely new"
  (deliberately excluded — see Core Model)
- Perishability metadata in the ingredient catalog
- Aisle-based verification intervals
- Shopping mode toggle

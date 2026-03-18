# What's for Dinner? — Design Spec

**Date:** 2026-03-18
**Version:** v0.5.9
**Scope:** Weighted random recipe picker dialog on the menu page

## Overview

A "What's for Dinner?" dialog on the menu page that suggests recipes using
weighted randomness. Users can influence the pick with per-session tag
preferences (thumbs up/down) and re-roll with declining probability for
rejected recipes. Accepting a suggestion checks it on the menu. Cook history
is tracked via individual recipe unchecks and used to bias toward variety.

Alongside this feature, the select-all and clear-all menu stubs are removed.

## Data Layer

### Cook History

Cook history is stored as an event array in the existing `MealPlan` JSON blob:

```json
{
  "selected_recipes": ["tacos", "bagels"],
  "cook_history": [
    { "slug": "tacos", "at": "2026-03-15T19:30:00Z" },
    { "slug": "bagels", "at": "2026-03-10T18:00:00Z" },
    { "slug": "tacos", "at": "2026-02-28T20:00:00Z" }
  ]
}
```

- `cook_history` is **not** added to `MealPlan::STATE_KEYS`. It is not an
  array that `ensure_state_keys` should initialize — it is created on first
  deselect and accessed with `state.fetch('cook_history', [])`.
- Each individual recipe uncheck appends one `{ slug, at }` entry. The
  append happens inside `MealPlan#apply_select` when `selected: false` and
  `type == 'recipe'` — before the `toggle_array` call that removes the slug
  from `selected_recipes`. This keeps the side effect in the model alongside
  the state mutation it relates to, inside the same `mutate_plan` /
  `with_optimistic_retry` block.
- Only recipe deselections produce history. Quick bite deselections do not.
- Duplicate slugs are expected — frequency is a signal ("we cook tacos a lot").
- Bulk operations (select-all, clear-all) are being removed entirely, so only
  individual unchecks produce history.
- **Pruning:** entries older than 90 days are dropped on every write that
  appends a new entry. Pruning happens in the same `apply_select` call,
  before `save!`, not as a separate write.

### MealPlan#clear! and cook_history

The model method `clear!` sets `self.state = {}`, which would destroy cook
history. Since `clear!` is only called by `MealPlanWriteService#clear` (which
is being removed) and `clear_selections!` (also being removed), both methods
and `clear!` itself are removed. If a future need arises for clearing
selections, it should preserve `cook_history`.

### Recipe Deletion and Cook History

When a recipe is deleted, `MealPlan.reconcile_kitchen!` prunes stale slugs
from `selected_recipes` via `prune_stale_selections`. Cook history entries
for deleted recipes are intentionally **not** pruned — historical data
remains useful for variety weighting even after a recipe is removed. Stale
history entries age out naturally via the 90-day pruning window.

### Recency Weight Formula

`CookHistoryWeighter` computes a weight per recipe from cook history:

```
weight(recipe) = 1 / (1 + Σ ((90 - d) / 90)²)
```

Where `d` is the number of days since each cook event for that recipe within
the 90-day window.

Properties of this formula:
- **Quadratic decay:** penalty contributions fade nonlinearly. A cook from
  45 days ago contributes only 25% of the penalty of a cook from today.
  The tail is gradual — recipes re-enter rotation naturally.
- **Compounding frequency:** multiple cooks in the window sum their
  contributions, so frequently cooked recipes get penalized more.
- **Natural floor:** `1/(1+x)` approaches but never reaches zero. No
  clamping or `max()` needed — every recipe remains possible.
- **One parameter:** the exponent (2, quadratic) is the sole tuning knob.
  No separate `penalty_scale` constant.

Recipes with no cook history get weight 1.0 (neutral).

`CookHistoryWeighter` lives in `app/services/` alongside
`RecipeAvailabilityCalculator` and `ShoppingListBuilder` — pure-function
services consumed by controllers. Input: cook history array. Output:
`{ slug => weight }` hash. Recipes not in history are omitted from the
output (client defaults to 1.0).

## Client-Side Picker Algorithm

The Stimulus controller receives server-computed recency weights and applies
two session-local adjustments:

### Tag Preferences

The dialog shows all tags used across the kitchen's recipes. Each tag is a
3-state toggle pill:

- **Neutral** (default): multiplier 1× — no effect
- **Thumbs up** (green): multiplier 2× — recipes with this tag are favored
- **Thumbs down** (red): multiplier 0.25× — recipes with this tag are suppressed
- Cycle: tap to advance neutral → up → down → neutral

Multiple tag preferences compound multiplicatively. Thumbs-up on "quick" AND
"italian" strongly favors quick Italian recipes.

### Decline Penalty

Each time the user re-rolls past a recipe, its weight is multiplied by 0.3.
This is cumulative within the session:

- Declined once: weight × 0.3
- Declined twice: weight × 0.09
- The recipe can still appear but becomes very unlikely

### Final Weight

```
final_weight = recency_weight × Π(tag_multipliers) × 0.3^times_declined
```

Selection uses standard weighted random sampling: sum all final weights, pick
a random point in [0, total), walk the list.

### Data Sources

The picker reads recipe data from two JSON embeds:

1. **Search data** (existing `SearchDataHelper` blob in layout): provides
   `title`, `slug`, `description`, `category`, `tags` per recipe, plus
   `all_tags`.
2. **Recency weights** (new data attribute on `dinner-picker` controller
   element): `{ slug: weight }` hash from `CookHistoryWeighter`. A data
   attribute is simpler than a nonced script tag for a small hash and
   consistent with how other controller data is passed (e.g.,
   `data-select-url`).

The controller joins these by slug. No duplication of recipe data.

## UI & Interaction Flow

### Entry Point

A "What's for Dinner?" button in the menu page header, next to the existing
"Edit QuickBites" button. Members only (guarded by `current_member?`).

**Edge case — zero recipes:** if the kitchen has no recipes, the button is
hidden entirely (nothing to pick from).

### Dialog States

The dialog progresses through three states. This is a custom `<dialog>`, not
an editor dialog — the `shared/editor_dialog` layout pattern does not apply
here because there is no load/save/content lifecycle. The dialog is opened
and closed directly by the Stimulus controller.

**State 1 — Tag Preferences:**
- Heading: "What are you in the mood for?"
- Subheading: "Tap tags to steer the pick, or just spin."
- Tag pills for all kitchen tags, styled with smart tag decorations if
  `decorate_tags` is enabled. 3-state toggle (neutral/up/down).
- Single action button with a randomly selected quip (see below).
- On re-entry from State 3: tag preferences are preserved, quip re-randomized.

**State 2 — Slot Machine Animation:**
- Recipe names cycle in a display window with decelerating interval.
- Starts fast (~80ms), slows exponentially over ~12-15 cycles.
- Names are drawn from the weighted pool, so the eventual winner is more
  likely to flash by toward the end.
- Duration: ~2s for first spin (12-15 cycles), ~1s for re-rolls (6-8
  cycles, same deceleration curve but fewer iterations).
- Lands on the selected recipe with a brief CSS scale-up transition.
- **Accessibility:** if `prefers-reduced-motion` is active, skip the
  animation and jump straight to the result card.

**State 3 — Result Card:**
- "Tonight's Pick" label.
- Recipe title (large), description, tag pills.
- Buttons: "Add to Menu" (green) and "Try again" (plain).
- "View Recipe" link below buttons — URL constructed from slug using a
  base path data attribute on the controller element (e.g.,
  `data-dinner-picker-recipe-base-path-value`). The controller appends
  the slug to build the full URL.
- **"Add to Menu"** dispatches a synthetic `change` event on the
  corresponding recipe checkbox in the menu DOM. `menu_controller` already
  listens for checkbox changes, so this reuses existing wiring with no
  coupling between controllers. If the recipe is already selected
  (checkbox already checked), this is a no-op — the button text can
  remain "Add to Menu" since this is a harmless edge case.
- "Try again" applies decline penalty to the current recipe, returns to
  State 1 with tag preferences preserved.

### Button Quips

The spin button text is randomly selected from this list on every render
(dialog open, return from State 3):

- I'm feeling lucky
- Baby needs new shoes
- Let it ride
- Fortune favors the bold
- Big money, no whammies
- Today's my lucky day
- This one's got my name on it
- Third time's the charm
- This is the one

Selection is fully random — no first-roll vs re-roll distinction. Chaos.

### Session Lifecycle

All picker state (tag preferences, decline penalties) resets when the dialog
closes. Opening the dialog starts a fresh session.

## Stimulus Controller

**Controller:** `dinner_picker_controller`

**Registration:** must be imported and registered in `application.js`.

**Targets:** dialog, tag container, spin button, result area, slot display

**Values:**
- `recipeBasePath` (String) — base URL for recipe links (e.g., `/recipes/`)
- `weights` (Object) — `{ slug: weight }` from `CookHistoryWeighter`

**Instance state (ephemeral):**
- `tagPreferences` — `{ tagName: multiplier }` (1, 2, or 0.25)
- `declinePenalties` — `{ slug: count }` tracking re-rolls this session
- Reset on dialog close

**Data sources (read on connect):**
- Search data JSON (existing, from layout) — recipes and all_tags
- Recency weights (from `weights` value on controller element)

**Smart tag decorations:** tag pills in the dialog use emoji + color from the
smart tag JSON embed (already in layout), matching the search overlay style.

**DOM construction:** all dynamic elements built via `createElement` /
`textContent` per strict CSP. No `innerHTML`.

## Server-Side Changes

### MealPlan Model

- `apply_select`: when `selected: false` and `type == 'recipe'`, call a
  new private `record_cook_event(slug)` method before the existing
  `toggle_array` call. `record_cook_event` appends
  `{ slug:, at: Time.current.iso8601 }` to `state['cook_history']` and
  prunes entries older than `COOK_HISTORY_WINDOW` (90 days). This keeps
  `apply_select` within the 5-line method limit. The 90-day constant is
  defined on `MealPlan` as `COOK_HISTORY_WINDOW = 90` (days) and shared
  with `CookHistoryWeighter` to avoid drift.
  This runs inside `with_optimistic_retry` (via `mutate_plan` in the
  write service), so a `StaleObjectError` re-reads state before retrying.
- Remove `clear!`, `clear_selections!`, and `select_all!` methods.

### MealPlanWriteService

- Remove `select_all` method and class method.
- Remove `clear` method and class method.
- `apply_action` is unchanged — cook history append is handled by the model.

### CookHistoryWeighter

New service in `app/services/cook_history_weighter.rb` (pure function):

- Input: cook history array (from MealPlan JSON)
- Output: `{ slug => weight }` hash
- Formula: `1 / (1 + Σ ((90 - d) / 90)²)` per slug
- Recipes not in history are omitted (client defaults to 1.0)

### MenuController

- Remove `select_all` and `clear` actions.
- In `show`: compute recency weights via `CookHistoryWeighter` and pass
  to the view as an instance variable.

### Routes

- Remove `select_all` and `clear` routes.
- No new routes — picker is fully client-side after page load.

### Menu View

- Add "What's for Dinner?" button in header (members only, hidden if zero
  recipes).
- Add dinner picker `<dialog>` with `dinner_picker_controller` data
  attributes, including `weights` value and `recipe-base-path` value.
- Remove `#menu-actions` div (select-all / clear-all buttons).
- Remove `data-select-all-url` and `data-clear-url` from `menu-app` div.

### CLAUDE.md Updates

- Update `MealPlanWriteService` line from "select/deselect, select-all,
  clear, reconciliation" to "select/deselect, reconciliation".
- Add note that `MealPlan#apply_select` records cook history on recipe
  deselect (data layer detail lives in the model, not the write service).
- Add `dinner_picker_controller` to the architecture notes.

## Cleanup: Select-All / Clear-All Removal

These are testing stubs being removed to simplify the codebase:

- **Routes:** remove `select_all` and `clear` routes
- **MenuController:** remove `select_all` and `clear` actions
- **MealPlanWriteService:** remove `select_all` and `clear` methods (both
  class and instance)
- **MealPlan model:** remove `clear!`, `clear_selections!`, `select_all!`
- **Menu view:** remove `#menu-actions` div, remove URL data attributes
- **menu_controller.js:** remove `selectAll` and `clear` methods and
  related URL targets
- **Tests:** remove tests for select-all and clear-all across controller,
  service, and model test files

## Testing Strategy

### Ruby (Minitest)

- `CookHistoryWeighter` unit tests:
  - No history → empty hash (client defaults to 1.0)
  - Single recent cook → reduced weight
  - Multiple cooks for same recipe → compounding penalty
  - Cook at 89 days → near-zero penalty contribution
  - Cook at 90+ days → pruned, no contribution
  - Mixed recipes → independent weights

- `MealPlan` model tests:
  - `apply_select` with `selected: false, type: 'recipe'` appends to
    cook history
  - `apply_select` with `selected: false, type: 'quick_bite'` does not
    append cook history
  - Cook history pruning removes entries older than 90 days
  - Cook history is preserved across other state changes

- Menu controller tests:
  - Recency weights data is available in the view
  - Select-all / clear-all routes are removed (no longer routable)

### JavaScript

- Weighted random selection: test deterministic parts (weight computation,
  final weight formula) with known inputs. Test selection function with
  mocked `Math.random` for deterministic output, not statistical sampling.
- Tag multiplier computation: neutral/up/down combinations
- Decline penalty accumulation: verify compounding
- Quip randomization: picks from list (no crashes on empty, etc.)

### Integration

- Full flow: open dialog → toggle tags → spin → verify result card shows
  a recipe → accept → verify recipe is selected on menu
- Re-roll: verify decline penalty state is updated (deterministic check,
  not statistical)

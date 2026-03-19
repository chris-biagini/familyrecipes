# Grocery List: Need / On Hand Layout

**Date:** 2026-03-19
**Status:** Draft
**GitHub Issue:** #256

## Problem

The grocery page serves double duty as a persistent ingredient inventory and an
active shopping list, but the current flat layout creates three UX problems:

1. **Noise.** All ingredients from selected recipes are visible regardless of
   checked state. Staples like salt, olive oil, and oregano occupy screen space
   and consume mental resources during scanning.

2. **Missed items.** Signal is lost in noise. Scrolling through five screenfuls
   of checked staples makes it easy to overlook the two items you actually need.

3. **Cognitive confusion.** The checkbox interaction is semantically overloaded:
   at home, "check" means "I already have this"; at the store, "check" means
   "I just bought this." The user's brain wants "tap" to mean "take action,"
   but the required action inverts between contexts.

## Design

### Core Concept: Visual Separation of Need vs. Have

Each aisle splits into two visual zones:

- **To buy** (unchecked items) — prominent, at the top of the aisle.
- **On hand** (checked items) — dimmed, below a collapsible divider.

The "to buy" zone across all aisles IS the shopping list. By surfacing only
unchecked items prominently, the page transforms from a noisy inventory into a
clean, scannable list of what you actually need.

Custom items that `ShoppingListBuilder` merges into aisle groups participate in
the need/have split identically to recipe ingredients — no special-casing.
They have the same `data-item` attribute and follow the same check/uncheck
mechanics.

### Aisle States

An aisle is in one of three visual states based on its items:

1. **Mixed** (has both unchecked and checked items) — Always expanded. Shows
   unchecked items prominently, then a subtle divider ("5 on hand ▸") followed
   by the collapsible on-hand section. The on-hand section defaults to
   collapsed.

2. **All unchecked** (nothing checked yet) — Always expanded. Shows unchecked
   items with no on-hand divider (nothing to collapse).

3. **All checked** (every item on hand) — Auto-collapses to a single summary
   line: "Pantry — all on hand." Tap to expand and see/manage items.

Aisles no longer have manual collapse — the page adapts to item state. This
replaces the current `<details>` toggle with automatic behavior, eliminating
nested collapsibility (the old design had both aisle collapse and would have
needed on-hand collapse within aisles).

### HTML Structure

The current `<details class="aisle">` / `<summary>` pattern is replaced:

- **Mixed / all-unchecked aisles** use a plain `<section>` with an `<h3>`
  header (always visible, not interactive). The on-hand section is a `<div>`
  toggled via a `hidden` attribute (with a CSS `[hidden] { display: none }`
  rule to override any explicit display). The on-hand divider is a `<button>`
  with `aria-expanded` and `aria-controls` pointing to the on-hand `<div>`.

- **All-checked aisles** use a `<section>` with a `<button>` header that
  toggles expansion. `aria-expanded` and `aria-controls` attributes provide
  accessibility. Keyboard navigation (Enter/Space) works natively on the
  `<button>`.

All interactive collapse elements are `<button>` for keyboard and screen reader
accessibility.

### Summary Bar

The existing `#item-count` span inside `.shopping-list-header` is redesigned.
Current format: "X of Y items needed." New format: "**N** items to buy" (where
N is the count of unchecked items across all aisles, including custom items).
The "X of Y" format is retired — showing only the unchecked count is cleaner
and matches the design's focus on what you need. When no recipes are selected
(empty shopping list), the summary bar is hidden and the existing empty-state
message ("No items yet.") renders as before.

### Checking an Item (To Buy → On Hand)

1. Checkbox fills red, item gets strikethrough + fade animation.
2. Brief pause (~400ms) so the user registers the action.
3. Item animates down below the on-hand divider.
4. Summary bar updates (optimistic, before server response).
5. If the on-hand section is expanded, the item appears there dimmed. If
   collapsed, the on-hand count increments.
6. If this was the last unchecked item in the aisle, the aisle auto-collapses
   to its "all checked" single-line state.

### Unchecking an Item (On Hand → To Buy)

1. User expands the on-hand section (if collapsed).
2. Taps the checked item.
3. Item animates up into the "to buy" zone.
4. Summary bar increments.
5. If the aisle was in "all checked" (collapsed) state, it expands to mixed
   state.

### Usage Scenarios

**At home — inventory scan:**
Open the groceries page. The "to buy" zones show only items you need (staples
from last week are already checked). Scan the short list. See something you
already have? Check it — it slides to "on hand." Done in seconds instead of
scrolling five screens.

**At home — "we ran out of X":**
Expand the on-hand section for the relevant aisle. Find the item. Tap to
uncheck — it slides up to "to buy." Next time you shop, it's waiting for you.

**At the store — shopping:**
The page shows a clean, short list organized by aisle. Check items as you put
them in the cart — each one gets a satisfying animation and slides below the
divider. The summary bar counts down. Expand on-hand within an aisle if you
need to reverse a mistake. Fully-cleared aisles collapse to a single line as
you finish them.

### On-Hand Section Persistence

The expand/collapse state of each aisle's on-hand section is persisted in
localStorage under a **new key**: `grocery-on-hand-{kitchenSlug}` (an object
mapping aisle name → boolean expanded state). The old `grocery-aisles-{slug}`
key is ignored and can be cleaned up on first load. Default for all aisles is
collapsed.

### Print Behavior

Print CSS needs updates to account for the new DOM structure:

- On-hand divider elements: `display: none` in print.
- On-hand section wrapper: `display: none` in print (checked items already
  hidden, but the wrapper itself must not take space).
- All-checked aisle summary lines: `display: none` in print.
- The existing print rules hiding checked `<li>` elements may need selector
  updates to match the new container structure. Verify during implementation
  and adjust `:has()` selectors as needed.
- Unchecked items in the "to buy" zone print with empty square checkboxes
  exactly as before.

## Technical Approach

### Data Model: No Changes

The `MealPlan` JSONB `checked_off` array works as-is. Items are identified by
canonicalized ingredient name. The entire change is in the view/CSS/JS layer.

### Server-Side Changes

**`_shopping_list.html.erb` partial** — Restructure to render items in two
groups per aisle:

1. Unchecked items (the "to buy" zone).
2. A divider `<button>` with on-hand count and `aria-expanded`/`aria-controls`.
3. Checked items (the "on hand" zone, in a `<div>` with `hidden` attribute
   when collapsed).

Aisles where every item is checked render as a single collapsed summary line
(a `<section>` with a `<button>` header) instead of the two-zone layout.

**`GroceriesHelper`** — Add a helper to partition items into checked/unchecked
groups and compute the total unchecked count for the summary bar. Currently the
view iterates items and applies a checked class; the new template needs items
pre-sorted into groups.

**`GroceriesController#show`** — Pass the total unchecked count to the template
for the summary bar (or compute it in the helper).

### Client-Side Changes

**`grocery_ui_controller.js`** — The main changes:

- **Check animation:** Current behavior fires a server request and lets Turbo
  morph handle the DOM update. New behavior: optimistically animate the item
  (strikethrough → pause → slide below divider), update summary bar and
  on-hand count, then fire the server request. The server response triggers a
  Turbo morph which rebuilds the page with items in their correct zones.

- **Morph strategy for animations:** When a Turbo morph arrives, any
  in-progress check/uncheck animation is completed immediately (skip to end
  state). The morph then applies cleanly because the DOM is already in the
  target state. Use the `turbo:before-morph-element` hook to detect animating
  items and snap them to completion. This is simpler and more robust than
  trying to defer morphs or preserve mid-animation state.

- **On-hand expand/collapse:** New interaction for the on-hand divider button.
  Click toggles the on-hand section's `hidden` attribute and updates
  `aria-expanded`. State persisted in localStorage under the new
  `grocery-on-hand-{kitchenSlug}` key.

- **Auto-collapse detection:** After a check animation completes, check if all
  items in the aisle are now checked. If so, transition the aisle to the
  collapsed single-line state.

- **Uncheck from on-hand:** Tap a checked item in the on-hand section →
  animate it back to the to-buy zone, update counts.

- **Summary bar updates:** Optimistically update the "N items to buy" count on
  every check/uncheck.

- **Turbo morph preservation:** On `turbo:before-render`, save on-hand
  expand/collapse state for all aisles. After render, restore from saved
  state. Same pattern as current aisle collapse preservation, but using the
  new key and targeting on-hand sections instead of `<details>` elements.

**`groceries.css`** — New styles:

- On-hand divider: subtle centered line with count text and expand arrow.
- On-hand section: collapsible via `[hidden]` with `section[hidden] { display:
  none }` override (since aisle sections may have explicit display rules).
- Checked items in on-hand zone: dimmed + strikethrough.
- Fully-checked aisle: single-line summary with check circle icon.
- Slide-down / slide-up animations for items transitioning between zones.
- Summary bar styling for the redesigned `#item-count`.
- Print rules: hide on-hand dividers, on-hand wrappers, and all-checked aisle
  summary lines. Update existing `:has()` selectors for the new structure.

### ActionCable / Multi-Device

No changes to the broadcast mechanism. `Kitchen#broadcast_update` triggers a
Turbo morph refresh as before. The morph rebuilds the page with the correct
checked/unchecked grouping server-side. The JS controller's morph-preservation
hooks save and restore on-hand collapse state (same pattern as current aisle
collapse preservation, new key).

### What's NOT Changing

- `MealPlan` model and JSONB schema
- `ShoppingListBuilder` service
- `MealPlanWriteService`
- `GroceriesController` endpoints (check, custom_items, aisle_order)
- Custom items input form (`_custom_items.html.erb`)
- Wake lock controller
- The check/uncheck server-side action semantics

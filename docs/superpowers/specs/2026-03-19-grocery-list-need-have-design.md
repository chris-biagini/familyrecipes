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

### Summary Bar

A summary bar at the top of the page shows the global count: "**7** items to
buy · 4 aisles". This serves as the primary progress indicator during shopping
— as you check items off, the count decrements.

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
localStorage (per kitchen, same mechanism as current aisle collapse). Default
is collapsed. Users who prefer to see checked items can leave sections expanded.

### Print Behavior

The existing print CSS already hides checked items and renders unchecked items
with empty square checkboxes. This works naturally with the new layout — only
the "to buy" zones print. Fully-checked aisles are omitted. No print changes
needed.

## Technical Approach

### Data Model: No Changes

The `MealPlan` JSONB `checked_off` array works as-is. Items are identified by
canonicalized ingredient name. The entire change is in the view/CSS/JS layer.

### Server-Side Changes

**`_shopping_list.html.erb` partial** — Restructure to render items in two
groups per aisle:

1. Unchecked items (the "to buy" zone).
2. A divider element with on-hand count.
3. Checked items (the "on hand" zone, wrapped in a collapsible container).

Aisles where every item is checked render as a single collapsed summary line
instead of the two-zone layout.

**`GroceriesHelper`** — May need a helper to partition items into
checked/unchecked groups and compute counts for the summary bar. Currently the
view iterates items and applies a checked class; the new template needs items
pre-sorted into groups.

**`GroceriesController#show`** — May need to pass the total unchecked count to
the template for the summary bar (or compute it in the view/helper).

### Client-Side Changes

**`grocery_ui_controller.js`** — The main changes:

- **Check animation:** Current behavior fires a server request and lets Turbo
  morph handle the DOM update. New behavior: optimistically animate the item
  (strikethrough → pause → slide below divider), update summary bar and
  on-hand count, then fire the server request. On Turbo morph, preserve
  animation state.

- **On-hand expand/collapse:** New interaction for the on-hand divider. Click
  toggles the on-hand section. State persisted in localStorage per aisle per
  kitchen (replaces current aisle-level collapse storage).

- **Auto-collapse detection:** After a check animation completes, check if all
  items in the aisle are now checked. If so, transition the aisle to the
  collapsed single-line state.

- **Uncheck from on-hand:** Tap a checked item in the on-hand section →
  animate it back to the to-buy zone, update counts.

- **Summary bar updates:** Optimistically update the global "X items to buy"
  count on every check/uncheck.

- **Turbo morph preservation:** The existing morph-preservation logic for
  checkboxes needs to extend to on-hand collapse state and mid-animation
  items.

**`groceries.css`** — New styles:

- On-hand divider: subtle centered line with count text and expand arrow.
- On-hand section: collapsible container (CSS `max-height` or `grid-template-rows`
  transition, matching the current aisle collapse pattern).
- Checked items in on-hand zone: dimmed + strikethrough.
- Fully-checked aisle: single-line summary with check circle icon.
- Slide-down / slide-up animations for items transitioning between zones.
- Summary bar: sticky or fixed at top with item count.

### ActionCable / Multi-Device

No changes to the broadcast mechanism. `Kitchen#broadcast_update` triggers a
Turbo morph refresh as before. The morph will rebuild the page with the correct
checked/unchecked grouping. The JS controller's morph-preservation hooks need
to save and restore on-hand collapse state (same pattern as current aisle
collapse preservation).

### What's NOT Changing

- `MealPlan` model and JSONB schema
- `ShoppingListBuilder` service
- `MealPlanWriteService`
- `GroceriesController` endpoints (check, custom_items, aisle_order)
- Custom items section
- Print behavior (works naturally)
- The check/uncheck server-side action semantics

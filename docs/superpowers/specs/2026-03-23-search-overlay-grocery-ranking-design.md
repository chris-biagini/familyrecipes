# Search Overlay: Grocery Section Ranking & Layout

## Problem

The search overlay's "Need [xxx]?" grocery quick-add row always occupies the
first position in search results. Even when the user types an exact recipe
title, the grocery option sits above it. This is confusing and slows down
recipe navigation — the most common search intent alongside grocery quick-add.

Additionally, ingredient suggestions are presented in a compact "also: x, y,
z" format that looks and behaves differently from recipe results, creating an
inconsistent experience.

## Solution

Replace the single grocery quick-add row with a **floating grocery section** —
a visually distinct container holding full-sized ingredient suggestion rows.
The section floats above or below recipe results based on a ranking heuristic.

## Ranking Heuristic

The grocery section position depends on the best recipe match tier (from the
existing tiered ranking in `search_match.js`):

| Best recipe tier | Grocery position | Rationale |
|---|---|---|
| Tier 0 (title) | Below recipes | Clear recipe intent |
| Tier 1 (description) | Below recipes | Likely looking for a recipe |
| Tier 2 (category) | Above recipes | Ambiguous — grocery is equally likely |
| Tier 3 (tag) | Above recipes | Ambiguous — grocery is equally likely |
| Tier 4 (ingredient) | Above recipes | Could be grocery shopping |
| No match | Above (only section) | Definitely grocery |

Rule: **groceries float above recipes unless a recipe matches at Tier 0 or
Tier 1** (title or description).

## Grocery Section Layout

The grocery section is a contained box with:

- **Section header:** "Add to grocery list" — small, uppercase, green-tinted
  label. Replaces the current "Need X?" phrasing.
- **Full-height ingredient rows:** Each suggestion is the same height as a
  recipe result row, individually navigable with arrow keys.
- **Visual distinction:** Subtle green background tint + green border on the
  edge facing the recipe list (bottom border when promoted above recipes, top
  border when demoted below).
- **Max 4 ingredient rows.** Down from 6 in the current compact alternates
  format. Tighter limit since each row is full height.
- **↵ hint** appears only on the currently highlighted row.

### When promoted (above recipes)

```
┌─────────────────────────────────┐
│ ⌗ chick                        │
├─────────────────────────────────┤
│ ░ ADD TO GROCERY LIST           │
│ ░ chicken                     ↵ │
│ ░ chicken broth                 │
│ ░ chickpeas                     │
│ ═══════════════════════════════ │
│   Chickpea Curry        Mains  │
│   Honey Chicken Wings   Mains  │
│   Chicken Stock         Basics │
└─────────────────────────────────┘
```

### When demoted (below recipes)

```
┌─────────────────────────────────┐
│ ⌗ chick                        │
├─────────────────────────────────┤
│   Chicken Parmesan      Mains ↵│
│   Chicken Tikka Masala  Mains  │
│   Chickpea Curry        Mains  │
│ ═══════════════════════════════ │
│ ░ ADD TO GROCERY LIST           │
│ ░ chicken                       │
│ ░ chicken broth                 │
│ ░ chickpeas                     │
└─────────────────────────────────┘
```

## Keyboard Navigation

- Arrow keys move **linearly through the full list** — recipes and grocery
  rows form one flat sequence. No concept of "zones" from the user's
  perspective.
- **Default selection (index 0)** is the first item in the rendered list —
  whichever section the heuristic placed on top.
- **Enter** on a grocery row fires POST to `/groceries/need`. On a recipe
  row, navigates to the recipe via Turbo. Same as today.
- No special key to jump between sections (Tab behavior TBD in a future
  iteration).

## Result Limits

- **Recipe cap: 8 results.** Currently uncapped. Capping keeps the overlay
  manageable and ensures the grocery section is usually visible.
- **Grocery suggestion cap: 4 rows.**
- **Empty query:** No results, no grocery section. Same as today.

## Edge Cases

- **Query matches only recipes, no ingredient match:** Grocery section still
  shows with the raw query text as a single row. Preserves custom-item
  quick-add for items not in the ingredient corpus.
- **Query matches only ingredients, no recipes:** Grocery section is the only
  thing showing.
- **Tag/category pills active:** Grocery section is hidden. Pills indicate
  recipe filtering intent.

## Files Changed

- `app/javascript/controllers/search_overlay_controller.js` — Rendering
  logic, navigation index management, grocery section positioning.
- `app/javascript/utilities/grocery_action.js` — Replace single-row builder
  with section builder producing multiple full-height rows.
- `app/javascript/utilities/search_match.js` — Export best match tier so
  the controller can use it for positioning.
- `app/assets/stylesheets/navigation.css` — Grocery section styles: green
  container, header label, full-height rows, border direction.

## What This Does NOT Change

- Server-side: no changes to `SearchDataHelper`, `GroceriesController`,
  `MealPlanWriteService`, or the `/groceries/need` endpoint.
- Ingredient matching algorithm (`ingredient_match.js`) — same fuzzy matching.
- Recipe ranking algorithm (`search_match.js`) — same tiered scoring, just
  exposing the best tier.
- Tag pill behavior — same conversion and filtering logic.
- Flash feedback after quick-add — same "Added!" / "Already on your list"
  animation.

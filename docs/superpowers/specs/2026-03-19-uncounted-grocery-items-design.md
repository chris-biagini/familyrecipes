# Uncounted Grocery Items Indicator

**Issue:** #255
**Date:** 2026-03-19

## Problem

When a counted ingredient ("Red bell pepper, 1") is merged with an uncounted
one ("Red bell pepper" from another recipe or Quick Bite), the grocery list
silently drops the uncounted occurrence. The information is lost at two levels:

1. `IngredientAggregator.merge_amounts` deduplicates nils — multiple uncounted
   sources collapse to a single `nil` in the amounts array.
2. `ShoppingListBuilder#serialize_amounts` calls `.compact`, stripping even
   that single `nil`.

The user sees "(1)" with no hint that another recipe also needs peppers — and
buys too few.

## Display Rules

Two cases depending on whether the ingredient has any counted quantities:

### Mixed (counted + uncounted)

Append "+N more" after the quantity, where N is the number of uncounted
source contributions.

```
Red bell peppers (1 +1 more)
Olive oil (3 Tbsp +2 more)
Garlic (4 cloves)           ← fully counted, no indicator
```

### All uncounted

Show "(N uses)" where N is the total number of sources, but only when N > 1.
A single uncounted ingredient stays bare — there's nothing hidden.

```
Red bell peppers (3 uses)
Salt                        ← single source, no indicator
```

## Data Flow Changes

### Tracking uncounted sources in ShoppingListBuilder

The nil count cannot be derived from `IngredientAggregator` output because
`merge_amounts` collapses all nils to a single boolean. Instead, track
uncounted sources as a separate integer alongside the amounts array.

**`merge_ingredient`** — when the incoming `amounts` array is `[nil]` (the
convention for an entirely uncounted contribution), increment the uncounted
counter instead of merging into amounts. When amounts contain a mix (some
Quantity values plus a trailing nil from `aggregate_amounts`), count the nil
and keep only the Quantity values for merging.

**Data structure during aggregation:** each entry becomes
`{ amounts: [...], sources: [...], uncounted: Integer }`.

**`merge_entries`** — sums uncounted counts from both sides when merging.

### ShoppingListBuilder#serialize_amounts

No longer responsible for handling nils — amounts reaching this method are
already nil-free. `.compact` call can be removed (amounts will only contain
Quantity objects).

### ShoppingListBuilder output format

Each item in the organized hash gains an `uncounted:` integer:

```ruby
{ name: "Red bell pepper", amounts: [[1.0, nil]], uncounted: 1, sources: ["Focaccia", "Stir Fry"] }
{ name: "Olive oil", amounts: [[3.0, "Tbsp"]], uncounted: 2, sources: [...] }
{ name: "Garlic", amounts: [[4.0, "cloves"]], uncounted: 0, sources: [...] }
{ name: "Salt", amounts: [], uncounted: 1, sources: ["Focaccia"] }
```

### GroceriesHelper#format_amounts

Accepts `uncounted:` keyword argument. Rendering logic:

- `amounts` present + `uncounted > 0` → `"(1 +2 more)"`
- `amounts` empty + `uncounted > 1` → `"(3 uses)"`
- `amounts` empty + `uncounted <= 1` → `""` (no parenthetical)
- `amounts` present + `uncounted == 0` → existing behavior `"(1)"`

### View partial

`_shopping_list.html.erb` passes `item[:uncounted]` to `format_amounts` at
each call site.

## Edge Cases

- **Cross-reference ingredients** — `CrossReference#expanded_ingredients`
  preserves nils through scaling. An uncounted ingredient from a cross-ref
  recipe that also appears counted in the parent recipe will be correctly
  tracked as an uncounted contribution.
- **Custom items** — always `amounts: []` with `sources: []` and no uncounted
  tracking. Unaffected.
- **Quick Bites** — always contribute `[nil]` per ingredient. Each Quick Bite
  ingredient counts as one uncounted source.

## What Stays the Same

- **IngredientAggregator** — no changes needed. Its nil deduplication is fine
  for its other consumers (NutritionCalculator, Recipe model). The uncounted
  counting is ShoppingListBuilder's concern.
- **Source tracking / tooltips** — the existing "Needed for:" title attribute
  is sufficient context.

## Testing

- ShoppingListBuilder: mixed counted+uncounted from 2 recipes → correct `uncounted` count.
- ShoppingListBuilder: 3+ recipes contributing same uncounted ingredient → `uncounted: 3`.
- ShoppingListBuilder: single uncounted source → `uncounted: 1`, no indicator displayed.
- ShoppingListBuilder: fully counted ingredients → `uncounted: 0`.
- ShoppingListBuilder: cross-reference with uncounted ingredient merged into parent → counted.
- ShoppingListBuilder: Quick Bite ingredient merged with counted recipe ingredient → uncounted incremented.
- GroceriesHelper: `format_amounts` renders "+N more" for mixed case.
- GroceriesHelper: `format_amounts` renders "(N uses)" for all-uncounted with N > 1.
- GroceriesHelper: `format_amounts` renders empty string for single uncounted source.

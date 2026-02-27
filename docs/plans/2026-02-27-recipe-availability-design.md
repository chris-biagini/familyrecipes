# Recipe Availability & Ingredient Provenance Design

**Date:** 2026-02-27
**Status:** Approved

## Goal

Help users discover which recipes they can make with ingredients they already have on hand (based on checked-off grocery items), and show which recipes contribute each ingredient on the shopping list.

## Features

### 1. Availability Indicators (Menu Page)

Colored dots next to each recipe and quick bite in the selector, showing how feasible each item is given what's currently checked off on the Groceries page:

| Missing Count | Color | CSS Variable |
|---------------|-------|--------------|
| 0 | Green | `--available-color` |
| 1 | Yellow | `--almost-color` |
| 2 | Orange | `--close-color` |
| 3+ | Gray | `--unavailable-color` |

Indicators appear on ALL recipes and quick bites regardless of selection state. They update whenever meal plan state changes (check-off, selection change, etc.). Hidden in print.

### 2. Ingredient Popover (Menu Page)

Clicking an availability dot opens a lightweight popover showing the recipe's ingredient list with missing items called out:

```
Flour, Water, Olive oil, Salt, Yeast
Missing: Yeast
```

Single shared `<div id="ingredient-popover">` repositioned per click. Dismissed by clicking outside or pressing Escape. Only one open at a time. Positioned below the dot via `getBoundingClientRect()`, flips above if viewport overflow.

Accessibility: `role="tooltip"`, `aria-expanded` on the dot, `aria-describedby` linking to the popover. Escape returns focus to the dot.

### 3. Provenance Tooltips (Groceries Page)

Native `title` attribute on each shopping list `<li>`:

```
Needed for: Focaccia, Bagels, Cheese Bread
```

Shows which recipes contribute each ingredient. Quick bite titles included alongside recipe titles. Custom items have no tooltip (no recipe source).

## Architecture

### Separate State Endpoints

The Menu and Groceries pages have different data needs. Each gets its own state endpoint:

**`GET /menu/state`** returns:
```json
{
  "version": 10,
  "selected_recipes": ["focaccia", "bagels"],
  "selected_quick_bites": ["nachos"],
  "availability": {
    "focaccia": {
      "missing": 0,
      "missing_names": [],
      "ingredients": ["Flour", "Water", "Olive oil", "Salt", "Yeast"]
    },
    "nachos": {
      "missing": 1,
      "missing_names": ["Jalapenos"],
      "ingredients": ["Tortilla chips", "Cheese", "Jalapenos"]
    }
  }
}
```

**`GET /groceries/state`** returns (existing, extended):
```json
{
  "version": 10,
  "shopping_list": {
    "Dairy": [
      {
        "name": "Butter",
        "amounts": [[200, "g"]],
        "sources": ["Focaccia", "Bagels"]
      }
    ]
  },
  "checked_off": [...],
  "custom_items": [...]
}
```

Both pages subscribe to the same `MealPlanChannel` for version broadcasts. Each refetches its own endpoint when the version bumps.

### New Service: RecipeAvailabilityCalculator

Computes per-recipe/quick-bite availability given the kitchen's recipes and the current checked_off set.

- Collects non-omitted ingredient names per recipe (aisle != 'omit' in IngredientCatalog)
- Diffs each recipe's ingredient set against the checked_off set
- Returns a hash mapping slug to `{ missing:, missing_names:, ingredients: }`

### Extended ShoppingListBuilder

Tracks which recipes contribute each ingredient during the existing aggregation pass. Adds a `sources` array (recipe/quick-bite titles) to each shopping list item.

## Computation Rules

- **Name-based matching only** (not quantity-based). Ingredient names are compared as-is.
- **Omitted ingredients excluded.** Ingredients with `aisle: 'omit'` in IngredientCatalog are assumed always on hand and excluded from both the ingredient list and the missing count.
- **Cross-reference ingredients included.** If Focaccia uses Pizza Dough (a cross-reference), Pizza Dough's ingredients count toward Focaccia's ingredient list.
- **Empty checked_off = all gray.** When nothing is checked off, every recipe shows its full ingredient count as missing.

## No New Database Tables

Everything is computed on the fly from existing data:
- `MealPlan#state['checked_off']` for the on-hand set
- `Recipe#all_ingredients_with_quantities` for per-recipe ingredients
- `QuickBite#all_ingredient_names` for per-quick-bite ingredients
- `IngredientCatalog` for the omit list

# Format Numeric Consolidation — Design

**Issue:** #136 — Float-formatting logic written 3 different ways.

## Problem

The pattern "display as integer if whole, float otherwise" (`3.0` → `3`, `1.5` → `1.5`) appears in three places with three different implementations:

| Location | Returns | Code |
|---|---|---|
| `Recipe#makes` | Numeric (interpolated) | `makes_quantity.to_i == makes_quantity ? makes_quantity.to_i : makes_quantity` |
| `_embedded_recipe.html.erb` | Numeric (interpolated) | `multiplier == multiplier.to_i ? multiplier.to_i : multiplier` |
| `IngredientsHelper#format_nutrient_value` | String | `value == value.to_i ? value.to_i.to_s : value.to_s` |

## Design

### New: `ApplicationHelper#format_numeric(value)`

Single canonical method returning a string. Available in all views and helpers.

### Remove: `Recipe#makes`

This method composes a display string (`"30 cookies"`) — presentation logic that belongs in the view layer. `NutritionCalculator` uses it only as a truthy check and already accesses `makes_quantity` directly.

### New: `RecipesHelper#format_makes(recipe)`

Replaces `Recipe#makes` as a view helper. Composes the formatted text using `format_numeric(recipe.makes_quantity)` and `recipe.makes_unit_noun`.

### Update: `_recipe_content.html.erb`

- Presence check: `recipe.makes_quantity` instead of `recipe.makes`
- Display: `format_makes(recipe)` passed to `format_yield_line` / `format_yield_with_unit`

### Update: `_embedded_recipe.html.erb`

Replace inline ternary with `format_numeric(cross_reference.multiplier)`.

### Update: `IngredientsHelper#format_nutrient_value`

Delegate to `format_numeric`, keeping the nil guard.

### Update: `NutritionCalculator#parse_serving_count`

Change `recipe.makes` → `recipe.makes_quantity` (already accesses `makes_quantity` on the next line).

### Tests

- Remove `Recipe#makes` model tests; add `RecipesHelper#format_makes` helper tests
- Add `ApplicationHelper#format_numeric` tests
- Verify existing integration tests still pass

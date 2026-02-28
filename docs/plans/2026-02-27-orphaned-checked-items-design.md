# Orphaned Checked Items Fix

GitHub issue: #112

## Problem

When a recipe or quick bite is deselected on the menu page, its ingredients drop off the visible grocery list. However, the `checked_off` array in `MealPlan.state` retains those ingredient names indefinitely. `RecipeAvailabilityCalculator` uses the full `checked_off` list to determine ingredient availability, so orphaned entries make recipes appear permanently "on hand" on the ingredients page.

Re-selecting the recipe later also resurrects the stale checked state, which is confusing.

## Fix

Add a `prune_checked_off` method to `MealPlan` that intersects the `checked_off` array with the set of ingredient names currently visible on the shopping list. Call it inside `apply_select` when deselecting (removing a recipe or quick bite). Also call it from `clear_selections!` — clearing all selections means zero visible ingredients, so all checked items are orphaned.

### prune_checked_off flow

1. Build the shopping list via `ShoppingListBuilder` for the current (post-deselect) state.
2. Collect all ingredient names from the shopping list (flat set across aisles).
3. Include custom items — they're user-managed and should survive.
4. Replace `checked_off` with `checked_off & visible_names`.

This runs inside the same `save!` as the deselect toggle, so the prune is atomic.

### Affected code paths

- `MealPlan#apply_select` — calls `prune_checked_off` after toggling when `selected: false`.
- `MealPlan#clear_selections!` — clears `checked_off` along with selections.
- `MealPlan#prune_checked_off` — new private method.

### Edge cases

- **Shared ingredients**: "Flour" needed by both Focaccia and Sourdough — unchecking Focaccia alone does not prune "Flour" since Sourdough still requires it.
- **Re-selecting**: Previously checked items that were pruned won't come back checked. Correct per the issue: "an ingredient should never be both orphaned and treated as available."
- **Custom items**: Stored in `custom_items`, not derived from recipes. Unaffected by prune logic.
- **`clear!`**: Already resets the entire state hash. No change needed.

# Fix #156: Case-insensitive custom items + orphan cleanup

## Problem

Two bugs in `MealPlan` custom grocery items:

1. **Case-sensitive matching.** `toggle_array` uses `Array#include?` and `Array#delete` (exact match), so "Butter" and "butter" are treated as separate items.
2. **Orphaned checked-off state.** Deleting a custom item from `custom_items` leaves its entry in `checked_off` forever. Re-adding the same name (or a recipe ingredient matching it) shows up pre-checked.

Recipe ingredients are not affected — `ShoppingListBuilder#canonical_name` already does case-insensitive lookup.

## Approach

Case-insensitive comparison in `MealPlan` model only. No JS, controller, or ShoppingListBuilder changes.

### `toggle_array` — case-insensitive for `custom_items` and `checked_off`

- **Add:** `any? { |v| v.casecmp?(value) }` — "butter" when "Butter" exists is a no-op (first-entered casing wins)
- **Remove:** `reject! { |v| v.casecmp?(value) }` — removing "Butter" also removes "butter"
- Slug keys (`selected_recipes`, `selected_quick_bites`) stay exact-match

### `apply_custom_items` — orphan cleanup on remove

When `action == 'remove'`, also remove matching entries from `checked_off` (case-insensitively).

### `prune_checked_off` — case-insensitive custom item retention

Use `any? { |c| c.casecmp?(item) }` instead of `Set#include?`.

## Tests

- Add custom item ignores case-insensitive duplicate
- Remove custom item is case-insensitive
- Check-off matching is case-insensitive
- Removing a custom item cleans up its checked-off entry
- Prune preserves custom items case-insensitively

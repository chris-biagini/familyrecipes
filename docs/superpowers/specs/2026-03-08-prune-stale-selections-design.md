# Prune Stale MealPlan Selections (#196)

## Problem

When recipes are deleted/renamed or Quick Bites are edited, stale slugs/IDs accumulate in `MealPlan.state`. `ShoppingListBuilder` silently filters them on read, but if a new recipe or Quick Bite reuses a previously-deleted slug/ID, it gets auto-selected without user action.

## Design

Add `prune_stale_selections(kitchen:)` to `MealPlan`. It queries valid recipe slugs and Quick Bite IDs from the kitchen, then removes any entries from `selected_recipes` and `selected_quick_bites` that no longer exist. Saves only if something changed.

Call sites:
- `RecipeWriteService#prune_stale_meal_plan_items` — already runs after every recipe mutation
- `MenuController#update_quick_bites` — already runs post-save cleanup

`ShoppingListBuilder`'s read-side filtering stays as a safety net.

## Method

```ruby
def prune_stale_selections(kitchen:)
  ensure_state_keys
  valid_slugs = kitchen.recipes.pluck(:slug).to_set
  valid_qb_ids = kitchen.parsed_quick_bites.map(&:id).to_set

  recipes_before = state['selected_recipes'].size
  qb_before = state['selected_quick_bites'].size

  state['selected_recipes'].select! { |s| valid_slugs.include?(s) }
  state['selected_quick_bites'].select! { |s| valid_qb_ids.include?(s) }

  changed = state['selected_recipes'].size < recipes_before ||
            state['selected_quick_bites'].size < qb_before
  save! if changed
end
```

## Test Scenarios

1. Recipe delete prunes its slug from `selected_recipes`
2. Recipe rename prunes old slug from `selected_recipes`
3. Quick Bite edit prunes removed Quick Bite IDs from `selected_quick_bites`
4. Slug reuse does NOT auto-select
5. No-op when all selections are valid (no unnecessary save)

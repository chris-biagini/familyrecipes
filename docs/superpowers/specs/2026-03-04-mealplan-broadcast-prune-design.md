# MealPlan Broadcast + Prune Refactor (#179 + #180)

## Problem

**#179:** `Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)` is copy-pasted in three places (MealPlanActions, CatalogWriteService, RecipeBroadcaster). Changing the stream name or mechanism requires a three-file edit.

**#180:** `MealPlan.prune_stale_items` is a class method that internally constructs a `ShoppingListBuilder` to determine which checked-off items are still visible. This puts orchestration logic on the model that belongs with callers.

## Design

### #179: Extract `MealPlan.broadcast_refresh`

Add a class method to `MealPlan`:

```ruby
def self.broadcast_refresh(kitchen)
  Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
end
```

Replace all three call sites to delegate to it.

### #180: Inline pruning at call sites

Remove `MealPlan.prune_stale_items` class method. Keep `prune_checked_off(visible_names:)` instance method.

Each caller computes visible names via ShoppingListBuilder and calls `prune_checked_off` directly:

1. **MealPlanActions#prune_if_deselect** — already inside `mutate_plan`'s retry block with `plan` in hand. Build shopping list, extract visible names, call `plan.prune_checked_off(visible_names:)`.

2. **RecipeWriteService#post_write_cleanup** — fetch plan, wrap in `with_optimistic_retry`, build list, prune.

3. **MenuController#update_quick_bites** — same pattern as RecipeWriteService.

`with_optimistic_retry` stays on MealPlan (model concern for optimistic locking). Update MealPlan header comment to remove ShoppingListBuilder mention.

# MealPlan Reconciliation Design

## Problem

Meal plan pruning logic is scattered across three call sites with inconsistent
patterns. Each caller manually constructs a ShoppingListBuilder, calls the right
combination of prune methods, and wraps in optimistic retry — a contract that
must be replicated exactly every time.

Additionally:
- RecipeWriteService broadcasts *before* pruning, so clients briefly see stale
  state (orphan categories, deleted-recipe selections).
- Catalog name changes (renaming an ingredient's canonical name via the resolver)
  leave orphaned checked-off items that no one prunes.

## Solution

`MealPlan#reconcile!` — a single public method that does a full consistency
sweep. Callers say `plan.reconcile!` and don't need to know the internals.

```ruby
def reconcile!
  visible = ShoppingListBuilder.new(kitchen:, meal_plan: self).visible_names
  prune_checked_off(visible_names: visible)
  prune_stale_selections(kitchen:)
end
```

### Design decisions

- **Always full sweep.** No scoped hints or optimization paths. The pluck is
  trivially cheap against SQLite, and "callers don't need to think" is the point.
- **Lives on MealPlan.** The model already owns the prune methods; reconcile is
  the missing orchestrator. Prune methods become private implementation details.
- **apply_action purely mutates, callers reconcile.** The inline
  `prune_checked_off_for` in `apply_custom_items` is removed. Reconciliation is
  always the caller's responsibility (via `apply_plan` or direct call).
- **Callers broadcast.** `reconcile!` is purely about MealPlan consistency.
  Broadcasting is a separate concern owned by controllers and services.

## Call site changes

### MealPlanActions concern

`apply_plan` calls `reconcile!` after every action unconditionally. Deleted:
`prune_if_deselect`, `shopping_list_visible_names`.

```ruby
def apply_plan(action_type, **action_params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **action_params)
    plan.reconcile!
  end
end
```

### MealPlan#apply_custom_items

Simplified — just toggle and save, no inline prune. `prune_checked_off_for`
deleted.

```ruby
def apply_custom_items(item:, action:, **)
  toggle_array('custom_items', item, action == 'add')
end
```

### MenuController#update_quick_bites

Replaces manual retry+prune block with `mutate_plan(&:reconcile!)`.

### RecipeWriteService

`prune_stale_meal_plan_items` calls `plan.reconcile!` inside optimistic retry.
`broadcast_update` moves after `post_write_cleanup` in create, update, destroy.

### CatalogWriteService (new)

Adds `reconcile_meal_plan` called after upsert and destroy, closing the catalog
name-change gap.

## What gets deleted

| Method | File | Reason |
|---|---|---|
| `prune_if_deselect` | MealPlanActions | Subsumed by unconditional reconcile |
| `shopping_list_visible_names` | MealPlanActions | ShoppingListBuilder now internal to reconcile |
| `prune_checked_off_for` | MealPlan | Subsumed by full sweep |

`prune_checked_off` and `prune_stale_selections` become private.

## What doesn't change

`mutate_plan`, `with_optimistic_retry`, `apply_action`, `broadcast_update`
semantics, StaleObjectError handling, ShoppingListBuilder internals.

## Test changes

Existing prune tests rewritten as `reconcile!` tests — same scenarios, testing
the public API. New tests for catalog name-change reconciliation and
CatalogWriteService integration.

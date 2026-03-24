# MealPlan#reconcile! Refactor Design

## Problem

`MealPlan#reconcile!` depends on `ShoppingListBuilder`, inverting the normal
dependency direction (models should not depend on services). It also builds the
entire shopping list — amounts, aisle grouping, sorting — just to extract
ingredient names, then throws everything else away. Finally, it does up to two
separate `save!` calls (one per prune method), which is wasteful and
complicates optimistic retry.

## Changes

### 1. Rewrite `ShoppingListBuilder#visible_names`

Current implementation calls `build` (full shopping list pipeline) then
extracts names. Rewrite to collect ingredient names directly: iterate selected
recipes and quick bites, resolve canonical names, filter omitted, add custom
items. No amount aggregation, no aisle grouping, no sorting.

### 2. Make `MealPlan#reconcile!` accept `visible_names:` as a required kwarg

The model no longer instantiates `ShoppingListBuilder`. Callers compute
visible names and pass them in. This fixes the dependency direction: services
compute, model consumes.

Both `prune_checked_off` and `prune_stale_selections` mutate state in memory
and return whether anything changed. `reconcile!` saves once at the end if
either method changed something.

### 3. Update all call sites

Five places currently call `plan.reconcile!`:

- `RecipeWriteService#prune_stale_meal_plan_items`
- `CatalogWriteService#reconcile_meal_plan`
- `QuickBitesWriteService#finalize`
- `MealPlanWriteService` (inside `mutate_plan` blocks and `reconcile`)
- `Kitchen.finalize_batch`

Each gains a one-liner to compute visible names via
`ShoppingListBuilder.visible_names_for(kitchen:, meal_plan:)` before calling
`plan.reconcile!(visible_names:)`.

## What does NOT change

- `ShoppingListBuilder#build` and `GroceriesController#show` are untouched.
- The batching protocol (`Kitchen.batching?` guards) stays identical.
- `MealPlanWriteService`'s reconcile-inside-mutate pattern stays — reconcile
  still runs inside the optimistic retry block alongside the mutation.
- No new classes. The lightweight name collection lives on `ShoppingListBuilder`
  as a class method.

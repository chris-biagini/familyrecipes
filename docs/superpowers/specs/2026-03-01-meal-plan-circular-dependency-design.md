# Break MealPlan ↔ ShoppingListBuilder Circular Dependency

**Issue:** #133
**Date:** 2026-03-01

## Problem

`MealPlan#visible_item_names` instantiates `ShoppingListBuilder` to discover which ingredient names are currently on the shopping list. `ShoppingListBuilder` reads `@meal_plan.state` to get selections. This creates a circular dependency: Model → Service → Model.

The model shouldn't need to know about a service that consumes it. It also makes MealPlan harder to test in isolation — prune tests require real recipes, catalog entries, and the full ShoppingListBuilder pipeline.

## Design

**Inject visible names instead of discovering them.** `prune_checked_off` accepts a `visible_names:` keyword argument — a Set of ingredient name strings currently on the shopping list. The model performs a pure data operation (intersect `checked_off` with the set) without ever touching `ShoppingListBuilder`.

### Changes to MealPlan

`prune_checked_off(visible_names:, force_save: false)` — requires a `visible_names:` keyword. Removes any `checked_off` entry not in the set (or among `custom_items`, which are always visible). Saves when items were actually pruned or when `force_save` is true.

`apply_select` no longer calls `prune_checked_off` directly. When deselecting, it toggles the selection off and saves. The controller is responsible for pruning afterward.

Remove `visible_item_names` entirely — no more `ShoppingListBuilder` reference in the model.

### Changes to controllers

Extract a `build_visible_names` helper into `MealPlanActions` concern:

```ruby
def build_visible_names(kitchen, meal_plan)
  shopping_list = ShoppingListBuilder.new(kitchen: kitchen, meal_plan: meal_plan).build
  names = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }
  Set.new(names)
end
```

Update the three call sites:

1. **`MealPlanActions#apply_and_respond`** — after `apply_action`, if the action was a deselect, build visible names and call `prune_checked_off`.
2. **`MenuController#update_quick_bites`** — build visible names, pass to `prune_checked_off`.
3. **`RecipesController#update` and `#destroy`** — build visible names, pass to `prune_checked_off`.

### Changes to tests

MealPlan model tests become simpler: `prune_checked_off` tests just pass in a Set of names directly — no need to set up real recipes or catalog entries. The integration behavior (controller builds list, passes to prune) is covered by controller tests.

## Alternatives considered

**Move prune into ShoppingListBuilder.** The builder already builds the list, so it could also prune. But `checked_off` is MealPlan's data — having the builder mutate and save the model it reads from is its own smell.

**Move prune into controllers inline.** Works but duplicates the same 3-line prune pattern across 4 call sites. The concern helper avoids this.

## Scope

- `app/models/meal_plan.rb` — change `prune_checked_off` signature, remove `visible_item_names`, remove `apply_select`'s prune call
- `app/controllers/concerns/meal_plan_actions.rb` — add `build_visible_names`, update `apply_and_respond` for deselect pruning
- `app/controllers/menu_controller.rb` — pass visible names to `prune_checked_off`
- `app/controllers/recipes_controller.rb` — pass visible names to `prune_checked_off`
- `test/models/meal_plan_test.rb` — simplify prune tests to use injected names
- Controller tests — verify prune still works end-to-end

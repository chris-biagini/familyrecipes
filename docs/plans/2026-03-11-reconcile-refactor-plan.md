# MealPlan#reconcile! Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Remove MealPlan's dependency on ShoppingListBuilder, make `visible_names` computation lightweight, and consolidate the double save in `reconcile!`.

**Architecture:** `MealPlan#reconcile!` gains a required `visible_names:` keyword argument — the model no longer instantiates any service. `ShoppingListBuilder#visible_names` is rewritten to collect names directly without building the full shopping list. All five call sites pass in computed visible names.

**Tech Stack:** Ruby on Rails, Minitest, SQLite

---

### Task 1: Rewrite `ShoppingListBuilder#visible_names`

**Files:**
- Modify: `app/services/shopping_list_builder.rb:29-31`
- Test: `test/services/shopping_list_builder_test.rb`

**Step 1: Run existing `visible_names` tests to establish baseline**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /visible_names/`
Expected: 4 tests PASS

**Step 2: Rewrite `visible_names` to skip the full build pipeline**

Replace the current `visible_names` method in `app/services/shopping_list_builder.rb`:

```ruby
def visible_names
  names = Set.new

  selected_recipes.each do |recipe|
    recipe.all_ingredients_with_quantities.each { |name, _| names << canonical_name(name) }
  end

  selected_quick_bites.each do |qb|
    qb.ingredients_with_quantities.each { |name, _| names << canonical_name(name) }
  end

  names.reject! { |name| @resolver.omitted?(name) }

  @meal_plan.custom_items_list.each { |item| names << canonical_name(item) }

  names
end
```

**Step 3: Run `visible_names` tests to verify behavior unchanged**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /visible_names/`
Expected: 4 tests PASS — same results, no `build` call underneath

**Step 4: Run full ShoppingListBuilder test file**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All PASS — `build` is untouched, `visible_names` is independent

**Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb
git commit -m "refactor: rewrite visible_names to skip full shopping list build"
```

---

### Task 2: Refactor `MealPlan#reconcile!` to accept `visible_names:` and save once

**Files:**
- Modify: `app/models/meal_plan.rb:91-121`
- Test: `test/models/meal_plan_test.rb`

**Step 1: Run existing reconcile tests to establish baseline**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /reconcile/`
Expected: 10 tests PASS

**Step 2: Update `reconcile!` to require `visible_names:` kwarg and save once**

Replace the `reconcile!` method and its two private prune methods in
`app/models/meal_plan.rb`:

```ruby
def reconcile!(visible_names:)
  ensure_state_keys
  changed = prune_checked_off(visible_names:)
  changed |= prune_stale_selections
  save! if changed
end

private

def prune_checked_off(visible_names:)
  custom = state['custom_items']
  before_size = state['checked_off'].size
  state['checked_off'].select! { |item| visible_names.include?(item) || custom.any? { |c| c.casecmp?(item) } }
  state['checked_off'].size < before_size
end

def prune_stale_selections
  valid_slugs = kitchen.recipes.pluck(:slug).to_set
  valid_qb_ids = kitchen.parsed_quick_bites.to_set(&:id)

  recipes_before = state['selected_recipes'].size
  qb_before = state['selected_quick_bites'].size

  state['selected_recipes'].select! { |s| valid_slugs.include?(s) }
  state['selected_quick_bites'].select! { |s| valid_qb_ids.include?(s) }

  state['selected_recipes'].size < recipes_before ||
    state['selected_quick_bites'].size < qb_before
end
```

Remove the redundant `ensure_state_keys` calls from each prune method — `reconcile!`
calls it once at the top.

**Step 3: Update all `reconcile!` calls in tests to pass `visible_names:`**

Every test that calls `plan.reconcile!` needs to pass a `visible_names:` set.
Most tests can use a `ShoppingListBuilder` to compute it — or pass an explicit
set when the test is simpler.

Add a helper at the top of the test class:

```ruby
def reconcile_plan!(plan)
  visible = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).visible_names
  plan.reconcile!(visible_names: visible)
end
```

Then replace every `plan.reconcile!` with `reconcile_plan!(plan)` (or
`reconcile_plan!(list)` where the local is named `list`). The affected tests:

- `reconcile! removes checked-off items not on shopping list`
- `reconcile! preserves checked-off items on shopping list`
- `reconcile! preserves custom items even when not in visible names`
- `reconcile! preserves custom items case-insensitively`
- `reconcile! removes deleted recipe slugs from selections`
- `reconcile! removes deleted quick bite IDs from selections`
- `reconcile! is idempotent when nothing to prune`
- `reconcile! saves when items are pruned`
- `removing custom item and reconciling cleans up checked-off entry`
- `removing custom item and reconciling cleans up case-mismatched checked-off entry`

**Step 4: Run reconcile tests**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /reconcile/`
Expected: 10 tests PASS

**Step 5: Run full MealPlan test file**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All PASS

**Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "refactor: MealPlan#reconcile! accepts visible_names kwarg, saves once"
```

---

### Task 3: Update write service call sites

**Files:**
- Modify: `app/services/meal_plan_write_service.rb:32-61`
- Modify: `app/services/recipe_write_service.rb:95-106`
- Modify: `app/services/catalog_write_service.rb:73-83`
- Modify: `app/services/quick_bites_write_service.rb:42-48`
- Modify: `app/models/kitchen.rb:40-44`
- Test: `test/services/meal_plan_write_service_test.rb`

**Step 1: Update `MealPlanWriteService`**

In `app/services/meal_plan_write_service.rb`, update the three `mutate_plan`
blocks that call `plan.reconcile!` and the standalone `reconcile` method.

Each block needs to compute visible names before reconciling:

```ruby
def apply_action(action_type:, **params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **params)
    reconcile_plan(plan) unless Kitchen.batching?
  end
  finalize
end

def select_all(recipe_slugs:, quick_bite_slugs:)
  mutate_plan do |plan|
    plan.select_all!(recipe_slugs, quick_bite_slugs)
    reconcile_plan(plan) unless Kitchen.batching?
  end
  finalize
end

def clear
  mutate_plan do |plan|
    plan.clear_selections!
    reconcile_plan(plan) unless Kitchen.batching?
  end
  finalize
end

def reconcile
  return if Kitchen.batching?

  mutate_plan { |plan| reconcile_plan(plan) }
  kitchen.broadcast_update
end
```

Add the private helper:

```ruby
def reconcile_plan(plan)
  visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
  plan.reconcile!(visible_names: visible)
end
```

**Step 2: Update `RecipeWriteService`**

In `app/services/recipe_write_service.rb`, replace `prune_stale_meal_plan_items`:

```ruby
def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end
end
```

**Step 3: Update `CatalogWriteService`**

In `app/services/catalog_write_service.rb`, replace `reconcile_meal_plan`:

```ruby
def reconcile_meal_plan
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end
end
```

**Step 4: Update `QuickBitesWriteService`**

In `app/services/quick_bites_write_service.rb`, replace the finalize body:

```ruby
def finalize
  return if Kitchen.batching?

  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end
  kitchen.broadcast_update
end
```

**Step 5: Update `Kitchen.finalize_batch`**

In `app/models/kitchen.rb`, replace `finalize_batch`:

```ruby
def self.finalize_batch(kitchen)
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end
  kitchen.broadcast_update
end
```

**Step 6: Run write service tests**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: All PASS

**Step 7: Run full test suite**

Run: `rake test`
Expected: All PASS

**Step 8: Commit**

```bash
git add app/services/meal_plan_write_service.rb app/services/recipe_write_service.rb \
       app/services/catalog_write_service.rb app/services/quick_bites_write_service.rb \
       app/models/kitchen.rb
git commit -m "refactor: callers pass visible_names to reconcile!, fixing dependency direction"
```

---

### Task 4: Update header comments and lint

**Files:**
- Modify: `app/models/meal_plan.rb` (header comment)
- Modify: `app/services/shopping_list_builder.rb` (header comment)

**Step 1: Update MealPlan header comment**

Remove the mention of ShoppingListBuilder from the header comment since MealPlan
no longer depends on it. Replace the `MealPlan#reconcile!` description to note
the required `visible_names:` argument.

**Step 2: Update ShoppingListBuilder header comment**

Note that `visible_names` is a lightweight method that does NOT call `build`.
Mention that it is used by write services for meal plan reconciliation.

**Step 3: Run lint**

Run: `bundle exec rubocop app/models/meal_plan.rb app/services/shopping_list_builder.rb app/services/meal_plan_write_service.rb app/services/recipe_write_service.rb app/services/catalog_write_service.rb app/services/quick_bites_write_service.rb app/models/kitchen.rb`
Expected: No offenses

**Step 4: Run full suite + lint**

Run: `rake`
Expected: All tests PASS, 0 RuboCop offenses

**Step 5: Commit**

```bash
git add app/models/meal_plan.rb app/services/shopping_list_builder.rb
git commit -m "docs: update header comments for reconcile refactor"
```

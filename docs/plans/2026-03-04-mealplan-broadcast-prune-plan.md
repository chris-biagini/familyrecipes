# MealPlan Broadcast + Prune Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** DRY the meal-plan broadcast call (#179) and move prune orchestration out of MealPlan (#180).

**Architecture:** Extract `MealPlan.broadcast_refresh` class method to own the stream tuple. Remove `MealPlan.prune_stale_items` and inline the ShoppingListBuilder orchestration at each call site. Keep `prune_checked_off(visible_names:)` and `with_optimistic_retry` on MealPlan.

**Tech Stack:** Rails 8, Turbo Streams, Minitest

---

### Task 1: Extract `MealPlan.broadcast_refresh` class method

**Files:**
- Modify: `app/models/meal_plan.rb:26` (add class method before `prune_stale_items`)
- Modify: `app/controllers/concerns/meal_plan_actions.rb:41-43`
- Modify: `app/services/catalog_write_service.rb:71-73`
- Modify: `app/services/recipe_broadcaster.rb:66`
- Test: `test/models/meal_plan_test.rb`

**Step 1: Add the class method to MealPlan**

Add after `for_kitchen`:

```ruby
def self.broadcast_refresh(kitchen)
  Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
end
```

**Step 2: Replace MealPlanActions#broadcast_meal_plan_refresh**

Replace lines 41-43 of `meal_plan_actions.rb`:

```ruby
def broadcast_meal_plan_refresh
  MealPlan.broadcast_refresh(current_kitchen)
end
```

**Step 3: Replace CatalogWriteService#broadcast_meal_plan_refresh**

Replace lines 71-73 of `catalog_write_service.rb`:

```ruby
def broadcast_meal_plan_refresh
  MealPlan.broadcast_refresh(kitchen)
end
```

**Step 4: Replace RecipeBroadcaster inline call**

Replace line 66 of `recipe_broadcaster.rb`:

```ruby
MealPlan.broadcast_refresh(kitchen)
```

**Step 5: Run tests**

Run: `rake test`
Expected: All pass — behavior unchanged.

**Step 6: Commit**

```bash
git add app/models/meal_plan.rb app/controllers/concerns/meal_plan_actions.rb app/services/catalog_write_service.rb app/services/recipe_broadcaster.rb
git commit -m "refactor: extract MealPlan.broadcast_refresh to DRY stream tuple (#179)"
```

---

### Task 2: Remove `MealPlan.prune_stale_items`, inline at call sites

**Files:**
- Modify: `app/models/meal_plan.rb:26-31` (remove `prune_stale_items`)
- Modify: `app/controllers/concerns/meal_plan_actions.rb:29-34` (inline in `prune_if_deselect`)
- Modify: `app/services/recipe_write_service.rb:96-99` (inline in `post_write_cleanup`)
- Modify: `app/controllers/menu_controller.rb:50` (inline in `update_quick_bites`)
- Modify: `test/models/meal_plan_test.rb` (update tests that call `prune_stale_items`)

**Step 1: Inline pruning in `MealPlanActions#prune_if_deselect`**

`prune_if_deselect` is called inside `mutate_plan`'s `with_optimistic_retry` block, which already yields `plan`. Replace `prune_if_deselect` (lines 29-34):

```ruby
def prune_if_deselect(plan, action_type, action_params)
  return unless action_type == 'select'
  return if MealPlan.truthy?(action_params[:selected])

  visible = shopping_list_visible_names(plan)
  plan.prune_checked_off(visible_names: visible)
end
```

Also update `apply_plan` to pass `plan`:

```ruby
def apply_plan(action_type, **action_params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **action_params)
    prune_if_deselect(plan, action_type, action_params)
  end
end
```

Add a private helper to the concern:

```ruby
def shopping_list_visible_names(plan)
  shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
end
```

**Step 2: Inline pruning in `RecipeWriteService#post_write_cleanup`**

Replace `post_write_cleanup` (lines 96-99):

```ruby
def post_write_cleanup
  Category.cleanup_orphans(kitchen)
  prune_stale_meal_plan_items
end

def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
  visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
end
```

**Step 3: Inline pruning in `MenuController#update_quick_bites`**

Replace line 50:

```ruby
def update_quick_bites
  content = params[:content].to_s
  return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

  current_kitchen.update!(quick_bites_content: content)
  plan = MealPlan.for_kitchen(current_kitchen)
  visible = shopping_list_visible_names(plan)
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
  broadcast_meal_plan_refresh
  render json: { status: 'ok' }
end
```

`shopping_list_visible_names` is already defined in MealPlanActions (from Step 1).

**Step 4: Remove `MealPlan.prune_stale_items`**

Delete lines 26-31 from `app/models/meal_plan.rb`.

**Step 5: Update MealPlan header comment**

Replace lines 3-9:

```ruby
# Singleton-per-kitchen record that stores shared meal planning state as a JSON
# blob: selected recipes, selected quick bites, custom grocery items, and
# checked-off items. Synced across devices via Turbo page-refresh broadcasts
# with optimistic locking (lock_version). Both the menu and groceries pages
# read and write this model.
```

**Step 6: Update tests**

The three `prune_stale_items` tests in `meal_plan_test.rb` need to inline the same pattern. Replace each `MealPlan.prune_stale_items(kitchen: @kitchen)` call with:

```ruby
plan = MealPlan.for_kitchen(@kitchen)
shopping_list = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan).build
visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
```

This affects tests at lines 253, 281, and 369.

**Step 7: Run tests**

Run: `rake test`
Expected: All pass.

**Step 8: Commit**

```bash
git add app/models/meal_plan.rb app/controllers/concerns/meal_plan_actions.rb app/services/recipe_write_service.rb app/controllers/menu_controller.rb test/models/meal_plan_test.rb
git commit -m "refactor: move prune orchestration out of MealPlan (#180)"
```

---

### Task 3: Lint and close issues

**Step 1: Run lint**

Run: `rake lint`
Expected: 0 offenses.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 3: Commit any lint fixes if needed**

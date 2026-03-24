# Break MealPlan ↔ ShoppingListBuilder Circular Dependency — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Remove MealPlan's dependency on ShoppingListBuilder by injecting visible names from controllers.

**Architecture:** Change `prune_checked_off` to accept a `visible_names:` keyword instead of discovering names itself. Move `ShoppingListBuilder` instantiation to a `MealPlanActions` concern helper. Update all call sites (controllers) to build visible names and pass them in.

**Tech Stack:** Ruby (Rails model, concern, controllers), Minitest.

---

### Task 1: Update MealPlan#prune_checked_off to accept injected visible names

**Files:**
- Modify: `app/models/meal_plan.rb:66-72` (prune_checked_off)
- Modify: `app/models/meal_plan.rb:80-89` (apply_select)
- Delete: `app/models/meal_plan.rb:100-104` (visible_item_names)
- Test: `test/models/meal_plan_test.rb`

**Step 1: Rewrite prune_checked_off model tests to use injected names**

Replace the existing prune tests (lines 204-288) with versions that inject `visible_names:` directly — no recipes, no catalog entries, no ShoppingListBuilder needed.

```ruby
test 'prune_checked_off removes items not in visible names' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)
  list.apply_action('check', item: 'Salt', checked: true)

  list.prune_checked_off(visible_names: Set.new(['Flour']))

  assert_includes list.state['checked_off'], 'Flour'
  assert_not_includes list.state['checked_off'], 'Salt'
end

test 'prune_checked_off removes all when visible set is empty' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)
  list.apply_action('check', item: 'Salt', checked: true)

  list.prune_checked_off(visible_names: Set.new)

  assert_empty list.state['checked_off']
end

test 'prune_checked_off preserves custom items even when not in visible names' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'birthday candles', action: 'add')
  list.apply_action('check', item: 'birthday candles', checked: true)
  list.apply_action('check', item: 'Flour', checked: true)

  list.prune_checked_off(visible_names: Set.new)

  assert_includes list.state['checked_off'], 'birthday candles'
  assert_not_includes list.state['checked_off'], 'Flour'
end

test 'prune_checked_off is idempotent when nothing to prune' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)
  version_before = list.lock_version

  list.prune_checked_off(visible_names: Set.new(['Flour']))

  assert_equal version_before, list.lock_version
end

test 'prune_checked_off saves when items are pruned' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)
  version_before = list.lock_version

  list.prune_checked_off(visible_names: Set.new)

  assert_operator list.lock_version, :>, version_before
end

test 'prune_checked_off saves when force_save is true even if nothing pruned' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)
  version_before = list.lock_version

  list.prune_checked_off(visible_names: Set.new(['Flour']), force_save: true)

  assert_operator list.lock_version, :>, version_before
end
```

Also remove the following tests entirely — they test deselect-triggers-prune integration that will move to controller tests:
- `deselecting recipe prunes orphaned checked_off items` (line 204)
- `deselecting recipe preserves checked items still on shopping list` (line 216)
- `deselecting quick bite prunes orphaned checked_off items` (line 230)
- `selecting does not prune checked_off` (line 242)
- `prune preserves custom items in checked_off` (line 278)
- `prune_checked_off removes orphaned entries when called directly` (line 252)
- `prune_checked_off is idempotent when nothing to prune` (line 266)

And remove the helpers that are no longer needed: `setup_recipe_with_ingredients`, `setup_two_recipes_sharing_ingredient`, `ensure_catalog_entries`.

**Step 2: Run the new tests to verify they fail**

```bash
ruby -Itest test/models/meal_plan_test.rb -n '/prune_checked_off/'
```

Expected: FAIL — `prune_checked_off` doesn't accept `visible_names:` yet.

**Step 3: Update MealPlan model**

In `app/models/meal_plan.rb`:

1. Change `prune_checked_off` to accept `visible_names:` keyword and use it directly:

```ruby
def prune_checked_off(visible_names:, force_save: false)
  ensure_state_keys
  custom = Set.new(state['custom_items'])
  before_size = state['checked_off'].size
  state['checked_off'].select! { |item| visible_names.include?(item) || custom.include?(item) }
  save! if force_save || state['checked_off'].size < before_size
end
```

2. In `apply_select`, remove the prune call on deselect. Replace:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  adding = truthy?(selected)

  if adding
    toggle_array(key, slug, true)
  else
    toggle_array(key, slug, false, save: false)
    prune_checked_off(force_save: true)
  end
end
```

With:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  toggle_array(key, slug, truthy?(selected))
end
```

3. Delete the `visible_item_names` private method entirely (lines 100-104).

**Step 4: Run model tests**

```bash
ruby -Itest test/models/meal_plan_test.rb
```

Expected: All pass. The deselect test (`apply_action removes recipe from selected_recipes`) should still pass since it only checks that the slug is removed from the array.

**Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "refactor: MealPlan#prune_checked_off accepts injected visible_names (#133)"
```

---

### Task 2: Add build_visible_names helper to MealPlanActions concern

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb`

**Step 1: Add the helper method**

Add to `MealPlanActions` private section:

```ruby
def build_visible_names(meal_plan)
  shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: meal_plan).build
  names = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }
  Set.new(names)
end
```

Note: uses `current_kitchen` from the controller (available in all controllers that include this concern).

**Step 2: Update apply_and_respond for deselect pruning**

The `apply_and_respond` method handles `MenuController#select` and `GroceriesController` actions. After calling `apply_action`, if it was a deselect, prune:

```ruby
def apply_and_respond(action_type, **action_params)
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry do
    plan.apply_action(action_type, **action_params)
    prune_if_deselect(plan, action_type, action_params)
  end
  MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
  render json: { version: plan.lock_version }
end
```

Add:

```ruby
def prune_if_deselect(plan, action_type, action_params)
  return unless action_type == 'select' && !plan.send(:truthy?, action_params[:selected])

  visible = build_visible_names(plan)
  plan.prune_checked_off(visible_names: visible)
end
```

Wait — `truthy?` is private on MealPlan. We should check the param ourselves in the concern. The logic is simple: `selected` is `'true'`, `true`, `'false'`, or `false`.

```ruby
def prune_if_deselect(plan, action_type, action_params)
  return unless action_type == 'select'
  return if [true, 'true'].include?(action_params[:selected])

  plan.prune_checked_off(visible_names: build_visible_names(plan))
end
```

**Step 3: Run all tests to check nothing breaks**

```bash
rake test
```

Expected: All pass except the model tests that tested deselect-prune integration (which we already removed in Task 1).

**Step 4: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb
git commit -m "refactor: add build_visible_names and prune_if_deselect to MealPlanActions (#133)"
```

---

### Task 3: Update MenuController and RecipesController prune call sites

**Files:**
- Modify: `app/controllers/menu_controller.rb:62`
- Modify: `app/controllers/recipes_controller.rb:59,78`

**Step 1: Update MenuController#update_quick_bites**

Change line 62 from:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off }
```

To:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off(visible_names: build_visible_names(plan)) }
```

**Step 2: Update RecipesController#update**

Change line 59 from:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off }
```

To:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off(visible_names: build_visible_names(plan)) }
```

**Step 3: Update RecipesController#destroy**

Change line 78 from:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off }
```

To:

```ruby
plan.with_optimistic_retry { plan.prune_checked_off(visible_names: build_visible_names(plan)) }
```

**Step 4: Run all tests**

```bash
rake test
```

Expected: All pass.

**Step 5: Run linter**

```bash
bundle exec rubocop app/controllers/menu_controller.rb app/controllers/recipes_controller.rb app/controllers/concerns/meal_plan_actions.rb app/models/meal_plan.rb
```

Expected: No offenses.

**Step 6: Commit**

```bash
git add app/controllers/menu_controller.rb app/controllers/recipes_controller.rb
git commit -m "refactor: pass visible_names to prune_checked_off at all controller call sites (#133)"
```

---

### Task 4: Update MealPlan header comment and close issue

**Files:**
- Modify: `app/models/meal_plan.rb:1-8` (header comment)

**Step 1: Update the architectural header comment**

The current comment (lines 3-8) references ShoppingListBuilder consuming MealPlan. After this change, the model no longer references ShoppingListBuilder at all. Update:

```ruby
# Singleton-per-kitchen record that stores shared meal planning state as a JSON
# blob: selected recipes, selected quick bites, custom grocery items, and
# checked-off items. Synced across devices via MealPlanChannel (ActionCable)
# with optimistic locking (lock_version). Both the menu and groceries pages
# read and write this model. Controllers handle pruning stale checked-off
# items by injecting visible ingredient names from ShoppingListBuilder.
```

**Step 2: Run full test suite and linter**

```bash
rake
```

Expected: All tests pass, no RuboCop offenses.

**Step 3: Commit**

```bash
git add app/models/meal_plan.rb
git commit -m "docs: update MealPlan header comment to reflect removed ShoppingListBuilder dependency (#133)"
```

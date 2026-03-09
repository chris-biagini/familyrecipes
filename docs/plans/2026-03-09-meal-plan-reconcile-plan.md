# MealPlan Reconciliation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate scattered meal plan pruning into a single `MealPlan#reconcile!` method, fix broadcast ordering, and close the catalog name-change gap.

**Architecture:** Add `reconcile!` to MealPlan as the sole public pruning API. Existing prune methods become private implementation details. All call sites switch to `plan.reconcile!`. CatalogWriteService gains reconciliation after upsert/destroy.

**Tech Stack:** Rails 8, Minitest, SQLite

---

### Task 0: Add `MealPlan#reconcile!` and rewrite prune tests

**Files:**
- Modify: `app/models/meal_plan.rb:89-110` (add reconcile!, make prune methods private)
- Modify: `test/models/meal_plan_test.rb:200-431` (rewrite prune tests as reconcile! tests)

**Step 1: Add `reconcile!` to MealPlan**

In `app/models/meal_plan.rb`, add `reconcile!` as a public method just above the
`private` keyword (before line 112). Then move `prune_checked_off` and
`prune_stale_selections` below the `private` keyword, and remove the
`rubocop:disable` comment from `prune_stale_selections`.

The new method:

```ruby
def reconcile!
  ensure_state_keys
  visible = ShoppingListBuilder.new(kitchen:, meal_plan: self).visible_names
  prune_checked_off(visible_names: visible)
  prune_stale_selections
end
```

Note: `prune_stale_selections` no longer needs a `kitchen:` keyword argument
since it can use the `kitchen` association directly (from `acts_as_tenant`).
Update the method signature and body to use `kitchen` instead of the parameter.

**Step 2: Rewrite prune tests as `reconcile!` tests**

Replace the 12 direct prune tests (lines 200-431) with equivalent `reconcile!`
tests. The integration-style tests at lines 253-294 that build real recipes and
ShoppingListBuilder can be simplified — `reconcile!` does that internally now.

Key test cases to preserve (all calling `reconcile!` instead of prune methods directly):

```ruby
# --- reconcile! ---

test 'reconcile! removes checked-off items not on shopping list' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Phantom Item', checked: true)

  plan.reconcile!
  plan.reload

  assert_empty plan.state['checked_off']
end

test 'reconcile! preserves checked-off items on shopping list' do
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('check', item: 'Flour', checked: true)
  plan.apply_action('check', item: 'Phantom', checked: true)

  plan.reconcile!
  plan.reload

  assert_includes plan.state['checked_off'], 'Flour'
  assert_not_includes plan.state['checked_off'], 'Phantom'
end

test 'reconcile! preserves custom items even when not in visible names' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
  plan.apply_action('check', item: 'birthday candles', checked: true)

  plan.reconcile!
  plan.reload

  assert_includes plan.state['checked_off'], 'birthday candles'
end

test 'reconcile! preserves custom items case-insensitively' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
  plan.apply_action('check', item: 'birthday candles', checked: true)

  plan.reconcile!
  plan.reload

  assert_includes plan.state['checked_off'], 'birthday candles'
end

test 'reconcile! removes deleted recipe slugs from selections' do
  category = Category.find_or_create_by!(name: 'Test', slug: 'test', kitchen: @kitchen)
  MarkdownImporter.import("# Exists\n\n## Step (do it)\n\n- Flour, 1 cup\n\nDo it.\n", kitchen: @kitchen, category:)

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'exists', selected: true)
  plan.apply_action('select', type: 'recipe', slug: 'gone', selected: true)

  plan.reconcile!

  assert_includes plan.state['selected_recipes'], 'exists'
  assert_not_includes plan.state['selected_recipes'], 'gone'
end

test 'reconcile! removes deleted quick bite IDs from selections' do
  @kitchen.update!(quick_bites_content: "Snacks:\n- Nachos: Chips\n")

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
  plan.apply_action('select', type: 'quick_bite', slug: 'gone-bite', selected: true)

  plan.reconcile!

  assert_includes plan.state['selected_quick_bites'], 'nachos'
  assert_not_includes plan.state['selected_quick_bites'], 'gone-bite'
end

test 'reconcile! is idempotent when nothing to prune' do
  plan = MealPlan.for_kitchen(@kitchen)
  version_before = plan.lock_version

  plan.reconcile!

  assert_equal version_before, plan.reload.lock_version
end

test 'reconcile! saves when items are pruned' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Phantom', checked: true)
  version_before = plan.lock_version

  plan.reconcile!

  assert_operator plan.lock_version, :>, version_before
end
```

**Step 3: Run tests to verify**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All pass. Some tests in other files that call `prune_checked_off` or
`prune_stale_selections` directly will break — that's expected and fixed in later
tasks.

**Step 4: Commit**

```
feat: add MealPlan#reconcile! and rewrite prune tests
```

---

### Task 1: Simplify `apply_custom_items` and update custom item tests

**Files:**
- Modify: `app/models/meal_plan.rb:127-138` (simplify apply_custom_items, delete prune_checked_off_for)
- Modify: `test/models/meal_plan_test.rb` (update custom item removal tests)

**Step 1: Simplify `apply_custom_items`**

Replace the current implementation (lines 127-134) with:

```ruby
def apply_custom_items(item:, action:, **)
  toggle_array('custom_items', item, action == 'add')
end
```

Delete `prune_checked_off_for` (lines 136-138).

**Step 2: Update the custom item removal tests**

The two tests that assert checked-off cleanup on custom item removal
(lines 330-352: "removing custom item cleans up checked-off entry" and "removing
custom item cleans up case-mismatched checked-off entry") need updating.

These tests currently assert that removing a custom item immediately prunes the
matching checked-off entry. With the new design, `apply_action` purely mutates —
pruning happens via `reconcile!`. Update these tests to call `reconcile!` after
the removal:

```ruby
test 'removing custom item and reconciling cleans up checked-off entry' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Birthday Candles', action: 'add')
  list.apply_action('check', item: 'Birthday Candles', checked: true)
  list.apply_action('custom_items', item: 'Birthday Candles', action: 'remove')
  list.reconcile!

  list.reload

  assert_empty list.state['custom_items']
  assert_empty list.state['checked_off']
end

test 'removing custom item and reconciling cleans up case-mismatched checked-off entry' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'Test', action: 'add')
  list.apply_action('check', item: 'Test', checked: true)
  list.apply_action('custom_items', item: 'test', action: 'remove')
  list.reconcile!

  list.reload

  assert_empty list.state['custom_items']
  assert_empty list.state['checked_off']
end
```

**Step 3: Run meal plan tests**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All pass.

**Step 4: Commit**

```
refactor: simplify apply_custom_items, delete prune_checked_off_for
```

---

### Task 2: Update `MealPlanActions` concern and controller call sites

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb:22-39` (simplify apply_plan, delete helpers)
- Modify: `app/controllers/menu_controller.rb:45-59` (simplify update_quick_bites)

**Step 1: Simplify `MealPlanActions`**

Replace `apply_plan` (lines 22-27) with:

```ruby
def apply_plan(action_type, **action_params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **action_params)
    plan.reconcile!
  end
end
```

Delete `prune_if_deselect` (lines 29-35) and `shopping_list_visible_names`
(lines 37-39).

Update the header comment (lines 3-6) to reflect the new design:

```ruby
# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry with a common StaleObjectError handler.
# Every mutation is followed by MealPlan#reconcile! to prune stale state.
# Used by MenuController and GroceriesController.
```

**Step 2: Simplify `MenuController#update_quick_bites`**

Replace lines 49-53 with:

```ruby
mutate_plan(&:reconcile!)
```

The full method becomes:

```ruby
def update_quick_bites
  stored = params[:content].to_s.presence
  result = parse_quick_bites(stored)
  current_kitchen.update!(quick_bites_content: stored)
  mutate_plan(&:reconcile!)
  current_kitchen.broadcast_update

  body = { status: 'ok' }
  body[:warnings] = result.warnings if result.warnings.any?
  render json: body
end
```

**Step 3: Run controller tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb test/controllers/groceries_controller_test.rb`
Expected: All pass. The existing tests for deselect pruning and
`update_quick_bites` pruning exercise the new path through `reconcile!`.

**Step 4: Commit**

```
refactor: MealPlanActions uses reconcile!, delete manual prune helpers
```

---

### Task 3: Fix `RecipeWriteService` broadcast ordering and use `reconcile!`

**Files:**
- Modify: `app/services/recipe_write_service.rb:31-57, 96-108` (reorder broadcast, use reconcile!)
- Modify: `test/services/recipe_write_service_test.rb` (verify existing tests pass)

**Step 1: Reorder broadcast and use `reconcile!` in RecipeWriteService**

In `create` (lines 31-37), swap lines 34-35:

```ruby
def create(markdown:, category_name:)
  category = find_or_create_category(category_name)
  recipe = import_and_timestamp(markdown, category:)
  post_write_cleanup
  kitchen.broadcast_update
  Result.new(recipe:, updated_references: [])
end
```

Same for `update` (lines 39-48):

```ruby
def update(slug:, markdown:, category_name:)
  old_recipe = kitchen.recipes.find_by!(slug:)
  category = find_or_create_category(category_name)
  recipe = import_and_timestamp(markdown, category:)
  updated_references = rename_cross_references(old_recipe, recipe)
  handle_slug_change(old_recipe, recipe)
  post_write_cleanup
  kitchen.broadcast_update
  Result.new(recipe:, updated_references:)
end
```

Same for `destroy` (lines 50-57):

```ruby
def destroy(slug:)
  recipe = kitchen.recipes.find_by!(slug:)
  RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
  recipe.destroy!
  post_write_cleanup
  kitchen.broadcast_update
  Result.new(recipe:, updated_references: [])
end
```

Replace `prune_stale_meal_plan_items` (lines 101-108) with:

```ruby
def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry { plan.reconcile! }
end
```

Update the header comment (lines 1-11) to reflect the new ordering:

```ruby
# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), clean up
# orphan categories, and reconcile stale meal plan entries. Broadcasts a
# page-refresh morph via Kitchen#broadcast_update after all cleanup completes.
#
# - MarkdownImporter: parses markdown into AR records
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - RecipeBroadcaster: targeted delete notifications and rename redirects
# - CrossReferenceUpdater: renames cross-references on title change
# - MealPlan#reconcile!: prunes stale selections and checked-off items
```

**Step 2: Run recipe write service tests**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass. The "destroy prunes deleted recipe from meal plan selections"
and "update with rename prunes old slug from meal plan selections" tests exercise
the new path.

**Step 3: Commit**

```
fix: RecipeWriteService broadcasts after cleanup, uses reconcile!
```

---

### Task 4: Add meal plan reconciliation to `CatalogWriteService`

**Files:**
- Modify: `app/services/catalog_write_service.rb:38-56, 67` (add reconcile_meal_plan calls)
- Modify: `test/services/catalog_write_service_test.rb` (add reconciliation tests)

**Step 1: Write the failing tests**

Add to `test/services/catalog_write_service_test.rb`, before the `private` line:

```ruby
# --- meal plan reconciliation ---

test 'upsert reconciles stale checked-off items when canonical name changes' do
  create_catalog_entry('flour', aisle: 'Baking')
  @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Bread

    ## Mix (combine)

    - flour, 2 cups

    Stir together.
  MD

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'bread', selected: true)
  plan.apply_action('check', item: 'flour', checked: true)

  # Rename the canonical name by adding an alias that captures 'flour'
  # and destroying the old entry, then creating a new one
  IngredientCatalog.where(kitchen: @kitchen, ingredient_name: 'flour').delete_all
  upsert_entry('All-Purpose Flour', nutrients: {}, aisle: 'Baking', aliases: ['flour'])

  plan.reload

  assert_not_includes plan.state['checked_off'], 'flour',
                      'stale checked-off item should be pruned after catalog name change'
end

test 'destroy reconciles meal plan state' do
  create_catalog_entry('flour', aisle: 'Baking')

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'flour', checked: true)

  CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')

  plan.reload

  assert_empty plan.state['checked_off'],
               'checked-off items should be pruned after catalog entry destroyed'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/catalog_write_service_test.rb -n '/reconcile/'`
Expected: FAIL — CatalogWriteService doesn't call reconcile yet.

**Step 3: Add `reconcile_meal_plan` to CatalogWriteService**

In `app/services/catalog_write_service.rb`, add reconciliation calls to `upsert`
and `destroy`. Insert `reconcile_meal_plan` before `kitchen.broadcast_update` in
both methods.

In `upsert` (after line 44, before line 45):

```ruby
reconcile_meal_plan
```

In `destroy` (after line 53, before line 54):

```ruby
reconcile_meal_plan
```

Add the private method (after the `attr_reader` line):

```ruby
def reconcile_meal_plan
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry { plan.reconcile! }
end
```

Update the header comment to include MealPlan#reconcile! as a collaborator:

```ruby
# Orchestrates IngredientCatalog create/update/destroy with post-write side
# effects: syncing new aisles to the kitchen's aisle_order, recalculating
# nutrition for affected recipes, reconciling stale meal plan state, and
# broadcasting a page-refresh morph. Mirrors RecipeWriteService — controllers
# call class methods, never inline post-save logic. Also provides bulk_import
# for ImportService: batch save with single-pass aisle sync and nutrition
# recalc, no per-entry broadcast or reconciliation.
#
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution for affected-recipe queries
# - RecipeNutritionJob: recalculates recipe nutrition_data
# - AisleWriteService: aisle sync after catalog saves
# - MealPlan#reconcile!: prunes stale selections and checked-off items
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass, including the two new reconciliation tests.

**Step 5: Commit**

```
feat: CatalogWriteService reconciles meal plan after upsert/destroy
```

---

### Task 5: Run full test suite and lint

**Files:** None (verification only)

**Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass. No tests should be calling the now-private
`prune_checked_off` or `prune_stale_selections` methods directly.

**Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No new offenses. The ABC metric on `prune_stale_selections` may have
lost its `rubocop:disable` comment — verify the private method is under threshold
now (it was borderline before).

**Step 3: Fix any issues found**

Address any test failures or lint violations.

**Step 4: Update `html_safe_allowlist.yml` if needed**

If any line numbers shifted in files tracked by the allowlist, update accordingly.

**Step 5: Commit (if fixes were needed)**

```
chore: fix lint/test issues from reconcile refactoring
```

---

### Task 6: Update architectural comments and CLAUDE.md

**Files:**
- Modify: `app/models/meal_plan.rb` (update header comment)
- Modify: `CLAUDE.md` (update Architecture section)

**Step 1: Update MealPlan header comment**

Update the header comment (lines 1-6) to mention `reconcile!`:

```ruby
# Singleton-per-kitchen record that stores shared meal planning state as a JSON
# blob: selected recipes, selected quick bites, custom grocery items, and
# checked-off items. Both the menu and groceries pages read and write this
# model. Cross-device sync is handled by Kitchen#broadcast_update.
# MealPlan#reconcile! is the sole entry point for pruning stale state —
# called after any mutation that changes what appears on the shopping list.
```

**Step 2: Update CLAUDE.md Architecture section**

In the **Write path** paragraph, add a sentence about reconciliation. After the
line about `MealPlanActions`:

```
`MealPlan#reconcile!` is the single pruning entry point — removes stale checked-off items and stale selections based on current shopping list state. Called after recipe CRUD, quick bites edits, catalog changes, and deselects.
```

**Step 3: Commit**

```
docs: update architectural comments for MealPlan#reconcile!
```

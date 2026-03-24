# RecipeBroadcaster Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Seal the RecipeBroadcaster abstraction so no code outside it calls `Turbo::StreamsChannel` for recipe-related content, and DRY up the MealPlanActions concern.

**Architecture:** Five focused refactors in dependency order. Changes 1-2 are foundation (Kitchen model, MealPlan model). Changes 3-5 build on them (MealPlanActions concern, RecipeBroadcaster class methods, destroy path consolidation). All changes are behavior-preserving — existing tests must continue to pass, with new unit tests added for new public methods.

**Tech Stack:** Rails 8, Turbo Streams, ActionCable, Minitest

**Design doc:** `docs/plans/2026-03-03-broadcaster-consolidation-design.md`

---

### Task 0: Verify Baseline

**Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass, 0 failures, 0 errors.

**Step 2: Run linter**

Run: `bundle exec rubocop`
Expected: 0 offenses.

---

### Task 1: Kitchen#quick_bites_by_subsection

Extract the duplicated Quick Bites grouping logic into the Kitchen model.

**Files:**
- Modify: `app/models/kitchen.rb:30-34` (add method after `parsed_quick_bites`)
- Test: `test/models/kitchen_test.rb`

**Step 1: Write the failing test**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'quick_bites_by_subsection groups parsed quick bites by stripped category' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-qb',
                            quick_bites_content: "## Quick Bites: Snacks\n- Chips\n- Pretzels\n\n## Quick Bites: Drinks\n- Juice\n")

  result = kitchen.quick_bites_by_subsection

  assert_kind_of Hash, result
  assert_includes result.keys, 'Snacks'
  assert_includes result.keys, 'Drinks'
  assert_equal 2, result['Snacks'].size
  assert_equal 1, result['Drinks'].size
end

test 'quick_bites_by_subsection returns empty hash when no content' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-qb-empty')

  assert_equal({}, kitchen.quick_bites_by_subsection)
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/kitchen_test.rb -n /quick_bites_by_subsection/`
Expected: FAIL — `NoMethodError: undefined method 'quick_bites_by_subsection'`

**Step 3: Implement Kitchen#quick_bites_by_subsection**

Add to `app/models/kitchen.rb` after `parsed_quick_bites` (after line 34):

```ruby
def quick_bites_by_subsection
  parsed_quick_bites.group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/kitchen_test.rb -n /quick_bites_by_subsection/`
Expected: 2 tests, 2 passes.

**Step 5: Update callers**

In `app/controllers/menu_controller.rb`:
- Line 16: Change `load_quick_bites_by_subsection` to `current_kitchen.quick_bites_by_subsection`
- Lines 70-73: Delete the `load_quick_bites_by_subsection` private method
- Line 94: Change `load_quick_bites_by_subsection` to `current_kitchen.quick_bites_by_subsection`

In `app/services/recipe_broadcaster.rb`:
- Line 83: Change `parse_quick_bites` to `kitchen.quick_bites_by_subsection`
- Lines 156-159: Delete the `parse_quick_bites` private method

**Step 6: Run full test suite for affected files**

Run: `ruby -Itest test/models/kitchen_test.rb && ruby -Itest test/controllers/menu_controller_test.rb && ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: All pass.

**Step 7: Update header comment on Kitchen**

The Kitchen model header comment should mention `quick_bites_by_subsection` as a derived view alongside `parsed_quick_bites`. Update if needed.

**Step 8: Commit**

```bash
git add app/models/kitchen.rb app/controllers/menu_controller.rb app/services/recipe_broadcaster.rb test/models/kitchen_test.rb
git commit -m "refactor: extract Kitchen#quick_bites_by_subsection"
```

---

### Task 2: Promote MealPlan.truthy? to Public Class Method

**Files:**
- Modify: `app/models/meal_plan.rb:131-134` (promote `truthy?`)
- Modify: `app/controllers/concerns/meal_plan_actions.rb:27` (use `MealPlan.truthy?`)
- Test: `test/models/meal_plan_test.rb`

**Step 1: Write the failing test**

Add to `test/models/meal_plan_test.rb`:

```ruby
test 'truthy? class method recognizes true and string true' do
  assert MealPlan.truthy?(true)
  assert MealPlan.truthy?('true')
  refute MealPlan.truthy?(false)
  refute MealPlan.truthy?('false')
  refute MealPlan.truthy?(nil)
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/meal_plan_test.rb -n test_truthy\\?_class_method`
Expected: FAIL — `NoMethodError: undefined method 'truthy?' for MealPlan:Class`

**Step 3: Promote truthy? to public class method**

In `app/models/meal_plan.rb`, move `truthy?` from private instance method (lines 132-134) to a public class method after `prune_stale_items` (after line 31):

```ruby
def self.truthy?(value)
  [true, 'true'].include?(value)
end
```

Then update the private instance method to delegate:

```ruby
def truthy?(value)
  self.class.truthy?(value)
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/meal_plan_test.rb -n test_truthy\\?_class_method`
Expected: PASS.

**Step 5: Update MealPlanActions#prune_if_deselect**

In `app/controllers/concerns/meal_plan_actions.rb`, line 27, change:

```ruby
return if [true, 'true'].include?(action_params[:selected])
```

to:

```ruby
return if MealPlan.truthy?(action_params[:selected])
```

**Step 6: Run affected tests**

Run: `ruby -Itest test/models/meal_plan_test.rb && ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass.

**Step 7: Commit**

```bash
git add app/models/meal_plan.rb app/controllers/concerns/meal_plan_actions.rb test/models/meal_plan_test.rb
git commit -m "refactor: promote MealPlan.truthy? to public class method"
```

---

### Task 3: Extract MealPlanActions#mutate_and_respond

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb` (add `mutate_and_respond`, refactor `apply_and_respond`)
- Modify: `app/controllers/menu_controller.rb:26-38` (refactor `select_all`, `clear`)

**Step 1: Run existing tests to capture baseline**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass. Note the test count.

**Step 2: Add mutate_and_respond to MealPlanActions**

In `app/controllers/concerns/meal_plan_actions.rb`, add after line 13 (after `private`):

```ruby
def mutate_and_respond
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry { yield plan }
  MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
  render json: { version: plan.lock_version }
end
```

**Step 3: Refactor apply_and_respond to use mutate_and_respond**

Replace `apply_and_respond` (lines 15-23) with:

```ruby
def apply_and_respond(action_type, **action_params)
  mutate_and_respond do |plan|
    plan.apply_action(action_type, **action_params)
    prune_if_deselect(action_type, action_params)
  end
end
```

**Step 4: Verify existing tests still pass**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: Same test count, all pass. This confirms `apply_and_respond` refactor is safe.

**Step 5: Refactor MenuController#select_all**

Replace `select_all` (lines 26-31) with:

```ruby
def select_all
  mutate_and_respond { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
end
```

**Step 6: Refactor MenuController#clear**

Replace `clear` (lines 33-38) with:

```ruby
def clear
  mutate_and_respond { |plan| plan.clear_selections! }
end
```

**Step 7: Run full affected tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb && ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass. Both controllers include MealPlanActions.

**Step 8: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb app/controllers/menu_controller.rb
git commit -m "refactor: extract mutate_and_respond in MealPlanActions"
```

---

### Task 4: RecipeBroadcaster.broadcast_recipe_selector Class Method

**Files:**
- Modify: `app/services/recipe_broadcaster.rb` (add class method, refactor private method)
- Modify: `app/controllers/menu_controller.rb` (delegate to broadcaster)
- Test: `test/services/recipe_broadcaster_test.rb`

**Step 1: Write the failing test**

Add to `test/services/recipe_broadcaster_test.rb`:

```ruby
test 'broadcast_recipe_selector broadcasts to specified stream' do
  calls = []
  capture = ->(*args, **kw) { calls << { args:, kw: } }

  Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
    RecipeBroadcaster.broadcast_recipe_selector(kitchen: @kitchen, stream: 'menu_content')
  end

  selector_call = calls.find { |c| c[:kw][:target] == 'recipe-selector' }
  assert selector_call, 'Expected a broadcast targeting recipe-selector'
  assert_equal @kitchen, selector_call[:args][0]
  assert_equal 'menu_content', selector_call[:args][1]
end

test 'broadcast_recipe_selector defaults to recipes stream' do
  calls = []
  capture = ->(*args, **kw) { calls << { args:, kw: } }

  Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
    RecipeBroadcaster.broadcast_recipe_selector(kitchen: @kitchen)
  end

  selector_call = calls.find { |c| c[:kw][:target] == 'recipe-selector' }
  assert selector_call, 'Expected a broadcast targeting recipe-selector'
  assert_equal 'recipes', selector_call[:args][1]
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb -n /broadcast_recipe_selector/`
Expected: FAIL — `NoMethodError: undefined method 'broadcast_recipe_selector' for RecipeBroadcaster:Class`

**Step 3: Implement RecipeBroadcaster.broadcast_recipe_selector**

Add class method to `app/services/recipe_broadcaster.rb` after line 20 (after `self.broadcast`):

```ruby
def self.broadcast_recipe_selector(kitchen:, stream: 'recipes')
  new(kitchen).broadcast_recipe_selector(stream:)
end
```

Refactor the existing private `broadcast_recipe_selector` (lines 82-90) to accept a `stream:` keyword with default `'recipes'`, and accept optional `categories:`:

```ruby
def broadcast_recipe_selector(categories: nil, stream: 'recipes')
  categories ||= kitchen.categories.ordered.includes(:recipes)
  Turbo::StreamsChannel.broadcast_replace_to(
    kitchen, stream,
    target: 'recipe-selector',
    partial: 'menu/recipe_selector',
    locals: { categories:, quick_bites_by_subsection: kitchen.quick_bites_by_subsection }
  )
end
```

Update the call in `broadcast` (line 56) to pass the pre-loaded categories:

```ruby
broadcast_recipe_selector(categories:)
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb -n /broadcast_recipe_selector/`
Expected: 2 tests, 2 passes.

**Step 5: Update MenuController to delegate**

In `app/controllers/menu_controller.rb`, replace line 63 (`broadcast_recipe_selector_update`) with:

```ruby
RecipeBroadcaster.broadcast_recipe_selector(kitchen: current_kitchen, stream: 'menu_content')
```

Delete the `broadcast_recipe_selector_update` private method (lines 87-97).

**Step 6: Run affected tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb && ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: All pass. The existing `update_quick_bites broadcasts Turbo Stream to menu_content` test (line 252 of menu controller test) must still pass — it asserts `assert_turbo_stream_broadcasts [@kitchen, 'menu_content']`.

**Step 7: Commit**

```bash
git add app/services/recipe_broadcaster.rb app/controllers/menu_controller.rb test/services/recipe_broadcaster_test.rb
git commit -m "refactor: add RecipeBroadcaster.broadcast_recipe_selector class method"
```

---

### Task 5: RecipeBroadcaster.broadcast_destroy

Collapse the three broadcast calls in the destroy path into a single RecipeBroadcaster method.

**Files:**
- Modify: `app/services/recipe_broadcaster.rb` (add `broadcast_destroy`, make `notify_recipe_deleted` private-accessible)
- Modify: `app/services/recipe_write_service.rb:44-53` (collapse destroy method)
- Test: `test/services/recipe_broadcaster_test.rb`

**Step 1: Write the failing test**

Add to `test/services/recipe_broadcaster_test.rb`:

```ruby
test 'broadcast_destroy notifies recipe page, updates parents, and fires CRUD broadcast' do
  xref_recipe = @kitchen.recipes.find_by!(slug: 'white-pizza')
  target_recipe = @kitchen.recipes.find_by!(slug: 'pizza-dough')
  parent_ids = target_recipe.referencing_recipes.pluck(:id)

  calls = []
  capture = ->(*args, **kw) { calls << { args:, kw: } }
  append_calls = []
  append_capture = ->(*args, **kw) { append_calls << { args:, kw: } }

  target_recipe.destroy!

  Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
    Turbo::StreamsChannel.stub :broadcast_append_to, append_capture do
      RecipeBroadcaster.broadcast_destroy(
        kitchen: @kitchen, recipe: target_recipe,
        recipe_title: 'Pizza Dough', parent_ids: parent_ids
      )
    end
  end

  # Notified the deleted recipe's page
  deleted_call = calls.find { |c| c[:kw][:partial] == 'recipes/deleted' }
  assert deleted_call, 'Expected a broadcast with recipes/deleted partial'

  # Updated referencing recipe pages
  parent_call = calls.find { |c| c[:kw][:partial] == 'recipes/recipe_content' && c[:args][0].is_a?(Recipe) }
  assert parent_call, 'Expected a broadcast updating a parent recipe page'

  # Fired the full CRUD broadcast (listings, selector, etc.)
  listings_call = calls.find { |c| c[:kw][:target] == 'recipe-listings' }
  assert listings_call, 'Expected a broadcast updating recipe-listings'

  # Fired toast
  toast_call = append_calls.find { |c| c[:kw][:partial] == 'shared/toast' }
  assert toast_call, 'Expected a toast notification'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb -n /broadcast_destroy/`
Expected: FAIL — `NoMethodError: undefined method 'broadcast_destroy' for RecipeBroadcaster:Class`

**Step 3: Implement RecipeBroadcaster.broadcast_destroy**

Add class method to `app/services/recipe_broadcaster.rb` after `broadcast_recipe_selector`:

```ruby
def self.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
  notify_recipe_deleted(recipe, recipe_title:)
  broadcaster = new(kitchen)
  broadcaster.send(:update_referencing_recipes, parent_ids)
  broadcaster.broadcast(action: :deleted, recipe_title:)
end
```

Add private instance method `update_referencing_recipes`:

```ruby
def update_referencing_recipes(parent_ids)
  return if parent_ids.empty?

  kitchen.recipes.where(id: parent_ids).includes(SHOW_INCLUDES).find_each do |parent|
    replace_recipe_content(parent)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb -n /broadcast_destroy/`
Expected: PASS.

**Step 5: Collapse RecipeWriteService#destroy**

Replace `destroy` method in `app/services/recipe_write_service.rb` (lines 44-53) with:

```ruby
def destroy(slug:)
  recipe = kitchen.recipes.find_by!(slug:)
  parent_ids = recipe.referencing_recipes.pluck(:id)
  recipe.destroy!
  RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title: recipe.title, parent_ids:)
  post_write_cleanup
  Result.new(recipe:, updated_references: [])
end
```

Delete `broadcast_to_referencing_recipes` private method (lines 83-94).

**Step 6: Run affected tests**

Run: `ruby -Itest test/services/recipe_write_service_test.rb && ruby -Itest test/services/recipe_broadcaster_test.rb && ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All pass.

**Step 7: Update header comments**

Update `RecipeBroadcaster` header comment (lines 3-9) to mention `broadcast_destroy` and `broadcast_recipe_selector` as public class-method entry points.

Update `RecipeWriteService` header comment (lines 3-7) — it no longer does direct Turbo broadcasting; all broadcasting is via `RecipeBroadcaster`.

**Step 8: Commit**

```bash
git add app/services/recipe_broadcaster.rb app/services/recipe_write_service.rb test/services/recipe_broadcaster_test.rb
git commit -m "refactor: consolidate destroy broadcasting into RecipeBroadcaster"
```

---

### Task 6: Final Verification and Cleanup

**Step 1: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 2: Run linter**

Run: `bundle exec rubocop`
Expected: 0 offenses. Check that no new RuboCop issues were introduced.

**Step 3: Check html_safe allowlist**

Run: `rake lint:html_safe`
Expected: No new violations. Line numbers in `config/html_safe_allowlist.yml` may need updating if edits shifted lines in broadcaster/controller files.

**Step 4: Verify no stray Turbo::StreamsChannel calls outside RecipeBroadcaster**

Run: `grep -rn 'Turbo::StreamsChannel' app/ --include='*.rb' | grep -v recipe_broadcaster.rb`
Expected: Only hits in files that own non-recipe broadcasting (e.g., if there are any non-recipe Turbo broadcasts elsewhere). No hits in `recipe_write_service.rb` or `menu_controller.rb`.

**Step 5: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: broadcaster consolidation cleanup"
```

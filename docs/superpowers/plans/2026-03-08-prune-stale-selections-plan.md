# Prune Stale MealPlan Selections Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Prune stale recipe slugs and Quick Bite IDs from MealPlan selections when recipes are mutated or Quick Bites are edited, preventing auto-selection on slug/ID reuse.

**Architecture:** Add `prune_stale_selections(kitchen:)` to `MealPlan`, call it from the two existing post-write cleanup paths (`RecipeWriteService#prune_stale_meal_plan_items` and `MenuController#update_quick_bites`). Keep `ShoppingListBuilder` read-side filtering as safety net.

**Tech Stack:** Rails 8, Minitest, SQLite

---

### Task 1: Add `prune_stale_selections` to MealPlan with tests

**Files:**
- Modify: `app/models/meal_plan.rb:89-95` (add new method after `prune_checked_off`)
- Test: `test/models/meal_plan_test.rb`

**Step 1: Write failing tests**

Add these tests to `test/models/meal_plan_test.rb`:

```ruby
test 'prune_stale_selections removes deleted recipe slugs' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'exists', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'gone', selected: true)

  category = Category.find_or_create_by!(name: 'Test', slug: 'test', kitchen: @kitchen)
  MarkdownImporter.import("# Exists\n\n## Step (do it)\n\n- Flour, 1 cup\n\nDo it.\n", kitchen: @kitchen, category:)

  list.prune_stale_selections(kitchen: @kitchen)

  assert_includes list.state['selected_recipes'], 'exists'
  assert_not_includes list.state['selected_recipes'], 'gone'
end

test 'prune_stale_selections removes deleted quick bite IDs' do
  @kitchen.update!(quick_bites_content: "## Quick Bites: Snacks\n\n- Nachos\n  - Chips, 1 bag\n")
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
  list.apply_action('select', type: 'quick_bite', slug: 'gone-bite', selected: true)

  list.prune_stale_selections(kitchen: @kitchen)

  assert_includes list.state['selected_quick_bites'], 'nachos'
  assert_not_includes list.state['selected_quick_bites'], 'gone-bite'
end

test 'prune_stale_selections is idempotent when all selections valid' do
  category = Category.find_or_create_by!(name: 'Test', slug: 'test', kitchen: @kitchen)
  MarkdownImporter.import("# Exists\n\n## Step (do it)\n\n- Flour, 1 cup\n\nDo it.\n", kitchen: @kitchen, category:)

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'exists', selected: true)
  version_before = list.lock_version

  list.prune_stale_selections(kitchen: @kitchen)

  assert_equal version_before, list.lock_version
end

test 'prune_stale_selections saves when items pruned' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'gone', selected: true)
  version_before = list.lock_version

  list.prune_stale_selections(kitchen: @kitchen)

  assert_operator list.lock_version, :>, version_before
  assert_empty list.state['selected_recipes']
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /prune_stale_selections/`
Expected: FAIL — `prune_stale_selections` is not defined.

**Step 3: Implement `prune_stale_selections`**

Add to `app/models/meal_plan.rb` after `prune_checked_off` (line 95), before `private`:

```ruby
def prune_stale_selections(kitchen:)
  ensure_state_keys
  valid_slugs = kitchen.recipes.pluck(:slug).to_set
  valid_qb_ids = kitchen.parsed_quick_bites.map(&:id).to_set

  recipes_before = state['selected_recipes'].size
  qb_before = state['selected_quick_bites'].size

  state['selected_recipes'].select! { |s| valid_slugs.include?(s) }
  state['selected_quick_bites'].select! { |s| valid_qb_ids.include?(s) }

  save! if state['selected_recipes'].size < recipes_before ||
           state['selected_quick_bites'].size < qb_before
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /prune_stale_selections/`
Expected: 4 tests, all PASS.

**Step 5: Run full MealPlan test suite**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: add MealPlan#prune_stale_selections (#196)"
```

---

### Task 2: Wire `prune_stale_selections` into RecipeWriteService

**Files:**
- Modify: `app/services/recipe_write_service.rb:101-105`
- Test: `test/services/recipe_write_service_test.rb`

**Step 1: Write failing tests**

Add to `test/services/recipe_write_service_test.rb`:

```ruby
test 'destroy prunes deleted recipe from meal plan selections' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

  plan.reload
  assert_not_includes plan.state['selected_recipes'], 'focaccia'
end

test 'update with rename prunes old slug from meal plan selections' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  renamed = <<~MD
    # Rosemary Focaccia

    ## Make (do it)

    - Flour, 4 cups

    Mix.
  MD

  RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')

  plan.reload
  assert_not_includes plan.state['selected_recipes'], 'focaccia'
end

test 'slug reuse after delete does not auto-select' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

  new_markdown = <<~MD
    # Focaccia

    A different focaccia.

    ## Make (do it)

    - Flour, 2 cups

    Mix.
  MD
  RecipeWriteService.create(markdown: new_markdown, kitchen: @kitchen, category_name: 'Bread')

  plan.reload
  assert_not_includes plan.state['selected_recipes'], 'focaccia'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n /prune.*meal_plan\|slug_reuse/`
Expected: FAIL — stale slug still in `selected_recipes`.

**Step 3: Update `prune_stale_meal_plan_items`**

In `app/services/recipe_write_service.rb`, replace `prune_stale_meal_plan_items`:

```ruby
def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry do
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.prune_checked_off(visible_names: visible)
    plan.prune_stale_selections(kitchen:)
  end
end
```

Note: both prune methods check `size` before saving, so wrapping them in a single optimistic retry block is correct — if a concurrent update causes a `StaleObjectError`, both prune operations retry together.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "fix: prune stale recipe selections on write (#196)"
```

---

### Task 3: Wire `prune_stale_selections` into MenuController for Quick Bites

**Files:**
- Modify: `app/controllers/menu_controller.rb:45-56`
- Test: `test/controllers/menu_controller_test.rb`

**Step 1: Write failing test**

Add to `test/controllers/menu_controller_test.rb`:

```ruby
test 'update_quick_bites prunes removed quick bite from selections' do
  @kitchen.update!(quick_bites_content: "## Quick Bites: Snacks\n\n- Nachos\n  - Chips, 1 bag\n\n- Pretzels\n  - Pretzels, 1 bag\n")
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
  plan.apply_action('select', type: 'quick_bite', slug: 'pretzels', selected: true)

  patch menu_update_quick_bites_path, params: { content: "## Quick Bites: Snacks\n\n- Nachos\n  - Chips, 1 bag\n" }

  plan.reload
  assert_includes plan.state['selected_quick_bites'], 'nachos'
  assert_not_includes plan.state['selected_quick_bites'], 'pretzels'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /prunes_removed_quick_bite/`
Expected: FAIL — `pretzels` still in selections.

**Step 3: Add `prune_stale_selections` call to `update_quick_bites`**

In `app/controllers/menu_controller.rb`, update the `update_quick_bites` method:

```ruby
def update_quick_bites
  stored = params[:content].to_s.presence
  result = parse_quick_bites(stored)
  current_kitchen.update!(quick_bites_content: stored)
  plan = MealPlan.for_kitchen(current_kitchen)
  plan.with_optimistic_retry do
    plan.prune_checked_off(visible_names: shopping_list_visible_names(plan))
    plan.prune_stale_selections(kitchen: current_kitchen)
  end
  current_kitchen.broadcast_update

  body = { status: 'ok' }
  body[:warnings] = result.warnings if result.warnings.any?
  render json: body
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /prunes_removed_quick_bite/`
Expected: PASS.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 6: Lint**

Run: `bundle exec rubocop app/models/meal_plan.rb app/services/recipe_write_service.rb app/controllers/menu_controller.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add app/controllers/menu_controller.rb test/controllers/menu_controller_test.rb
git commit -m "fix: prune stale Quick Bite selections on edit (#196)"
```

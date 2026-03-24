# Orphaned Checked Items Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Prune orphaned `checked_off` entries when recipes/quick bites are deselected, fixing issue #112.

**Architecture:** Add a `prune_checked_off` method to `MealPlan` that computes the current shopping list and removes any `checked_off` items not present. Call it on deselect and clear-selections. Two existing tests expect checked items to survive `clear_selections!` — update them.

**Tech Stack:** Ruby/Rails, Minitest

---

### Task 1: Add failing tests for prune behavior on deselect

**Files:**
- Modify: `test/models/meal_plan_test.rb`

**Step 1: Write the failing tests**

Add these tests at the end of `MealPlanTest`, before the closing `end`:

```ruby
test 'deselecting recipe prunes orphaned checked_off items' do
  setup_recipe_with_ingredients

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('check', item: 'Flour', checked: true)
  list.apply_action('check', item: 'Salt', checked: true)

  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

  assert_empty list.state['checked_off']
end

test 'deselecting recipe preserves checked items still on shopping list' do
  setup_two_recipes_sharing_ingredient

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'bagels', selected: true)
  list.apply_action('check', item: 'Flour', checked: true)
  list.apply_action('check', item: 'Salt', checked: true)

  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

  assert_includes list.state['checked_off'], 'Flour'
  assert_not_includes list.state['checked_off'], 'Salt'
end

test 'deselecting quick bite prunes orphaned checked_off items' do
  @kitchen.update!(quick_bites_content: "## Drinks\n  - Wine: Wine")
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Wine') do |p|
    p.basis_grams = 0
    p.aisle = 'Beverages'
  end

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'quick_bite', slug: 'wine', selected: true)
  list.apply_action('check', item: 'Wine', checked: true)

  list.apply_action('select', type: 'quick_bite', slug: 'wine', selected: false)

  assert_empty list.state['checked_off']
end

test 'selecting does not prune checked_off' do
  setup_recipe_with_ingredients

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('check', item: 'Flour', checked: true)

  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  assert_includes list.state['checked_off'], 'Flour'
end

test 'prune preserves custom items in checked_off' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'birthday candles', action: 'add')
  list.apply_action('check', item: 'birthday candles', checked: true)

  list.apply_action('select', type: 'recipe', slug: 'nonexistent', selected: false)

  assert_includes list.state['checked_off'], 'birthday candles'
end
```

Also add these private helper methods at the bottom of the test class:

```ruby
def setup_recipe_with_ingredients
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix well.
  MD
  ensure_catalog_entries('Flour' => 'Baking', 'Salt' => 'Spices')
end

def setup_two_recipes_sharing_ingredient
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix well.
  MD
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Bagels

    Category: Bread

    ## Mix (combine)

    - Flour, 4 cups
    - Yeast, 1 tsp

    Mix well.
  MD
  ensure_catalog_entries('Flour' => 'Baking', 'Salt' => 'Spices', 'Yeast' => 'Baking')
end

def ensure_catalog_entries(name_aisle_pairs)
  name_aisle_pairs.each do |name, aisle|
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: name) do |p|
      p.basis_grams = 0
      p.aisle = aisle
    end
  end
end
```

**Step 2: Run the tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/prune|orphan/'`
Expected: All five new tests FAIL (MealPlan does not prune yet).

**Step 3: Commit the failing tests**

```bash
git add test/models/meal_plan_test.rb
git commit -m "test: add failing tests for orphaned checked_off pruning (#112)"
```

---

### Task 2: Implement prune_checked_off in MealPlan

**Files:**
- Modify: `app/models/meal_plan.rb`

**Step 1: Add prune_checked_off private method**

Add this private method to `MealPlan`, after `apply_custom_items`:

```ruby
def prune_checked_off
  visible = visible_item_names
  state['checked_off'].select! { |item| visible.include?(item) }
end

def visible_item_names
  shopping_list = ShoppingListBuilder.new(kitchen: kitchen, meal_plan: self).build
  names = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }
  Set.new(names)
end
```

**Step 2: Call prune on deselect in apply_select**

Change `apply_select` from:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  toggle_array(key, slug, truthy?(selected))
end
```

To:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  adding = truthy?(selected)
  toggle_array(key, slug, adding)
  prune_checked_off unless adding
end
```

Note: `toggle_array` already calls `save!` when it changes something, and `prune_checked_off` just mutates the in-memory array. The `save!` in `toggle_array` will persist both the selection removal and the prune in one write. However, if `toggle_array` finds nothing to change (idempotent no-op), it won't save — and in that case prune still runs but there's nothing new to prune either, so it's safe.

Wait — there's a subtlety. `toggle_array` calls `save!` *before* `prune_checked_off` runs, so the prune won't be persisted by that save. We need to adjust the flow so prune happens before the save, or add a second save.

The cleanest approach: have `apply_select` manage its own save instead of relying on `toggle_array`'s save. Refactor to:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  adding = truthy?(selected)
  changed = toggle_array_in_memory(key, slug, adding)
  prune_checked_off unless adding
  save! if changed || state_changed?
end
```

Actually, that's over-engineered. Simpler: call `prune_checked_off` which does a `save!` if anything was pruned:

```ruby
def apply_select(type:, slug:, selected:, **)
  key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
  adding = truthy?(selected)
  toggle_array(key, slug, adding)
  return if adding

  prune_checked_off
end
```

And make `prune_checked_off` save only when it actually removes items:

```ruby
def prune_checked_off
  visible = visible_item_names
  before_size = state['checked_off'].size
  state['checked_off'].select! { |item| visible.include?(item) }
  save! if state['checked_off'].size < before_size
end
```

This way: `toggle_array` saves the deselection, then `prune_checked_off` saves again only if items were actually pruned. Two saves in the worst case, but both are needed and correct.

**Step 3: Run the new tests**

Run: `ruby -Itest test/models/meal_plan_test.rb -n '/prune|orphan/'`
Expected: All five tests PASS.

**Step 4: Run full model test suite**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add app/models/meal_plan.rb
git commit -m "fix: prune orphaned checked_off items on deselect (#112)"
```

---

### Task 3: Update clear_selections! to also clear checked_off

**Files:**
- Modify: `app/models/meal_plan.rb`
- Modify: `test/models/meal_plan_test.rb`

**Step 1: Update existing test expectation**

The test `'clear_selections resets selections but preserves custom items and checked off'` (line ~139) needs to expect checked_off to be cleared. Change the assertion:

From:
```ruby
assert_includes list.state['checked_off'], 'milk'
```

To:
```ruby
assert_empty list.state['checked_off']
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/meal_plan_test.rb -n test_clear_selections_resets_selections_but_preserves_custom_items_and_checked_off`
Expected: FAIL — checked_off still contains 'milk'.

**Step 3: Update clear_selections! implementation**

Change `clear_selections!` from:

```ruby
def clear_selections!
  ensure_state_keys
  state['selected_recipes'] = []
  state['selected_quick_bites'] = []
  save!
end
```

To:

```ruby
def clear_selections!
  ensure_state_keys
  state['selected_recipes'] = []
  state['selected_quick_bites'] = []
  state['checked_off'] = []
  save!
end
```

**Step 4: Run updated test**

Run: `ruby -Itest test/models/meal_plan_test.rb -n test_clear_selections_resets_selections_but_preserves_custom_items_and_checked_off`
Expected: PASS.

**Step 5: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "fix: clear checked_off when clearing all selections (#112)"
```

---

### Task 4: Update controller test for clear endpoint

**Files:**
- Modify: `test/controllers/menu_controller_test.rb`

**Step 1: Update clear test expectation**

The test `'clear resets selections only'` (line ~165) asserts `checked_off` is preserved. Update it to match new behavior.

Change:
```ruby
assert_includes plan.state['checked_off'], 'flour'
```

To:
```ruby
assert_empty plan.state['checked_off']
```

**Step 2: Run the test**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n test_clear_resets_selections_only`
Expected: PASS (the model change from Task 3 makes this work).

**Step 3: Commit**

```bash
git add test/controllers/menu_controller_test.rb
git commit -m "test: update clear controller test for checked_off clearing (#112)"
```

---

### Task 5: Run full test suite and lint

**Step 1: Run lint**

Run: `rake lint`
Expected: No offenses.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 3: If lint or tests fail, fix issues**

Address any failures before proceeding.

**Step 4: Final commit if any lint fixes were needed**

```bash
git add -A
git commit -m "fix: lint cleanup for orphaned checked items fix (#112)"
```

---

### Task 6: Close issue with final commit

**Step 1: Verify all changes are committed**

Run: `git status`
Expected: Clean working tree.

**Step 2: Close the GitHub issue**

Run: `gh issue close 112 --comment "Fixed: orphaned checked_off items are now pruned when recipes/quick bites are deselected, and cleared when all selections are cleared."`

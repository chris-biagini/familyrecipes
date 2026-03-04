# Ingredient Traversal Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate duplicated eager-load includes (5 files) and duplicated visible-names extraction (2 files) by centralizing both on the classes that own the data.

**Architecture:** Add a `with_full_tree` scope to `Recipe` as the single definition of the eager-load graph. Add a `visible_names` method to `ShoppingListBuilder` to encapsulate the name-extraction logic. All consumers switch to these new APIs. No new classes, no new abstractions.

**Tech Stack:** Rails 8, Minitest, SQLite

---

### Task 1: Add `Recipe.with_full_tree` scope

**Files:**
- Modify: `app/models/recipe.rb:28` (add scope after existing `alphabetical` scope)
- Test: `test/models/recipe_model_test.rb`

**Step 1: Write the failing test**

Add to `test/models/recipe_model_test.rb`:

```ruby
# --- with_full_tree scope ---

test 'with_full_tree eager loads steps, ingredients, and cross references' do
  recipe = MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Poolish

    Category: Test

    ## Mix (combine)

    - Flour, 1 cup

    Mix.
  MD

  loaded = Recipe.with_full_tree.find(recipe.id)

  assert_predicate loaded.association(:steps), :loaded?
  assert_predicate loaded.steps.first.association(:ingredients), :loaded?
  assert_predicate loaded.steps.first.association(:cross_references), :loaded?
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/recipe_model_test.rb -n test_with_full_tree_eager_loads_steps`
Expected: FAIL — `NoMethodError: undefined method 'with_full_tree'`

**Step 3: Write minimal implementation**

Add to `app/models/recipe.rb` after the `alphabetical` scope:

```ruby
scope :with_full_tree, -> {
  includes(:category,
           steps: [:ingredients,
                   { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }])
}
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/recipe_model_test.rb -n test_with_full_tree_eager_loads_steps`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/recipe.rb test/models/recipe_model_test.rb
git commit -m "feat: add Recipe.with_full_tree scope for canonical eager loading"
```

---

### Task 2: Replace inline eager-load in ShoppingListBuilder

**Files:**
- Modify: `app/services/shopping_list_builder.rb:47-53` (`selected_recipes` method)

**Step 1: Replace the inline includes**

In `selected_recipes`, replace:
```ruby
def selected_recipes
  slugs = @meal_plan.state.fetch('selected_recipes', [])
  xref_includes = { cross_references: { target_recipe: { steps: :ingredients } } }
  @kitchen.recipes
          .includes(:category, steps: [:ingredients, xref_includes])
          .where(slug: slugs)
end
```

With:
```ruby
def selected_recipes
  slugs = @meal_plan.state.fetch('selected_recipes', [])
  @kitchen.recipes.with_full_tree.where(slug: slugs)
end
```

**Step 2: Run existing ShoppingListBuilder tests**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All 18 tests PASS (no behavioral change)

**Step 3: Commit**

```bash
git add app/services/shopping_list_builder.rb
git commit -m "refactor: use Recipe.with_full_tree in ShoppingListBuilder"
```

---

### Task 3: Replace inline eager-load in RecipeAvailabilityCalculator

**Files:**
- Modify: `app/services/recipe_availability_calculator.rb:61-63` (`loaded_recipes` method)

**Step 1: Replace the inline includes**

Replace:
```ruby
def loaded_recipes
  xref_includes = { cross_references: { target_recipe: { steps: :ingredients } } }
  @kitchen.recipes.includes(steps: [:ingredients, xref_includes])
end
```

With:
```ruby
def loaded_recipes
  @kitchen.recipes.with_full_tree
end
```

**Step 2: Run existing tests**

Run: `ruby -Itest test/services/recipe_availability_calculator_test.rb`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/services/recipe_availability_calculator.rb
git commit -m "refactor: use Recipe.with_full_tree in RecipeAvailabilityCalculator"
```

---

### Task 4: Replace inline eager-load in RecipeNutritionJob

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb:24-27` (`eager_load_recipe` method)

**Step 1: Replace the inline includes**

Replace:
```ruby
def eager_load_recipe(recipe)
  Recipe.includes(steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
        .find(recipe.id)
end
```

With:
```ruby
def eager_load_recipe(recipe)
  Recipe.with_full_tree.find(recipe.id)
end
```

**Step 2: Run existing tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb
git commit -m "refactor: use Recipe.with_full_tree in RecipeNutritionJob"
```

---

### Task 5: Replace SHOW_INCLUDES constant in RecipeBroadcaster

**Files:**
- Modify: `app/services/recipe_broadcaster.rb:13-16` (remove `SHOW_INCLUDES`), lines 82, 117, 125, 133 (callers)

**Step 1: Remove SHOW_INCLUDES and replace all usages**

Remove the constant:
```ruby
SHOW_INCLUDES = [
  :category,
  { steps: [:ingredients, { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }] }
].freeze
```

Replace `includes(SHOW_INCLUDES)` with `.with_full_tree` in these methods:

- `preload_categories` (line 82): Change `kitchen.categories.ordered.includes(recipes: { steps: :ingredients })` to `kitchen.categories.ordered.includes(recipes: Recipe.with_full_tree.values[:includes])` — actually, this one loads categories with nested recipes, not recipes directly. Keep reading below.

Actually, `preload_categories` loads from `kitchen.categories`, not `kitchen.recipes`. The eager load there is `recipes: { steps: :ingredients }` which is different from `with_full_tree`. Only `SHOW_INCLUDES` usages need replacing. Those are:

- `broadcast_recipe_page` line 117: `kitchen.recipes.includes(SHOW_INCLUDES).find_by(slug: recipe.slug)` → `kitchen.recipes.with_full_tree.find_by(slug: recipe.slug)`
- `broadcast_referencing_recipes` line 125: `recipe.referencing_recipes.includes(SHOW_INCLUDES).find_each` → `recipe.referencing_recipes.with_full_tree.find_each`
- `update_referencing_recipes` line 133: `kitchen.recipes.where(id: parent_ids).includes(SHOW_INCLUDES).find_each` → `kitchen.recipes.where(id: parent_ids).with_full_tree.find_each`

**Step 2: Run existing tests**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/services/recipe_broadcaster.rb
git commit -m "refactor: use Recipe.with_full_tree in RecipeBroadcaster"
```

---

### Task 6: Replace inline eager-load in RecipesController

**Files:**
- Modify: `app/controllers/recipes_controller.rb:10-16` (`show` action)

**Step 1: Replace the inline includes**

Replace:
```ruby
def show
  embedded_steps = { steps: %i[ingredients cross_references] }
  @recipe = current_kitchen.recipes
                           .includes(:category,
                                     steps: [:ingredients,
                                             { cross_references: { target_recipe: embedded_steps } }])
                           .find_by!(slug: params[:slug])
  @nutrition = @recipe.nutrition_data
end
```

With:
```ruby
def show
  @recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  @nutrition = @recipe.nutrition_data
end
```

**Step 2: Run existing tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "refactor: use Recipe.with_full_tree in RecipesController"
```

---

### Task 7: Add `ShoppingListBuilder#visible_names`

**Files:**
- Modify: `app/services/shopping_list_builder.rb` (add public method after `build`)
- Test: `test/services/shopping_list_builder_test.rb`

**Step 1: Write the failing test**

Add to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'visible_names returns set of all ingredient names in shopping list' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  names = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).visible_names

  assert_instance_of Set, names
  assert_includes names, 'Flour'
  assert_includes names, 'Salt'
end

test 'visible_names includes custom items' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'birthday candles', action: 'add')

  names = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).visible_names

  assert_includes names, 'birthday candles'
end

test 'visible_names excludes omitted ingredients' do
  IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: 'omit')
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  names = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).visible_names

  assert_not_includes names, 'Salt'
  assert_includes names, 'Flour'
end

test 'visible_names returns empty set when nothing selected' do
  list = MealPlan.for_kitchen(@kitchen)
  names = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).visible_names

  assert_empty names
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /visible_names/`
Expected: FAIL — `NoMethodError: undefined method 'visible_names'`

**Step 3: Write minimal implementation**

Add to `app/services/shopping_list_builder.rb` after the `build` method:

```ruby
def visible_names
  build.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /visible_names/`
Expected: All 4 PASS

**Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "feat: add ShoppingListBuilder#visible_names"
```

---

### Task 8: Simplify callers to use `visible_names`

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb:37-39`
- Modify: `app/services/recipe_write_service.rb:101-106`

**Step 1: Simplify MealPlanActions**

Replace `shopping_list_visible_names` in `meal_plan_actions.rb`:

```ruby
def shopping_list_visible_names(plan)
  shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
end
```

With:
```ruby
def shopping_list_visible_names(plan)
  ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).visible_names
end
```

**Step 2: Simplify RecipeWriteService**

Replace `prune_stale_meal_plan_items` in `recipe_write_service.rb`:

```ruby
def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
  visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
end
```

With:
```ruby
def prune_stale_meal_plan_items
  plan = MealPlan.for_kitchen(kitchen)
  visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
end
```

**Step 3: Run full test suite to verify no regressions**

Run: `rake test`
Expected: All tests PASS

**Step 4: Run linter**

Run: `bundle exec rubocop`
Expected: No offenses

**Step 5: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb app/services/recipe_write_service.rb
git commit -m "refactor: use ShoppingListBuilder#visible_names in callers"
```

---

### Task 9: Final verification

**Step 1: Run full test suite**

Run: `rake`
Expected: All tests PASS, 0 RuboCop offenses

**Step 2: Verify no remaining inline eager-load duplicates**

Search for the old pattern to confirm it's fully removed:
```bash
grep -rn "cross_references.*target_recipe.*steps.*ingredients" app/ --include="*.rb"
```
Expected: Only `app/models/recipe.rb` (the scope definition)

**Step 3: Verify no remaining visible-names extraction**

```bash
grep -rn "each_value.flat_map.*items.*name" app/ --include="*.rb"
```
Expected: Only `app/services/shopping_list_builder.rb` (the `visible_names` method)

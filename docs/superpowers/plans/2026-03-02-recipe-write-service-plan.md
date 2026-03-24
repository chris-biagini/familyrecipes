# RecipeWriteService Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract recipe write-path orchestration from RecipesController into RecipeWriteService, and consolidate prune logic into MealPlan.prune_stale_items.

**Architecture:** Single service class with create/update/destroy class methods returning Data.define Result objects. MealPlan gets a new class method that owns the full prune-checked-off operation. Controllers become thin HTTP adapters.

**Tech Stack:** Rails 8, Minitest, Turbo Streams, ActionCable

**Design doc:** `docs/plans/2026-03-02-recipe-write-service-design.md`

---

### Task 1: Add MealPlan.prune_stale_items with tests

This is the foundation — everything else depends on it. Build bottom-up.

**Files:**
- Modify: `app/models/meal_plan.rb:7-8` (header comment), add class method after line 22
- Test: `test/models/meal_plan_test.rb` (append new tests)

**Step 1: Write the failing tests**

Append to `test/models/meal_plan_test.rb`, before the final `end`:

```ruby
test 'prune_stale_items removes checked items not on shopping list' do
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix well.
  MD

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('check', item: 'Flour', checked: true)
  plan.apply_action('check', item: 'Phantom Item', checked: true)

  MealPlan.prune_stale_items(kitchen: @kitchen)

  plan.reload

  assert_includes plan.state['checked_off'], 'Flour'
  assert_not_includes plan.state['checked_off'], 'Phantom Item'
end

test 'prune_stale_items preserves custom items' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'birthday candles', action: 'add')
  plan.apply_action('check', item: 'birthday candles', checked: true)

  MealPlan.prune_stale_items(kitchen: @kitchen)

  plan.reload

  assert_includes plan.state['checked_off'], 'birthday candles'
end

test 'prune_stale_items is no-op when nothing to prune' do
  plan = MealPlan.for_kitchen(@kitchen)
  version_before = plan.lock_version

  MealPlan.prune_stale_items(kitchen: @kitchen)

  assert_equal version_before, plan.reload.lock_version
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /prune_stale_items/`
Expected: FAIL — `NoMethodError: undefined method 'prune_stale_items' for MealPlan`

**Step 3: Implement MealPlan.prune_stale_items**

Add to `app/models/meal_plan.rb` after the `for_kitchen` method (after line 22):

```ruby
def self.prune_stale_items(kitchen:)
  plan = for_kitchen(kitchen)
  shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
  visible = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
  plan.with_optimistic_retry { plan.prune_checked_off(visible_names: visible) }
end
```

Update the header comment (lines 7-8) to mention the new class method:

```ruby
# read and write this model. MealPlan.prune_stale_items encapsulates the full
# prune operation (building the shopping list + retry) so callers need not
# depend on ShoppingListBuilder directly.
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /prune_stale_items/`
Expected: 3 tests, 0 failures

**Step 5: Run full MealPlan test suite**

Run: `ruby -Itest test/models/meal_plan_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "feat: add MealPlan.prune_stale_items class method"
```

---

### Task 2: Create RecipeWriteService with create action

**Files:**
- Create: `app/services/recipe_write_service.rb`
- Create: `test/services/recipe_write_service_test.rb`

**Step 1: Write the failing tests**

Create `test/services/recipe_write_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipeWriteServiceTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Recipe.destroy_all
    Category.destroy_all
  end

  BASIC_MARKDOWN = <<~MD
    # Focaccia

    A simple flatbread.

    Category: Bread
    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix everything together.
  MD

  test 'create imports recipe and returns Result' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_instance_of RecipeWriteService::Result, result
    assert_equal 'Focaccia', result.recipe.title
    assert_empty result.updated_references
  end

  test 'create sets edited_at' do
    result = RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_not_nil result.recipe.edited_at
  end

  test 'create cleans up orphan categories' do
    Category.create!(name: 'Empty', slug: 'empty', position: 99, kitchen: @kitchen)

    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

    assert_nil Category.find_by(slug: 'empty')
  end

  test 'create raises on invalid record' do
    bad_markdown = <<~MD
      # Focaccia

      Category: Bread

      ## Step (do it)

      - Flour, 3 cups

      Mix.
    MD

    RecipeWriteService.create(markdown: bad_markdown, kitchen: @kitchen)

    assert_raises(ActiveRecord::RecordInvalid) do
      RecipeWriteService.create(markdown: "# \n\nCategory: Bread\n\n## S (s)\n\n- F\n\nM.", kitchen: @kitchen)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: FAIL — `NameError: uninitialized constant RecipeWriteService`

**Step 3: Create the service**

Create `app/services/recipe_write_service.rb`:

```ruby
# frozen_string_literal: true

# Orchestrates recipe create/update/destroy. Owns the full post-write pipeline:
# import via MarkdownImporter, handle renames (CrossReferenceUpdater), broadcast
# real-time updates (RecipeBroadcaster), clean up orphan categories, and prune
# stale meal plan entries. Controllers validate input and render responses;
# this service owns domain orchestration.
class RecipeWriteService
  Result = Data.define(:recipe, :updated_references)

  def self.create(markdown:, kitchen:)
    new(kitchen:).create(markdown:)
  end

  def self.update(slug:, markdown:, kitchen:)
    new(kitchen:).update(slug:, markdown:)
  end

  def self.destroy(slug:, kitchen:)
    new(kitchen:).destroy(slug:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def create(markdown:)
    recipe = import_and_timestamp(markdown)
    RecipeBroadcaster.broadcast(kitchen:, action: :created, recipe_title: recipe.title, recipe:)
    post_write_cleanup
    Result.new(recipe:, updated_references: [])
  end

  private

  attr_reader :kitchen

  def import_and_timestamp(markdown)
    recipe = MarkdownImporter.import(markdown, kitchen:)
    recipe.update!(edited_at: Time.current)
    recipe
  end

  def post_write_cleanup
    Category.cleanup_orphans(kitchen)
    MealPlan.prune_stale_items(kitchen:)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: add RecipeWriteService with create action"
```

---

### Task 3: Add update action to RecipeWriteService

**Files:**
- Modify: `app/services/recipe_write_service.rb` — add `update` method
- Modify: `test/services/recipe_write_service_test.rb` — add update tests

**Step 1: Write the failing tests**

Append to `test/services/recipe_write_service_test.rb`, before the final `end`:

```ruby
test 'update imports recipe and returns Result' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  updated = <<~MD
    # Focaccia

    A revised flatbread.

    Category: Bread
    Serves: 12

    ## Make the dough (combine ingredients)

    - Flour, 4 cups

    Mix everything.
  MD

  result = RecipeWriteService.update(slug: 'focaccia', markdown: updated, kitchen: @kitchen)

  assert_equal 'Focaccia', result.recipe.title
  assert_equal 'A revised flatbread.', result.recipe.description
  assert_empty result.updated_references
end

test 'update with title rename returns updated_references' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Panzanella

    Category: Bread

    ## Make bread.
    >>> @[Focaccia], 1

    ## Assemble (put it together)

    - Tomatoes, 3

    Tear bread and toss.
  MD

  renamed = <<~MD
    # Rosemary Focaccia

    Category: Bread
    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 4 cups

    Mix everything.
  MD

  result = RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen)

  assert_includes result.updated_references, 'Panzanella'
  assert_equal 'rosemary-focaccia', result.recipe.slug
end

test 'update with slug change destroys old record' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  renamed = <<~MD
    # Rosemary Focaccia

    Category: Bread

    ## Make (do it)

    - Flour, 4 cups

    Mix.
  MD

  RecipeWriteService.update(slug: 'focaccia', markdown: renamed, kitchen: @kitchen)

  assert_nil Recipe.find_by(slug: 'focaccia')
  assert Recipe.find_by(slug: 'rosemary-focaccia')
end

test 'update cleans up orphan categories' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  recategorized = <<~MD
    # Focaccia

    Category: Pastry

    ## Make (do it)

    - Flour, 3 cups

    Mix.
  MD

  RecipeWriteService.update(slug: 'focaccia', markdown: recategorized, kitchen: @kitchen)

  assert_nil Category.find_by(slug: 'bread')
  assert Category.find_by(slug: 'pastry')
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n /update/`
Expected: FAIL — `update` method not yet implemented (raises NotImplementedError or similar)

**Step 3: Implement update**

Add to `app/services/recipe_write_service.rb`, after the `create` method:

```ruby
def update(slug:, markdown:)
  old_recipe = kitchen.recipes.find_by!(slug:)
  recipe = import_and_timestamp(markdown)
  updated_references = rename_cross_references(old_recipe, recipe)
  handle_slug_change(old_recipe, recipe)
  RecipeBroadcaster.broadcast(kitchen:, action: :updated, recipe_title: recipe.title, recipe:)
  post_write_cleanup
  Result.new(recipe:, updated_references:)
end
```

Add private helpers:

```ruby
def rename_cross_references(old_recipe, new_recipe)
  return [] if old_recipe.title == new_recipe.title

  CrossReferenceUpdater.rename_references(
    old_title: old_recipe.title, new_title: new_recipe.title, kitchen:
  )
end

def handle_slug_change(old_recipe, new_recipe)
  return if new_recipe.slug == old_recipe.slug

  RecipeBroadcaster.broadcast_rename(
    old_recipe, new_title: new_recipe.title,
    redirect_path: Rails.application.routes.url_helpers.recipe_path(new_recipe)
  )
  old_recipe.destroy!
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: add update action to RecipeWriteService"
```

---

### Task 4: Add destroy action to RecipeWriteService

**Files:**
- Modify: `app/services/recipe_write_service.rb` — add `destroy` method
- Modify: `test/services/recipe_write_service_test.rb` — add destroy tests

**Step 1: Write the failing tests**

Append to `test/services/recipe_write_service_test.rb`, before the final `end`:

```ruby
test 'destroy removes recipe and returns Result' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  result = RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

  assert_equal 'Focaccia', result.recipe.title
  assert_nil Recipe.find_by(slug: 'focaccia')
end

test 'destroy cleans up orphan categories' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

  assert_nil Category.find_by(slug: 'bread')
end

test 'destroy nullifies inbound cross-references' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Panzanella

    Category: Bread

    ## Make bread.
    >>> @[Focaccia], 1

    ## Assemble (put it together)

    - Tomatoes, 3

    Tear bread and toss.
  MD

  xref = Recipe.find_by!(slug: 'panzanella').cross_references.find_by!(target_title: 'Focaccia')

  RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)

  assert_nil xref.reload.target_recipe_id
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n /destroy/`
Expected: FAIL — method not implemented

**Step 3: Implement destroy**

Add to `app/services/recipe_write_service.rb`, after the `update` method:

```ruby
def destroy(slug:)
  recipe = kitchen.recipes.find_by!(slug:)
  parent_ids = recipe.referencing_recipes.pluck(:id)
  RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
  recipe.destroy!
  broadcast_to_referencing_recipes(parent_ids)
  RecipeBroadcaster.broadcast(kitchen:, action: :deleted, recipe_title: recipe.title)
  post_write_cleanup
  Result.new(recipe:, updated_references: [])
end
```

Add private helper:

```ruby
def broadcast_to_referencing_recipes(parent_ids)
  return if parent_ids.empty?

  kitchen.recipes.where(id: parent_ids).includes(RecipeBroadcaster::SHOW_INCLUDES).find_each do |parent|
    Turbo::StreamsChannel.broadcast_replace_to(
      parent, 'content',
      target: 'recipe-content',
      partial: 'recipes/recipe_content',
      locals: { recipe: parent, nutrition: parent.nutrition_data }
    )
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: add destroy action to RecipeWriteService"
```

---

### Task 5: Rewire RecipesController to use RecipeWriteService

**Files:**
- Modify: `app/controllers/recipes_controller.rb` — replace action bodies, remove `include MealPlanActions`
- Existing tests: `test/controllers/recipes_controller_test.rb` (no changes — validates the refactor)

**Step 1: Run existing controller tests as baseline**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All pass (establishes baseline)

**Step 2: Rewrite RecipesController**

Replace `app/controllers/recipes_controller.rb` entirely:

```ruby
# frozen_string_literal: true

# Thin HTTP adapter for recipe CRUD. Show is public; writes require membership.
# Validates Markdown params, delegates to RecipeWriteService for orchestration,
# and renders JSON responses. All domain logic (import, broadcast, cleanup)
# lives in the service.
class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    embedded_steps = { steps: %i[ingredients cross_references] }
    @recipe = current_kitchen.recipes
                             .includes(:category,
                                       steps: [:ingredients,
                                               { cross_references: { target_recipe: embedded_steps } }])
                             .find_by!(slug: params[:slug])
    @nutrition = @recipe.nutrition_data
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    result = RecipeWriteService.create(markdown: params[:markdown_source], kitchen: current_kitchen)
    render json: { redirect_url: recipe_path(result.recipe.slug) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def update
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    result = RecipeWriteService.update(slug: params[:slug], markdown: params[:markdown_source], kitchen: current_kitchen)
    response_json = { redirect_url: recipe_path(result.recipe.slug) }
    response_json[:updated_references] = result.updated_references if result.updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordInvalid, RuntimeError => error
    render json: { errors: [error.message] }, status: :unprocessable_content
  end

  def destroy
    RecipeWriteService.destroy(slug: params[:slug], kitchen: current_kitchen)
    render json: { redirect_url: home_path }
  end
end
```

**Step 3: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All 22 tests pass

**Step 4: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "refactor: rewire RecipesController to use RecipeWriteService"
```

---

### Task 6: Simplify MealPlanActions and MenuController

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb:27-38` — delete `build_visible_names`, simplify `prune_if_deselect`
- Modify: `app/controllers/menu_controller.rb:61-62` — replace inline prune
- Existing tests: `test/controllers/menu_controller_test.rb` (validates the refactor)

**Step 1: Run existing tests as baseline**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass

**Step 2: Simplify MealPlanActions concern**

Replace `app/controllers/concerns/meal_plan_actions.rb`:

```ruby
# frozen_string_literal: true

# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry with version broadcasting and a common
# StaleObjectError handler. Used by MenuController and GroceriesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def apply_and_respond(action_type, **action_params)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry do
      plan.apply_action(action_type, **action_params)
      prune_if_deselect(action_type, action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def prune_if_deselect(action_type, action_params)
    return unless action_type == 'select'
    return if [true, 'true'].include?(action_params[:selected])

    MealPlan.prune_stale_items(kitchen: current_kitchen)
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end
```

**Step 3: Simplify MenuController#update_quick_bites**

In `app/controllers/menu_controller.rb`, replace lines 61-62:

```ruby
# OLD:
plan = MealPlan.for_kitchen(current_kitchen)
plan.with_optimistic_retry { plan.prune_checked_off(visible_names: build_visible_names(plan)) }

# NEW:
MealPlan.prune_stale_items(kitchen: current_kitchen)
```

**Step 4: Run menu controller tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass

**Step 5: Run groceries controller tests too (also uses MealPlanActions)**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb app/controllers/menu_controller.rb
git commit -m "refactor: simplify MealPlanActions and MenuController prune logic"
```

---

### Task 7: Update header comments and CLAUDE.md

**Files:**
- Modify: `app/controllers/recipes_controller.rb:3-6` — header comment
- Modify: `app/controllers/concerns/meal_plan_actions.rb:3-7` — header comment
- Modify: `app/models/meal_plan.rb:3-8` — header comment
- Modify: `CLAUDE.md` — mention RecipeWriteService in Architecture > Services section

**Step 1: Update RecipesController header**

Already done in Task 5 — the new file has the updated header.

**Step 2: Update MealPlan header comment**

The model's header (lines 3-8) currently says "Controllers inject visible_names into prune_checked_off — this model has no dependency on ShoppingListBuilder." This is no longer true. Update to reflect that `prune_stale_items` now owns the ShoppingListBuilder call.

**Step 3: Update CLAUDE.md Services section**

In the Architecture > Services paragraph, add RecipeWriteService to the list:

```
**Services.** Beyond `MarkdownImporter`, `app/services/` has: `RecipeWriteService`
(create/update/destroy orchestration — import, broadcast, cleanup),
`ShoppingListBuilder` ...
```

**Step 4: Commit**

```bash
git add app/models/meal_plan.rb CLAUDE.md
git commit -m "docs: update header comments and CLAUDE.md for RecipeWriteService"
```

---

### Task 8: Run full test suite and lint

**Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. The old RuboCop disable comments on `update` are gone. If new offenses appear (e.g., line length in the service), fix them.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass (855+ tests, 0 failures)

**Step 3: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass — no new `.html_safe` calls added.

**Step 4: Fix any issues found, then commit**

```bash
git add -A
git commit -m "chore: fix lint issues from RecipeWriteService refactor"
```

(Skip this commit if no issues found.)

---

### Task 9: Final review

**Step 1: Verify RecipesController is thin**

Read `app/controllers/recipes_controller.rb` — each action should be ≤8 lines. No RuboCop disable comments. No `include MealPlanActions`.

**Step 2: Verify no remaining `build_visible_names` references**

Run: `grep -r "build_visible_names" app/`
Expected: No results.

**Step 3: Verify no remaining inline prune blocks**

Run: `grep -r "prune_checked_off" app/controllers/`
Expected: No results — all pruning goes through `MealPlan.prune_stale_items`.

**Step 4: Verify `prune_checked_off` only called from MealPlan itself**

Run: `grep -r "prune_checked_off" app/`
Expected: Only `app/models/meal_plan.rb` (the instance method and the class method that calls it).

# Async Broadcasting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Move RecipeBroadcaster calls and CascadeNutritionJob off the request thread so recipe saves return immediately.

**Architecture:** New `RecipeBroadcastJob` wraps all `RecipeBroadcaster` calls and runs via `perform_later` on the `:async` adapter (in-process thread pool — no Solid Queue yet). `CascadeNutritionJob` also switches to `perform_later`. Synchronous callers (`broadcast_rename`, `notify_recipe_deleted`, primary `RecipeNutritionJob`) stay on the request thread because their results must be visible before the HTTP response.

**Tech Stack:** ActiveJob with `:async` adapter (Rails default), Minitest, Turbo Broadcastable test helpers.

---

### Task 1: Create RecipeBroadcastJob with tests

**Files:**
- Create: `app/jobs/recipe_broadcast_job.rb`
- Create: `test/jobs/recipe_broadcast_job_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipeBroadcastJobTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple bread.

      Category: Bread

      ## Dough

      - Flour, 3 cups

      Mix and knead.
    MD
  end

  test 'broadcast calls RecipeBroadcaster.broadcast with correct args' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    called = false

    RecipeBroadcaster.stub :broadcast, ->(kitchen:, action:, recipe_title:, recipe: nil) {
      called = true
      assert_equal @kitchen, kitchen
      assert_equal :updated, action
      assert_equal 'Focaccia', recipe_title
      assert_equal recipe.id, recipe&.id
    } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'updated',
        recipe_title: 'Focaccia', recipe_id: recipe.id
      )
    end

    assert called, 'Expected RecipeBroadcaster.broadcast to be called'
  end

  test 'broadcast skips gracefully when recipe not found' do
    called = false

    RecipeBroadcaster.stub :broadcast, ->(**) { called = true } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'created',
        recipe_title: 'Ghost', recipe_id: -1
      )
    end

    assert called, 'Expected broadcast to still fire (recipe: nil for deleted recipes)'
  end

  test 'destroy calls RecipeBroadcaster.broadcast_destroy' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    parent_ids = [42, 99]
    called = false

    RecipeBroadcaster.stub :broadcast_destroy, ->(kitchen:, recipe:, recipe_title:, parent_ids:) {
      called = true
      assert_equal @kitchen, kitchen
      assert_equal 'Focaccia', recipe_title
      assert_equal [42, 99], parent_ids
    } do
      RecipeBroadcastJob.perform_now(
        kitchen_id: @kitchen.id, action: 'destroy',
        recipe_title: 'Focaccia', recipe_id: recipe.id,
        parent_ids: parent_ids
      )
    end

    assert called, 'Expected RecipeBroadcaster.broadcast_destroy to be called'
  end
end
```

**Step 2: Run to verify it fails**

Run: `ruby -Itest test/jobs/recipe_broadcast_job_test.rb`
Expected: NameError — `RecipeBroadcastJob` not defined.

**Step 3: Write the job**

```ruby
# frozen_string_literal: true

# Runs RecipeBroadcaster calls off the request thread via perform_later.
# Accepts only primitive/serializable arguments so ActiveJob can enqueue
# without serializing AR objects. Re-fetches records and sets tenant context.
#
# - RecipeWriteService: sole enqueuer
# - RecipeBroadcaster: does the actual Turbo Stream work
class RecipeBroadcastJob < ApplicationJob
  def perform(kitchen_id:, action:, recipe_title:, recipe_id: nil, parent_ids: [])
    kitchen = Kitchen.find(kitchen_id)
    recipe = kitchen.recipes.find_by(id: recipe_id)

    if action == 'destroy'
      RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title:, parent_ids:)
    else
      RecipeBroadcaster.broadcast(kitchen:, action: action.to_sym, recipe_title:, recipe:)
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/jobs/recipe_broadcast_job_test.rb`
Expected: 3 tests, 0 failures.

**Step 5: Commit**

```bash
git add app/jobs/recipe_broadcast_job.rb test/jobs/recipe_broadcast_job_test.rb
git commit -m "feat: add RecipeBroadcastJob for async broadcasting (gh-177)"
```

---

### Task 2: Wire RecipeWriteService to enqueue RecipeBroadcastJob

**Files:**
- Modify: `app/services/recipe_write_service.rb`
- Modify: `test/services/recipe_write_service_test.rb`

**Step 1: Add enqueue assertions to the test file**

Add these tests to `RecipeWriteServiceTest`:

```ruby
test 'create enqueues RecipeBroadcastJob' do
  assert_enqueued_with(job: RecipeBroadcastJob) do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)
  end
end

test 'update enqueues RecipeBroadcastJob' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  assert_enqueued_with(job: RecipeBroadcastJob) do
    RecipeWriteService.update(slug: 'focaccia', markdown: BASIC_MARKDOWN, kitchen: @kitchen)
  end
end

test 'destroy enqueues RecipeBroadcastJob with parent_ids' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen)

  assert_enqueued_with(job: RecipeBroadcastJob) do
    RecipeWriteService.destroy(slug: 'focaccia', kitchen: @kitchen)
  end
end
```

**Step 2: Run to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n /enqueues/`
Expected: FAIL — jobs are being performed inline, not enqueued.

**Step 3: Update RecipeWriteService**

In `create`:
```ruby
# Before:
RecipeBroadcaster.broadcast(kitchen:, action: :created, recipe_title: recipe.title, recipe:)

# After:
enqueue_broadcast(action: :created, recipe_title: recipe.title, recipe:)
```

In `update`:
```ruby
# Before:
RecipeBroadcaster.broadcast(kitchen:, action: :updated, recipe_title: recipe.title, recipe:)

# After:
enqueue_broadcast(action: :updated, recipe_title: recipe.title, recipe:)
```

In `destroy`:
```ruby
# Before:
RecipeBroadcaster.broadcast_destroy(kitchen:, recipe:, recipe_title: recipe.title, parent_ids:)

# After:
RecipeBroadcastJob.perform_later(
  kitchen_id: kitchen.id, action: 'destroy',
  recipe_title: recipe.title, recipe_id: recipe.id, parent_ids:
)
```

Add private helper:
```ruby
def enqueue_broadcast(action:, recipe_title:, recipe:)
  RecipeBroadcastJob.perform_later(
    kitchen_id: kitchen.id, action: action.to_s,
    recipe_title:, recipe_id: recipe.id
  )
end
```

Also update the header comment: broadcasting is now async via `RecipeBroadcastJob`.

**Step 4: Run tests**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass (new enqueue tests + existing tests).

**Step 5: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: enqueue RecipeBroadcastJob from RecipeWriteService (gh-177)"
```

---

### Task 3: Move CascadeNutritionJob to perform_later

**Files:**
- Modify: `app/services/markdown_importer.rb`
- Modify: `app/jobs/cascade_nutrition_job.rb` (header comment only)

**Step 1: Add enqueue assertion**

Add this test to the existing `test/jobs/recipe_nutrition_job_test.rb` (which already tests cascade behavior):

```ruby
test 'MarkdownImporter enqueues CascadeNutritionJob' do
  assert_enqueued_with(job: CascadeNutritionJob) do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Cascade Test

      Category: Test

      ## Step (do it)

      - Flour, 1 cup

      Mix.
    MD
  end
end
```

**Step 2: Run to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n /enqueues/`
Expected: FAIL — CascadeNutritionJob is called with `perform_now`.

**Step 3: Update MarkdownImporter**

In `compute_nutrition`:
```ruby
# Before:
def compute_nutrition(recipe)
  RecipeNutritionJob.perform_now(recipe)
  CascadeNutritionJob.perform_now(recipe)
end

# After:
def compute_nutrition(recipe)
  RecipeNutritionJob.perform_now(recipe)
  CascadeNutritionJob.perform_later(recipe)
end
```

Update header comment to note cascade is async.

**Step 4: Run full test suite**

Run: `rake test`
Expected: All pass. Some tests that relied on cascade completing synchronously may need `perform_enqueued_jobs` — check and fix.

**Step 5: Commit**

```bash
git add app/services/markdown_importer.rb app/jobs/cascade_nutrition_job.rb test/jobs/recipe_nutrition_job_test.rb
git commit -m "feat: run CascadeNutritionJob async via perform_later (gh-177)"
```

---

### Task 4: Full suite verification and cleanup

**Files:**
- Possibly modify: any tests that break from async behavior
- Modify: `CLAUDE.md` if architectural notes need updating

**Step 1: Run full test suite**

Run: `rake`
Expected: Lint clean, all tests pass.

**Step 2: Fix any test failures**

Tests that previously relied on broadcasts or cascade nutrition completing synchronously may need wrapping in `perform_enqueued_jobs` blocks. Fix as needed.

**Step 3: Update CLAUDE.md Architecture section**

Add a note that broadcasting and cascade nutrition run async via `perform_later` on the `:async` adapter. Mention that Solid Queue can be swapped in later with zero code changes.

**Step 4: Final commit and close issue**

```bash
git add -A
git commit -m "chore: fix test suite for async broadcasting (gh-177)"
gh issue close 177
```

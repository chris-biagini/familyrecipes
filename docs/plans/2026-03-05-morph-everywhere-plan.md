# Morph Everywhere Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace targeted Turbo Stream broadcasts with a single kitchen-wide `broadcast_refresh_to` stream, drop non-critical toasts, and simplify the nutrition editor to JSON-only responses.

**Architecture:** One broadcast stream `[kitchen, :updates]` for all page morphs. Per-recipe stream `[recipe, "content"]` retained solely for delete/rename notifications. `Kitchen#broadcast_update` is the single entry point. `RecipeBroadcaster` shrinks to delete/rename only. `RecipeBroadcastJob` deleted.

**Tech Stack:** Rails 8, Turbo Streams, ActionCable, Solid Cable, Stimulus, Minitest

---

### Task 1: Add `Kitchen#broadcast_update`

**Files:**
- Modify: `app/models/kitchen.rb:9` (add method)
- Test: `test/models/kitchen_test.rb`

**Step 1: Write the failing test**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'broadcast_update sends refresh to kitchen updates stream' do
  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    @kitchen.broadcast_update
  end
end
```

Ensure `include Turbo::Broadcastable::TestHelper` is present.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_broadcast_update`
Expected: FAIL — `NoMethodError: undefined method 'broadcast_update'`

**Step 3: Write minimal implementation**

Add to `app/models/kitchen.rb`:

```ruby
def broadcast_update
  Turbo::StreamsChannel.broadcast_refresh_to(self, :updates)
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_broadcast_update`
Expected: PASS

**Step 5: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_test.rb
git commit -m "feat: add Kitchen#broadcast_update for morph-everywhere"
```

---

### Task 2: Switch `MealPlanActions` to `Kitchen#broadcast_update`

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb:46-48`
- Test: `test/controllers/menu_controller_test.rb`, `test/controllers/groceries_controller_test.rb`

**Step 1: Update the broadcast tests**

In `test/controllers/menu_controller_test.rb`, change all `assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates]` to `assert_turbo_stream_broadcasts [@kitchen, :updates]`. Lines: 161, 238, 266, 329.

In `test/controllers/groceries_controller_test.rb`, same change. Lines: 361, 370, 379.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /broadcasts/`
Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /broadcasts/`
Expected: FAIL — no broadcasts on `[:updates]` stream

**Step 3: Update the concern**

In `app/controllers/concerns/meal_plan_actions.rb`, replace `broadcast_meal_plan_refresh`:

```ruby
def broadcast_meal_plan_refresh
  current_kitchen.broadcast_update
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb test/controllers/menu_controller_test.rb test/controllers/groceries_controller_test.rb
git commit -m "refactor: MealPlanActions uses Kitchen#broadcast_update"
```

---

### Task 3: Switch `CatalogWriteService` to `Kitchen#broadcast_update`

**Files:**
- Modify: `app/services/catalog_write_service.rb:73-75`
- Test: `test/services/catalog_write_service_test.rb`, `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Update broadcast tests**

In `test/services/catalog_write_service_test.rb`, change `[@kitchen, :meal_plan_updates]` to `[@kitchen, :updates]`. Lines: 133, 185.

In `test/controllers/nutrition_entries_controller_test.rb`, same change. Lines: 161, 460.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/catalog_write_service_test.rb -n /broadcast/`
Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n /broadcast/`
Expected: FAIL

**Step 3: Update the service**

In `app/services/catalog_write_service.rb`, replace `broadcast_meal_plan_refresh`:

```ruby
def broadcast_meal_plan_refresh
  kitchen.broadcast_update
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/catalog_write_service.rb test/services/catalog_write_service_test.rb test/controllers/nutrition_entries_controller_test.rb
git commit -m "refactor: CatalogWriteService uses Kitchen#broadcast_update"
```

---

### Task 4: Gut `RecipeBroadcaster` and delete `RecipeBroadcastJob`

This is the big one. `RecipeBroadcaster` shrinks to delete/rename only. The job is deleted entirely. `RecipeWriteService` calls `kitchen.broadcast_update` directly.

**Files:**
- Rewrite: `app/services/recipe_broadcaster.rb`
- Delete: `app/jobs/recipe_broadcast_job.rb`
- Modify: `app/services/recipe_write_service.rb:53-69`
- Rewrite: `test/services/recipe_broadcaster_test.rb`
- Modify: `test/controllers/recipes_controller_test.rb:492-504`

**Step 1: Rewrite `RecipeBroadcaster` tests**

Replace `test/services/recipe_broadcaster_test.rb` entirely:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipeBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple bread.

      Category: Bread

      ## Dough

      - Flour, 3 cups
      - Water, 1 cup

      Mix and knead.
    MD
  end

  test 'notify_recipe_deleted broadcasts to recipe-specific stream' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: 'Focaccia')
    end
  end

  test 'notify_recipe_deleted replaces content with deleted partial and appends toast' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    calls = []
    capture = ->(*args, **kw) { calls << { args:, kw: } }
    append_calls = []
    append_capture = ->(*args, **kw) { append_calls << { args:, kw: } }

    Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
      Turbo::StreamsChannel.stub :broadcast_append_to, append_capture do
        RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: 'Focaccia')
      end
    end

    deleted_call = calls.find { |c| c[:kw][:partial] == 'recipes/deleted' }
    toast_call = append_calls.find { |c| c[:kw][:partial] == 'shared/toast' }

    assert deleted_call, 'Expected recipes/deleted partial'
    assert toast_call, 'Expected toast notification'
  end

  test 'broadcast_rename broadcasts redirect to old recipe stream' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    calls = []
    capture = ->(*args, **kw) { calls << { args:, kw: } }
    Turbo::StreamsChannel.stub :broadcast_replace_to, capture do
      RecipeBroadcaster.broadcast_rename(
        recipe, new_title: 'Focaccia Genovese',
                redirect_path: '/recipes/focaccia-genovese'
      )
    end

    assert_equal 1, calls.size
    call = calls.first

    assert_equal recipe, call[:args][0]
    assert_equal 'content', call[:args][1]
    assert_equal 'recipe-content', call[:kw][:target]
    assert_equal 'Focaccia Genovese', call[:kw][:locals][:redirect_title]
    assert_equal '/recipes/focaccia-genovese', call[:kw][:locals][:redirect_path]
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: Some tests fail because the old methods still exist and are referenced

**Step 3: Rewrite `RecipeBroadcaster`**

Replace `app/services/recipe_broadcaster.rb`:

```ruby
# frozen_string_literal: true

# Handles targeted recipe-specific broadcasts that cannot be expressed as page
# morphs: delete notifications (recipe no longer exists) and rename redirects
# (recipe URL changed). All other recipe updates use Kitchen#broadcast_update
# for page-refresh morphs.
#
# - RecipeWriteService: sole caller
# - Turbo::StreamsChannel: transport layer for targeted stream pushes
class RecipeBroadcaster
  def self.notify_recipe_deleted(recipe, recipe_title:)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: }
    )
    Turbo::StreamsChannel.broadcast_append_to(
      recipe, 'content',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was deleted" }
    )
  end

  def self.broadcast_rename(old_recipe, new_title:, redirect_path:)
    Turbo::StreamsChannel.broadcast_replace_to(
      old_recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: old_recipe.title,
                redirect_path:,
                redirect_title: new_title }
    )
  end
end
```

**Step 4: Update `RecipeWriteService`**

In `app/services/recipe_write_service.rb`, replace `enqueue_broadcast` and update `destroy`:

Remove the `enqueue_broadcast` private method entirely. Replace calls:

In `create` (line 34), replace `enqueue_broadcast(...)` with `kitchen.broadcast_update`.

In `update` (line 44), replace `enqueue_broadcast(...)` with `kitchen.broadcast_update`.

In `destroy` (lines 53-56), replace the `RecipeBroadcastJob.perform_later(...)` block with:

```ruby
RecipeBroadcaster.notify_recipe_deleted(recipe, recipe_title: recipe.title)
recipe.destroy!
kitchen.broadcast_update
```

Note: `notify_recipe_deleted` must be called before `destroy!` so the recipe record is still valid for the stream key.

Also update the header comment to remove references to `RecipeBroadcastJob`.

**Step 5: Delete `RecipeBroadcastJob`**

```bash
rm app/jobs/recipe_broadcast_job.rb
```

**Step 6: Update recipes controller test**

In `test/controllers/recipes_controller_test.rb`, replace the destroy broadcast test (around lines 472-505). The test that stubs `broadcast_replace_to` and checks for parent recipe broadcasts should be replaced with:

```ruby
test 'destroy broadcasts to kitchen updates stream' do
  log_in

  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    delete recipe_path('focaccia')
  end
end
```

Also update the `create enqueues broadcast job` test (around line 514) to assert `broadcast_refresh_to` instead. Replace with:

```ruby
test 'create broadcasts to kitchen updates stream' do
  log_in

  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    post recipes_path, params: { markdown_source: "# New Bread\n\nCategory: Bread\n\n## Mix\n\n- Flour, 1 cup\n\nMix." }, as: :json
  end
end
```

**Step 7: Run all broadcaster and recipe tests**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: PASS

**Step 8: Commit**

```bash
git add app/services/recipe_broadcaster.rb app/services/recipe_write_service.rb test/services/recipe_broadcaster_test.rb test/controllers/recipes_controller_test.rb
git rm app/jobs/recipe_broadcast_job.rb
git commit -m "refactor: gut RecipeBroadcaster, delete RecipeBroadcastJob, use Kitchen#broadcast_update"
```

---

### Task 5: Simplify `NutritionEntriesController` to JSON-only

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb:16-19,69-83`
- Delete: `app/views/nutrition_entries/upsert.turbo_stream.erb`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js:329-380`
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Update tests — remove turbo stream tests, update save-and-next test**

In `test/controllers/nutrition_entries_controller_test.rb`:

Delete the three turbo stream tests entirely (around lines 369-415):
- `upsert responds with turbo stream when requested`
- `turbo stream response includes updated row data`
- `turbo stream aisle-only update shows incomplete status`

The `save_and_next` test (line 338) stays as-is — it already tests JSON.

**Step 2: Run tests to verify they pass (removal only)**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: PASS (removing tests can't break anything)

**Step 3: Simplify controller**

Replace the `upsert` method in `app/controllers/nutrition_entries_controller.rb`:

```ruby
def upsert
  result = CatalogWriteService.upsert(kitchen: current_kitchen, ingredient_name:, params: catalog_params) # rubocop:disable Rails/SkipsModelValidations
  return render_errors(result.entry) unless result.persisted

  render_json_response
end
```

Delete `render_turbo_stream_update` method (lines 77-83) and the `row_builder` and `resolver` methods (lines 85-91) since they're only used by the turbo stream path. Keep `render_json_response` but remove the `save_and_next` / `next_ingredient` logic from it since that feature is being dropped:

```ruby
def render_json_response
  render json: { status: 'ok' }
end
```

Also delete the `save_and_next` test (line 338) and any `next_ingredient` references since the feature is being dropped.

**Step 4: Delete the turbo stream template**

```bash
rm app/views/nutrition_entries/upsert.turbo_stream.erb
```

**Step 5: Simplify the Stimulus controller**

In `app/javascript/controllers/nutrition_editor_controller.js`:

Replace `performSave` (lines 329-355) to always use JSON:

```javascript
async performSave(andNext) {
  const data = this.collectFormData()
  const errors = this.validateForm(data)

  if (errors.length > 0) {
    showErrors(this.errorsTarget, errors)
    return
  }

  this.disableSaveButtons("Saving\u2026")
  clearErrors(this.errorsTarget)
  this.saving = true

  try {
    await this.saveWithJson(data)
  } catch {
    showErrors(this.errorsTarget, ["Network error. Please check your connection and try again."])
  } finally {
    this.saving = false
    this.enableSaveButtons()
  }
}
```

Simplify `saveWithJson` (lines 382-410) — remove the `next_ingredient` branch:

```javascript
async saveWithJson(payload) {
  const response = await fetch(this.nutritionUrl(this.currentIngredient), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": getCsrfToken()
    },
    body: JSON.stringify(payload)
  })

  if (response.ok) {
    this.dialogTarget.close()
    this.currentIngredient = null
    this.originalSnapshot = null
  } else if (response.status === 422) {
    const result = await response.json()
    showErrors(this.errorsTarget, result.errors)
  } else {
    showErrors(this.errorsTarget, [`Server error (${response.status}). Please try again.`])
  }
}
```

Delete `saveWithTurboStream` (lines 357-380) entirely.

Remove `saveAndNext` method (lines 105-107) and the `andNext` parameter from `performSave`.

Remove save-and-next related targets from `static targets`: `"nextLabel"`, `"nextName"`.

Remove `saveNextButton` from targets and `updateSaveNextVisibility` method (lines 317-327).

Remove the `Turbo` import (line 2) since it's no longer used.

**Step 6: Remove save-and-next button from ingredients view**

In `app/views/ingredients/index.html.erb`, remove the save-and-next button (lines 48-52):

```erb
<button type="button" class="btn btn-primary editor-save-next"
        data-nutrition-editor-target="saveNextButton"
        data-action="click->nutrition-editor#saveAndNext" hidden>
  Save &amp; Next<span data-nutrition-editor-target="nextLabel"></span>
</button>
```

Also remove the hidden `nextName` input from the nutrition editor form partial if it exists. Check `app/views/ingredients/_edit_form.html.erb` or similar.

**Step 7: Run all tests**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: PASS

**Step 8: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb app/javascript/controllers/nutrition_editor_controller.js app/views/ingredients/index.html.erb
git rm app/views/nutrition_entries/upsert.turbo_stream.erb
git commit -m "refactor: nutrition editor JSON-only, drop save-and-next and turbo stream response"
```

---

### Task 6: Unify view stream subscriptions

**Files:**
- Modify: `app/views/homepage/show.html.erb:12`
- Modify: `app/views/menu/show.html.erb:15-16`
- Modify: `app/views/groceries/show.html.erb:15`
- Modify: `app/views/ingredients/index.html.erb:3`
- Modify: `app/views/recipes/show.html.erb:17`

**Step 1: Update all `turbo_stream_from` tags**

Homepage (`app/views/homepage/show.html.erb:12`):
```erb
<%= turbo_stream_from current_kitchen, :updates %>
```

Menu (`app/views/menu/show.html.erb:15-16`) — replace both lines with one:
```erb
<%= turbo_stream_from current_kitchen, :updates %>
```

Groceries (`app/views/groceries/show.html.erb:15`):
```erb
<%= turbo_stream_from current_kitchen, :updates %>
```

Ingredients (`app/views/ingredients/index.html.erb:3`):
```erb
<%= turbo_stream_from current_kitchen, :updates %>
```

Recipe show (`app/views/recipes/show.html.erb:17`) — keep both streams:
```erb
<%= turbo_stream_from current_kitchen, :updates %>
<%= turbo_stream_from @recipe, "content" %>
```

Wait — the homepage and recipe show currently gate the stream subscription behind `current_member?`. The menu and groceries pages already require membership. The ingredients page has it ungated. Let's keep the existing gating patterns:

Homepage:
```erb
<% if current_member? %>
  <%= turbo_stream_from current_kitchen, :updates %>
<% end %>
```

Recipe show:
```erb
<% if current_member? %>
  <%= turbo_stream_from current_kitchen, :updates %>
  <%= turbo_stream_from @recipe, "content" %>
<% end %>
```

**Step 2: Run the full test suite**

Run: `rake test`
Expected: PASS

**Step 3: Commit**

```bash
git add app/views/homepage/show.html.erb app/views/menu/show.html.erb app/views/groceries/show.html.erb app/views/ingredients/index.html.erb app/views/recipes/show.html.erb
git commit -m "refactor: unify all views on single [kitchen, :updates] stream"
```

---

### Task 7: Delete the global `turbo:before-stream-render` hook

**Files:**
- Modify: `app/javascript/application.js:12-35`

**Step 1: Remove the hook**

In `app/javascript/application.js`, delete lines 12-35 (the `turbo:before-stream-render` event listener and its comment). The file should look like:

```javascript
/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Turbo progress bar styles live in style.css
 * (not Turbo's dynamic <style> injection) to satisfy our strict CSP.
 * Pinned in config/importmap.rb as "application".
 */
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

Turbo.config.drive.progressBarDelay = 300

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
```

**Step 2: Verify with manual testing or full suite**

Run: `rake test`
Expected: PASS (no server-side tests depend on this JS hook)

**Step 3: Commit**

```bash
git add app/javascript/application.js
git commit -m "refactor: remove global turbo:before-stream-render hook (morph handles state preservation)"
```

---

### Task 8: Delete `MealPlan.broadcast_refresh` class method

**Files:**
- Modify: `app/models/meal_plan.rb:24-26`
- Test: `test/models/meal_plan_test.rb` (if it tests broadcast_refresh)

**Step 1: Check for remaining callers**

Grep for `broadcast_refresh` across the codebase. After tasks 2-4, there should be zero callers. If any remain, update them to `kitchen.broadcast_update` first.

**Step 2: Delete the method**

Remove from `app/models/meal_plan.rb`:

```ruby
def self.broadcast_refresh(kitchen)
  Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
end
```

Also update the header comment to remove mention of "Turbo page-refresh broadcasts".

**Step 3: Run the full test suite**

Run: `rake test`
Expected: PASS

**Step 4: Commit**

```bash
git add app/models/meal_plan.rb
git commit -m "cleanup: remove MealPlan.broadcast_refresh (replaced by Kitchen#broadcast_update)"
```

---

### Task 9: Update CLAUDE.md and architectural comments

**Files:**
- Modify: `CLAUDE.md`
- Modify: `app/services/recipe_broadcaster.rb` (header comment already updated in Task 4)
- Modify: `app/services/recipe_write_service.rb` (header comment)
- Modify: `app/services/catalog_write_service.rb` (header comment)
- Modify: `app/controllers/concerns/meal_plan_actions.rb` (header comment)
- Modify: `app/models/meal_plan.rb` (header comment)
- Modify: `app/javascript/application.js` (header comment already updated in Task 7)

**Step 1: Update CLAUDE.md**

In the **Architecture** section, update the **ActionCable** paragraph to reflect the new architecture. Replace mentions of `RecipeBroadcaster handles recipe CRUD streams with targeted broadcasts` and `broadcast_refresh_to` with the new model: single `Kitchen#broadcast_update` for all page-refresh morphs, `RecipeBroadcaster` retained only for delete/rename targeted notifications.

Remove mention of `RecipeBroadcastJob` and `RecipeBroadcaster` from the write path section where it says "broadcasts off the request thread via `perform_later`".

**Step 2: Update header comments**

Update header comments on modified files to accurately reflect the new architecture. Remove references to `RecipeBroadcastJob`, targeted broadcasts, and toast notifications where they no longer apply.

`recipe_write_service.rb` header: remove `RecipeBroadcastJob` from collaborators, add `Kitchen#broadcast_update`.

`catalog_write_service.rb` header: change `MealPlan: broadcasts meal plan refresh signals` to `Kitchen: broadcasts page-refresh morphs`.

`meal_plan_actions.rb` header: change "page-refresh broadcast" to reference `Kitchen#broadcast_update`.

`meal_plan.rb` header: remove "Synced across devices via Turbo page-refresh broadcasts" — that's now Kitchen's job.

**Step 3: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Run full suite**

Run: `rake test`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add CLAUDE.md app/services/recipe_write_service.rb app/services/catalog_write_service.rb app/controllers/concerns/meal_plan_actions.rb app/models/meal_plan.rb
git commit -m "docs: update CLAUDE.md and architectural comments for morph-everywhere"
```

---

### Task 10: Final verification

**Step 1: Run the full test suite and lint**

Run: `rake`
Expected: ALL PASS, 0 offenses

**Step 2: Grep for stale references**

```bash
grep -r "meal_plan_updates" app/ test/ --include="*.rb" --include="*.erb"
grep -r "broadcast_replace_to\|broadcast_append_to" app/ --include="*.rb"
grep -r "RecipeBroadcastJob" app/ test/ --include="*.rb"
grep -r 'recipes.*stream\|recipes.*broadcast' app/ --include="*.rb"
```

Expected: No stale references in `app/` or `test/`. The only `broadcast_replace_to` / `broadcast_append_to` calls should be in `RecipeBroadcaster` (delete/rename).

**Step 3: Manual smoke test (optional)**

Start the dev server (`bin/dev`) and verify:
- Edit a recipe → homepage and ingredients pages update via morph
- Delete a recipe while viewing it → "deleted" message appears
- Check/uncheck items on menu → groceries page updates across tabs
- Edit nutrition entry → ingredients table updates after dialog closes

**Step 4: Commit any fixes, then report done**

# Batch Writes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Coordinate broadcast and reconciliation across write services so composed operations (imports, multi-service calls) fire exactly once instead of N times.

**Architecture:** `Kitchen.batch_writes` block scope using `Current` attributes. Services check `Kitchen.batching?` and skip finalization when inside a batch. New `QuickBitesWriteService` completes the service layer. `select_all`/`clear` gain missing reconciliation.

**Tech Stack:** Rails 8, ActiveSupport::CurrentAttributes, Minitest, Turbo Streams

---

### Task 1: Add `batching_kitchen` to Current and `Kitchen.batch_writes`

**Files:**
- Modify: `app/models/current.rb`
- Modify: `app/models/kitchen.rb`
- Create: `test/models/kitchen_batch_writes_test.rb`

**Step 1: Write the failing tests**

Create `test/models/kitchen_batch_writes_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class KitchenBatchWritesTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
  end

  test 'batching? is false outside a batch block' do
    assert_not Kitchen.batching?
  end

  test 'batching? is true inside a batch block' do
    Kitchen.batch_writes(@kitchen) do
      assert Kitchen.batching?
    end
  end

  test 'batching? is false after block exits' do
    Kitchen.batch_writes(@kitchen) { }

    assert_not Kitchen.batching?
  end

  test 'batching? is false after block raises' do
    assert_raises(RuntimeError) do
      Kitchen.batch_writes(@kitchen) { raise 'boom' }
    end

    assert_not Kitchen.batching?
  end

  test 'batch_writes broadcasts once on block exit' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      Kitchen.batch_writes(@kitchen) { }
    end
  end

  test 'batch_writes reconciles once on block exit' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    Kitchen.batch_writes(@kitchen) { }

    plan.reload
    assert_not_includes plan.state['selected_recipes'], 'ghost'
  end

  test 'batch_writes reconciles and broadcasts even when block raises' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      assert_raises(RuntimeError) do
        Kitchen.batch_writes(@kitchen) { raise 'boom' }
      end
    end

    plan.reload
    assert_not_includes plan.state['selected_recipes'], 'ghost'
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/kitchen_batch_writes_test.rb`
Expected: FAIL — `Kitchen.batching?` and `Kitchen.batch_writes` are not defined

**Step 3: Implement `Current.batching_kitchen` and `Kitchen.batch_writes`**

In `app/models/current.rb`, add `batching_kitchen` attribute:

```ruby
attribute :session, :batching_kitchen
```

In `app/models/kitchen.rb`, add class methods after line 26 (before `def broadcast_update`):

```ruby
def self.batch_writes(kitchen)
  Current.batching_kitchen = kitchen
  yield
ensure
  Current.batching_kitchen = nil
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry { plan.reconcile! }
  kitchen.broadcast_update
end

def self.batching?
  Current.batching_kitchen.present?
end
```

Update the header comment on Kitchen to mention `batch_writes`.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/kitchen_batch_writes_test.rb`
Expected: all pass

**Step 5: Run full suite + lint**

Run: `bundle exec rubocop app/models/current.rb app/models/kitchen.rb test/models/kitchen_batch_writes_test.rb && rake test`

**Step 6: Commit**

```bash
git add app/models/current.rb app/models/kitchen.rb test/models/kitchen_batch_writes_test.rb
git commit -m "feat: add Kitchen.batch_writes for coordinated reconcile + broadcast"
```

---

### Task 2: Guard RecipeWriteService finalization

**Files:**
- Modify: `app/services/recipe_write_service.rb`
- Modify: `test/services/recipe_write_service_test.rb`

**Step 1: Write the failing test**

Add to `test/services/recipe_write_service_test.rb`:

```ruby
test 'create skips broadcast and reconcile when batching' do
  Kitchen.batch_writes(@kitchen) do
    assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
      RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
    end
  end
end
```

Note: `assert_no_turbo_stream_broadcasts` may not exist — check `Turbo::Broadcastable::TestHelper`. If it doesn't, use a counting approach:

```ruby
test 'create skips broadcast when batching' do
  broadcast_count = 0
  @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
  Kitchen.stub(:batching?, true) do
    RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')
  end
  assert_equal 0, broadcast_count
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n test_create_skips_broadcast_when_batching`
Expected: FAIL — broadcast fires even when batching

**Step 3: Extract `finalize` guard in RecipeWriteService**

Replace the `post_write_cleanup` + `kitchen.broadcast_update` pattern in `create`, `update`, `destroy` with a single `finalize` call. Replace lines 35-36, 46-47, 55-56 with `finalize` calls, and add:

```ruby
def finalize
  post_write_cleanup
  return if Kitchen.batching?

  kitchen.broadcast_update
end
```

Also guard the reconcile inside `post_write_cleanup` — rename `prune_stale_meal_plan_items` to guard:

```ruby
def post_write_cleanup
  Category.cleanup_orphans(kitchen)
  return if Kitchen.batching?

  prune_stale_meal_plan_items
end
```

Wait — `Category.cleanup_orphans` should always run (it's a local DB cleanup, not a broadcast). Only reconcile and broadcast should be deferred. So:

```ruby
def finalize
  Category.cleanup_orphans(kitchen)
  return if Kitchen.batching?

  prune_stale_meal_plan_items
  kitchen.broadcast_update
end
```

This replaces both `post_write_cleanup` and the broadcast call. Remove `post_write_cleanup` entirely.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: all pass (existing tests still work because standalone calls aren't batching)

**Step 5: Run full suite + lint**

Run: `bundle exec rubocop app/services/recipe_write_service.rb && ruby -Itest test/services/recipe_write_service_test.rb`

**Step 6: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_test.rb
git commit -m "feat: guard RecipeWriteService finalization behind Kitchen.batching?"
```

---

### Task 3: Guard CatalogWriteService finalization

**Files:**
- Modify: `app/services/catalog_write_service.rb`
- Modify: `test/services/catalog_write_service_test.rb`

**Step 1: Write the failing test**

Add to `test/services/catalog_write_service_test.rb`:

```ruby
test 'upsert skips broadcast when batching' do
  broadcast_count = 0
  @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
  Kitchen.stub(:batching?, true) do
    CatalogWriteService.upsert(
      kitchen: @kitchen, ingredient_name: 'flour',
      params: { aisle: 'Baking', basis_grams: 125.0, nutrients: {} }
    )
  end
  assert_equal 0, broadcast_count
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/catalog_write_service_test.rb -n test_upsert_skips_broadcast_when_batching`
Expected: FAIL

**Step 3: Guard CatalogWriteService**

In `upsert` and `destroy`, wrap reconcile + broadcast:

```ruby
def upsert(params:)
  entry = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name:)
  entry.assign_from_params(**params, sources: WEB_SOURCE)
  return Result.new(entry:, persisted: false) unless entry.save

  AisleWriteService.sync_new_aisle(kitchen:, aisle: entry.aisle) if entry.aisle
  recalculate_recipes_for(names: [ingredient_name]) if entry.basis_grams.present?
  finalize

  Result.new(entry:, persisted: true)
end

def destroy
  entry = IngredientCatalog.find_by!(kitchen:, ingredient_name:)
  entry.destroy!
  recalculate_recipes_for(names: [ingredient_name])
  finalize
  Result.new(entry:, persisted: true)
end
```

Add private `finalize`:

```ruby
def finalize
  return if Kitchen.batching?

  reconcile_meal_plan
  kitchen.broadcast_update
end
```

`bulk_import` is unchanged — it already skips both.

**Step 4: Run tests**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: all pass

**Step 5: Lint + full test**

Run: `bundle exec rubocop app/services/catalog_write_service.rb && ruby -Itest test/services/catalog_write_service_test.rb`

**Step 6: Commit**

```bash
git add app/services/catalog_write_service.rb test/services/catalog_write_service_test.rb
git commit -m "feat: guard CatalogWriteService finalization behind Kitchen.batching?"
```

---

### Task 4: Guard MealPlanWriteService + add reconcile to select_all/clear

**Files:**
- Modify: `app/services/meal_plan_write_service.rb`
- Modify: `test/services/meal_plan_write_service_test.rb`

**Step 1: Write failing tests for reconcile in select_all and clear**

Add to `test/services/meal_plan_write_service_test.rb`:

```ruby
test 'select_all reconciles stale selections' do
  @plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

  MealPlanWriteService.select_all(
    kitchen: @kitchen, recipe_slugs: %w[real], quick_bite_slugs: []
  )

  @plan.reload
  assert_not_includes @plan.state['selected_recipes'], 'ghost'
end

test 'clear reconciles stale selections' do
  @plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

  MealPlanWriteService.clear(kitchen: @kitchen)

  @plan.reload
  assert_not_includes @plan.state['selected_recipes'], 'ghost'
end

test 'apply_action skips broadcast when batching' do
  broadcast_count = 0
  @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
  Kitchen.stub(:batching?, true) do
    MealPlanWriteService.apply_action(
      kitchen: @kitchen, action_type: 'check',
      item: 'flour', checked: true
    )
  end
  assert_equal 0, broadcast_count
end
```

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: reconcile tests fail (select_all/clear don't reconcile), batching test fails

**Step 3: Add reconcile to select_all/clear + guard all finalization**

```ruby
def apply_action(action_type:, **params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **params)
    plan.reconcile!
  end
  finalize
end

def select_all(recipe_slugs:, quick_bite_slugs:)
  mutate_plan do |plan|
    plan.select_all!(recipe_slugs, quick_bite_slugs)
    plan.reconcile!
  end
  finalize
end

def clear
  mutate_plan do |plan|
    plan.clear_selections!
    plan.reconcile!
  end
  finalize
end

def reconcile
  mutate_plan(&:reconcile!)
  finalize
end

private

attr_reader :kitchen

def finalize
  return if Kitchen.batching?

  kitchen.broadcast_update
end

def mutate_plan
  plan = MealPlan.for_kitchen(kitchen)
  plan.with_optimistic_retry { yield plan }
  plan
end
```

Note: MealPlanWriteService's reconcile happens *inside* `mutate_plan` (within the optimistic retry), not in `finalize`. The batching guard only suppresses the broadcast. The `batch_writes` block's own reconcile at the end handles the final pass.

Actually — we should also guard the per-call reconcile inside `mutate_plan` when batching, since `batch_writes` will do a final reconcile. But `select_all` and `clear` need reconcile for correctness even standalone... The cleanest approach: always reconcile inside `mutate_plan` (it's cheap and correct), only guard the broadcast. The `batch_writes` final reconcile is the last-pass cleanup.

Wait — for RecipeWriteService importing 30 recipes, each `create` calls `prune_stale_meal_plan_items` which is a reconcile. That's the N² query problem from the issue. So we DO need to skip reconcile when batching. The design says we skip both reconcile and broadcast when batching.

So for MealPlanWriteService, guard reconcile too:

```ruby
def apply_action(action_type:, **params)
  mutate_plan do |plan|
    plan.apply_action(action_type, **params)
    plan.reconcile! unless Kitchen.batching?
  end
  finalize
end

def select_all(recipe_slugs:, quick_bite_slugs:)
  mutate_plan do |plan|
    plan.select_all!(recipe_slugs, quick_bite_slugs)
    plan.reconcile! unless Kitchen.batching?
  end
  finalize
end

def clear
  mutate_plan do |plan|
    plan.clear_selections!
    plan.reconcile! unless Kitchen.batching?
  end
  finalize
end

def reconcile
  mutate_plan do |plan|
    plan.reconcile! unless Kitchen.batching?
  end
  finalize
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: all pass

**Step 5: Lint**

Run: `bundle exec rubocop app/services/meal_plan_write_service.rb`

**Step 6: Commit**

```bash
git add app/services/meal_plan_write_service.rb test/services/meal_plan_write_service_test.rb
git commit -m "feat: add reconcile to select_all/clear, guard finalization behind batching"
```

---

### Task 5: Create QuickBitesWriteService

**Files:**
- Create: `app/services/quick_bites_write_service.rb`
- Create: `test/services/quick_bites_write_service_test.rb`

**Step 1: Write the failing tests**

Create `test/services/quick_bites_write_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class QuickBitesWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
  end

  test 'update persists content to kitchen' do
    QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")

    assert_equal "Snacks:\n- Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update clears content when blank' do
    @kitchen.update!(quick_bites_content: 'old')

    QuickBitesWriteService.update(kitchen: @kitchen, content: '')

    assert_nil @kitchen.reload.quick_bites_content
  end

  test 'update returns warnings from parser' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "Snacks:\n- Goldfish\ngarbage"
    )

    assert_equal 1, result.warnings.size
    assert_match(/line 3/i, result.warnings.first)
  end

  test 'update returns empty warnings for valid content' do
    result = QuickBitesWriteService.update(
      kitchen: @kitchen, content: "Snacks:\n- Goldfish"
    )

    assert_empty result.warnings
  end

  test 'update reconciles meal plan' do
    @kitchen.update!(quick_bites_content: "Snacks:\n- Nachos: Chips\n- Pretzels: Pretzels")
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'quick_bite', slug: 'nachos', selected: true)
    plan.apply_action('select', type: 'quick_bite', slug: 'pretzels', selected: true)

    QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Nachos: Chips")

    plan.reload
    assert_includes plan.state['selected_quick_bites'], 'nachos'
    assert_not_includes plan.state['selected_quick_bites'], 'pretzels'
  end

  test 'update broadcasts to kitchen updates stream' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")
    end
  end

  test 'update skips broadcast when batching' do
    broadcast_count = 0
    @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }
    Kitchen.stub(:batching?, true) do
      QuickBitesWriteService.update(kitchen: @kitchen, content: "Snacks:\n- Goldfish")
    end
    assert_equal 0, broadcast_count
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/quick_bites_write_service_test.rb`
Expected: FAIL — class not defined

**Step 3: Implement QuickBitesWriteService**

Create `app/services/quick_bites_write_service.rb`:

```ruby
# frozen_string_literal: true

# Orchestrates quick bites content updates. Owns persistence to
# Kitchen#quick_bites_content, parse validation (returning warnings),
# meal plan reconciliation, and broadcast. Parallels RecipeWriteService
# and CatalogWriteService — controllers call class methods, never
# inline post-save logic.
#
# - Kitchen#quick_bites_content: raw markdown storage
# - FamilyRecipes.parse_quick_bites_content: parser returning warnings
# - MealPlan#reconcile!: prunes stale selections after content changes
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(content:)
    stored = content.to_s.presence
    warnings = parse_warnings(stored)
    kitchen.update!(quick_bites_content: stored)
    finalize
    Result.new(warnings:)
  end

  private

  attr_reader :kitchen

  def parse_warnings(content)
    return [] unless content

    FamilyRecipes.parse_quick_bites_content(content).warnings
  end

  def finalize
    return if Kitchen.batching?

    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { plan.reconcile! }
    kitchen.broadcast_update
  end
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/services/quick_bites_write_service_test.rb`
Expected: all pass

**Step 5: Lint**

Run: `bundle exec rubocop app/services/quick_bites_write_service.rb test/services/quick_bites_write_service_test.rb`

**Step 6: Commit**

```bash
git add app/services/quick_bites_write_service.rb test/services/quick_bites_write_service_test.rb
git commit -m "feat: add QuickBitesWriteService for consistent service layer"
```

---

### Task 6: Update MenuController to use QuickBitesWriteService

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `test/controllers/menu_controller_test.rb`

**Step 1: Verify existing tests pass before refactoring**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: all pass

**Step 2: Update MenuController#update_quick_bites**

Replace the `update_quick_bites` action (lines 51-59) with:

```ruby
def update_quick_bites
  result = QuickBitesWriteService.update(
    kitchen: current_kitchen, content: params[:content]
  )

  body = { status: 'ok' }
  body[:warnings] = result.warnings if result.warnings.any?
  render json: body
end
```

Remove the private `parse_quick_bites` method (lines 64-68) — it's no longer needed.

**Step 3: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: all pass — behavior is identical, just routed through the service

**Step 4: Lint**

Run: `bundle exec rubocop app/controllers/menu_controller.rb`

**Step 5: Commit**

```bash
git add app/controllers/menu_controller.rb
git commit -m "refactor: MenuController delegates quick bites writes to QuickBitesWriteService"
```

---

### Task 7: Update ImportService to use batch_writes + QuickBitesWriteService

**Files:**
- Modify: `app/services/import_service.rb`
- Modify: `test/services/import_service_test.rb`

**Step 1: Write integration test for single broadcast**

Add to `test/services/import_service_test.rb`:

```ruby
require 'turbo/broadcastable/test_helper'

# Add to class:
include Turbo::Broadcastable::TestHelper

test 'multi-recipe import produces exactly one broadcast' do
  broadcast_count = 0
  @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }

  content = { 'recipes/' => nil }
  3.times do |i|
    content["recipes/Recipe#{i}.md"] = simple_recipe("Recipe #{i}")
  end

  import_zip_with_entries(content)

  assert_equal 1, broadcast_count
  assert_equal 3, @kitchen.recipes.count
end
```

Check if `import_zip_with_entries` helper exists. If not, use the existing test pattern for ZIP imports. Look at how ZIP fixtures are built in the existing tests.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/import_service_test.rb -n test_multi_recipe_import_produces_exactly_one_broadcast`
Expected: FAIL — broadcast fires once per recipe + once at end

**Step 3: Wrap import in batch_writes**

Update `import` method:

```ruby
def import
  zip_file = files.find { |f| File.extname(f.original_filename).casecmp('.zip').zero? }
  Kitchen.batch_writes(kitchen) do
    zip_file ? import_zip(zip_file) : files.each { |f| import_recipe_file(f, 'Miscellaneous') }
  end
  build_result
end
```

Remove the `kitchen.broadcast_update` call on what was line 40.

Update `import_quick_bites` to use the service:

```ruby
def import_quick_bites(content)
  return if content.blank?

  QuickBitesWriteService.update(kitchen:, content:)
  @quick_bites_imported = true
end
```

**Step 4: Run all import tests**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: all pass

**Step 5: Run full suite + lint**

Run: `bundle exec rubocop app/services/import_service.rb && rake test`

**Step 6: Commit**

```bash
git add app/services/import_service.rb test/services/import_service_test.rb
git commit -m "feat: ImportService uses batch_writes for single reconcile + broadcast"
```

---

### Task 8: Update CLAUDE.md and close issue

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update Architecture section in CLAUDE.md**

Add a note about `Kitchen.batch_writes` to the write path section. After the bullet about write services:

```
- `Kitchen.batch_writes(kitchen)` — block scope that defers reconciliation
  and broadcast to a single pass on block exit. Services check
  `Kitchen.batching?` and skip their own finalize when true.
```

Add `QuickBitesWriteService` to the service list:

```
- `QuickBitesWriteService` — quick bites content persistence, parse
  validation, reconciliation, broadcast.
```

**Step 2: Final full suite run**

Run: `rake`
Expected: all tests pass, 0 RuboCop offenses

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with batch_writes and QuickBitesWriteService"
```

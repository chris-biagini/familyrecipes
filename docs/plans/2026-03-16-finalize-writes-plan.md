# Centralize Write Finalization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize the post-write finalization pipeline (orphan cleanup, meal plan reconciliation, broadcast) into a single `Kitchen.finalize_writes` class method, replacing 7 per-service implementations.

**Architecture:** Every write service currently implements its own finalization: checking `Kitchen.batching?`, optionally reconciling the meal plan, and broadcasting. This plan extracts that into `Kitchen.finalize_writes(kitchen)` (public, respects batching guard) backed by `Kitchen.run_finalization` (private, shared with `batch_writes`). Services replace their custom finalize methods with a single call. No new files — just modifications.

**Tech Stack:** Rails 8, Minitest, Turbo Streams

---

## File Map

| File | Action | Responsibility change |
|------|--------|-----------------------|
| `app/models/kitchen.rb` | Modify | Add `finalize_writes` + `run_finalization`, refactor `finalize_batch` |
| `app/services/recipe_write_service.rb` | Modify | Replace `finalize` + `prune_stale_meal_plan_items` with `Kitchen.finalize_writes` |
| `app/services/catalog_write_service.rb` | Modify | Replace `finalize` + `reconcile_meal_plan` with `Kitchen.finalize_writes` |
| `app/services/quick_bites_write_service.rb` | Modify | Replace `finalize` with `Kitchen.finalize_writes` |
| `app/services/meal_plan_write_service.rb` | Modify | Replace `finalize`, drop inline `reconcile_plan`, drop unused `reconcile` method |
| `app/services/aisle_write_service.rb` | Modify | Replace `kitchen.broadcast_update` with `Kitchen.finalize_writes` |
| `app/services/category_write_service.rb` | Modify | Replace `kitchen.broadcast_update` with `Kitchen.finalize_writes` |
| `app/services/tag_write_service.rb` | Modify | Replace `kitchen.broadcast_update` with `Kitchen.finalize_writes` |
| `test/models/kitchen_batch_writes_test.rb` | Modify | Add tests for `finalize_writes` and orphan cleanup in batch finalization |
| `CLAUDE.md` | Modify | Update write path documentation |

---

### Task 1: Add Kitchen.finalize_writes with tests

**Files:**
- Modify: `test/models/kitchen_batch_writes_test.rb`
- Modify: `app/models/kitchen.rb`

- [ ] **Step 1: Write failing tests for Kitchen.finalize_writes**

Add these tests to `test/models/kitchen_batch_writes_test.rb`:

```ruby
test 'finalize_writes broadcasts when not batching' do
  assert_turbo_stream_broadcasts [@kitchen, :updates] do
    Kitchen.finalize_writes(@kitchen)
  end
end

test 'finalize_writes skips everything when batching' do
  broadcast_count = 0
  @kitchen.define_singleton_method(:broadcast_update) { broadcast_count += 1 }

  Kitchen.stub(:batching?, true) do
    Kitchen.finalize_writes(@kitchen)
  end

  assert_equal 0, broadcast_count
end

test 'finalize_writes reconciles meal plan' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'ghost', selected: true)

  Kitchen.finalize_writes(@kitchen)

  plan.reload

  assert_not_includes plan.selected_recipes_set, 'ghost'
end

test 'finalize_writes cleans up orphan categories' do
  Category.create!(name: 'Empty', slug: 'empty', position: 99, kitchen: @kitchen)

  Kitchen.finalize_writes(@kitchen)

  assert_nil Category.find_by(slug: 'empty', kitchen: @kitchen)
end

test 'finalize_writes cleans up orphan tags' do
  Tag.create!(name: 'orphan', kitchen: @kitchen)

  Kitchen.finalize_writes(@kitchen)

  assert_nil Tag.find_by(name: 'orphan', kitchen: @kitchen)
end

test 'batch_writes runs orphan cleanup on block exit' do
  Category.create!(name: 'Empty', slug: 'empty', position: 99, kitchen: @kitchen)

  Kitchen.batch_writes(@kitchen) { :noop }

  assert_nil Category.find_by(slug: 'empty', kitchen: @kitchen)
end
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `ruby -Itest test/models/kitchen_batch_writes_test.rb`
Expected: FAIL — `Kitchen.finalize_writes` is not defined.

- [ ] **Step 3: Implement Kitchen.finalize_writes and run_finalization**

In `app/models/kitchen.rb`, replace `finalize_batch` and add the new methods:

```ruby
def self.finalize_writes(kitchen)
  return if batching?

  run_finalization(kitchen)
end

def self.run_finalization(kitchen)
  Category.cleanup_orphans(kitchen)
  Tag.cleanup_orphans(kitchen)
  MealPlan.reconcile_kitchen!(kitchen)
  kitchen.broadcast_update
end
private_class_method :run_finalization
```

Update `batch_writes` ensure block to call `run_finalization` instead of `finalize_batch`. Delete the old `finalize_batch` method.

```ruby
def self.batch_writes(kitchen)
  Current.batching_kitchen = kitchen
  yield
ensure
  Current.batching_kitchen = nil
  run_finalization(kitchen)
end
```

Update the Kitchen header comment — replace the line about write services checking `Kitchen.batching?` with:

```
# Kitchen.finalize_writes(kitchen) is the single post-write entry point for
# all write services: orphan cleanup, meal plan reconciliation, broadcast.
# Kitchen.batch_writes defers finalization to block exit via the same pipeline.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/kitchen_batch_writes_test.rb`
Expected: All PASS (existing + new).

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All pass. No other code calls `finalize_batch` (it was private).

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop app/models/kitchen.rb test/models/kitchen_batch_writes_test.rb`

- [ ] **Step 7: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_batch_writes_test.rb
git commit -m "feat: add Kitchen.finalize_writes as single post-write entry point

Extracts run_finalization (orphan cleanup + reconcile + broadcast) as a
shared pipeline used by both finalize_writes (respects batching guard)
and batch_writes (runs unconditionally on block exit). This is the
foundation for migrating all write services off custom finalize methods."
```

---

### Task 2: Migrate RecipeWriteService, CatalogWriteService, QuickBitesWriteService

These three services have identical finalization patterns: check batching → reconcile → broadcast. Replace with `Kitchen.finalize_writes`.

**Files:**
- Modify: `app/services/recipe_write_service.rb`
- Modify: `app/services/catalog_write_service.rb`
- Modify: `app/services/quick_bites_write_service.rb`

**Note on behavioral change:** Currently, `RecipeWriteService#finalize` runs `Category.cleanup_orphans` and `Tag.cleanup_orphans` *unconditionally* — even during batching — before the batching guard. After this migration, orphan cleanup is deferred to batch exit (via `run_finalization`). This is an improvement: a 50-recipe ZIP import currently runs 50 orphan cleanup passes; after the change, it runs one. Orphan cleanup is also now part of every write service's finalization (not just recipes), which is correct — any write that deletes a recipe could orphan a category.

- [ ] **Step 1: Migrate RecipeWriteService**

In `app/services/recipe_write_service.rb`, replace the `finalize` and `prune_stale_meal_plan_items` methods (lines 141-159) with:

```ruby
def finalize
  Kitchen.finalize_writes(kitchen)
end
```

Update header comment — remove the line about `MealPlan#reconcile!` from the collaborators list. Replace with `Kitchen.finalize_writes: centralized post-write finalization`.

- [ ] **Step 2: Run RecipeWriteService tests**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: All pass. The "create broadcasts" tests pass because `finalize_writes` broadcasts. The "create skips broadcast when batching" test passes because `finalize_writes` checks `Kitchen.batching?`. The "destroy prunes deleted recipe from meal plan" test passes because `finalize_writes` reconciles.

- [ ] **Step 3: Migrate CatalogWriteService**

In `app/services/catalog_write_service.rb`, replace the `finalize` and `reconcile_meal_plan` methods (lines 91-100) with:

```ruby
def finalize
  Kitchen.finalize_writes(kitchen)
end
```

Update header comment — remove `MealPlan#reconcile!` collaborator, add `Kitchen.finalize_writes`.

- [ ] **Step 4: Run CatalogWriteService tests**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass.

- [ ] **Step 5: Migrate QuickBitesWriteService**

In `app/services/quick_bites_write_service.rb`, replace the `finalize` method (lines 49-54) with:

```ruby
def finalize
  Kitchen.finalize_writes(kitchen)
end
```

Update header comment — remove `MealPlan#reconcile!` and `Kitchen#broadcast_update` collaborators, add `Kitchen.finalize_writes`.

- [ ] **Step 6: Run QuickBitesWriteService tests**

Run: `ruby -Itest test/services/quick_bites_write_service_test.rb`
Expected: All pass.

- [ ] **Step 7: Lint**

Run: `bundle exec rubocop app/services/recipe_write_service.rb app/services/catalog_write_service.rb app/services/quick_bites_write_service.rb`

- [ ] **Step 8: Full test suite**

Run: `rake test`
Expected: All pass.

- [ ] **Step 9: Commit**

```bash
git add app/services/recipe_write_service.rb app/services/catalog_write_service.rb app/services/quick_bites_write_service.rb
git commit -m "refactor: migrate Recipe/Catalog/QuickBites write services to Kitchen.finalize_writes

Replaces per-service finalize methods (batching guard, reconcile,
broadcast) with a single Kitchen.finalize_writes call. Orphan cleanup
(Category + Tag), previously only in RecipeWriteService, now runs for
all writes via the centralized pipeline — harmless no-ops when nothing
is orphaned, but correct during batch import where recipe deletes could
orphan categories."
```

---

### Task 3: Migrate MealPlanWriteService

This service is different: it reconciles *inside* the optimistic retry block, then only broadcasts in `finalize`. The inline reconciliation can be removed because `Kitchen.finalize_writes` → `MealPlan.reconcile_kitchen!` loads a fresh plan with its own retry — actually more correct for concurrent modification.

**Files:**
- Modify: `app/services/meal_plan_write_service.rb`

- [ ] **Step 1: Migrate MealPlanWriteService**

Replace the entire file content. The new version:

```ruby
# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items), select-all, and clear. Owns optimistic-locking retry
# for MealPlan state changes. Post-write finalization (reconciliation,
# broadcast) is handled by Kitchen.finalize_writes.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - Kitchen.finalize_writes: centralized post-write finalization
class MealPlanWriteService
  def self.apply_action(kitchen:, action_type:, **params)
    new(kitchen:).apply_action(action_type:, **params)
  end

  def self.select_all(kitchen:, recipe_slugs:, quick_bite_slugs:)
    new(kitchen:).select_all(recipe_slugs:, quick_bite_slugs:)
  end

  def self.clear(kitchen:)
    new(kitchen:).clear
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def apply_action(action_type:, **params)
    mutate_plan { |plan| plan.apply_action(action_type, **params) }
    Kitchen.finalize_writes(kitchen)
  end

  def select_all(recipe_slugs:, quick_bite_slugs:)
    mutate_plan { |plan| plan.select_all!(recipe_slugs, quick_bite_slugs) }
    Kitchen.finalize_writes(kitchen)
  end

  def clear
    mutate_plan { |plan| plan.clear_selections! }
    Kitchen.finalize_writes(kitchen)
  end

  private

  attr_reader :kitchen

  def mutate_plan
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end
end
```

Key changes vs. the current file:
- Removed `reconcile` public method (unused — callers use `Kitchen.finalize_writes` or `MealPlan.reconcile_kitchen!` directly)
- Removed `finalize` private method
- Removed `reconcile_plan` private method (inline reconciliation inside retry block — now handled by `finalize_writes`)
- Each public method calls `Kitchen.finalize_writes(kitchen)` after `mutate_plan`

- [ ] **Step 2: Run MealPlanWriteService tests**

Run: `ruby -Itest test/services/meal_plan_write_service_test.rb`
Expected: All pass.

- "apply_action persists the mutation" — `mutate_plan` still saves. PASS.
- "apply_action reconciles stale selections" — `finalize_writes` reconciles. PASS.
- "apply_action broadcasts" — `finalize_writes` broadcasts. PASS.
- "apply_action retries on StaleObjectError" — retry is still in `mutate_plan`. PASS.
- "apply_action skips broadcast when batching" — `finalize_writes` returns early. PASS.
- "select_all reconciles stale checked-off items" — `finalize_writes` reconciles. PASS.
- "clear reconciles stale checked-off items" — `finalize_writes` reconciles. PASS.

- [ ] **Step 3: Lint**

Run: `bundle exec rubocop app/services/meal_plan_write_service.rb`

- [ ] **Step 4: Full test suite**

Run: `rake test`

- [ ] **Step 5: Commit**

```bash
git add app/services/meal_plan_write_service.rb
git commit -m "refactor: migrate MealPlanWriteService to Kitchen.finalize_writes

Removes inline reconcile_plan (ran inside optimistic retry) — reconciliation
now happens in finalize_writes via MealPlan.reconcile_kitchen!, which loads
a fresh plan with its own retry. Removes the unused public reconcile method.
Service shrinks from 79 to ~48 lines."
```

---

### Task 4: Migrate AisleWriteService, CategoryWriteService, TagWriteService

These three services broadcast directly without a finalize method and without checking `Kitchen.batching?`. Replace with `Kitchen.finalize_writes`.

**Files:**
- Modify: `app/services/aisle_write_service.rb`
- Modify: `app/services/category_write_service.rb`
- Modify: `app/services/tag_write_service.rb`

- [ ] **Step 1: Migrate AisleWriteService**

In `app/services/aisle_write_service.rb`, replace `kitchen.broadcast_update` (line 47) with `Kitchen.finalize_writes(kitchen)`.

Update header comment — replace `Kitchen#broadcast_update` collaborator with `Kitchen.finalize_writes`.

- [ ] **Step 2: Run AisleWriteService tests**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: All pass. "update_order broadcasts" passes because `finalize_writes` broadcasts. "does not broadcast on validation failure" passes because early return happens before `finalize_writes`.

- [ ] **Step 3: Migrate CategoryWriteService**

In `app/services/category_write_service.rb`, replace `kitchen.broadcast_update` (line 36) with `Kitchen.finalize_writes(kitchen)`.

Update header comment — replace `Kitchen#broadcast_update` collaborator with `Kitchen.finalize_writes`.

- [ ] **Step 4: Run CategoryWriteService tests**

Run: `ruby -Itest test/services/category_write_service_test.rb`
Expected: All pass.

- [ ] **Step 5: Migrate TagWriteService**

In `app/services/tag_write_service.rb`, replace `kitchen.broadcast_update` (line 23) with `Kitchen.finalize_writes(kitchen)`.

Update header comment — replace `Kitchen#broadcast_update` collaborator with `Kitchen.finalize_writes`.

- [ ] **Step 6: Run TagWriteService tests**

Run: `ruby -Itest test/services/tag_write_service_test.rb`
Expected: All pass.

- [ ] **Step 7: Lint**

Run: `bundle exec rubocop app/services/aisle_write_service.rb app/services/category_write_service.rb app/services/tag_write_service.rb`

- [ ] **Step 8: Full test suite**

Run: `rake test`

- [ ] **Step 9: Commit**

```bash
git add app/services/aisle_write_service.rb app/services/category_write_service.rb app/services/tag_write_service.rb
git commit -m "refactor: migrate Aisle/Category/Tag write services to Kitchen.finalize_writes

These three services previously broadcast directly without checking
Kitchen.batching? — a latent double-broadcast risk if ever called inside
a batch. Kitchen.finalize_writes handles the batching guard, orphan
cleanup, reconciliation, and broadcast uniformly."
```

---

### Task 5: Update MealPlan header comment and CLAUDE.md

**Files:**
- Modify: `app/models/meal_plan.rb` (header comment only)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update MealPlan header comment**

In `app/models/meal_plan.rb`, update the header comment (lines 1-10). Remove the line about `.reconcile_kitchen!` being the "canonical post-write reconciliation entry point" — that's now `Kitchen.finalize_writes`. Replace with:

```ruby
# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, checked-off items. Both menu and
# groceries pages read/write this model.
#
# - .reconcile_kitchen!(kitchen) — computes visible ingredient names (via
#   ShoppingListBuilder) and prunes stale checked-off/selection state.
#   Called by Kitchen.run_finalization; not called directly by services.
# - #reconcile!(visible_names:) — inner pruning for callers already holding
#   the plan inside a retry block.
```

- [ ] **Step 2: Update CLAUDE.md write path section**

In the **Write path** section under **Architecture**, update the `Kitchen.batch_writes` bullet to describe the centralized pipeline:

Replace:
```
- `Kitchen.batch_writes(kitchen)` — block scope that defers reconciliation
  and broadcast to a single pass on block exit. Services check
  `Kitchen.batching?` and skip their own finalize when true.
```

With:
```
- `Kitchen.finalize_writes(kitchen)` — single post-write entry point for
  all write services: orphan cleanup (categories + tags), meal plan
  reconciliation, and broadcast. Respects `Kitchen.batching?` guard.
- `Kitchen.batch_writes(kitchen)` — block scope that defers finalization
  to a single pass on block exit. Write services inside a batch call
  `finalize_writes` as usual — it returns early, and the batch runs the
  same pipeline once on exit.
```

- [ ] **Step 3: Lint**

Run: `bundle exec rubocop app/models/meal_plan.rb`

- [ ] **Step 4: Full test suite**

Run: `rake test`
Expected: All pass (comment-only changes to meal_plan.rb).

Run: `bundle exec rubocop`
Expected: 0 offenses.

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan.rb CLAUDE.md
git commit -m "docs: update MealPlan comment and CLAUDE.md for Kitchen.finalize_writes"
```

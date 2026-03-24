# MealPlan Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose MealPlan's single JSON blob into four normalized tables, fix broadcast brittleness, and push work from Ruby to SQLite.

**Architecture:** Four new AR models (`MealPlanSelection`, `OnHandEntry`, `CustomGroceryItem`, `CookHistoryEntry`) replace the `meal_plans.state` JSON column. SM-2 adaptive interval logic moves to `OnHandEntry` instance methods. Broadcasts coalesce via `Current.broadcast_pending` + `after_action`.

**Tech Stack:** Rails 8, SQLite (COLLATE NOCASE, date functions), ActiveSupport::CurrentAttributes, acts_as_tenant, Minitest.

**Spec:** `docs/superpowers/specs/2026-03-24-mealplan-decomposition-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|----------------|
| `db/migrate/014_decompose_meal_plan.rb` | Create 4 tables, migrate JSON data, drop `state`/`lock_version` |
| `app/models/meal_plan_selection.rb` | Menu selections (recipe/QB toggle) |
| `app/models/on_hand_entry.rb` | Inventory tracking with SM-2 adaptive intervals |
| `app/models/custom_grocery_item.rb` | User-added grocery items |
| `app/models/cook_history_entry.rb` | Recipe cook log for dinner picker |
| `test/models/meal_plan_selection_test.rb` | Selection model tests |
| `test/models/on_hand_entry_test.rb` | SM-2 logic + scope tests |
| `test/models/custom_grocery_item_test.rb` | Custom item model tests |
| `test/models/cook_history_entry_test.rb` | Cook history model tests |

### Modified Files

| File | What Changes |
|------|-------------|
| `app/models/meal_plan.rb` | Near-total rewrite: 517 → ~100 lines. Becomes thin coordinator. |
| `app/models/kitchen.rb` | Add `has_many` associations, rewrite `run_finalization` |
| `app/models/current.rb` | Add `broadcast_pending` attribute |
| `app/services/meal_plan_write_service.rb` | Full rewrite: delegate to AR models, remove recursion |
| `app/services/shopping_list_builder.rb` | Query AR models instead of JSON arrays |
| `app/services/cook_history_weighter.rb` | Consume AR objects instead of JSON hashes |
| `app/services/recipe_write_service.rb` | Move RecipeBroadcaster calls to after_commit |
| `app/services/recipe_broadcaster.rb` | Update header comment only |
| `app/controllers/application_controller.rb` | Add `after_action :flush_broadcast` |
| `app/controllers/groceries_controller.rb` | Read from AR models in `show` |
| `app/controllers/menu_controller.rb` | Read from AR models in `show` |
| `app/helpers/groceries_helper.rb` | Consume AR objects, update constant refs |
| `app/helpers/search_data_helper.rb` | Query AR models for ingredient/custom corpus |
| `app/views/groceries/_shopping_list.html.erb` | Replace hash lookups with indexed AR data |
| `test/test_helper.rb` | Add helpers for new models, clean new tables |
| `test/models/meal_plan_test.rb` | Near-total rewrite |
| `test/services/meal_plan_write_service_test.rb` | Near-total rewrite |
| `test/controllers/groceries_controller_test.rb` | Update state setup patterns |
| `test/controllers/menu_controller_test.rb` | Update state setup patterns |
| `test/helpers/groceries_helper_test.rb` | Hash entries → AR objects |
| `test/helpers/search_data_helper_test.rb` | 3 tests that set JSON state directly |
| `test/services/shopping_list_builder_test.rb` | Replace `apply_action` with AR creates |
| `test/models/kitchen_batch_writes_test.rb` | Update state assertions |
| `config/html_safe_allowlist.yml` | Update line numbers if edits shift them |

---

## Task 1: Feature Branch + Migration

**Files:**
- Create: `db/migrate/014_decompose_meal_plan.rb`

This migration creates all four tables, migrates data from JSON, and drops
the old columns. Run it first so all subsequent tasks develop against the
new schema.

**Important:** After this migration runs, the full test suite will be broken
(~12 test files reference `plan.state` which no longer exists). This is
expected — the feature branch will be broken from Task 1 through Task 13.
Individual new model tests (Tasks 2-5) will pass in isolation. Do not
merge to main until Task 14 verifies full green. `bin/dev` will also fail
to render pages that use MealPlan until the consuming code is updated.

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feature/mealplan-decomposition
```

- [ ] **Step 2: Write the migration**

Create `db/migrate/014_decompose_meal_plan.rb`. Use bare SQL for the data
migration (per CLAUDE.md: never call application models from migrations).

Key details:
- `meal_plan_selections`: `kitchen_id` (integer), `selectable_type` (string),
  `selectable_id` (string), `created_at` (datetime). Unique index on
  `[kitchen_id, selectable_type, selectable_id]`.
- `on_hand_entries`: `kitchen_id` (integer), `ingredient_name` (string,
  `collation: 'NOCASE'`), `confirmed_at` (date), `interval` (float, nullable),
  `ease` (float, nullable), `depleted_at` (date, nullable), `orphaned_at`
  (date, nullable), timestamps. Unique index on
  `[kitchen_id, ingredient_name]`.
- `custom_grocery_items`: `kitchen_id` (integer), `name` (string,
  `collation: 'NOCASE'`), `aisle` (string, default `'Miscellaneous'`),
  `on_hand_at` (date, nullable), `last_used_at` (date, not null),
  `created_at` (datetime). Unique index on `[kitchen_id, name]`.
- `cook_history_entries`: `kitchen_id` (integer), `recipe_slug` (string),
  `cooked_at` (datetime). Index on `[kitchen_id, recipe_slug, cooked_at]`.

Data migration: for each `meal_plans` row, parse `state` JSON and insert
into the four new tables using raw SQL `INSERT INTO` statements.

Then: `remove_column :meal_plans, :state` and
`remove_column :meal_plans, :lock_version`.

- [ ] **Step 3: Run the migration**

```bash
rails db:migrate
```

Verify schema version is 14 and all tables exist.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/014_decompose_meal_plan.rb db/schema.rb
git commit -m "Add migration: decompose meal_plans.state into four tables"
```

---

## Task 2: MealPlanSelection Model + Tests

**Files:**
- Create: `app/models/meal_plan_selection.rb`
- Create: `test/models/meal_plan_selection_test.rb`
- Modify: `app/models/kitchen.rb:23` — add `has_many :meal_plan_selections`

Thin AR model for menu selections.

- [ ] **Step 1: Write tests for MealPlanSelection**

Test file: `test/models/meal_plan_selection_test.rb`

Cover:
- `acts_as_tenant` scoping
- Uniqueness validation on `[kitchen_id, selectable_type, selectable_id]`
- `recipes` scope filters `selectable_type: 'Recipe'`
- `quick_bites` scope filters `selectable_type: 'QuickBite'`
- `toggle` class method: creates when `selected: true`, destroys when
  `selected: false`, idempotent for both
- Stale selection pruning: `prune_stale!(kitchen:, valid_recipe_slugs:,
  valid_qb_ids:)` removes selections whose IDs no longer exist

- [ ] **Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/models/meal_plan_selection_test.rb
```

- [ ] **Step 3: Implement MealPlanSelection**

Create `app/models/meal_plan_selection.rb`:
- `acts_as_tenant :kitchen`
- `validates :selectable_type, inclusion: { in: %w[Recipe QuickBite] }`
- `validates :selectable_id, uniqueness: { scope: %i[kitchen_id selectable_type] }`
- `scope :recipes, -> { where(selectable_type: 'Recipe') }`
- `scope :quick_bites, -> { where(selectable_type: 'QuickBite') }`
- `toggle(kitchen:, type:, id:, selected:)` class method
- `prune_stale!(kitchen:, valid_recipe_slugs:, valid_qb_ids:)` class method

Add `has_many :meal_plan_selections, dependent: :destroy` to `Kitchen`
(after line 23).

- [ ] **Step 4: Run tests to verify they pass**

```bash
ruby -Itest test/models/meal_plan_selection_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan_selection.rb test/models/meal_plan_selection_test.rb app/models/kitchen.rb
git commit -m "Add MealPlanSelection model with toggle and pruning"
```

---

## Task 3: CookHistoryEntry Model + Tests

**Files:**
- Create: `app/models/cook_history_entry.rb`
- Create: `test/models/cook_history_entry_test.rb`
- Modify: `app/models/kitchen.rb` — add `has_many :cook_history_entries`

Thin append-only model for cook history.

- [ ] **Step 1: Write tests for CookHistoryEntry**

Test file: `test/models/cook_history_entry_test.rb`

Cover:
- `acts_as_tenant` scoping
- `record(kitchen:, recipe_slug:)` creates an entry with `cooked_at: Time.current`
- `recent` scope returns entries within the `WINDOW` (90 days), excludes older
- `prune!(kitchen:)` deletes entries older than `WINDOW`
- Constant `WINDOW = 90`

- [ ] **Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/models/cook_history_entry_test.rb
```

- [ ] **Step 3: Implement CookHistoryEntry**

Create `app/models/cook_history_entry.rb`:
- `WINDOW = 90`
- `acts_as_tenant :kitchen`
- `scope :recent, ->(now: Time.current) { where('cooked_at > ?', now - WINDOW.days) }`
- `record(kitchen:, recipe_slug:)` class method
- `prune!(kitchen:)` deletes entries older than window

Add `has_many :cook_history_entries, dependent: :destroy` to `Kitchen`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
ruby -Itest test/models/cook_history_entry_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/cook_history_entry.rb test/models/cook_history_entry_test.rb app/models/kitchen.rb
git commit -m "Add CookHistoryEntry model with record and recent scope"
```

---

## Task 4: CustomGroceryItem Model + Tests

**Files:**
- Create: `app/models/custom_grocery_item.rb`
- Create: `test/models/custom_grocery_item_test.rb`
- Modify: `app/models/kitchen.rb` — add `has_many :custom_grocery_items`

Model for user-added grocery items with visibility and staleness scopes.

- [ ] **Step 1: Write tests for CustomGroceryItem**

Test file: `test/models/custom_grocery_item_test.rb`

Cover:
- `acts_as_tenant` scoping
- NOCASE uniqueness: creating two items with same name different case raises
- `MAX_NAME_LENGTH = 100`
- `RETENTION = 45`
- `visible(now:)` scope: includes items with `on_hand_at: nil`, includes
  items with `on_hand_at >= now`, excludes items with `on_hand_at < now`
- `stale(cutoff:)` scope: includes items with `last_used_at < cutoff`
- Validates `name` presence, length <= MAX_NAME_LENGTH

- [ ] **Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/models/custom_grocery_item_test.rb
```

- [ ] **Step 3: Implement CustomGroceryItem**

Create `app/models/custom_grocery_item.rb`:
- `MAX_NAME_LENGTH = 100`
- `RETENTION = 45`
- `acts_as_tenant :kitchen`
- Validations: name presence, uniqueness (scope: kitchen_id, case_sensitive: false), length
- `scope :visible, ->(now: Date.current) { where('on_hand_at IS NULL OR on_hand_at >= ?', now) }`
- `scope :stale, ->(cutoff:) { where('last_used_at < ?', cutoff) }`

Add `has_many :custom_grocery_items, dependent: :destroy` to `Kitchen`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
ruby -Itest test/models/custom_grocery_item_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/custom_grocery_item.rb test/models/custom_grocery_item_test.rb app/models/kitchen.rb
git commit -m "Add CustomGroceryItem model with visible and stale scopes"
```

---

## Task 5: OnHandEntry Model + Tests

**Files:**
- Create: `app/models/on_hand_entry.rb`
- Create: `test/models/on_hand_entry_test.rb`
- Modify: `app/models/kitchen.rb` — add `has_many :on_hand_entries`

The largest new model. SM-2 adaptive interval logic moves here from MealPlan.

- [ ] **Step 1: Write tests for OnHandEntry — scopes and constants**

Test file: `test/models/on_hand_entry_test.rb`

Cover:
- `acts_as_tenant` scoping
- NOCASE uniqueness on `[kitchen_id, ingredient_name]`
- Constants: `STARTING_INTERVAL = 7`, `MAX_INTERVAL = 180`,
  `STARTING_EASE = 1.5`, `MIN_EASE = 1.1`, `MAX_EASE = 2.5`,
  `EASE_BONUS = 0.05`, `EASE_PENALTY = 0.15`, `SAFETY_MARGIN = 0.9`,
  `ORPHAN_SENTINEL = '1970-01-01'`, `ORPHAN_RETENTION = 180`
- `active(now:)` scope: includes entries where `depleted_at IS NULL` and
  either `interval IS NULL` or the date math holds. Excludes depleted.
  Excludes expired entries. Accepts `now:` param for testability.
- `depleted` scope: `where.not(depleted_at: nil)`
- `orphaned` scope: `where.not(orphaned_at: nil)`

- [ ] **Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 3: Implement OnHandEntry — scopes and constants**

Create `app/models/on_hand_entry.rb` with constants, scopes, and
`acts_as_tenant`. The `active` scope:

```ruby
scope :active, ->(now: Date.current) {
  where(depleted_at: nil).where(
    'interval IS NULL OR date(confirmed_at, ' \
    "'+' || CAST(interval * #{SAFETY_MARGIN} AS INTEGER) || ' days') >= date(?)",
    now.iso8601
  )
}
```

Add `has_many :on_hand_entries, dependent: :destroy` to `Kitchen`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/models/on_hand_entry.rb test/models/on_hand_entry_test.rb app/models/kitchen.rb
git commit -m "Add OnHandEntry model with SM-2 constants and active scope"
```

- [ ] **Step 6: Write tests for OnHandEntry — SM-2 instance methods**

Add to `test/models/on_hand_entry_test.rb`:

- `have_it!` on new entry: sets `confirmed_at`, starting interval/ease
- `have_it!` on existing with sentinel: grows standard (resets confirmed_at)
- `have_it!` on existing with real date: grows anchored (preserves confirmed_at)
- `have_it!` one-step growth cap: anchored growth only multiplies once
- `have_it!` when already on hand: no-op
- `need_it!` on new entry: creates depleted entry
- `need_it!` on existing: blended interval, ease penalty, marks depleted
- `need_it!` on sentinel entry: ease penalty only, no interval change
- `check!(custom_item:)`: when `custom_item:` is provided, updates
  `CustomGroceryItem#on_hand_at` as well
- `uncheck!`: same-day undo grace (deletes if defaults, depletes otherwise)
- `uncheck!` with custom: removes on_hand and clears custom `on_hand_at`
- Ease caps: ease never below `MIN_EASE`, never above `MAX_EASE`
- Interval caps: interval never below `STARTING_INTERVAL`, capped at `MAX_INTERVAL`

Port the core assertions from `test/models/meal_plan_test.rb` lines 579-1220,
adapting from hash manipulation to AR attribute assertions.

- [ ] **Step 7: Run tests to verify they fail**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 8: Implement SM-2 instance methods**

Add to `app/models/on_hand_entry.rb`:

- `have_it!(now: Date.current)` — growth logic from MealPlan lines 425-516
- `need_it!(now: Date.current)` — depletion logic from MealPlan lines 439-474
- `check!(now: Date.current, custom_item: nil)` — from lines 154-168, 356-362
- `uncheck!(now: Date.current, custom_item: nil)` — from lines 191-235
- Private helpers: `grow_anchored`, `grow_standard`, `mark_depleted`,
  `mark_depleted_sentinel`, `undo_same_day_check`

Each method operates on `self` (AR attributes) and calls `save!`. The
`custom_item:` parameter, when present, also updates
`custom_item.update!(on_hand_at:)` for cross-table sync.

- [ ] **Step 9: Run tests to verify they pass**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 10: Commit**

```bash
git add app/models/on_hand_entry.rb test/models/on_hand_entry_test.rb
git commit -m "Add SM-2 instance methods to OnHandEntry"
```

- [ ] **Step 11: Write tests for OnHandEntry — reconciliation**

Add to `test/models/on_hand_entry_test.rb`:

- `reconcile!` expires orphaned entries (sets `orphaned_at`, `confirmed_at`
  to sentinel) for names not in `visible_names`
- `reconcile!` fixes orphaned null intervals (sets `STARTING_INTERVAL`/ease
  for entries with nil interval that aren't custom items)
- `reconcile!` purges stale orphans older than `ORPHAN_RETENTION`
- `reconcile!` re-canonicalizes keys via resolver (renames ingredient_name
  to canonical form)
- `reconcile!` merge conflict: when re-canon creates duplicate, keeps the
  entry with the longer interval

- [ ] **Step 12: Run tests to verify they fail**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 13: Implement reconciliation**

Add `self.reconcile!(kitchen:, visible_names:, resolver:, now:)` class
method to `OnHandEntry`. Four passes as scoped queries:

1. Re-canonicalize: query all entries, resolve names, update changed ones.
   Handle merge conflicts by keeping the longer-interval entry.
2. Expire orphans: `where.not(ingredient_name: visible_names)` +
   `where(orphaned_at: nil, depleted_at: nil)` → `update_all(orphaned_at:,
   confirmed_at: ORPHAN_SENTINEL)`
3. Fix null intervals: entries with nil interval that aren't backed by a
   custom item → set to `STARTING_INTERVAL`/`STARTING_EASE`
4. Purge stale orphans: `where('orphaned_at < ?', now - ORPHAN_RETENTION)`
   + `where(depleted_at: nil)` → `delete_all`

The custom item check in pass 3 queries `CustomGroceryItem.where(kitchen:)`
to get custom names.

- [ ] **Step 14: Run tests to verify they pass**

```bash
ruby -Itest test/models/on_hand_entry_test.rb
```

- [ ] **Step 15: Commit**

```bash
git add app/models/on_hand_entry.rb test/models/on_hand_entry_test.rb
git commit -m "Add reconciliation to OnHandEntry"
```

---

## Task 6: Broadcast Infrastructure

**Files:**
- Modify: `app/models/current.rb:10` — add `broadcast_pending`
- Modify: `app/controllers/application_controller.rb:26` — add `after_action`
- Modify: `app/models/kitchen.rb:50-55` — rewrite `run_finalization`
- Modify: `app/services/recipe_write_service.rb:87-91,129-137` — move broadcaster to after_commit

- [ ] **Step 1: Add `broadcast_pending` to Current**

Modify `app/models/current.rb` line 10: add `:broadcast_pending` to the
attribute list. Update header comment to document its purpose.

- [ ] **Step 2: Add `flush_broadcast` after_action to ApplicationController**

Add after line 26 of `app/controllers/application_controller.rb`:

```ruby
after_action :flush_broadcast
```

Add private method:

```ruby
def flush_broadcast
  kitchen = Current.broadcast_pending
  return unless kitchen

  Current.broadcast_pending = nil
  kitchen.broadcast_update
end
```

- [ ] **Step 3: Rewrite `Kitchen.run_finalization`**

Modify `app/models/kitchen.rb` lines 50-55. Replace:

```ruby
def self.run_finalization(kitchen)
  Category.cleanup_orphans(kitchen)
  Tag.cleanup_orphans(kitchen)
  MealPlan.reconcile_kitchen!(kitchen)
  kitchen.broadcast_update
end
```

With:

```ruby
def self.run_finalization(kitchen)
  Category.cleanup_orphans(kitchen)
  Tag.cleanup_orphans(kitchen)
  reconcile_meal_plan_tables(kitchen)
  Current.broadcast_pending = kitchen
end

def self.reconcile_meal_plan_tables(kitchen)
  resolver = IngredientCatalog.resolver_for(kitchen)
  visible = ShoppingListBuilder.visible_names_for(kitchen:, resolver:)
  OnHandEntry.reconcile!(kitchen:, visible_names: visible, resolver:)
  CustomGroceryItem.where(kitchen_id: kitchen.id).stale(cutoff: Date.current - CustomGroceryItem::RETENTION).delete_all
  CookHistoryEntry.prune!(kitchen:)
  valid_slugs = kitchen.recipes.pluck(:slug)
  valid_qb_ids = kitchen.parsed_quick_bites.map(&:id)
  MealPlanSelection.prune_stale!(kitchen:, valid_recipe_slugs: valid_slugs, valid_qb_ids:)
end
```

- [ ] **Step 3b: Extract `ShoppingListBuilder.visible_names_for`**

Add a class method to `app/services/shopping_list_builder.rb` so
`Kitchen.reconcile_meal_plan_tables` can call it immediately (the full
consumer rewrite happens in Task 9):

```ruby
def self.visible_names_for(kitchen:, resolver: nil)
  resolver ||= IngredientCatalog.resolver_for(kitchen)
  new(kitchen:).visible_names
end
```

Update the constructor to make `meal_plan:` optional (default nil). The
`visible_names` method already uses AR queries for the new tables
(after Task 9 completes the full rewrite); for now, selection queries
come from `MealPlanSelection` and custom items from `CustomGroceryItem`.

Since `selected_recipes` and `selected_quick_bites` still reference
`@meal_plan.selected_recipes` at this point, create a temporary shim:
if `@meal_plan` is nil, query `MealPlanSelection` directly. Task 9
removes this shim when it rewrites the full builder.

- [ ] **Step 4: Fix RecipeBroadcaster cross-DB atomicity**

In `app/services/recipe_write_service.rb`:

**Destroy** (lines 84-95): Move `RecipeBroadcaster.notify_recipe_deleted`
from inside the transaction (line 89) to after the transaction (after line 91,
before `finalize` on line 93). The recipe object will be frozen (destroyed)
but still holds `title` for the notification.

**Update/slug change** (lines 129-137): Move
`RecipeBroadcaster.broadcast_rename` from inside `handle_slug_change` to
the `update` method, after the transaction block (after line 72, before
`finalize` on line 74). Capture the old recipe's stream key data (id, class
name) and title *before* the transaction, since `old_recipe.destroy!` runs
inside the transaction. `RecipeBroadcaster.broadcast_rename` uses the old
recipe as a Turbo stream channel key — verify that a destroyed-but-committed
AR record still works as a stream signing key, or pass pre-captured values
instead.

- [ ] **Step 5: Commit**

```bash
git add app/models/current.rb app/controllers/application_controller.rb app/models/kitchen.rb app/services/recipe_write_service.rb
git commit -m "Add broadcast deduplication via Current and fix cross-DB atomicity"
```

---

## Task 7: Rewrite MealPlan Model

**Files:**
- Modify: `app/models/meal_plan.rb` — near-total rewrite

The model shrinks from 517 lines to ~100. It becomes a thin coordinator
that delegates to the new AR models.

- [ ] **Step 1: Rewrite MealPlan**

Replace the entire body of `app/models/meal_plan.rb`. Keep:
- `acts_as_tenant :kitchen`
- `validates :kitchen_id, uniqueness: true`
- `self.for_kitchen(kitchen)` (unchanged)
- `with_optimistic_retry` (for batch ops — note: `lock_version` column is
  gone, so this now catches StaleObjectError from the new models if needed;
  may simplify to just yield without retry since row-level updates don't
  contend)

Add delegating methods:
- `selected_recipes` → `MealPlanSelection.where(kitchen:).recipes.pluck(:selectable_id)`
- `selected_quick_bites` → `MealPlanSelection.where(kitchen:).quick_bites.pluck(:selectable_id)`

Remove everything else — all state accessors, `apply_action`, SM-2 logic,
reconciliation, pruning, custom items, cook history. These now live on
the four new models.

- [ ] **Step 2: Run lint**

```bash
bundle exec rubocop app/models/meal_plan.rb
```

- [ ] **Step 3: Commit**

```bash
git add app/models/meal_plan.rb
git commit -m "Slim MealPlan to thin coordinator delegating to new models"
```

---

## Task 8: Rewrite MealPlanWriteService + Tests

**Files:**
- Modify: `app/services/meal_plan_write_service.rb` — full rewrite
- Modify: `test/services/meal_plan_write_service_test.rb` — near-total rewrite

- [ ] **Step 1: Rewrite MealPlanWriteService**

The service keeps its public API (`apply_action` with action types) but
delegates to AR models instead of mutating JSON:

- `apply_select` → `MealPlanSelection.toggle(kitchen:, type:, id:, selected:)`.
  On deselect of a recipe, also call
  `CookHistoryEntry.record(kitchen:, recipe_slug:)`.
- `apply_check` → Find or initialize `OnHandEntry`, call `check!`/`uncheck!`.
  Detect custom items via
  `CustomGroceryItem.where(kitchen:, name: item).first`.
- `apply_custom_items` → `CustomGroceryItem.create!`/`.destroy`.
- `apply_have_it` → Find or initialize `OnHandEntry`, call `have_it!`.
- `apply_need_it` → Find or initialize `OnHandEntry`, call `need_it!`.
- `apply_quick_add` → Direct `OnHandEntry`/`CustomGroceryItem` creation.
  No recursive self-call. Query `OnHandEntry` for status detection:
  `OnHandEntry.active(now:).find_by(kitchen:, ingredient_name:)` for
  "already on hand", `.depleted.find_by(...)` for "already needed".

Keep: `validate_action` (update constant ref to
`CustomGroceryItem::MAX_NAME_LENGTH`), `Result`, `QuickAddResult`.

Remove: `mutate_plan`, `enrich_check_params` (inline the logic).

Call `Kitchen.finalize_writes(kitchen)` after mutations (unchanged pattern).

- [ ] **Step 2: Rewrite MealPlanWriteService tests**

Rewrite `test/services/meal_plan_write_service_test.rb`. Assertions change
from `plan.state['selected_recipes']` to
`MealPlanSelection.where(kitchen:).recipes.exists?(selectable_id:)`,
from `plan.on_hand` to `OnHandEntry.find_by(kitchen:, ingredient_name:)`,
etc.

Key test patterns:
- Select/deselect: assert `MealPlanSelection` records created/destroyed
- Check/uncheck: assert `OnHandEntry` attributes
- Custom items: assert `CustomGroceryItem` records
- Have it/need it: assert `OnHandEntry` interval/ease/depleted_at
- Quick add: assert no recursive calls, correct records created
- Canonicalization: assert `OnHandEntry.ingredient_name` is canonical form
- Cook history on deselect: assert `CookHistoryEntry` created

- [ ] **Step 3: Run tests**

```bash
ruby -Itest test/services/meal_plan_write_service_test.rb
```

- [ ] **Step 4: Commit**

```bash
git add app/services/meal_plan_write_service.rb test/services/meal_plan_write_service_test.rb
git commit -m "Rewrite MealPlanWriteService to delegate to AR models"
```

---

## Task 9: Update ShoppingListBuilder + CookHistoryWeighter

**Files:**
- Modify: `app/services/shopping_list_builder.rb:17,30-33,65-73,152-170`
- Modify: `app/services/cook_history_weighter.rb:31,33-38`
- Modify: `test/services/shopping_list_builder_test.rb` — update setup patterns

- [ ] **Step 1: Update ShoppingListBuilder**

Changes to `app/services/shopping_list_builder.rb`:

- Constructor (line 17): remove `meal_plan:` parameter. The builder queries
  AR models directly via `kitchen:`. Remove the temporary shim added in
  Task 6 Step 3b.
- Finalize `self.visible_names_for(kitchen:, resolver:)` — already extracted
  in Task 6 Step 3b; now remove the shim since the builder is fully
  rewritten.
- `selected_recipes` (line 66): replace
  `@meal_plan.selected_recipes` with
  `MealPlanSelection.where(kitchen_id: @kitchen.id).recipes.pluck(:selectable_id)`.
  Then `@kitchen.recipes.with_full_tree.where(slug: slugs)`.
- `selected_quick_bites` (line 70): replace
  `@meal_plan.selected_quick_bites` with
  `MealPlanSelection.where(kitchen_id: @kitchen.id).quick_bites.pluck(:selectable_id)`.
- `visible_names` (line 31): replace
  `@meal_plan.visible_custom_items.keys` with
  `CustomGroceryItem.where(kitchen_id: @kitchen.id).visible.pluck(:name)`.
- `add_custom_items` (line 153): replace
  `@meal_plan.visible_custom_items` with
  `CustomGroceryItem.where(kitchen_id: @kitchen.id).visible`.
  Update `custom_item_entry_from_hash` to read `.aisle` instead of
  `entry['aisle']`.

- [ ] **Step 2: Update CookHistoryWeighter**

Changes to `app/services/cook_history_weighter.rb`:

- Line 31: `MealPlan::COOK_HISTORY_WINDOW` →
  `CookHistoryEntry::WINDOW`
- Lines 33-38: Change from JSON hash iteration to AR object iteration:
  `entry['at']` → `entry.cooked_at`, `entry['slug']` → `entry.recipe_slug`.
  `Date.parse(entry['at'])` → `entry.cooked_at.to_date`.

- [ ] **Step 3: Update ShoppingListBuilder tests**

In `test/services/shopping_list_builder_test.rb`:
- Remove `meal_plan:` from constructor calls (grep for
  `ShoppingListBuilder.new` — appears ~30 times).
- Replace `@list.apply_action('select', ...)` with
  `MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe', selectable_id: slug)`.
- Replace `@list.apply_action('custom_items', ...)` with
  `CustomGroceryItem.create!(kitchen: @kitchen, name:, aisle:, last_used_at: Date.current)`.

- [ ] **Step 4: Run tests**

```bash
ruby -Itest test/services/shopping_list_builder_test.rb
ruby -Itest test/services/cook_history_weighter_test.rb
```

Note: `cook_history_weighter_test.rb` may not exist (the weighter may be
tested via menu controller tests). If it doesn't exist, verify via menu
tests later.

- [ ] **Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb app/services/cook_history_weighter.rb test/services/shopping_list_builder_test.rb
git commit -m "Update ShoppingListBuilder and CookHistoryWeighter for AR models"
```

---

## Task 10: Update GroceriesHelper + View Template

**Files:**
- Modify: `app/helpers/groceries_helper.rb` — constant refs + AR objects
- Modify: `app/views/groceries/_shopping_list.html.erb` — indexed lookups
- Modify: `test/helpers/groceries_helper_test.rb` — hash → AR objects

- [ ] **Step 1: Update GroceriesHelper**

All `MealPlan::` constant references → `OnHandEntry::` equivalents:
- `MealPlan::SAFETY_MARGIN` → `OnHandEntry::SAFETY_MARGIN` (lines 47, 79, 96)
- `MealPlan::STARTING_INTERVAL` → `OnHandEntry::STARTING_INTERVAL` (line 52)
- `MealPlan::STARTING_EASE` → `OnHandEntry::STARTING_EASE` (line 53)
- `MealPlan::ORPHAN_SENTINEL` → `OnHandEntry::ORPHAN_SENTINEL` (line 71)

Change method signatures to accept `OnHandEntry` objects instead of hashes.
The `on_hand_data` parameter changes from a raw hash
`{ 'Salt' => { 'confirmed_at' => ..., 'interval' => ... } }` to an indexed
hash of AR objects keyed by **downcased** ingredient name:
`entries.index_by { |e| e.ingredient_name.downcase }`. All lookup keys must
also be downcased: `on_hand_data[name.downcase]`. This is necessary because
`COLLATE NOCASE` only applies in SQL queries — Ruby `Hash` lookups are
case-sensitive, so `index_by(&:ingredient_name)` would silently miss
case-mismatched keys.

Key changes:
- `item_zone`: replace `on_hand_data.find { |k, _| k.casecmp?(name) }`
  with `on_hand_data[name.downcase]`.
  Replace `entry&.key?('depleted_at')` with `entry&.depleted_at?`.
  Replace `custom_items.any? { |k, _| k.casecmp?(name) }` with
  `custom_names.include?(name)` (pass a pre-built set).
- `restock_tooltip`: `entry['interval']` → `entry.interval`,
  `entry['confirmed_at']` → `entry.confirmed_at`, etc.
- `on_hand_sort_key`, `confirmed_today?`, `on_hand_freshness_class`,
  `days_until_restock`: same hash-to-AR-attribute changes.

- [ ] **Step 2: Update _shopping_list.html.erb**

`app/views/groceries/_shopping_list.html.erb`:

Change locals signature (line 1):
`(shopping_list:, on_hand_names:, on_hand_data:, custom_names:)`

- Line 3: `item_zone` call now passes `custom_names:` set instead of
  `custom_items:` hash.
- Line 54: Same change for zone_for lambda.
- Line 80: `custom_items.any? { |k, _| k.casecmp?(item[:name]) }` →
  `custom_names.include?(item[:name])`
- Line 114: `on_hand_data.find { |k, _| k.casecmp?(item[:name]) }&.last` →
  `on_hand_data[item[:name].downcase]`

- [ ] **Step 3: Update GroceriesController#show to pass new data shapes**

In `app/controllers/groceries_controller.rb` lines 17-23:

```ruby
def show
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen).build
  entries = OnHandEntry.where(kitchen_id: current_kitchen.id)
  @on_hand_names = entries.active.pluck(:ingredient_name).to_set
  @on_hand_data = entries.index_by { |e| e.ingredient_name.downcase }
  @custom_names = CustomGroceryItem.where(kitchen_id: current_kitchen.id).pluck(:name).to_set
end
```

Update `show.html.erb` line 33: pass `custom_names: @custom_names` instead
of `custom_items: @custom_items`.

- [ ] **Step 4: Update groceries_helper_test.rb**

In `test/helpers/groceries_helper_test.rb`:
- Replace hash entry construction `{ 'confirmed_at' => '...', 'interval' => 7 }`
  with `OnHandEntry.new(confirmed_at: Date.parse('...'), interval: 7, ...)`.
- Replace `MealPlan::` constant references with `OnHandEntry::`.
- Replace `custom_items` hash params with `custom_names` set params.

- [ ] **Step 5: Run tests**

```bash
ruby -Itest test/helpers/groceries_helper_test.rb
```

- [ ] **Step 6: Commit**

```bash
git add app/helpers/groceries_helper.rb app/views/groceries/_shopping_list.html.erb app/views/groceries/show.html.erb app/controllers/groceries_controller.rb test/helpers/groceries_helper_test.rb
git commit -m "Update groceries helper and view for OnHandEntry AR objects"
```

---

## Task 11: Update Controllers + SearchDataHelper

**Files:**
- Modify: `app/controllers/menu_controller.rb:17-28`
- Modify: `app/helpers/search_data_helper.rb:19,32-43`
- Modify: `test/helpers/search_data_helper_test.rb:105-138`

- [ ] **Step 1: Update MenuController#show**

In `app/controllers/menu_controller.rb` lines 17-28:

```ruby
def show
  @categories = recipe_selector_categories
  @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
  @selected_recipes = MealPlanSelection.where(kitchen_id: current_kitchen.id).recipes.pluck(:selectable_id).to_set
  @selected_quick_bites = MealPlanSelection.where(kitchen_id: current_kitchen.id).quick_bites.pluck(:selectable_id).to_set
  on_hand_names = OnHandEntry.where(kitchen_id: current_kitchen.id).active.pluck(:ingredient_name)
  recipes = @categories.flat_map(&:recipes)
  calculator = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:)
  @availability = calculator.call
  @cook_weights = CookHistoryWeighter.call(CookHistoryEntry.where(kitchen_id: current_kitchen.id).recent)
end
```

- [ ] **Step 2: Update SearchDataHelper**

In `app/helpers/search_data_helper.rb`:

- Line 19: remove `plan = MealPlan.for_kitchen(current_kitchen)`.
- `ingredient_corpus` (line 32): replace `plan.on_hand.keys` with
  `OnHandEntry.where(kitchen_id: current_kitchen.id).pluck(:ingredient_name)`.
- `custom_item_corpus` (line 38): replace plan-based iteration with
  `CustomGroceryItem.where(kitchen_id: current_kitchen.id).visible.pluck(:name, :aisle).map { |name, aisle| { name:, aisle: } }`.
  Remove `MealPlan::CUSTOM_ITEM_RETENTION` reference.

- [ ] **Step 3: Update search_data_helper_test.rb**

Lines 105-138: replace `plan.update!(state: plan.state.merge('on_hand' => ...))`
with `OnHandEntry.create!(kitchen: @kitchen, ingredient_name: ...,
confirmed_at: Date.current, interval: 7, ease: 1.5)`.

Replace `plan.update!(state: plan.state.merge('custom_items' => ...))`
with `CustomGroceryItem.create!(kitchen: @kitchen, name: ...,
last_used_at: Date.current, aisle: ...)`.

- [ ] **Step 4: Run tests**

```bash
ruby -Itest test/helpers/search_data_helper_test.rb
```

- [ ] **Step 5: Commit**

```bash
git add app/controllers/menu_controller.rb app/helpers/search_data_helper.rb test/helpers/search_data_helper_test.rb
git commit -m "Update MenuController and SearchDataHelper for decomposed models"
```

---

## Task 12: Rewrite MealPlan Tests

**Files:**
- Modify: `test/models/meal_plan_test.rb` — near-total rewrite

The existing 1221-line test file directly manipulates `plan.state`. Most
SM-2 tests have already been ported to `on_hand_entry_test.rb` in Task 5.
This file becomes much smaller — testing only the thin coordinator.

- [ ] **Step 1: Rewrite meal_plan_test.rb**

Keep tests for:
- `for_kitchen` creates or finds a MealPlan
- `for_kitchen` handles race condition (RecordNotUnique)
- `uniqueness` validation on `kitchen_id`

Delete tests for:
- All `state` manipulation (moved to individual model tests)
- All SM-2 logic (moved to `on_hand_entry_test.rb`)
- All reconciliation logic (moved to `on_hand_entry_test.rb`)
- All custom item logic (moved to `custom_grocery_item_test.rb`)
- All cook history logic (moved to `cook_history_entry_test.rb`)
- All selection logic (moved to `meal_plan_selection_test.rb`)

The file should shrink from ~1221 lines to ~50 lines.

- [ ] **Step 2: Run tests**

```bash
ruby -Itest test/models/meal_plan_test.rb
```

- [ ] **Step 3: Commit**

```bash
git add test/models/meal_plan_test.rb
git commit -m "Rewrite MealPlan tests for thin coordinator model"
```

---

## Task 13: Update Remaining Test Files

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `test/controllers/menu_controller_test.rb`
- Modify: `test/models/kitchen_batch_writes_test.rb`
- Modify: `test/test_helper.rb`
- Modify: `test/services/catalog_write_service_test.rb` — references `plan.state['on_hand']`, `plan.on_hand`, `plan.effective_on_hand`
- Modify: `test/services/recipe_write_service_test.rb` — references `plan.state['selected_recipes']`
- Modify: `test/services/quick_bites_write_service_test.rb` — references `plan.state['selected_quick_bites']`
- Modify: `test/services/ingredient_resolver_regression_test.rb` — references `plan.state['on_hand']`, `plan.effective_on_hand`

- [ ] **Step 1: Update test_helper.rb**

Add to `test/test_helper.rb` `setup_test_kitchen` method (after line 34):

```ruby
MealPlanSelection.where(kitchen_id: @kitchen.id).delete_all
OnHandEntry.where(kitchen_id: @kitchen.id).delete_all
CustomGroceryItem.where(kitchen_id: @kitchen.id).delete_all
CookHistoryEntry.where(kitchen_id: @kitchen.id).delete_all
```

This ensures clean state in each test (matching the existing
`MealPlan.where.delete_all` pattern in individual test files).

- [ ] **Step 2: Update groceries_controller_test.rb**

Key changes throughout `test/controllers/groceries_controller_test.rb`:
- Replace `plan = MealPlan.for_kitchen(@kitchen)` +
  `plan.apply_action('select', ...)` with
  `MealPlanSelection.create!(kitchen: @kitchen, selectable_type: 'Recipe',
  selectable_id: slug)`.
- Replace `plan.apply_action('check', item:, checked: true)` with
  `OnHandEntry.create!(kitchen: @kitchen, ingredient_name:,
  confirmed_at: Date.current, interval: 7, ease: 1.5)` or use
  `MealPlanWriteService.apply_action(...)` (the public API is unchanged).
- Replace assertions on `plan.on_hand`, `plan.custom_items` with
  `OnHandEntry.find_by(...)`, `CustomGroceryItem.find_by(...)`.
- Replace `MealPlan::MAX_CUSTOM_ITEM_LENGTH` with
  `CustomGroceryItem::MAX_NAME_LENGTH`.

- [ ] **Step 3: Update menu_controller_test.rb**

Key changes in `test/controllers/menu_controller_test.rb`:
- Replace `plan.apply_action('select', ...)` with
  `MealPlanSelection.create!(...)` or use the unchanged service API.
- Replace `plan.state['cook_history']` setup with
  `CookHistoryEntry.create!(...)`.
- Replace assertions on `plan.selected_recipes` with
  `MealPlanSelection.where(kitchen:).recipes.pluck(:selectable_id)`.

- [ ] **Step 4: Update kitchen_batch_writes_test.rb**

In `test/models/kitchen_batch_writes_test.rb`:
- Replace `plan.apply_action('select', ...)` with `MealPlanSelection.create!(...)`.
- Replace assertions like `plan.selected_recipes.include?(slug)` with
  `MealPlanSelection.exists?(kitchen: @kitchen, selectable_type: 'Recipe',
  selectable_id: slug)`.

- [ ] **Step 5: Update remaining service test files**

Four more test files reference MealPlan state directly:

- `test/services/catalog_write_service_test.rb`: Replace
  `plan.state['on_hand']` setup with `OnHandEntry.create!(...)`. Replace
  `plan.on_hand` and `plan.effective_on_hand` assertions with
  `OnHandEntry.find_by(...)` and `OnHandEntry.active.find_by(...)`.
- `test/services/recipe_write_service_test.rb`: Replace
  `plan.state['selected_recipes']` assertions with
  `MealPlanSelection.exists?(selectable_type: 'Recipe', selectable_id:)`.
- `test/services/quick_bites_write_service_test.rb`: Replace
  `plan.state['selected_quick_bites']` assertions with
  `MealPlanSelection.exists?(selectable_type: 'QuickBite', selectable_id:)`.
- `test/services/ingredient_resolver_regression_test.rb`: Replace
  `plan.state['on_hand']` setup with `OnHandEntry.create!(...)`. Replace
  `plan.effective_on_hand` assertions with `OnHandEntry.active` queries.

- [ ] **Step 6: Run all tests**

```bash
rake test
```

Fix any remaining failures. Common issues:
- Missed `MealPlan::` constant references → grep for `MealPlan::` across
  all test files
- Missed `plan.state` references → grep for `\.state\[` across test files
- Missed `apply_action` calls that now need AR model creation

- [ ] **Step 7: Run lint**

```bash
bundle exec rubocop
```

Fix any offenses. Update `config/html_safe_allowlist.yml` if line numbers
shifted in modified files.

- [ ] **Step 8: Commit**

```bash
git add test/ config/html_safe_allowlist.yml
git commit -m "Update all remaining tests for MealPlan decomposition"
```

---

## Task 14: Final Verification + Cleanup

**Files:**
- Possibly modify: various files for edge cases discovered during testing

- [ ] **Step 1: Run full test suite**

```bash
rake test
```

All tests must pass. Target: 0 failures, 0 errors.

- [ ] **Step 2: Run lint**

```bash
bundle exec rubocop
```

0 offenses.

- [ ] **Step 3: Run the html_safe audit**

```bash
rake lint:html_safe
```

- [ ] **Step 4: Verify the app runs**

```bash
bin/dev
```

Manually verify:
- Homepage loads
- Recipe page loads
- Menu page: select/deselect recipes and quick bites
- Groceries page: check/uncheck items, have it/need it, custom items
- Search overlay works
- Multi-device: open two browsers, mutations on one reflect on the other
  (single broadcast, no storm)

- [ ] **Step 5: Grep for stale references**

```bash
grep -r 'MealPlan::' app/ test/ --include='*.rb' | grep -v 'MAX_RETRY\|for_kitchen\|reconcile'
grep -r "state\['" app/models/meal_plan.rb
grep -r '\.on_hand\b' app/ --include='*.rb' | grep -v on_hand_entry | grep -v on_hand_at | grep -v on_hand_names | grep -v on_hand_data
```

Any hits indicate missed migration points. Fix and commit.

- [ ] **Step 6: Final commit if needed**

```bash
git add -A
git commit -m "Final cleanup for MealPlan decomposition"
```

- [ ] **Step 7: Create PR**

```bash
git push -u origin feature/mealplan-decomposition
gh pr create --title "Decompose MealPlan JSON blob into normalized tables" --body "$(cat <<'EOF'
## Summary

- Decomposes `meal_plans.state` JSON column into four normalized tables:
  `meal_plan_selections`, `on_hand_entries`, `custom_grocery_items`,
  `cook_history_entries`
- MealPlan model shrinks from 517 lines to ~100
- SQLite handles case-insensitive lookups (COLLATE NOCASE), date arithmetic,
  and row-level concurrent access natively
- Broadcast storm eliminated via `Current.broadcast_pending` deduplication
- Cross-DB atomicity bug fixed: RecipeBroadcaster calls moved to after_commit
- Recursive MealPlanWriteService self-call removed

Resolves #280, resolves #281

## Test plan

- [ ] All existing tests pass (adapted for new data model)
- [ ] New model tests cover SM-2 logic, scopes, reconciliation
- [ ] Manual test: multi-device grocery sync (single broadcast per mutation)
- [ ] Manual test: recipe delete/rename broadcasts only after commit
- [ ] `rake lint` passes
- [ ] `rake lint:html_safe` passes

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

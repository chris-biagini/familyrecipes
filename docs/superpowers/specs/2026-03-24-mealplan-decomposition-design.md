# MealPlan Decomposition + Broadcast Fixes

**Date:** 2026-03-24
**Issues:** #280 (Rails convention review), #281 (Data model review)
**Related:** #286 (Quick Bites normalization, future), #287 (search data, future), #288 (convention fixes, future)

## Problem

The `MealPlan` model (517 lines) stores all meal planning state in a single
JSON column (`state`). This column holds five distinct data domains: selected
recipes, selected quick bites, custom grocery items, on-hand ingredient
tracking with SM-2 adaptive intervals, and cook history. Every mutation reads
the entire blob, mutates it in Ruby, and writes the whole thing back.

This design causes three concrete problems:

1. **Broadcast storm.** Each individual grocery check-off fires
   `finalize_writes` → `broadcast_update`, triggering a full page re-fetch +
   morph on every connected client. Ten rapid check-offs = ten broadcasts.

2. **Contention.** All mutations compete for a single `lock_version`. After
   three `StaleObjectError` retries, the user gets a 409 with no recovery
   path.

3. **Ruby reimplements SQLite.** Case-insensitive key lookups are linear scans
   with `casecmp?`. Date arithmetic is `Date.parse` on JSON strings.
   Expiration, pruning, and orphan management iterate the entire hash in Ruby.

## Design

### New Tables

Four new tables replace the `meal_plans.state` JSON column.

#### `meal_plan_selections`

Tracks which recipes and quick bites are on this week's menu.

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| kitchen_id | integer | FK, tenant scoped |
| selectable_type | string | `'Recipe'` or `'QuickBite'` |
| selectable_id | string | slug or QB string ID (becomes FK in #286) |
| created_at | datetime | when added to menu |

- Unique index: `[kitchen_id, selectable_type, selectable_id]`
- `selectable_id` is a string for now. Recipe selections use slugs; QB
  selections use the parser-derived string IDs. When #286 normalizes Quick
  Bites into AR models, `QuickBite` selections migrate to proper FKs.

#### `on_hand_entries`

Ingredient inventory tracking with SM-2 adaptive intervals.

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| kitchen_id | integer | FK, tenant scoped |
| ingredient_name | string | canonical name, COLLATE NOCASE |
| confirmed_at | date | purchase/confirmation date |
| interval | float | nullable (nil for custom-item-sourced entries) |
| ease | float | nullable (nil for custom-item-sourced entries) |
| depleted_at | date | nullable — present means "need to buy" |
| orphaned_at | date | nullable — no longer on shopping list |
| created_at | datetime | |
| updated_at | datetime | |

- Unique index: `[kitchen_id, ingredient_name]`
- `COLLATE NOCASE` on `ingredient_name` eliminates Ruby-side `casecmp?`
  linear scans.
- Sentinel value `1970-01-01` for `confirmed_at` is preserved for
  orphaned/depleted entries (same semantics as current JSON design).

#### `custom_grocery_items`

User-added grocery items not tied to any recipe.

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| kitchen_id | integer | FK, tenant scoped |
| name | string | COLLATE NOCASE |
| aisle | string | default `'Miscellaneous'` |
| on_hand_at | date | nullable |
| last_used_at | date | not null |
| created_at | datetime | |

- Unique index: `[kitchen_id, name]`

#### `cook_history_entries`

Recipe cook log for dinner picker recency weighting.

| Column | Type | Notes |
|--------|------|-------|
| id | integer | PK |
| kitchen_id | integer | FK, tenant scoped |
| recipe_slug | string | |
| cooked_at | datetime | |

- Index: `[kitchen_id, recipe_slug, cooked_at]`

### Changes to Existing Tables

- `meal_plans`: drop the `state` column and `lock_version`. The table
  remains as the kitchen-scoped coordination point for `MealPlan.for_kitchen`
  and batch operations, though individual mutations no longer need optimistic
  locking on this row.

### What Happens to the MealPlan Model

The 517-line model shrinks to ~100 lines. Code falls into three categories:

**Deleted (handled by SQL/AR):**
- `find_on_hand_key` / `find_custom_key` — `COLLATE NOCASE` unique index
- `entry_on_hand?` with `Date.parse` — SQL date arithmetic
- `ensure_state_keys` — no JSON shape management
- `toggle_array` — `MealPlanSelection.create` / `.destroy`
- `prune_custom_items` — `WHERE last_used_at < ?`
- `purge_stale_orphans` — `WHERE orphaned_at < ?`
- `expire_orphaned_on_hand` — scoped `update_all`
- `recanon_on_hand_keys` — update query with resolver
- `pick_merge_winner` / `merge_on_hand_entry` — no key collisions with
  NOCASE unique index

**Moved to `OnHandEntry` (domain logic stays in Ruby):**
- SM-2 interval/ease growth: `grow_anchored`, `grow_standard`,
  `next_interval_and_ease`, `mark_depleted`, `undo_same_day_check`,
  `recheck_depleted`, `mark_depleted_sentinel`, `deplete_existing`. These
  become instance methods on `OnHandEntry` operating on AR attributes instead
  of hash keys. ~100 lines.

**Simplified on `MealPlan`:**
- `with_optimistic_retry` — retained for batch operations only
- `reconcile!` — each cleanup step becomes a scoped SQL query
- `apply_action` dispatch — delegates to new AR models

### New Model Classes

**`MealPlanSelection`** — thin AR model.
- `acts_as_tenant :kitchen`
- Scopes: `recipes`, `quick_bites`
- Class methods: `toggle(kitchen:, type:, id:, selected:)`

**`OnHandEntry`** — AR model with SM-2 logic.
- `acts_as_tenant :kitchen`
- Scopes: `active(now:)` (not expired, not depleted), `depleted`, `orphaned`,
  `expired(now:)` (past safety margin)
- `active` scope uses SQL with a bound date parameter for testability:
  `WHERE depleted_at IS NULL AND (interval IS NULL OR
  date(confirmed_at, '+' || CAST(interval * 0.9 AS INTEGER) || ' days') >=
  date(?))`. Entries with `NULL` interval (custom-item-sourced) are always
  active when not depleted — the explicit `OR interval IS NULL` clause is
  required because SQLite date arithmetic on NULL produces NULL.
- Instance methods: `have_it!(now:)`, `need_it!(now:)`, `check!(now:)`,
  `uncheck!(now:)` — encapsulate SM-2 growth/depletion logic.
- `check!` and `uncheck!` accept an optional `custom_item:` parameter. When
  present, they also update `CustomGroceryItem#on_hand_at` in the same
  call — this replaces the current `sync_custom_on_hand` cross-hash
  coordination. The cross-table update lives on `OnHandEntry` (not in a
  callback) so the coupling is explicit and testable.
- Class method: `reconcile!(kitchen:, visible_names:, resolver:, now:)` —
  the four cleanup passes as scoped queries.

**`CustomGroceryItem`** — thin AR model.
- `acts_as_tenant :kitchen`
- Scope: `visible(now:)` — `WHERE on_hand_at IS NULL OR on_hand_at >= date(?)`
  (includes today — an item marked on-hand today is still visible)
- Scope: `stale(cutoff:)` — items where `last_used_at < cutoff`

**`CookHistoryEntry`** — thin AR model, append-only.
- `acts_as_tenant :kitchen`
- Scope: `recent(window:)` — entries within the history window (90 days)
- Class method: `record(kitchen:, recipe_slug:)` — appends a row; does not
  prune. Old entries are ignored by the `recent` scope, so they are harmless.
  Pruning happens during reconciliation: `CookHistoryEntry.where('cooked_at < ?',
  window.ago).delete_all`.

### Broadcast Fixes

#### A. Eliminate broadcast storm

Use `ActiveSupport::CurrentAttributes` (the existing `Current` class) to
deduplicate broadcasts per request cycle.

Add a `broadcast_pending` flag to `Current`. The new AR models
(`OnHandEntry`, `MealPlanSelection`, `CustomGroceryItem`) register
`after_commit` callbacks that set `Current.broadcast_pending = kitchen`. The
actual `broadcast_update` fires once, at the end of the request, via a
controller `after_action` callback (or `around_action` in
`ApplicationController`).

This means:
- Individual check-offs: one mutation, one broadcast (same as now, but no
  unnecessary `finalize_writes` overhead).
- Rapid mutations in a single request: one broadcast total.
- `Kitchen.batch_writes`: continues to work — defers finalization to block
  exit, single broadcast.

#### B. Fix RecipeBroadcaster cross-database atomicity

Move `RecipeBroadcaster` calls from inside the primary DB transaction to
`after_commit` callbacks. The broadcast to Solid Cable then only fires after
the primary transaction has successfully committed. If the transaction rolls
back, no broadcast is sent.

#### C. Remove recursive MealPlanWriteService self-calls

The `quick_add` path currently calls `apply_action` recursively, triggering
nested `finalize_writes` with nested retry loops. With the decomposition,
`quick_add` directly creates/updates the relevant records (`OnHandEntry` or
`CustomGroceryItem`) without going through the full `apply_action` dispatch.
One write path, one finalize, one broadcast.

### Migration Strategy

A single migration (following the project's sequential numbering):

1. Create the four new tables with indexes.
2. Data migration: iterate each `MealPlan` row, read its `state` JSON, insert
   rows into the new tables using bare SQL or migration-local model stubs (per
   CLAUDE.md: never call application models from migrations).
3. Drop the `state` and `lock_version` columns from `meal_plans`.

The JSON structure is well-documented and deterministic. The migration handles:
- `state['selected_recipes']` → `meal_plan_selections` (type: `Recipe`)
- `state['selected_quick_bites']` → `meal_plan_selections` (type: `QuickBite`)
- `state['on_hand']` → `on_hand_entries` (one row per hash entry)
- `state['custom_items']` → `custom_grocery_items` (one row per hash entry)
- `state['cook_history']` → `cook_history_entries` (one row per event)

### Service Layer Changes

**`MealPlanWriteService`** — stays as orchestrator, delegates to AR models:
- `apply_select` → `MealPlanSelection.toggle`
- `apply_check` → `OnHandEntry.find_or_initialize_by` + instance methods
- `apply_custom_items` → `CustomGroceryItem.create` / `.destroy`
- `apply_have_it` / `apply_need_it` → `OnHandEntry` instance methods
- `apply_quick_add` → direct record creation, no recursive self-call.
  Currently reads `plan.on_hand` and `plan.effective_on_hand` directly;
  these become `OnHandEntry` queries.
- `enrich_check_params` custom item detection: the current
  `plan.custom_items.any? { |k, _| k.casecmp?(item) }` becomes
  `CustomGroceryItem.where(kitchen:, name: item).exists?` (NOCASE index
  handles case-insensitivity).

**`ShoppingListBuilder`** — queries `MealPlanSelection` instead of JSON
arrays. `visible_names` queries `OnHandEntry` and `CustomGroceryItem`
directly.

**`RecipeAvailabilityCalculator`** — receives on-hand names from
`OnHandEntry.active.pluck(:ingredient_name)` instead of
`plan.effective_on_hand.keys`.

**`CookHistoryWeighter`** — queries `CookHistoryEntry.recent` instead of
`plan.cook_history`.

**`Kitchen.finalize_writes`** — reconciliation simplifies to scoped queries:
- `CustomGroceryItem.stale(cutoff:).delete_all`
- `OnHandEntry.reconcile!(kitchen:, visible_names:, resolver:, now:)`
- Broadcast via `Current`-based deduplication

**`GroceriesController`** — `show` action reads from AR models instead of
JSON state:
- `@on_hand_names` from `OnHandEntry.active.pluck(:ingredient_name)`
- `@on_hand_data` from `OnHandEntry.where(kitchen:)` (for interval display)
- `@custom_items` from `CustomGroceryItem.where(kitchen:)`

**`MenuController`** — `show` action reads selections from
`MealPlanSelection` and cook history from `CookHistoryEntry.recent`.

**`GroceriesHelper`** — the heaviest consumer of raw on-hand data outside
the model. Six methods read hash entries directly (`item_zone`,
`restock_tooltip`, `on_hand_sort_key`, `confirmed_today?`,
`on_hand_freshness_class`). After decomposition, these receive `OnHandEntry`
AR objects instead of hash entries. Attribute access changes from
`entry['interval']` to `entry.interval`. References to `MealPlan::` constants
(e.g. `MealPlan::SAFETY_MARGIN`, `MealPlan::ORPHAN_SENTINEL`) move to the
new models (see Constants section below).

**`_shopping_list.html.erb`** — the view template does direct hash lookups:
`on_hand_data.find { |k, _| k.casecmp?(item[:name]) }&.last`. After
decomposition, the controller passes an indexed hash of `OnHandEntry` objects
keyed by ingredient name, or the view queries `@on_hand_entries` directly.
The `casecmp?` scan is eliminated by the NOCASE index.

**`SearchDataHelper`** — reads `plan.on_hand.keys` for the ingredient corpus
and filters `plan.custom_items` by retention date. After decomposition:
- Ingredient corpus: `OnHandEntry.where(kitchen:).pluck(:ingredient_name)`
- Custom items: `CustomGroceryItem.visible(now:).pluck(:name, :aisle)`

### Constant Relocation

Constants currently on `MealPlan` move to the model that owns the concept:

| Current | New home |
|---------|----------|
| `MealPlan::STARTING_INTERVAL` | `OnHandEntry::STARTING_INTERVAL` |
| `MealPlan::MAX_INTERVAL` | `OnHandEntry::MAX_INTERVAL` |
| `MealPlan::STARTING_EASE` | `OnHandEntry::STARTING_EASE` |
| `MealPlan::MIN_EASE` | `OnHandEntry::MIN_EASE` |
| `MealPlan::MAX_EASE` | `OnHandEntry::MAX_EASE` |
| `MealPlan::EASE_BONUS` | `OnHandEntry::EASE_BONUS` |
| `MealPlan::EASE_PENALTY` | `OnHandEntry::EASE_PENALTY` |
| `MealPlan::SAFETY_MARGIN` | `OnHandEntry::SAFETY_MARGIN` |
| `MealPlan::ORPHAN_SENTINEL` | `OnHandEntry::ORPHAN_SENTINEL` |
| `MealPlan::ORPHAN_RETENTION` | `OnHandEntry::ORPHAN_RETENTION` |
| `MealPlan::MAX_CUSTOM_ITEM_LENGTH` | `CustomGroceryItem::MAX_NAME_LENGTH` |
| `MealPlan::CUSTOM_ITEM_RETENTION` | `CustomGroceryItem::RETENTION` |
| `MealPlan::COOK_HISTORY_WINDOW` | `CookHistoryEntry::WINDOW` |
| `MealPlan::MAX_RETRY_ATTEMPTS` | stays on `MealPlan` (batch ops) |

### MealPlanActions Concern

The `MealPlanActions` concern provides `rescue_from StaleObjectError` and
`truthy_param?`. After decomposition, `StaleObjectError` is unlikely for
individual mutations (row-level updates, no shared lock). Retain the rescue
as a safety net for batch operations (`confirm_all`, `deplete_all`) and
edge cases. `truthy_param?` is unaffected.

### Reconciliation: Stale Selection Pruning

The current `prune_stale_selections` removes recipe slugs and QB IDs that
no longer exist. This must migrate to `MealPlanSelection`:
- Recipe selections: `MealPlanSelection.recipes.where.not(selectable_id:
  kitchen.recipes.select(:slug)).delete_all`
- QB selections: filter against `kitchen.parsed_quick_bites.map(&:id)` (text
  parsing survives until #286 normalizes QBs)

This runs as part of `Kitchen.finalize_writes` reconciliation.

### Export/Import Impact

Neither `ExportService` nor `ImportService` currently touches MealPlan state
— exports include only recipes, catalog, aisle order, categories, and quick
bites. The decomposition does not change the export format. If we later want
to export on-hand state or cook history, that is a new feature, not a
migration concern.

### Test Impact

~4,800 lines across 13 test files need some level of update.

**Near-total rewrite (~1,500 lines):**
- `test/models/meal_plan_test.rb` (1220 lines) — every test directly
  manipulates `plan.state['on_hand']`, `plan.state['custom_items']`, etc.
  This is the densest test file and the primary SM-2 correctness guarantee.
- `test/services/meal_plan_write_service_test.rb` (257 lines) — asserts
  against `plan.state['selected_recipes']`, `plan.on_hand`, etc.

**Moderate rewrites:**
- `test/controllers/groceries_controller_test.rb` (1074 lines)
- `test/controllers/menu_controller_test.rb` (477 lines)
- `test/helpers/groceries_helper_test.rb` (282 lines)
- `test/helpers/search_data_helper_test.rb` (155 lines)
- `test/services/shopping_list_builder_test.rb` (859 lines)

**Minor updates:**
- `test/models/kitchen_batch_writes_test.rb` (120 lines)
- `test/services/recipe_availability_calculator_test.rb` (179 lines)
- `test/services/catalog_write_service_test.rb`
- `test/services/recipe_write_service_test.rb`
- `test/services/quick_bites_write_service_test.rb`

**Unaffected:**
- `test/sim/grocery_convergence.rb` — standalone simulation, no Rails deps.

**New test files needed:**
- `test/models/on_hand_entry_test.rb` (SM-2 logic, active scope, reconciliation)
- `test/models/meal_plan_selection_test.rb`
- `test/models/custom_grocery_item_test.rb`
- `test/models/cook_history_entry_test.rb`

## Key Wins

- `MealPlan` drops from ~517 lines to ~100
- SQLite handles case-insensitive lookups, date arithmetic, and row-level
  concurrent access natively
- Broadcast storm eliminated via `Current`-based deduplication
- Cross-DB atomicity bug fixed via `after_commit`
- Recursive write path straightened out
- No new gem dependencies — uses existing Rails/ActiveSupport primitives

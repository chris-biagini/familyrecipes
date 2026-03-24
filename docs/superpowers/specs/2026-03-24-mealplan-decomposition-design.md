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
- `active` scope uses SQL: `WHERE depleted_at IS NULL AND
  date(confirmed_at, '+' || CAST(interval * 0.9 AS INTEGER) || ' days') >=
  date('now')`. Entries with `NULL` interval (custom-item-sourced) are always
  active if not depleted.
- Instance methods: `have_it!(now:)`, `need_it!(now:)`, `check!(now:)`,
  `uncheck!(now:)` — encapsulate SM-2 growth/depletion logic.
- Class method: `reconcile!(kitchen:, visible_names:, resolver:, now:)` —
  the four cleanup passes as scoped queries.

**`CustomGroceryItem`** — thin AR model.
- `acts_as_tenant :kitchen`
- Scope: `visible(now:)` — items where `on_hand_at` is nil or in the future
- Scope: `stale(cutoff:)` — items where `last_used_at < cutoff`

**`CookHistoryEntry`** — thin AR model, append-only.
- `acts_as_tenant :kitchen`
- Scope: `recent(window:)` — entries within the history window (90 days)
- Class method: `record(kitchen:, recipe_slug:)`

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
- `apply_quick_add` → direct record creation, no recursive self-call

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

### Export/Import Impact

`ExportService` and `ImportService` currently serialize/deserialize the
`meal_plans.state` JSON as part of kitchen data export. These must be updated
to export/import the four new tables. The export format version should be
bumped to indicate the new structure, with backward-compatible import that
detects the old JSON format and migrates on import.

## Key Wins

- `MealPlan` drops from ~517 lines to ~100
- SQLite handles case-insensitive lookups, date arithmetic, and row-level
  concurrent access natively
- Broadcast storm eliminated via `Current`-based deduplication
- Cross-DB atomicity bug fixed via `after_commit`
- Recursive write path straightened out
- No new gem dependencies — uses existing Rails/ActiveSupport primitives

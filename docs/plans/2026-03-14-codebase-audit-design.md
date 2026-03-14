# Codebase Audit — 1.0 Readiness Pass

**Date:** 2026-03-14
**Goal:** Systematic audit and fix pass across security, reliability, performance,
and code quality. Fix-by-area approach: audit and fix within each area before
moving to the next, committing after each.

## Area 1: Security

### 1a. CSP nonce hardening

The nonce generator in `content_security_policy.rb` uses `request.session.id`,
which is deterministic per session. Standard practice is a per-request random
nonce, but Turbo Drive caches pages and replays snapshots — a per-request nonce
would break cached pages (stale nonce vs. new CSP header). Investigate whether
Rails' built-in `content_security_policy_nonce_generator` is compatible with
Turbo. If not, document the trade-off.

### 1b. `to_unsafe_h` tightening

`RecipesController`, `MenuController`, and `TagsController` call
`.to_unsafe_h.deep_symbolize_keys` on structure params. Data flows through
serializers and write services which validate structure, so risk is low — but we
should add lightweight schema validation at the controller boundary (expected
top-level keys, type checks) rather than relying on downstream code.

### 1c. `permit!` in NutritionEntriesController

The portions param uses `permit!` with manual regex validation. Replace with
explicit permits or at minimum add a size cap on the hash to prevent abuse.

### 1d. html_safe allowlist sync

Verify all `file:line_number` keys in `html_safe_allowlist.yml` still point to
the correct lines. Line numbers drift as code is edited.

## Area 2: Reliability

### 2a. AisleWriteService TOCTOU race

`sync_new_aisle` and `sync_new_aisles` check whether an aisle exists, then
append it — another request can insert between check and write, creating
duplicates. Fix: deduplicate on write (e.g., split + uniq + rejoin) or wrap
with reload + re-check inside a transaction. SQLite's single-writer constraint
limits blast radius but the code should be correct regardless of database.

### 2b. `sync_new_aisles` reload pattern

Line 64 of `AisleWriteService` calls `kitchen.reload.update!`, discarding
in-memory changes to the kitchen object. If called during a batch where other
services have modified kitchen attributes, the reload could clobber those
changes. Verify safety within `batch_writes` flow; if unsafe, restructure to
reload only the `aisle_order` column.

### 2c. Broadcast coverage audit

Walk every write path and confirm it triggers `Kitchen#broadcast_update`
(directly or via `batch_writes`). Pay special attention to `SettingsController`
updates, `TagWriteService` edge cases, and any service called outside
`batch_writes`.

## Area 3: Performance

### 3a. IngredientRowBuilder memory

`compute_recipes_by_ingredient` stores full AR `Recipe` objects in a hash
indexed by ingredient name. Every recipe containing "salt" stores its full
object. For the ingredients index page this means potentially all recipes held
in memory. Store lightweight data (id, title, slug) instead of full AR objects.
Note: the editor form view uses `source.title`, `source.slug`, and
`source.is_a?(Recipe)` — the replacement must preserve those three attributes
plus type discrimination.

### 3b. SearchDataHelper payload

Every page embeds a JSON blob with all recipes, tags, categories, and ingredient
lists for client-side search. Fine at 40 recipes but grows linearly. Evaluate
current payload size. If already non-trivial, consider lazy-loading on search
overlay open rather than embedding in every page.

### 3c. MealPlan reconciliation frequency

`prune_stale_selections` calls `kitchen.recipes.pluck(:slug)` on every
reconciliation, which runs after every recipe CRUD, quick bites edit, catalog
change, and deselect. Consider memoizing the slug set within a request, or only
reconciling when the recipe/quick-bites set has actually changed.

### 3d. Eager loading audit

`Recipe.with_full_tree` does deep eager loading for the show page. Verify that
collection pages (homepage, menu, ingredients) aren't triggering lazy loads on
associations they don't preload. Spot-check with `strict_loading` to confirm.

## Area 4: Code Quality

### 4a. Large Stimulus controllers

`nutrition_editor_controller` (682 lines) and `recipe_graphical_controller`
(497 lines) are outliers. Evaluate whether either has extractable sub-concerns
— e.g., the USDA search panel within nutrition_editor could be its own
controller.

### 4b. DRY audit

Look for duplicated patterns across services and controllers. "Consistent" can
mean "copy-pasted." Verify shared logic is actually shared, not just similar.

### 4c. Dead code sweep

After months of rapid development with refactors and feature removals (TUI
retirement, etc.), there may be orphaned methods, unused helpers, routes without
destinations, or views that aren't rendered. Systematic sweep to clean out.

### 4d. Stale comments and documentation

Architectural header comments may describe responsibilities that have shifted.
Verify header comments match current reality. Update CLAUDE.md if any
conventions have changed.

## Ordering

1. Security (1a → 1d)
2. Reliability (2a → 2c)
3. Performance (3a → 3d)
4. Code quality (4a → 4d)

Each area gets one or more commits when complete. Tests must pass (`rake test`)
and lint must be clean (`rake lint`) after each area.

## Out of scope

**Migration consolidation.** CLAUDE.md notes that all migrations should be
consolidated into a single `001_create_schema.rb` for v1.0. That is a separate
task from this audit and will be handled in its own pass.

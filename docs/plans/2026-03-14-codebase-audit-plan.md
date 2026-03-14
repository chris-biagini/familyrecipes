# Codebase Audit Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Systematic audit of all application code for security, reliability, performance, and code quality — reading every file, logging findings, then fixing what's found.

**Architecture:** Four sequential audit areas, each with parallelizable investigation tasks followed by a consolidation-and-fix task. Investigation tasks read files and report findings. Fix tasks implement changes, run tests, and commit.

**Tech Stack:** Rails 8, SQLite, Turbo/Stimulus/importmap, Minitest

**Spec:** `docs/plans/2026-03-14-codebase-audit-design.md`

---

## Chunk 1: Security Audit

### Task 1: Audit controllers for input boundaries and access control

Read every controller and concern. For each action that accepts params, trace the param from `params` through to its final use. Simultaneously check that write actions are gated behind `require_membership` and that all model queries go through `current_kitchen`.

**Files to read:**
- `app/controllers/application_controller.rb` (134 lines)
- `app/controllers/recipes_controller.rb` (140 lines)
- `app/controllers/menu_controller.rb` (97 lines)
- `app/controllers/nutrition_entries_controller.rb` (66 lines)
- `app/controllers/groceries_controller.rb` (62 lines)
- `app/controllers/pwa_controller.rb` (60 lines)
- `app/controllers/ingredients_controller.rb` (56 lines)
- `app/controllers/imports_controller.rb` (48 lines)
- `app/controllers/usda_search_controller.rb` (42 lines)
- `app/controllers/settings_controller.rb` (34 lines)
- `app/controllers/dev_sessions_controller.rb` (31 lines)
- `app/controllers/categories_controller.rb` (29 lines)
- `app/controllers/tags_controller.rb` (31 lines)
- `app/controllers/landing_controller.rb` (26 lines)
- `app/controllers/exports_controller.rb` (18 lines)
- `app/controllers/homepage_controller.rb` (14 lines)
- `app/controllers/concerns/authentication.rb` (58 lines)
- `app/controllers/concerns/meal_plan_actions.rb` (20 lines)

**Check for each controller:**

- [ ] **Step 1:** Read all controller files listed above.
- [ ] **Step 2:** For each action that accepts params, document the param flow:
  - What params does it accept?
  - How are they filtered? (`permit`, `permit!`, `to_unsafe_h`, manual filtering?)
  - Where do they end up? (model attribute, service argument, query condition?)
  - Could a crafted payload cause unexpected behavior?
- [ ] **Step 3:** For each controller, verify access control:
  - Are write actions (create, update, destroy, PATCH, POST, DELETE) guarded by
    `require_membership` or equivalent?
  - Are all model queries scoped through `current_kitchen`?
  - Are there any unscoped `find`, `find_by`, `where` calls on tenant-scoped models?
- [ ] **Step 4:** Log all findings in a structured format:
  - File, line number, issue type, severity (critical/medium/low), description.

---

### Task 2: Audit views and helpers for output safety

Read every view template and helper. Check that user-supplied content is properly escaped. Verify the html_safe allowlist is accurate.

**Files to read:**
- All 32 files in `app/views/` (1,520 lines total)
- `app/helpers/recipes_helper.rb` (185 lines)
- `app/helpers/ingredients_helper.rb` (52 lines)
- `app/helpers/groceries_helper.rb` (49 lines)
- `app/helpers/search_data_helper.rb` (34 lines)
- `app/helpers/application_helper.rb` (16 lines)
- `config/html_safe_allowlist.yml`

- [ ] **Step 1:** Read all view files and helpers listed above.
- [ ] **Step 2:** For each `.html_safe` and `raw()` call:
  - Is it justified? What data is being marked safe?
  - Is the data pre-escaped or guaranteed safe?
  - Does the allowlist entry's `file:line_number` match the actual location?
- [ ] **Step 3:** For each ERB template, check:
  - Are `<%= %>` tags outputting user content through Rails' auto-escaping?
  - Are there any places where user content bypasses escaping?
  - Are HTML attributes properly quoted and escaped?
- [ ] **Step 4:** For each helper method that produces HTML:
  - Is string interpolation of user content escaped with `ERB::Util.html_escape` or `h()`?
  - Are tag helpers (`tag.div`, `content_tag`) used instead of raw string concatenation?
- [ ] **Step 5:** Log all findings.

---

### Task 3: Audit JavaScript for DOM injection

Read every Stimulus controller and JS utility. Verify no unsafe DOM APIs are used with user-supplied data.

**Files to read:**
- All 25 files in `app/javascript/controllers/` (4,073 lines total)
- All 7 files in `app/javascript/utilities/` (735 lines total)
- `app/javascript/application.js` (29 lines)

**Pay particular attention to:**
- `recipe_graphical_controller.js` (497 lines) — builds DOM from recipe content
- `quickbites_graphical_controller.js` (339 lines) — builds DOM from quick bites content
- `nutrition_editor_controller.js` (682 lines) — renders USDA data in DOM
- `search_overlay_controller.js` (306 lines) — renders search results
- `ordered_list_editor_controller.js` (236 lines) — renders user-editable lists

- [ ] **Step 1:** Read all JavaScript files listed above.
- [ ] **Step 2:** Search for and audit every instance of:
  - `innerHTML`, `outerHTML`, `insertAdjacentHTML` — should not be used with
    user-supplied data (prefer `textContent`, `createTextNode`, `createElement`)
  - `eval`, `Function()`, `setTimeout/setInterval` with string args — should never appear
  - Template literals used to build HTML strings
- [ ] **Step 3:** For each graphical editor controller, trace how recipe/quick-bites
  content flows from the server response into DOM elements. Verify every
  user-visible string goes through `textContent` or `createTextNode`.
- [ ] **Step 4:** Log all findings.

---

### Task 4: Audit CSP configuration and nonce strategy

Read the CSP initializer and investigate the session-based nonce trade-off with Turbo Drive.

**Files to read:**
- `config/initializers/content_security_policy.rb` (28 lines)
- `app/views/layouts/application.html.erb` (36 lines)
- `config/importmap.rb` (9 lines)
- `app/javascript/application.js` (29 lines)

- [ ] **Step 1:** Read the CSP initializer. Document the full policy.
- [ ] **Step 2:** Verify every directive is as tight as possible:
  - `script-src`: only `'self'` + nonce? No `unsafe-inline` or `unsafe-eval`?
  - `style-src`: only `'self'` + Google Fonts? No `unsafe-inline`?
  - `connect-src`: does it need `ws:` and `wss:` for ActionCable? Are they scoped?
  - `default-src`, `img-src`, `font-src`, `object-src`, `frame-src`, `base-uri`,
    `form-action`: all as restrictive as possible?
- [ ] **Step 3:** Investigate the nonce strategy:
  - The nonce uses `request.session.id` — this is deterministic per session.
  - Research whether Turbo Drive's page caching/snapshot mechanism breaks
    per-request nonces (the cached HTML would have a stale nonce that doesn't
    match the new response's CSP header).
  - Check Rails' built-in `content_security_policy_nonce_generator` and whether
    it can work with Turbo.
  - Determine: implement per-request nonces, or document why session-based is
    the correct trade-off for this Turbo Drive architecture.
- [ ] **Step 4:** Log findings and recommended action.

---

### Task 5: Audit the import path end-to-end

Trace user-uploaded file content from upload through parsing into the database. This is the highest-risk input surface.

**Files to read:**
- `app/controllers/imports_controller.rb` (48 lines)
- `app/services/import_service.rb` (185 lines)
- `app/services/markdown_importer.rb` (164 lines)
- `app/services/markdown_validator.rb` (33 lines)
- `lib/familyrecipes/recipe_builder.rb` (200 lines)
- `lib/familyrecipes/line_classifier.rb` (49 lines)
- `lib/familyrecipes/ingredient_parser.rb` (30 lines)
- `lib/familyrecipes/cross_reference_parser.rb` (36 lines)

- [ ] **Step 1:** Read all files in the import chain.
- [ ] **Step 2:** Trace the flow:
  - How does the uploaded file arrive? (multipart form, file read, encoding?)
  - What validation happens before parsing? (file type, size limits, encoding?)
  - Can a malicious file crash the parser? (deeply nested structures, huge lines,
    binary content, null bytes?)
  - Does the parser sanitize or escape content before database insertion?
  - Could cross-reference titles (`> @[Title]`) be crafted to reference unintended
    recipes or cause injection?
- [ ] **Step 3:** Check the ImportService for:
  - File size limits
  - File count limits (zip imports)
  - Encoding handling (UTF-8 enforcement?)
  - Error handling for malformed files
- [ ] **Step 4:** Log findings.

---

### Task 6: Audit secrets and run dependency check

Check for hardcoded secrets in source. Verify encryption configuration. Check gem dependencies for known vulnerabilities.

- [ ] **Step 1:** Search the entire codebase for potential secrets:
  - Grep for: `password`, `secret`, `token`, `api_key`, `private_key`, `credential`
  - Check `.env`, `.env.example`, `database.yml`, `credentials.yml.enc`
  - Check `config/initializers/` for any hardcoded values
- [ ] **Step 2:** Verify Active Record Encryption is properly configured:
  - Read `config/credentials.yml.enc` setup (or equivalent)
  - Verify `Kitchen#usda_api_key` encryption configuration
- [ ] **Step 3:** Check gem dependencies:
  - Run `bundle audit check --update` (install `bundler-audit` gem if needed)
  - Review any reported vulnerabilities
  - Check `Gemfile.lock` for any outdated gems with known security patches
- [ ] **Step 4:** Log findings.

---

### Task 7: Fix security findings

Consolidate findings from Tasks 1-6. Implement fixes for all issues found.

- [ ] **Step 1:** Review all findings from Tasks 1-6. Triage by severity.
- [ ] **Step 2:** Implement fixes for critical and medium findings. For each fix:
  - Write a test if the fix is testable (e.g., param rejection, escaping)
  - Make the minimal change needed
- [ ] **Step 3:** For the CSP nonce decision (Task 4), either:
  - Implement per-request nonces if feasible, or
  - Add a code comment documenting the trade-off
- [ ] **Step 4:** Update `html_safe_allowlist.yml` if any line numbers drifted.
- [ ] **Step 5:** Run `rake test` — all tests must pass.
- [ ] **Step 6:** Run `rake lint` — zero offenses.
- [ ] **Step 7:** Run `rake lint:html_safe` — verify allowlist is clean.
- [ ] **Step 8:** Commit: `fix: security audit — [summary of changes]`

---

## Chunk 2: Reliability Audit

### Task 8: Trace all write paths end-to-end

For every controller action that mutates data, trace the complete path through
services, models, side effects, and broadcasts. Build a comprehensive map.

**Files to read (controllers that write):**
- `app/controllers/recipes_controller.rb` — create, update, destroy, parse, serialize
- `app/controllers/menu_controller.rb` — select, select_all, deselect, clear
- `app/controllers/groceries_controller.rb` — check, uncheck, update_custom_items
- `app/controllers/nutrition_entries_controller.rb` — upsert, destroy
- `app/controllers/categories_controller.rb` — update_order, rename, destroy
- `app/controllers/tags_controller.rb` — update
- `app/controllers/settings_controller.rb` — update
- `app/controllers/imports_controller.rb` — create

**Files to read (services they call):**
- `app/services/recipe_write_service.rb` (149 lines)
- `app/services/meal_plan_write_service.rb` (83 lines)
- `app/services/catalog_write_service.rb` (114 lines)
- `app/services/category_write_service.rb` (87 lines)
- `app/services/aisle_write_service.rb` (102 lines)
- `app/services/quick_bites_write_service.rb` (55 lines)
- `app/services/tag_write_service.rb` (48 lines)
- `app/services/import_service.rb` (185 lines)
- `app/services/markdown_importer.rb` (164 lines)
- `app/services/recipe_broadcaster.rb` (36 lines)
- `app/services/cross_reference_updater.rb` (38 lines)

**Files to read (supporting modules in the write path):**
- `lib/familyrecipes/recipe_serializer.rb` (169 lines) — IR hash → markdown for structure-based writes
- `lib/familyrecipes/quick_bites_serializer.rb` (51 lines) — same for quick bites
- `app/jobs/recipe_nutrition_job.rb` (30 lines) — side effect of recipe/catalog writes
- `app/jobs/cascade_nutrition_job.rb` (16 lines) — fans out to cross-referencing recipes

**Files to read (models with write-path logic):**
- `app/models/kitchen.rb` (103 lines) — batch_writes, broadcast_update
- `app/models/meal_plan.rb` (167 lines) — reconcile!, with_optimistic_retry
- `app/models/category.rb` (42 lines) — find_or_create_for, cleanup_orphans
- `app/models/tag.rb` (35 lines) — cleanup_orphans
- `app/models/cross_reference.rb` (44 lines) — resolve_pending

- [ ] **Step 1:** Read all files listed above.
- [ ] **Step 2:** For each write action, document the complete path:

  ```
  Controller#action
    -> params handling
    -> Service.method(args)
      -> model mutations (which models? transactions?)
      -> side effects (reconcile? cascade? nutrition job?)
      -> broadcast (Kitchen#broadcast_update? RecipeBroadcaster?)
    -> response (status code, format)
  ```

- [ ] **Step 3:** For each path, check:
  - Does the write always trigger a broadcast? Any path where it's missed?
  - Is `Kitchen.batch_writes` used when multiple services are called?
  - Can a partial failure leave inconsistent state? (e.g., recipe saved but
    cross-references not updated, or broadcast skipped on error)
  - Are all expected side effects triggered? (orphan cleanup, reconciliation,
    nutrition recalculation)
- [ ] **Step 4:** Log findings as a write-path map plus issues.

---

### Task 9: Audit concurrency and shared-state patterns

Read every service that modifies shared state. Check for races and unsafe reload patterns.

**Files to read:**
- `app/services/aisle_write_service.rb` (102 lines) — modifies Kitchen#aisle_order
- `app/services/meal_plan_write_service.rb` (83 lines) — modifies MealPlan#state
- `app/services/catalog_write_service.rb` (114 lines) — modifies IngredientCatalog
- `app/services/category_write_service.rb` (87 lines) — modifies Category ordering
- `app/services/recipe_write_service.rb` (149 lines) — cascade updates
- `app/models/kitchen.rb` (103 lines) — batch_writes, finalize_batch
- `app/models/meal_plan.rb` (167 lines) — with_optimistic_retry, reconcile!

- [ ] **Step 1:** Read all files listed above.
- [ ] **Step 2:** For each service, check for TOCTOU races:
  - Does it read state, make a decision, then write? Can another request
    interleave between the read and write?
  - Is the check-then-act wrapped in a transaction or otherwise atomic?
- [ ] **Step 3:** Check every `reload` call:
  - Does it discard in-memory changes from other services in the same request?
  - Is it safe within `batch_writes` flow? (batch_writes may call multiple
    services that modify the same Kitchen object)
- [ ] **Step 4:** Check optimistic locking:
  - MealPlan uses `lock_version` — is `with_optimistic_retry` used everywhere
    MealPlan is mutated?
  - Should Kitchen have optimistic locking for `aisle_order` / `category_order`?
- [ ] **Step 5:** Log findings.

---

### Task 10: Audit error handling and Turbo/morph resilience

Read every controller's error handling patterns. Read Stimulus controllers that interact with Turbo lifecycle events.

**Files to read (error handling):**
- All 16 controllers (re-read, focusing on rescue/error paths)
- `app/controllers/concerns/meal_plan_actions.rb` (20 lines)

**Files to read (Turbo/morph):**
- `app/javascript/application.js` (29 lines)
- `app/javascript/controllers/editor_controller.js` (266 lines)
- `app/javascript/controllers/menu_controller.js` (61 lines)
- `app/javascript/controllers/grocery_ui_controller.js` (167 lines)
- `app/javascript/controllers/recipe_state_controller.js` (246 lines)
- `app/javascript/controllers/scale_panel_controller.js` (125 lines)
- `app/javascript/utilities/turbo_fetch.js` (42 lines)

- [ ] **Step 1:** Read all error handling code.
- [ ] **Step 2:** For each controller, check:
  - Does it rescue expected exceptions? (RecordInvalid, StaleObjectError, etc.)
  - Are error responses useful? (status codes, error messages)
  - Can any action silently swallow an error?
- [ ] **Step 3:** Read all Turbo/morph interaction code.
- [ ] **Step 4:** Verify:
  - Open dialogs survive Turbo morphs (turbo:before-morph-element handler)
  - Dialogs close before Turbo cache snapshots (turbo:before-cache handler)
  - UI state is preserved across morphs (checkboxes, collapsed sections)
  - turbo_fetch.js retries network failures appropriately
- [ ] **Step 5:** Log findings.

---

### Task 11: Audit SQLite configuration and resilience

Check database configuration for production readiness. Verify handling of SQLite-specific concurrent access issues.

**Files to read:**
- `config/database.yml` (37 lines)
- `db/schema.rb` (205 lines)
- `app/models/application_record.rb` (7 lines)
- Grep results for `SQLITE_BUSY`, `busy_timeout`, `wal`, `journal_mode`

- [ ] **Step 1:** Read database configuration.
- [ ] **Step 2:** Check:
  - Is WAL mode enabled? (Critical for concurrent reads during writes.)
  - Is `busy_timeout` configured? (Prevents immediate SQLITE_BUSY failures.)
  - Is the Solid Cable database configured for concurrent access?
- [ ] **Step 3:** Check JSON column access patterns:
  - `meal_plans.state` — how is it read and written? Full JSON replacement or
    partial updates?
  - `ingredient_catalog.aliases`, `ingredient_catalog.portions`,
    `ingredient_catalog.sources` — same check.
  - `recipes.nutrition_data` — same check.
  - Are any JSON columns queried with SQL JSON functions that need indexes?
- [ ] **Step 4:** Log findings.

---

### Task 12: Note test coverage gaps

While reviewing write paths from Tasks 8-11, note gaps in test coverage.

**Files to read:**
- `test/controllers/` — all 17 controller test files (4,000 lines)
- `test/services/` — all 21 service test files (4,748 lines)
- `test/models/` — all 16 model test files (2,597 lines)

- [ ] **Step 1:** For each write path identified in Task 8, check whether there
  are tests for:
  - Success case (happy path)
  - Validation failure (bad input)
  - Unauthorized access (no membership)
  - Tenant isolation (Kitchen A cannot access Kitchen B's data)
- [ ] **Step 2:** For each broadcast trigger, check whether there is an assertion
  that it fires (or is skipped when batching).
- [ ] **Step 3:** Log gaps as a checklist. Do NOT write new tests in this task —
  just document what is missing. Flag critical gaps (tenant isolation, authz)
  for immediate attention in the fix task.

---

### Task 13: Fix reliability findings

Consolidate findings from Tasks 8-12. Implement fixes.

- [ ] **Step 1:** Review all findings from Tasks 8-12. Triage by severity.
- [ ] **Step 2:** Fix any missing broadcasts (e.g., SettingsController if confirmed).
- [ ] **Step 3:** Fix any TOCTOU races (e.g., AisleWriteService aisle sync).
- [ ] **Step 4:** Fix any unsafe reload patterns.
- [ ] **Step 5:** Fix any error handling gaps.
- [ ] **Step 6:** Fix SQLite configuration issues (WAL mode, busy_timeout).
- [ ] **Step 7:** Write tests for critical gaps found in Task 12 (tenant isolation,
  authorization — not comprehensive test expansion, just the critical holes).
- [ ] **Step 8:** Run `rake test` — all tests must pass.
- [ ] **Step 9:** Run `rake lint` — zero offenses.
- [ ] **Step 10:** Commit: `fix: reliability audit — [summary of changes]`

---

## Chunk 3: Performance Audit

### Task 14: Audit queries and eager loading

Read every controller action that loads data for rendering. Trace which queries
fire and whether associations are eagerly loaded.

**Files to read:**
- `app/controllers/homepage_controller.rb` (14 lines)
- `app/controllers/recipes_controller.rb` (140 lines) — show action
- `app/controllers/menu_controller.rb` (97 lines) — show action
- `app/controllers/groceries_controller.rb` (62 lines) — show action
- `app/controllers/ingredients_controller.rb` (56 lines) — index action
- `app/models/recipe.rb` (67 lines) — scopes, with_full_tree
- `app/models/category.rb` (42 lines) — scopes, with_recipes
- `app/models/ingredient_catalog.rb` (230 lines) — lookup_for, resolver_for

**Views that drive queries (read to understand what data is accessed):**
- `app/views/homepage/show.html.erb` (148 lines)
- `app/views/recipes/show.html.erb` + partials (269 lines total)
- `app/views/menu/show.html.erb` + partials (166 lines total)
- `app/views/groceries/show.html.erb` + partials (179 lines total)
- `app/views/ingredients/index.html.erb` + partials (414 lines total)

- [ ] **Step 1:** Read all files listed above.
- [ ] **Step 2:** For each page, trace the query chain:
  - What does the controller load? What `includes`/`preload` calls are made?
  - What associations does the view access? Are they all preloaded?
  - Are there any loops that trigger lazy loads (N+1)?
- [ ] **Step 3:** Check `Recipe.with_full_tree`:
  - Does it eagerly load everything the show page needs?
  - Does it load too much for pages that don't need the full tree?
- [ ] **Step 4:** Consider adding `strict_loading` spot-checks to confirm no
  lazy loads in critical paths.
- [ ] **Step 5:** Log findings.

---

### Task 15: Audit memory usage and in-memory data structures

Read every service and helper that builds in-memory collections. Check for
disproportionate memory use.

**Files to read:**
- `app/services/ingredient_row_builder.rb` (237 lines)
- `app/services/shopping_list_builder.rb` (159 lines)
- `app/services/recipe_availability_calculator.rb` (63 lines)
- `app/services/ingredient_resolver.rb` (85 lines)
- `app/helpers/search_data_helper.rb` (34 lines)
- `app/helpers/recipes_helper.rb` (185 lines)
- `app/helpers/groceries_helper.rb` (49 lines)

- [ ] **Step 1:** Read all files listed above.
- [ ] **Step 2:** For each service/helper, check:
  - What data structures does it build? How large can they get?
  - Are full AR objects stored where IDs or lightweight structs would suffice?
  - Is memoization used? Could memoized data leak across requests?
  - Are collections built eagerly when streaming/batching would work?
- [ ] **Step 3:** Specifically check `IngredientRowBuilder#compute_recipes_by_ingredient`:
  - It stores full `Recipe` AR objects indexed by ingredient name.
  - Downstream usage needs: `source.title`, `source.slug`, `source.is_a?(Recipe)`.
  - Evaluate whether a lighter representation would help.
- [ ] **Step 4:** Check `SearchDataHelper`:
  - What is the JSON blob size for a typical kitchen? (Count recipes, tags,
    ingredients to estimate.)
  - Is it embedded in every page or only pages with the search overlay?
  - Should it be lazy-loaded via fetch on overlay open?
- [ ] **Step 5:** Log findings.

---

### Task 16: Audit reconciliation frequency and index coverage

Trace MealPlan reconciliation call frequency. Verify database indexes match
query patterns.

**Files to read:**
- `app/models/meal_plan.rb` (167 lines) — reconcile_kitchen!, prune methods
- `app/models/kitchen.rb` (103 lines) — batch_writes, finalize_batch
- `db/schema.rb` (205 lines)
- All service files that call `reconcile` or `broadcast_update`

- [ ] **Step 1:** Read all files listed above.
- [ ] **Step 2:** Trace reconciliation:
  - Which services call `MealPlan.reconcile_kitchen!`?
  - How often does it fire? (After every recipe CRUD, quick bites edit,
    catalog change, deselect?)
  - What queries does `prune_stale_selections` run each time?
  - Is any of this work redundant? (e.g., reconciling after a catalog edit
    when no recipes or selections changed)
- [ ] **Step 3:** Verify index coverage:
  - Read `schema.rb` and list all indexes.
  - Cross-reference with query patterns observed in Tasks 14-15.
  - Check: are all foreign keys indexed? Are there composite queries that
    would benefit from composite indexes?
- [ ] **Step 4:** Log findings.

---

### Task 17: Fix performance findings

Consolidate findings from Tasks 14-16. Implement fixes.

- [ ] **Step 1:** Review all findings. Triage by impact.
- [ ] **Step 2:** Fix any N+1 queries found (add `includes`/`preload`).
- [ ] **Step 3:** Fix any disproportionate memory usage (e.g., IngredientRowBuilder).
- [ ] **Step 4:** Fix any missing indexes.
- [ ] **Step 5:** Optimize reconciliation frequency if warranted.
- [ ] **Step 6:** For SearchDataHelper: if payload is small (< 10KB), leave as-is
  with a comment noting the trade-off. If large, implement lazy-loading.
- [ ] **Step 7:** Run `rake test` — all tests must pass.
- [ ] **Step 8:** Run `rake lint` — zero offenses.
- [ ] **Step 9:** Commit: `perf: performance audit — [summary of changes]`

---

## Chunk 4: Code Quality Audit

### Task 18: Dead code sweep — Ruby

Systematically search for unused Ruby code across models, services, helpers, and controllers.

**Files to search across:**
- All files in `app/models/` (716 lines)
- All files in `app/services/` (1,661 lines)
- All files in `app/helpers/` (336 lines)
- All files in `app/controllers/` (888 lines)
- All files in `app/jobs/` (52 lines)
- All files in `lib/familyrecipes/` (2,274 lines)
- All files in `lib/tasks/` (rake tasks)
- `config/routes.rb` (60 lines)

- [ ] **Step 1:** For each public method in models and services, grep for callers.
  Flag any method with zero callers outside its own file and test file.
- [ ] **Step 2:** For each helper method, grep for usage in views and controllers.
  Flag unused helpers.
- [ ] **Step 3:** For each route in `routes.rb`, verify the controller action exists
  and is reachable. Flag orphaned routes.
- [ ] **Step 4:** For each view partial, grep for `render` calls that reference it.
  Flag unrendered partials.
- [ ] **Step 5:** Grep for references to removed features: `NutritionTui`,
  `nutrition_tui`, `bin/nutrition`, `tty-`, `pastel`, `ratatui`.
- [ ] **Step 6:** Log all dead code found.

---

### Task 19: Dead code sweep — JavaScript

Systematically search for unused JavaScript code.

**Files to search across:**
- All files in `app/javascript/controllers/` (4,073 lines)
- All files in `app/javascript/utilities/` (735 lines)
- `app/javascript/application.js` (29 lines)
- All view files in `app/views/` (1,520 lines)
- `config/importmap.rb` (9 lines)

- [ ] **Step 1:** For each Stimulus controller, grep for its `data-controller` name
  in view templates. Flag any controller not referenced in any view.
- [ ] **Step 2:** For each JS utility module, grep for imports across all JS files.
  Flag unused utilities.
- [ ] **Step 3:** For each exported function in utilities, grep for callers.
  Flag unused exports.
- [ ] **Step 4:** Check `importmap.rb` — are all pinned modules actually imported?
- [ ] **Step 5:** Log all dead code found.

---

### Task 20: DRY and complexity audit

Read through services, controllers, and large files looking for duplication
and excessive complexity.

**Files to read (complexity — all files over thresholds):**

Ruby files over 200 lines:
- `app/models/ingredient_catalog.rb` (230 lines)
- `app/services/ingredient_row_builder.rb` (237 lines)
- `lib/familyrecipes/nutrition_calculator.rb` (220 lines)
- `lib/familyrecipes/build_validator.rb` (209 lines)
- `lib/familyrecipes/recipe_builder.rb` (200 lines)

JavaScript files over 300 lines:
- `app/javascript/controllers/nutrition_editor_controller.js` (682 lines)
- `app/javascript/controllers/recipe_graphical_controller.js` (497 lines)
- `app/javascript/controllers/quickbites_graphical_controller.js` (339 lines)
- `app/javascript/controllers/search_overlay_controller.js` (306 lines)
- `app/javascript/utilities/ordered_list_editor_utils.js` (311 lines)

**Files to read (DRY — services with similar patterns):**
- All 18 service files (1,661 lines total)
- All 16 controller files (888 lines total)

- [ ] **Step 1:** Read all files above the complexity thresholds.
- [ ] **Step 2:** For each, evaluate:
  - Can it be decomposed into smaller, focused units?
  - Are there methods longer than 5 lines that should be extracted?
  - Is the abstraction level consistent?
  - For JS: could any sub-concern be a separate Stimulus controller?
- [ ] **Step 3:** Read all service files looking for duplication:
  - Are there duplicated patterns across services? (e.g., similar finalize
    patterns, similar broadcast calls, similar param validation)
  - Could any shared logic be extracted into a concern or utility?
- [ ] **Step 4:** Read all controller files looking for duplication:
  - Similar param handling patterns?
  - Similar error handling patterns?
  - Any copy-pasted blocks?
- [ ] **Step 5:** Log findings: what to extract, what to unify, what to split.

---

### Task 21: Convention consistency and documentation currency

Verify the codebase follows its own rules. Check that every architectural
header comment matches current reality.

**Files to read:**
- `CLAUDE.md` — the rules to check against
- Every Ruby class/module (all files in app/ and lib/familyrecipes/)
- Every JavaScript controller and utility

- [ ] **Step 1:** Read CLAUDE.md to refresh the rules.
- [ ] **Step 2:** Check Enumerable usage:
  - Grep for `each` + `<<` or `each` + `push` patterns. Flag any that should
    use `map`, `select`, `flat_map`, etc.
  - Grep for `result = []` followed by `.each` — the CLAUDE.md anti-pattern.
- [ ] **Step 3:** Check comment quality:
  - Grep for comments that restate method names or class names.
  - Flag narrating comments (per CLAUDE.md rules).
- [ ] **Step 4:** For every Ruby class/module, check that it has an architectural
  header comment. For each existing header comment, verify it accurately
  describes the class's current role, collaborators, and constraints.
- [ ] **Step 5:** For every JavaScript controller/utility, same check.
- [ ] **Step 6:** Check CLAUDE.md itself — does it still accurately describe
  the codebase? Are there any new conventions that should be documented?
- [ ] **Step 7:** Log findings: missing comments, stale comments, CLAUDE.md updates.

---

### Task 22: Fix code quality findings

Consolidate findings from Tasks 18-21. Implement fixes.

- [ ] **Step 1:** Review all findings. Triage by impact.
- [ ] **Step 2:** Delete dead code found in Tasks 18-19.
- [ ] **Step 3:** Extract duplicated logic found in Task 20 (if the duplication
  is substantial enough to warrant extraction — do not create abstractions for
  two similar lines).
- [ ] **Step 4:** Split or refactor files that are too complex (only if the
  split clearly improves the code — do not split just to hit a line count).
- [ ] **Step 5:** Fix Enumerable anti-patterns.
- [ ] **Step 6:** Remove or rewrite narrating comments.
- [ ] **Step 7:** Add missing architectural header comments.
- [ ] **Step 8:** Update stale header comments.
- [ ] **Step 9:** Update CLAUDE.md if needed.
- [ ] **Step 10:** Run `rake test` — all tests must pass.
- [ ] **Step 11:** Run `rake lint` — zero offenses.
- [ ] **Step 12:** Run `rake lint:html_safe` — verify allowlist is clean.
- [ ] **Step 13:** Commit: `refactor: code quality audit — [summary of changes]`

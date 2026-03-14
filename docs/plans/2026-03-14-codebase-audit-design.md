# Codebase Audit — 1.0 Readiness Pass

**Date:** 2026-03-14
**Goal:** Thorough, systematic audit of the entire codebase for security,
reliability, performance, and code quality. Each area is audited by reading
every relevant file, documenting findings, then fixing what's found. The
audit itself is the primary deliverable — the fix list emerges from the audit,
not the other way around.

**Approach:** Fix-by-area. For each area: read every file in scope, log
findings, fix issues, commit. Tests must pass and lint must be clean after
each area.

## Area 1: Security Audit

**Scope:** Every file that handles user input, renders output, or enforces
access control.

**Process:**

1. **Input boundary audit.** Read every controller action that accepts params.
   For each, trace the param from `params` through to its final use. Check:
   - Are strong params properly applied? Any `permit!` or `to_unsafe_h`?
   - Is user input validated before reaching models/services?
   - Could a crafted payload cause unexpected behavior?

2. **Output safety audit.** Read every view template (`.html.erb`) and every
   helper that produces HTML. For each:
   - Is user-supplied content properly escaped?
   - Are `.html_safe` and `raw()` calls justified? Do they match the allowlist?
   - Does the allowlist (`html_safe_allowlist.yml`) have accurate line numbers?

3. **CSP audit.** Read `content_security_policy.rb` and every file that injects
   scripts, styles, or external resources. Verify the policy is tight and
   correctly enforced. Investigate the session-based nonce and whether a
   per-request nonce is feasible with Turbo Drive.

4. **Access control audit.** Read every controller and verify that write actions
   are gated behind `require_membership`. Check that multi-tenant scoping is
   enforced everywhere — no unscoped model queries.

5. **Secrets audit.** Check for any hardcoded credentials, API keys, or secrets
   in source. Verify encrypted columns are properly configured.

**Done when:** Every controller, view, and helper has been read and checked
against the above criteria.

## Area 2: Reliability Audit

**Scope:** Every write path, broadcast, and concurrent-access pattern.

**Process:**

1. **Write path trace.** For every controller action that mutates data, trace
   the full path: controller → service → model → broadcast. For each path,
   check:
   - Does the write trigger the correct broadcast(s)?
   - Is the write wrapped in a transaction where needed?
   - Can partial failures leave the system in an inconsistent state?
   - Are side effects (reconciliation, cascade updates) properly triggered?

2. **Concurrency audit.** Read every service that modifies shared state
   (Kitchen attributes, MealPlan, IngredientCatalog). For each:
   - Are there TOCTOU races (check-then-act without atomicity)?
   - Is optimistic locking used where concurrent writes are possible?
   - Does `reload` discard in-memory changes from other services in the same
     request?

3. **Broadcast completeness.** Map every write path to its expected broadcast.
   Verify no path silently skips broadcasting. Check that `batch_writes`
   correctly defers and then fires a single broadcast.

4. **Error recovery.** Read every controller's error handling. Check:
   - Do validation failures return useful error messages?
   - Do `StaleObjectError` rescues cover all relevant controllers?
   - Can network failures or timeouts leave orphaned state?

5. **Turbo/morph resilience.** Read `application.js` and every Stimulus
   controller that interacts with Turbo events. Verify:
   - Open dialogs survive morphs
   - UI state (checkboxes, collapsed sections, scroll position) is preserved
   - Page caching doesn't serve stale content

**Done when:** Every write path has been traced end-to-end and every
concurrent-access pattern has been verified.

## Area 3: Performance Audit

**Scope:** Every database query, every page render, every data structure held
in memory.

**Process:**

1. **Query audit.** Read every model scope, every `includes`/`preload` call,
   and every controller that loads data. For each page:
   - What queries does it execute? Are associations eager-loaded?
   - Are there N+1 patterns hiding behind `each` loops?
   - Spot-check with `strict_loading` where suspicion warrants it.

2. **Memory audit.** Read every service and helper that builds in-memory data
   structures. Check:
   - Are full AR objects stored where lightweight data would suffice?
   - Are large collections built eagerly when they could be streamed?
   - Is memoization used appropriately (and not leaking across requests)?

3. **Payload audit.** Check what data is embedded in HTML responses. Measure
   the SearchDataHelper JSON blob size. Evaluate whether any embedded data
   should be lazy-loaded instead.

4. **Reconciliation frequency.** Trace how often `MealPlan#reconcile!` runs
   and what queries it triggers each time. Evaluate whether any work is
   redundant or could be deferred.

5. **Index coverage.** Read `schema.rb` and cross-reference with actual query
   patterns. Verify all frequently-queried columns and foreign keys are indexed.

**Done when:** Every page's query profile has been examined and every in-memory
data structure has been reviewed for proportionality.

## Area 4: Code Quality Audit

**Scope:** Every Ruby and JavaScript file in the application.

**Process:**

1. **Dead code sweep.** Systematically check for:
   - Model methods not called anywhere
   - Helper methods not referenced in views or controllers
   - Routes that don't map to used controller actions
   - Views/partials not rendered anywhere
   - JavaScript functions/controllers not referenced in HTML
   - Leftover references to removed features (TUI, etc.)

2. **DRY audit.** Read through services and controllers looking for:
   - Duplicated logic that should be extracted
   - Similar-but-different patterns that could be unified
   - Copy-pasted code blocks across files

3. **Complexity audit.** Read every file over 200 lines (Ruby) or 300 lines
   (JavaScript). For each:
   - Can it be decomposed into smaller, focused units?
   - Are there methods longer than 5 lines that should be extracted?
   - Is the abstraction level consistent within each file?

4. **Convention consistency.** Verify the codebase follows its own rules:
   - Enumerable over imperative loops (per CLAUDE.md)
   - No narrating comments (per CLAUDE.md)
   - Architectural header comments present and accurate on every class/module
   - Service patterns consistent (class method factories, finalize steps, etc.)

5. **Documentation currency.** Read every architectural header comment and
   verify it matches the code it describes. Update CLAUDE.md if conventions
   have drifted.

**Done when:** Every file has been read and checked against quality criteria.

## Ordering

1. Security — highest stakes, fix first
2. Reliability — correctness before speed
3. Performance — optimize what's known-correct
4. Code quality — clean up after substantive changes

## Out of scope

**Migration consolidation.** CLAUDE.md notes that all migrations should be
consolidated into a single `001_create_schema.rb` for v1.0. That is a separate
task from this audit and will be handled in its own pass.

**Feature work.** This audit fixes what exists. It does not add new features,
new pages, or new capabilities.

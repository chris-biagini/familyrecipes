# Release Audit System — Design Spec

A tiered code quality and release readiness system for Family Recipes,
designed to catch correctness, stability, and security issues before shipping.

## Problem

CI (test.yml) gates every push with lint, tests, Brakeman, and bundler-audit.
This is the right level for continuous development, but not enough for release
confidence. Heavier checks — code coverage analysis, dead code detection,
schema integrity, doc-vs-app contract verification, exploratory QA, security
pen tests, accessibility — are either missing entirely or exist but aren't
wired into any workflow (e.g., the Playwright security tests in
test/security/).

Ad-hoc "go find problems" prompts produce diminishing returns as the codebase
matures. The system needs structured, repeatable, automated quality gates
that scale with the project as it moves toward wider distribution and
eventually a paid hosted product.

## Design

Three tiers, each building on the last:

### Tier 1 — CI (every push, no changes)

Existing test.yml workflow. Runs on every push to main and every PR:

- RuboCop (lint + html_safe audit)
- Minitest (all test/**/*_test.rb)
- JavaScript tests (Node test runner)
- Brakeman (static security, medium+ confidence)
- bundler-audit (dependency vulnerabilities)
- Production migration/seed smoke test

No changes needed. This tier is already solid.

### Tier 2 — `rake release:audit` (before every release)

A single rake task that runs heavier automated checks too slow for every-push
CI but required before tagging a release. Exits nonzero on any failure.
Also runs in CI on tag pushes (added to docker.yml before the Docker build
step) as a safety net.

#### 2a. Code coverage analysis

**New gem: simplecov** (dev/test group only).

SimpleCov is added to test_helper.rb and instruments the test suite. It
writes an HTML report to `coverage/` (gitignored) and a machine-readable
`.last_run.json`.

The audit task reads `.last_run.json` and enforces a coverage floor. Starting
floor: **80% line coverage**. The floor is configured in a YAML file
(`config/release_audit.yml`) so it can ratchet up over time without editing
rake task code.

SimpleCov runs during `rake test` (already part of the default rake task).
The audit task only reads the result — it doesn't re-run the tests.

#### 2b. Dead code detection

**New gem: debride** (dev group only).

Scans app/ and lib/ for methods defined but never called. Uses an allowlist
(`config/debride_allowlist.txt`) for false positives:

- Callbacks (before_save, after_create, etc.)
- Template helpers called from ERB
- Stimulus action targets
- Dynamic dispatch (send, public_send)
- Rails conventions (perform, call, etc.)

The audit task runs debride, filters against the allowlist, and fails if new
unreachable methods appear. The allowlist is maintained manually — when
debride flags something legitimate, add it with a comment explaining why.

#### 2c. Dependency health

Three checks, run in sequence:

1. **bundler-audit** — known CVEs. Hard fail on any advisory.
2. **bundle outdated** — lists available updates categorized as patch, minor,
   major. Informational only (no fail), but printed in the report so the
   developer can make informed decisions.
3. **License audit** — uses `license_finder` to scan all dependencies for
   copyleft licenses (GPL, AGPL, SSPL, EUPL) that could create obligations
   for a paid product. Hard fail on any copyleft dependency. Allowlist for
   false positives (`config/license_allowlist.yml`) — some gems report GPL
   but are actually dual-licensed MIT.

#### 2d. Database schema integrity

Custom rake task that introspects the schema and ActiveRecord models:

1. **Missing foreign keys** — finds `belongs_to` associations without a
   corresponding FK constraint in the database. Reports but doesn't fail
   (SQLite FK support has nuances). Listed in the report as warnings.
2. **Missing indexes** — finds columns referenced in scopes, `find_by`,
   `where`, and `order` calls that lack a database index. Informational.
3. **Orphaned records** — runs referential integrity checks for all
   `belongs_to` associations, reporting any records pointing to nonexistent
   parents. Hard fail — orphaned data indicates a bug.

#### 2e. Doc-vs-app contract verification

The help site (docs/help/) is a behavioral contract. This check parses the
help docs and verifies key claims against the running app:

- **Route existence** — extracts route references from docs and verifies
  they resolve (using `Rails.application.routes.recognize_path` or
  integration test requests).
- **Feature flags** — verifies settings mentioned in docs correspond to
  actual Kitchen model columns or configuration.
- **UI element presence** — for key documented workflows (e.g., "click
  Settings to configure your kitchen"), runs lightweight integration checks
  that the referenced elements exist in rendered pages.

This is not a full E2E test — it's a contract check. It answers: "does the
app still have the things the docs say it has?"

Implementation: a Minitest integration test file
(`test/release/doc_contract_check.rb`) named to avoid the `_test.rb` suffix
so it won't match the normal `test/**/*_test.rb` FileList glob. Run only by
the audit task via explicit `ruby -Itest test/release/doc_contract_check.rb`.

#### 2f. Consolidated report

All Tier 2 checks produce a summary printed at the end:

```
=== Release Audit Report ===
Coverage:        87.3% (floor: 80%) ✓
Dead code:       0 new unreachable methods ✓
Vulnerabilities: 0 known CVEs ✓
Outdated deps:   3 patch, 1 minor (info only)
Licenses:        all permissive ✓
Schema FKs:      2 missing (warning)
Schema indexes:  1 unindexed column (warning)
Orphaned records: 0 ✓
Doc contracts:   14/14 verified ✓
─────────────────────────────
RESULT: PASS
```

Exit code 0 = pass, nonzero = fail. Warnings don't fail the audit but are
visible for the developer to assess.

### Tier 3 — Structured exploratory review (before minor/major releases)

Runs before minor (`vX.Y`) and major (`vX`) releases. Requires a running dev
server. Invoked via `rake release:audit:full` (which runs Tier 2 first, then
Tier 3) or individually.

#### 3a. Security pen tests

**Existing infrastructure, newly automated.**

Wraps the six Playwright specs in test/security/ into a single rake task:

```bash
rake release:audit:security
```

The task:
1. Starts a test server (MULTI_KITCHEN=true, test fixtures loaded)
2. Seeds security kitchens (idempotent seed_security_kitchens.rb)
3. Runs all test/security/*.spec.mjs via npx playwright test
4. Tears down the server
5. Reports pass/fail

No new tests needed — just orchestration.

#### 3b. Exploratory QA walkthrough

**New Playwright test suite** in `test/release/exploratory/`.

A structured walkthrough of every major user flow in a realistic multi-tenant
setup. This is product-level QA, not unit testing.

**Flows:**
- Recipe lifecycle: create, edit (graphical + plaintext), view, delete
- Quick Bites: create, edit, delete
- Cross-references: create recipe with `> @[Title]` import, verify rendering
- Menu management: add/remove recipes and quick bites
- Grocery list: verify generation from menu, check-off, custom items,
  aisle grouping, on-hand
- Ingredients catalog: search, USDA import, density/portion editing,
  coverage filter, nutrition label
- Dinner picker: spin, verify recency weighting affects results
- Settings: kitchen branding, API keys, tag management
- Multi-tenant: two kitchens, verify complete isolation
- Import/export: ZIP backup, restore (AI import mocked)
- Navigation: search overlay, mobile viewport FAB, breadcrumbs
- Edge cases: empty states, very long recipe titles, special characters

**Assertions at each step:**
- Zero JS console errors (Playwright console listener)
- No network errors (4xx/5xx responses, failed asset loads)
- Key content present after each action (title appears after save, list
  populates after selection, etc.)
- Page renders within 5 seconds (sanity, not benchmark)

```bash
rake release:audit:explore   # just exploratory QA
rake release:audit:full      # Tier 2 + 3a + 3b + 3c + 3d
```

#### 3c. Performance baseline

Captures page load times, asset sizes, and request counts for key pages.
Writes results to `tmp/perf_baseline_YYYY-MM-DD.json`. No pass/fail — purely
a record for trend detection over time.

**Pages measured:**
- Home / recipe index
- Single recipe view
- Recipe editor (graphical mode)
- Groceries page (with populated menu)
- Ingredients catalog
- Dinner picker

Uses Playwright's performance API (Navigation Timing, Resource Timing) to
capture real browser metrics.

#### 3d. Accessibility spot-check

**New npm dependency: @axe-core/playwright.**

Injects axe-core into key pages via Playwright and reports WCAG 2.1 AA
violations.

**Pages checked:** recipe view, recipe editor, groceries, ingredients
catalog, settings, dinner picker.

**Severity handling:**
- Critical / serious violations → hard fail
- Moderate / minor → reported as warnings

This catches mechanical issues (missing alt text, insufficient contrast,
missing labels, broken ARIA) but is not a substitute for manual accessibility
testing.

### Enforcement

#### Pre-push hook (enhanced)

The existing `.git/hooks/pre-push` runs `bundle exec rake lint`. Enhanced
behavior for tag pushes:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Running pre-push lint..."
bundle exec rake lint

# Detect tag pushes from stdin (git provides refs being pushed)
while read local_ref local_sha remote_ref remote_sha; do
  if [[ "$remote_ref" == refs/tags/v* ]]; then
    TAG="${remote_ref#refs/tags/}"
    BASE_TAG=$(echo "$TAG" | sed 's/[a-zA-Z]*$//')

    # Classify tag tier
    if echo "$BASE_TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
      TIER="patch"
    elif echo "$BASE_TAG" | grep -qE '^v[0-9]+(\.[0-9]+)?$'; then
      TIER="minor_or_major"
    else
      continue
    fi

    HEAD_SHA=$(git rev-parse HEAD)

    # Tier 2: require release:audit marker for all releases
    MARKER="tmp/release_audit_pass.txt"
    if [ ! -f "$MARKER" ]; then
      echo "ERROR: Release audit not run. Execute: rake release:audit"
      exit 1
    fi

    # Verify marker matches current HEAD (no commits since audit)
    MARKER_SHA=$(head -1 "$MARKER")
    if [ "$MARKER_SHA" != "$HEAD_SHA" ]; then
      echo "ERROR: Release audit was run against a different commit."
      echo "  Audit SHA: $MARKER_SHA"
      echo "  HEAD SHA:  $HEAD_SHA"
      echo "Re-run: rake release:audit"
      exit 1
    fi

    # Check marker freshness (48 hours)
    MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
    if [ "$MARKER_AGE" -gt 172800 ]; then
      echo "ERROR: Release audit is stale (>48h). Re-run: rake release:audit"
      exit 1
    fi

    # Tier 3: require full audit marker for minor/major
    if [ "$TIER" = "minor_or_major" ]; then
      FULL_MARKER="tmp/release_audit_full_pass.txt"
      if [ ! -f "$FULL_MARKER" ]; then
        echo "ERROR: Full release audit not run for $TIER release."
        echo "Execute: rake release:audit:full"
        exit 1
      fi
      FULL_SHA=$(head -1 "$FULL_MARKER")
      if [ "$FULL_SHA" != "$HEAD_SHA" ]; then
        echo "ERROR: Full audit was run against a different commit."
        echo "Re-run: rake release:audit:full"
        exit 1
      fi
      FULL_AGE=$(( $(date +%s) - $(stat -c %Y "$FULL_MARKER" 2>/dev/null || echo 0) ))
      if [ "$FULL_AGE" -gt 172800 ]; then
        echo "ERROR: Full release audit is stale (>48h). Re-run: rake release:audit:full"
        exit 1
      fi
    fi
  fi
done

echo "Pre-push checks passed."
```

Marker files (`tmp/release_audit_pass.txt`,
`tmp/release_audit_full_pass.txt`) are written by the audit tasks on
success. First line is the git SHA at time of audit; second line is a
human-readable timestamp. They are gitignored — they exist only locally
to prove the audit was run recently against the current code. The hook
verifies both freshness (< 48 hours) and SHA match (no commits since
audit).

#### CI enforcement (docker.yml)

New job steps added to docker.yml before the Docker build, running only on
tag pushes. The steps:

1. Set up Ruby, install gems, set up Node, install JS deps (same as test.yml)
2. Run `bundle exec rake test` with SimpleCov enabled to generate coverage data
3. Run `bundle exec rake release:audit` to check all Tier 2 gates

This is a safety net — even if the pre-push hook is bypassed (e.g., pushing
from a different machine), CI catches it.

For Tier 3 checks (which need a browser), CI does NOT run them — they're
enforced by the pre-push hook marker. CI runs Tier 2 only.

### Configuration

All thresholds and allowlists live in config files, not rake task code:

```
config/
  release_audit.yml          # coverage floor, marker freshness window
  debride_allowlist.txt      # dead code false positives
  license_allowlist.yml      # dual-licensed gems flagged as copyleft
  html_safe_allowlist.yml    # (existing) XSS audit allowlist
  brakeman.ignore            # (existing) Brakeman false positives
```

`release_audit.yml` example:

```yaml
coverage:
  floor: 80
  # Ratchet up over time as gaps are filled

marker:
  max_age_hours: 48

schema:
  # Foreign key warnings don't fail (SQLite nuances)
  fail_on_missing_fk: false
  fail_on_orphaned_records: true

licenses:
  # These license families trigger a hard fail
  copyleft:
    - GPL
    - AGPL
    - SSPL
    - EUPL
```

### New dependencies

**Ruby (Gemfile, development/test group):**
- `simplecov` — code coverage instrumentation and reporting
- `debride` — dead code detection (unreachable method finder)
- `license_finder` — dependency license scanning (ThoughtWorks tool,
  widely used in enterprise for license compliance)

**JavaScript (package.json, devDependencies):**
- `@axe-core/playwright` — accessibility testing via Playwright

### Git hooks

The pre-push hook is critical infrastructure — it enforces lint on every
push and release audit completion on tag pushes. Currently it lives only
in `.git/hooks/pre-push` (untracked). This feature moves it into the repo:

**`bin/hooks/pre-push`** — the canonical hook script, checked into git.

**`bin/setup`** — enhanced (or created) to symlink `bin/hooks/pre-push` →
`.git/hooks/pre-push` as part of project setup. This runs automatically
on `bin/setup` (standard Rails convention) so new clones get the hook
without manual steps.

### CLAUDE.md updates

A new "Release Audit" section in CLAUDE.md documenting the operational
view: tiers, commands, release workflow. Keeps it concise — points to the
spec for design rationale.

### File layout

New files created by this feature:

```
bin/
  hooks/
    pre-push                   # Canonical pre-push hook (symlinked into .git/hooks/)
  setup                        # Project setup script (installs hooks, deps)

lib/tasks/
  release_audit.rake           # Tier 2 orchestrator + individual tasks
  release_audit_schema.rake    # Schema integrity checks
  release_audit_coverage.rake  # Coverage floor enforcement
  release_audit_deps.rake      # Dependency health + license audit
  release_audit_dead_code.rake # Debride wrapper + allowlist
  release_audit_docs.rake      # Doc contract verification

config/
  release_audit.yml            # Thresholds and settings
  debride_allowlist.txt        # Dead code false positives
  license_allowlist.yml        # License overrides

test/release/
  doc_contract_check.rb        # Doc-vs-app contract checks (not _test.rb to avoid normal suite)
  exploratory/
    *.spec.mjs                 # Playwright exploratory QA specs
    helpers.mjs                # Shared Playwright test utilities

tmp/
  release_audit_pass.txt       # Tier 2 marker (gitignored)
  release_audit_full_pass.txt  # Tier 3 marker (gitignored)
  perf_baseline_*.json         # Performance snapshots (gitignored)
```

### Command summary

```bash
# Tier 2 — run before any release tag
rake release:audit

# Tier 3 — run before minor/major releases
rake release:audit:full      # Tier 2 + all Tier 3 checks
rake release:audit:security  # just security pen tests
rake release:audit:explore   # just exploratory QA
rake release:audit:a11y      # just accessibility check
rake release:audit:perf      # just performance baseline

# Individual Tier 2 checks (for debugging / partial runs)
rake release:audit:coverage
rake release:audit:dead_code
rake release:audit:deps
rake release:audit:schema
rake release:audit:docs
```

### What this does NOT cover

- **Feature completeness** — this system checks that what exists works
  correctly, not that everything planned for 1.0 is implemented.
- **Visual regression** — no screenshot diffing. The exploratory QA checks
  that pages render and contain expected content, but not that they look
  right. This could be added later if visual consistency becomes a concern.
- **Load testing** — the performance baseline measures single-user page
  loads, not concurrent user behavior. Appropriate for the current homelab
  scale; revisit when the hosted version launches.
- **Mobile device testing** — Playwright tests run in Chromium with viewport
  resizing but not on actual mobile hardware or Safari. Acceptable for now.

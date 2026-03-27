# Performance Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce first-page-load blocking payload from ~374KB to ~192KB gzipped, cut menu page queries from 82 to ~40, and eliminate redundant per-request computation.

**Architecture:** Back-end fixes (N+1 elimination, resolver caching, cache store) are independent of front-end changes (esbuild code splitting, asset cleanup). Back-end tasks come first since they're lower risk and immediately testable.

**Tech Stack:** Rails 8 / SQLite / Propshaft / esbuild / Stimulus / Turbo Drive

**Spec:** `docs/superpowers/specs/2026-03-27-performance-optimization-design.md`

---

## File Map

### Back-end changes
- Modify: `app/models/recipe.rb` — traverse preloaded associations
- Modify: `app/models/current.rb` — add resolver attribute
- Modify: `app/models/ingredient_catalog.rb` — use Current.resolver cache
- Modify: `app/services/meal_plan_write_service.rb` — use cached resolver
- Modify: `app/controllers/application_controller.rb` — memoize sole kitchen
- Modify: `config/environments/production.rb` — set memory_store
- Modify: `test/models/recipe_aggregation_test.rb` — verify fix uses preloaded data
- Create: `test/models/current_resolver_cache_test.rb` — verify per-request caching

### Front-end: code splitting
- Modify: `esbuild.config.mjs` — enable splitting + ESM
- Modify: `app/javascript/application.js` — add prefetch
- Modify: `app/javascript/controllers/plaintext_editor_controller.js` — dynamic import
- Modify: `app/views/layouts/application.html.erb` — type="module"
- Modify: `.gitignore` — add public/assets/chunks/
- Modify: `package.json` — update build scripts

### Front-end: cleanup
- Delete: `public/fonts/source-sans-3/` — unused fonts
- Modify: `app/views/layouts/application.html.erb` — media="print"
- Modify: `package.json` — add lightningcss + build:css script
- Modify: `Procfile.dev` — add CSS watch
- Modify: `Dockerfile` — lightningcss runs via npm run build

### SVG texture (existing spec)
- Implement per `docs/superpowers/specs/2026-03-20-svg-paper-texture-design.md`

---

### Task 1: Fix Recipe N+1 — Through-Association Bypass

**Files:**
- Modify: `app/models/recipe.rb:45-49`
- Test: `test/models/recipe_aggregation_test.rb`

The `has_many :ingredients, through: :steps` association generates a fresh SQL JOIN per recipe, bypassing preloaded `steps: [:ingredients]` data. Fix by traversing preloaded associations directly.

- [ ] **Step 1: Write a test that exposes the N+1**

Add a test to `test/models/recipe_aggregation_test.rb` that asserts `own_ingredients_aggregated` does not trigger additional queries when steps and ingredients are preloaded:

```ruby
test "own_ingredients_aggregated uses preloaded associations" do
  recipe = @kitchen.recipes.includes(steps: :ingredients).find_by!(title: "Focaccia")
  query_count = count_queries { recipe.own_ingredients_aggregated }

  assert_equal 0, query_count, "Should not issue queries when associations are preloaded"
end
```

Add the `count_queries` helper at the top of the test class (inside the class body, before the first test):

```ruby
private

def count_queries(&block)
  count = 0
  counter = ->(_name, _start, _finish, _id, payload) {
    count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
  }
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
  count
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/recipe_aggregation_test.rb -n test_own_ingredients_aggregated_uses_preloaded_associations`

Expected: FAIL — the through-association fires a query even with preloaded data.

- [ ] **Step 3: Fix `own_ingredients_aggregated`**

In `app/models/recipe.rb`, replace lines 45-49:

```ruby
def own_ingredients_aggregated
  steps.flat_map(&:ingredients).group_by(&:name).transform_values do |group|
    IngredientAggregator.aggregate_amounts(group)
  end
end
```

This traverses the already-preloaded `steps` → `ingredients` chain instead of using the through-association that generates its own SQL.

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/recipe_aggregation_test.rb -n test_own_ingredients_aggregated_uses_preloaded_associations`

Expected: PASS

- [ ] **Step 5: Run all recipe aggregation tests**

Run: `ruby -Itest test/models/recipe_aggregation_test.rb`

Expected: All tests pass (the behavior is identical, just the query path changed).

- [ ] **Step 6: Run menu controller tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`

Expected: All pass. The menu controller preloads `steps: [:ingredients, ...]` so this fix takes effect.

- [ ] **Step 7: Commit**

```bash
git add app/models/recipe.rb test/models/recipe_aggregation_test.rb
git commit -m "Fix N+1: traverse preloaded steps instead of through-association

own_ingredients_aggregated used has_many :ingredients (through: :steps)
which generates a fresh SQL JOIN per recipe, bypassing preloaded data.
Switch to steps.flat_map(&:ingredients) to use the already-loaded chain.
Eliminates ~40 redundant queries on the menu page."
```

---

### Task 2: Cache IngredientResolver per Request

**Files:**
- Modify: `app/models/current.rb:13`
- Modify: `app/models/ingredient_catalog.rb:61-63`
- Modify: `app/services/meal_plan_write_service.rb:140-142`
- Create: `test/models/current_resolver_cache_test.rb`

- [ ] **Step 1: Write the test**

Create `test/models/current_resolver_cache_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class CurrentResolverCacheTest < ActiveSupport::TestCase
  setup do
    @kitchen, @user = create_kitchen_and_user
    Current.reset
  end

  teardown { Current.reset }

  test "resolver_for returns same instance within a request" do
    first = IngredientCatalog.resolver_for(@kitchen)
    second = IngredientCatalog.resolver_for(@kitchen)

    assert_same first, second
  end

  test "resolver_for rebuilds after Current.reset" do
    first = IngredientCatalog.resolver_for(@kitchen)
    Current.reset
    second = IngredientCatalog.resolver_for(@kitchen)

    refute_same first, second
  end

  test "resolver_for issues no queries on second call" do
    IngredientCatalog.resolver_for(@kitchen)

    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      IngredientCatalog.resolver_for(@kitchen)
    end

    assert_equal 0, count, "Second call should use cached resolver"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/current_resolver_cache_test.rb`

Expected: FAIL on "resolver_for returns same instance within a request" — currently builds a new resolver each time.

- [ ] **Step 3: Add resolver attribute to Current**

In `app/models/current.rb`, change line 13:

```ruby
attribute :session, :batching_kitchen, :broadcast_pending, :resolver
```

- [ ] **Step 4: Cache in `resolver_for`**

In `app/models/ingredient_catalog.rb`, replace lines 61-63:

```ruby
def self.resolver_for(kitchen)
  Current.resolver ||= IngredientResolver.new(lookup_for(kitchen))
end
```

- [ ] **Step 5: Verify MealPlanWriteService benefits automatically**

`MealPlanWriteService#build_resolver` (line 140) already calls `IngredientCatalog.resolver_for(kitchen)`. No code change needed — it now gets the cached resolver via the `Current.resolver` memoization added in step 4. Verify by reading the method:

```bash
grep -A2 "def build_resolver" app/services/meal_plan_write_service.rb
```

Expected output: `IngredientCatalog.resolver_for(kitchen)`

- [ ] **Step 6: Run tests**

Run: `ruby -Itest test/models/current_resolver_cache_test.rb`

Expected: All 3 tests pass.

- [ ] **Step 7: Run full test suite to check for regressions**

Run: `rake test`

Expected: All pass. The resolver is functionally identical — only the caching behavior changed.

- [ ] **Step 8: Commit**

```bash
git add app/models/current.rb app/models/ingredient_catalog.rb test/models/current_resolver_cache_test.rb
git commit -m "Cache IngredientResolver per request via Current

resolver_for now memoizes on Current.resolver, avoiding 2 DB queries
and expensive variant hash construction on repeated calls within the
same request. Automatically resets between requests."
```

---

### Task 3: Memoize `resolve_sole_kitchen`

**Files:**
- Modify: `app/controllers/application_controller.rb:46-49`

- [ ] **Step 1: Memoize the method**

In `app/controllers/application_controller.rb`, replace `resolve_sole_kitchen` (lines 46-49):

```ruby
def resolve_sole_kitchen
  return @sole_kitchen if defined?(@sole_kitchen)

  kitchens = ActsAsTenant.without_tenant { Kitchen.limit(2).to_a }
  @sole_kitchen = kitchens.first if kitchens.size == 1
end
```

- [ ] **Step 2: Run controller tests**

Run: `rake test`

Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/controllers/application_controller.rb
git commit -m "Memoize resolve_sole_kitchen to avoid duplicate query

Both set_kitchen_from_path and auto_join_sole_kitchen call this method.
On first-ever requests (no membership yet), this eliminates a redundant
Kitchen.limit(2) query."
```

---

### Task 4: Configure Production Cache Store

**Files:**
- Modify: `config/environments/production.rb:50`

- [ ] **Step 1: Set memory_store**

In `config/environments/production.rb`, replace line 50:

```ruby
config.cache_store = :memory_store, { size: 16.megabytes }
```

(Replace the commented-out `# config.cache_store = :mem_cache_store` line.)

- [ ] **Step 2: Run tests**

Run: `rake test`

Expected: All pass (test environment uses its own cache config).

- [ ] **Step 3: Commit**

```bash
git add config/environments/production.rb
git commit -m "Configure :memory_store for production cache

Single-process Puma in Docker makes in-process memory cache appropriate.
Enables durable Rails.cache.fetch for SearchDataHelper and future use.
16MB limit prevents unbounded growth."
```

---

### Task 5: esbuild Code Splitting — CodeMirror Lazy Load

**Files:**
- Modify: `esbuild.config.mjs`
- Modify: `app/javascript/controllers/plaintext_editor_controller.js`
- Modify: `app/javascript/application.js`
- Modify: `app/views/layouts/application.html.erb:29`
- Modify: `.gitignore`
- Modify: `package.json`

This is the largest task. It converts the JS build from a single IIFE bundle to ESM with code splitting, moves CodeMirror to a lazy-loaded chunk, and adds prefetching.

- [ ] **Step 1: Update esbuild config for ESM splitting**

Replace the entire contents of `esbuild.config.mjs`:

```javascript
import { build, context } from "esbuild"
import { rmSync, mkdirSync } from "fs"

const watch = process.argv.includes("--watch")

// Clean chunks directory to remove stale hashed files
rmSync("public/assets/chunks", { recursive: true, force: true })
mkdirSync("public/assets/chunks", { recursive: true })

const config = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  splitting: true,
  format: "esm",
  sourcemap: true,
  outdir: "app/assets/builds",
  publicPath: "/assets",
  chunkNames: "../../../public/assets/chunks/[name]-[hash]",
  logLevel: "info",
}

if (watch) {
  const ctx = await context(config)
  await ctx.watch()
  console.log("Watching for changes...")
} else {
  await build({ ...config, minify: true })
}
```

- [ ] **Step 2: Add chunks directory to .gitignore**

Append to `.gitignore`:

```
/public/assets/chunks/
```

- [ ] **Step 3: Convert plaintext_editor_controller to dynamic import**

Replace the entire contents of `app/javascript/controllers/plaintext_editor_controller.js`:

```javascript
/**
 * Unified CodeMirror 6 plaintext editor for both recipes and Quick Bites.
 * Parameterized via Stimulus values: the classifier and fold service are
 * looked up by name from the codemirror registry, so the same controller
 * serves any content type that has a registered classifier.
 *
 * CodeMirror is loaded lazily via dynamic import() — the ~513KB library
 * only downloads when an editor actually mounts. The main bundle prefetches
 * the chunk in the background so it's typically cached before the user
 * opens an editor.
 *
 * - dual_mode_editor_controller: coordinator, calls .content and .isModified()
 * - editor_setup.js: shared CodeMirror factory
 * - registry.js: maps string keys to classifier/fold-service extensions
 * - auto_dash.js: shared bullet-continuation keymap
 */
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mount"]
  static values = {
    classifier: String,
    foldService: String,
    placeholder: String,
    initial: String
  }

  async mountTargetConnected(element) {
    this.editorView?.destroy()

    const [
      { createEditor },
      { classifiers, foldServices },
      { autoDashKeymap },
      { foldAll, unfoldCode }
    ] = await Promise.all([
      import("../codemirror/editor_setup"),
      import("../codemirror/registry"),
      import("../codemirror/auto_dash"),
      import("@codemirror/language")
    ])

    this._foldAll = foldAll
    this._unfoldCode = unfoldCode

    let doc = ""
    if (this.hasInitialValue) {
      doc = this.initialValue
    } else {
      const jsonEl = this.element.closest("turbo-frame")
        ?.querySelector("script[data-editor-markdown]")
      if (jsonEl) {
        const data = JSON.parse(jsonEl.textContent)
        doc = data.plaintext || ""
      }
    }

    this.editorView = createEditor({
      parent: element,
      doc,
      classifier: classifiers[this.classifierValue],
      foldService: this.hasFoldServiceValue ? foldServices[this.foldServiceValue] : null,
      placeholder: this.hasPlaceholderValue ? this.placeholderValue : "",
      extraExtensions: [autoDashKeymap]
    })
  }

  mountTargetDisconnected() {
    this.editorView?.destroy()
    this.editorView = null
  }

  disconnect() {
    this.editorView?.destroy()
    this.editorView = null
  }

  get content() {
    return this.editorView?.state.doc.toString() || ""
  }

  set content(text) {
    if (!this.editorView) return

    this.editorView.dispatch({
      changes: { from: 0, to: this.editorView.state.doc.length, insert: text }
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }

  focusCategory(name) {
    if (!this.editorView || !this._foldAll) return
    const view = this.editorView

    requestAnimationFrame(() => {
      this._foldAll(view)

      const doc = view.state.doc
      const target = `## ${name}`
      for (let i = 1; i <= doc.lines; i++) {
        const line = doc.line(i)
        if (line.text.trimEnd() === target) {
          view.dispatch({ selection: { anchor: line.from } })
          this._unfoldCode(view)
          return
        }
      }
    })
  }
}
```

Key changes: All CodeMirror imports replaced with dynamic `import()` inside `mountTargetConnected`. The `foldAll`/`unfoldCode` functions are stored as instance properties for use in `focusCategory`.

- [ ] **Step 4: Add prefetch to application.js**

In `app/javascript/application.js`, add the following after the service worker registration block (after line 78):

```javascript
// Prefetch CodeMirror chunk in background so it's cached before editor opens
const prefetchEditor = () => import("./codemirror/editor_setup")
if (typeof requestIdleCallback === "function") {
  requestIdleCallback(prefetchEditor)
} else {
  setTimeout(prefetchEditor, 1000)
}
```

- [ ] **Step 5: Change script tag to type="module"**

In `app/views/layouts/application.html.erb`, replace line 29:

```erb
<%= javascript_include_tag "application", type: "module" %>
```

Remove `defer: true` — ESM modules are deferred by default.

- [ ] **Step 6: Build and verify**

Run: `npm run build`

Expected: esbuild outputs:
- `app/assets/builds/application.js` (main bundle, ~252KB minified)
- `public/assets/chunks/editor_setup-XXXX.js` (CodeMirror chunk, ~513KB minified)
- Possibly additional small shared chunks

Verify the main bundle is significantly smaller:

```bash
wc -c app/assets/builds/application.js
ls -la public/assets/chunks/
```

Expected: `application.js` should be ~300-400KB (vs previous 1.5MB). Chunks directory should contain 1+ files.

- [ ] **Step 7: Run JS tests**

Run: `npm test`

Expected: All pass. The JS tests import classifiers directly and don't go through the controller, so they're unaffected by the dynamic import change.

- [ ] **Step 8: Start dev server and manually verify**

Run: `bin/dev`

Open a recipe page and click Edit. Verify:
1. Page loads without the CodeMirror chunk being requested initially
2. Opening the editor triggers the chunk load (check Network tab)
3. The editor functions normally (syntax highlighting, folding, etc.)
4. Subsequent editor opens are instant (chunk is cached)

- [ ] **Step 9: Run full Rails test suite**

Run: `rake test`

Expected: All pass. The system tests (if any) may need a running esbuild build, but controller/model tests don't touch JS.

- [ ] **Step 10: Commit**

```bash
git add esbuild.config.mjs app/javascript/controllers/plaintext_editor_controller.js \
  app/javascript/application.js app/views/layouts/application.html.erb .gitignore
git commit -m "Split CodeMirror into lazy-loaded chunk with prefetch

Convert esbuild from IIFE to ESM with code splitting. CodeMirror + Lezer
(~513KB minified) now loads on demand when an editor mounts, reducing the
main bundle from ~765KB to ~252KB minified. Background prefetch via
requestIdleCallback ensures the chunk is cached before users open editors.

Chunks write to public/assets/chunks/ (bypassing Propshaft fingerprinting)
with esbuild content hashes for cache busting. Layout script tag changes
from defer to type=module for ESM compatibility."
```

---

### Task 6: Add `media="print"` to print.css

**Files:**
- Modify: `app/views/layouts/application.html.erb:22`

- [ ] **Step 1: Add media attribute**

In `app/views/layouts/application.html.erb`, replace line 22:

```erb
<%= stylesheet_link_tag 'print', "data-turbo-track": "reload", media: "print" %>
```

- [ ] **Step 2: Run tests**

Run: `rake test`

Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "Defer print.css with media=print

Browser skips downloading print stylesheet until print is triggered.
Saves 1.2KB gzipped and one HTTP request on every page load."
```

---

### Task 7: Delete Unused Self-Hosted Fonts

**Files:**
- Delete: `public/fonts/source-sans-3/` (entire directory)

- [ ] **Step 1: Verify fonts are truly unused**

```bash
grep -r "source-sans\|SourceSans\|woff2" app/assets/stylesheets/ app/views/ app/javascript/
```

Expected: No matches.

- [ ] **Step 2: Delete the directory**

```bash
rm -rf public/fonts/source-sans-3
```

If `public/fonts/` is now empty, remove it too:

```bash
rmdir public/fonts 2>/dev/null || true
```

- [ ] **Step 3: Commit**

```bash
git add -A public/fonts/
git commit -m "Remove unused self-hosted Source Sans 3 fonts

Zero references in CSS, views, or JS. Saves ~60KB from repo and
Docker image."
```

---

### Task 8: CSS Minification with lightningcss

**Files:**
- Modify: `package.json`
- Modify: `Procfile.dev`

- [ ] **Step 1: Install lightningcss-cli**

```bash
npm install --save-dev lightningcss-cli
```

- [ ] **Step 2: Add build:css script to package.json**

In `package.json`, update the `"scripts"` section:

```json
"scripts": {
  "build": "node esbuild.config.mjs && npm run build:css",
  "build:css": "lightningcss --minify app/assets/stylesheets/*.css --output-dir app/assets/builds/",
  "build:watch": "node esbuild.config.mjs --watch",
  "test": "node --test test/javascript/*.mjs"
}
```

Note: the watch mode does not include CSS watching — that's handled by the Procfile.

- [ ] **Step 3: Update Procfile.dev to watch CSS**

Replace `Procfile.dev` contents:

```
web: bin/rails server -p 3030
js: npm run build:watch
css: npx lightningcss --minify app/assets/stylesheets/*.css --output-dir app/assets/builds/ --watch
```

- [ ] **Step 4: Build and verify size reduction**

```bash
npm run build:css
echo "=== Raw vs minified ==="
for f in base navigation editor nutrition recipe print groceries menu ingredients; do
  raw=$(wc -c < "app/assets/stylesheets/${f}.css" 2>/dev/null || echo 0)
  min=$(wc -c < "app/assets/builds/${f}.css" 2>/dev/null || echo 0)
  echo "${f}.css: ${raw} -> ${min}"
done
```

Expected: ~15-25% size reduction per file.

- [ ] **Step 5: Start dev server and verify CSS loads correctly**

Run: `bin/dev`

Verify pages render correctly — Propshaft serves from `app/assets/builds/` first, so the minified versions take precedence over the source files in `app/assets/stylesheets/`.

- [ ] **Step 6: Run tests**

Run: `rake test`

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json Procfile.dev
git commit -m "Add CSS minification via lightningcss

Minified CSS writes to app/assets/builds/ where Propshaft serves it
with priority over source files. Saves ~2-3KB gzipped on page load.
Watch mode in Procfile.dev rebuilds on stylesheet changes."
```

---

### Task 9: SVG Paper Texture (Existing Spec)

**Files:** Per `docs/superpowers/specs/2026-03-20-svg-paper-texture-design.md`

This task implements the existing SVG texture spec. It replaces `paper-noise.png` (34KB) with a procedural SVG filter.

- [ ] **Step 1: Read the existing spec and plan**

Read: `docs/superpowers/specs/2026-03-20-svg-paper-texture-design.md`
Read: `docs/superpowers/plans/2026-03-20-svg-paper-texture-plan.md`

Follow the plan in that document. It covers:
- Adding an inline `<svg>` filter definition to the layout
- Updating `base.css` to reference `url(#paper-texture)` instead of `url("paper-noise.png")`
- Removing the PNG asset
- Dark mode adaptation via CSS custom properties

- [ ] **Step 2: Implement per the existing plan**

Follow all steps in `docs/superpowers/plans/2026-03-20-svg-paper-texture-plan.md`.

- [ ] **Step 3: Run tests**

Run: `rake test`

Expected: All pass.

- [ ] **Step 4: Commit**

Commit message should reference the performance optimization context:

```bash
git commit -m "Replace paper-noise.png with SVG feTurbulence filter

Eliminates 34KB PNG asset and one HTTP request. Procedural noise via
feTurbulence + feDiffuseLighting produces richer texture that adapts
to dark mode. Per docs/superpowers/specs/2026-03-20-svg-paper-texture-design.md."
```

---

### Task 10: Update CLAUDE.md and html_safe Allowlist

**Files:**
- Modify: `CLAUDE.md` — document the code-splitting architecture
- Modify: `config/html_safe_allowlist.yml` — update line numbers if they shifted

- [ ] **Step 1: Update CLAUDE.md**

In the **Hotwire stack** section of `CLAUDE.md`, after the bullet about `npm run build`, add:

```markdown
- esbuild uses ESM format with code splitting. CodeMirror loads lazily
  via dynamic `import()` in `plaintext_editor_controller`. Chunks write
  to `public/assets/chunks/` (bypassing Propshaft) with content hashes
  for cache busting. `requestIdleCallback` prefetches the editor chunk
  after page load.
- CSS is minified by lightningcss into `app/assets/builds/`, where
  Propshaft serves them with priority over source files.
```

- [ ] **Step 2: Audit html_safe allowlist**

Run: `rake lint:html_safe`

If any line numbers shifted due to layout changes, update `config/html_safe_allowlist.yml` accordingly.

- [ ] **Step 3: Run full lint + test**

Run: `rake`

Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md config/html_safe_allowlist.yml
git commit -m "Document code-splitting architecture in CLAUDE.md"
```

---

## Task Dependency Graph

```
Task 1 (N+1 fix) ─────────┐
Task 2 (Resolver cache) ───┤
Task 3 (Sole kitchen) ─────┤─→ independent back-end tasks
Task 4 (Cache store) ──────┘

Task 5 (Code splitting) ──────→ depends on nothing, biggest change
Task 6 (media=print) ─────────→ independent
Task 7 (Delete fonts) ─────────→ independent
Task 8 (CSS minification) ────→ independent
Task 9 (SVG texture) ─────────→ independent, follows existing plan
Task 10 (CLAUDE.md) ──────────→ depends on Tasks 5 + 8
```

Tasks 1-4 are fully independent. Tasks 5-9 are independent of each other and of 1-4. Task 10 is a cleanup pass that goes last.

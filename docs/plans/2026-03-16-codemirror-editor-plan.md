# CodeMirror 6 Editor Integration Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the transparent-textarea-over-pre overlay with CodeMirror 6, eliminating cursor/highlight desync and gaining folding, undo history, and find/replace.

**Architecture:** Switch from importmap-rails to jsbundling-rails + esbuild for JS bundling. Replace `HighlightOverlay` + textarea with CodeMirror `EditorView` instances using `ViewPlugin` decorations for syntax highlighting and `foldService` for code folding. Plaintext controllers become thin wrappers; coordinators and dialog lifecycle unchanged.

**Tech Stack:** Rails 8, esbuild, CodeMirror 6 (`@codemirror/view`, `@codemirror/state`, `@codemirror/language`, `@codemirror/commands`, `@codemirror/lang-markdown`), Stimulus

**Spec:** `docs/plans/2026-03-16-codemirror-editor-design.md`

---

## Chunk 1: Build Tooling Migration

Switch from importmap-rails to jsbundling-rails + esbuild. After this chunk, the app works identically but JS is bundled by esbuild instead of served via importmap.

### Task 1: Add jsbundling-rails and esbuild

**Files:**
- Modify: `Gemfile:18` (replace importmap-rails with jsbundling-rails)
- Create: `package.json`
- Create: `esbuild.config.mjs`
- Create: `Procfile.dev`
- Modify: `bin/dev` (switch to foreman)
- Create: `app/assets/builds/.keep`
- Modify: `.gitignore` (ignore esbuild output)

- [ ] **Step 1: Replace importmap-rails with jsbundling-rails in Gemfile**

In `Gemfile`, replace line 18:
```ruby
gem 'importmap-rails'
```
with:
```ruby
gem 'jsbundling-rails'
```

Run:
```bash
bundle install
```
Expected: Gemfile.lock updated, `importmap-rails` removed, `jsbundling-rails` added.

- [ ] **Step 2: Create package.json with esbuild and CodeMirror packages**

Create `package.json`:
```json
{
  "name": "familyrecipes",
  "private": true,
  "scripts": {
    "build": "node esbuild.config.mjs",
    "build:watch": "node esbuild.config.mjs --watch"
  },
  "devDependencies": {
    "esbuild": "^0.25.0"
  },
  "dependencies": {
    "@hotwired/stimulus": "^3.2.0",
    "@hotwired/turbo-rails": "^8.0.0",
    "@rails/actioncable": "^8.0.0",
    "@codemirror/view": "^6.36.0",
    "@codemirror/state": "^6.5.0",
    "@codemirror/language": "^6.10.0",
    "@codemirror/commands": "^6.8.0",
    "@codemirror/lang-markdown": "^6.3.0"
  }
}
```

Run:
```bash
npm install
```
Expected: `node_modules/` created, `package-lock.json` generated.

- [ ] **Step 3: Create esbuild config**

Create `esbuild.config.mjs`:
```javascript
import { build, context } from "esbuild"

const watch = process.argv.includes("--watch")

const config = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  sourcemap: true,
  format: "esm",
  outdir: "app/assets/builds",
  publicPath: "/assets",
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

- [ ] **Step 4: Install foreman, create Procfile.dev, and update bin/dev**

Install foreman (process manager for Procfile-based dev servers):
```bash
gem install foreman
```

Create `Procfile.dev`:
```
web: bin/rails server -p 3030
js: npm run build:watch
```

Replace `bin/dev` contents with:
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Starts the Rails dev server and esbuild watcher via foreman.
# Kills any stale Puma process first so a leftover PID file
# doesn't block startup.
#

pid_file = File.expand_path('../tmp/pids/server.pid', __dir__)

if File.exist?(pid_file)
  pid = File.read(pid_file).strip.to_i
  begin
    Process.kill('TERM', pid)
    sleep 0.5
  rescue Errno::ESRCH
    # already dead
  end
  File.delete(pid_file) if File.exist?(pid_file)
end

exec 'foreman', 'start', '-f', 'Procfile.dev'
```

- [ ] **Step 5: Add .keep and .gitignore entries**

Create `app/assets/builds/.keep` (empty file).

Add to `.gitignore`:
```
/app/assets/builds/*
!/app/assets/builds/.keep
/node_modules
```

- [ ] **Step 6: Run initial build to verify esbuild works**

Run:
```bash
npm run build
```
Expected: `app/assets/builds/application.js` and `application.js.map` created. Build completes without errors (though the JS will fail at runtime until import paths are fixed in Task 2).

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock package.json package-lock.json esbuild.config.mjs Procfile.dev bin/dev app/assets/builds/.keep .gitignore
git commit -m "build: add jsbundling-rails + esbuild, remove importmap-rails"
```

### Task 2: Migrate import paths and Stimulus registration

**Files:**
- Modify: `app/javascript/application.js` (rewrite imports, Stimulus registration)
- Delete: `app/javascript/controllers/index.js`
- Delete: `app/javascript/controllers/application.js`
- Modify: all controller files in `app/javascript/controllers/` (update import paths)
- Modify: all utility files in `app/javascript/utilities/` (update import paths if they cross-reference)
- Delete: `config/importmap.rb`
- Modify: `app/views/layouts/application.html.erb:23` (replace importmap tag)

- [ ] **Step 1: Rewrite application.js as the esbuild entrypoint**

Replace `app/javascript/application.js` with explicit Stimulus bootstrap and controller registration. esbuild does not support `import.meta.glob`, so all controllers must be explicitly imported and registered.

```javascript
/**
 * Application entry point. Boots Turbo Drive and Stimulus, registers all
 * controllers, registers the service worker, and installs global Turbo
 * lifecycle handlers (dialog morph protection, pre-cache cleanup).
 *
 * - Turbo Drive: page navigation, morphing, stream rendering
 * - Stimulus: controller autoloading from controllers/
 */
import { Turbo } from "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false

import EditorController from "./controllers/editor_controller"
import ExportController from "./controllers/export_controller"
import GroceryUiController from "./controllers/grocery_ui_controller"
import ImportController from "./controllers/import_controller"
import IngredientTableController from "./controllers/ingredient_table_controller"
import MenuController from "./controllers/menu_controller"
import NavMenuController from "./controllers/nav_menu_controller"
import NutritionEditorController from "./controllers/nutrition_editor_controller"
import OrderedListEditorController from "./controllers/ordered_list_editor_controller"
import QuickbitesEditorController from "./controllers/quickbites_editor_controller"
import QuickbitesGraphicalController from "./controllers/quickbites_graphical_controller"
import QuickbitesPlaintextController from "./controllers/quickbites_plaintext_controller"
import RecipeEditorController from "./controllers/recipe_editor_controller"
import RecipeGraphicalController from "./controllers/recipe_graphical_controller"
import RecipePlaintextController from "./controllers/recipe_plaintext_controller"
import RecipeStateController from "./controllers/recipe_state_controller"
import RevealController from "./controllers/reveal_controller"
import ScalePanelController from "./controllers/scale_panel_controller"
import SearchOverlayController from "./controllers/search_overlay_controller"
import SettingsEditorController from "./controllers/settings_editor_controller"
import TagInputController from "./controllers/tag_input_controller"
import ToastController from "./controllers/toast_controller"
import WakeLockController from "./controllers/wake_lock_controller"

application.register("editor", EditorController)
application.register("export", ExportController)
application.register("grocery-ui", GroceryUiController)
application.register("import", ImportController)
application.register("ingredient-table", IngredientTableController)
application.register("menu", MenuController)
application.register("nav-menu", NavMenuController)
application.register("nutrition-editor", NutritionEditorController)
application.register("ordered-list-editor", OrderedListEditorController)
application.register("quickbites-editor", QuickbitesEditorController)
application.register("quickbites-graphical", QuickbitesGraphicalController)
application.register("quickbites-plaintext", QuickbitesPlaintextController)
application.register("recipe-editor", RecipeEditorController)
application.register("recipe-graphical", RecipeGraphicalController)
application.register("recipe-plaintext", RecipePlaintextController)
application.register("recipe-state", RecipeStateController)
application.register("reveal", RevealController)
application.register("scale-panel", ScalePanelController)
application.register("search-overlay", SearchOverlayController)
application.register("settings-editor", SettingsEditorController)
application.register("tag-input", TagInputController)
application.register("toast", ToastController)
application.register("wake-lock", WakeLockController)

Turbo.config.drive.progressBarDelay = 300

document.addEventListener("turbo:before-morph-element", (event) => {
  if (event.target.tagName === "DIALOG" && event.target.open) {
    event.preventDefault()
  }
})

document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("dialog[open]").forEach((d) => d.close())
})

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js")
}
```

- [ ] **Step 2: Update import paths in all controller files**

Every controller uses bare specifier imports. `@hotwired/stimulus`, `@hotwired/turbo-rails`, and `@rails/actioncable` stay as-is (npm resolves them). But `"utilities/..."` bare specifiers must become relative paths.

In all files under `app/javascript/controllers/`, change:
```javascript
import HighlightOverlay from "utilities/highlight_overlay"
```
to:
```javascript
import HighlightOverlay from "../utilities/highlight_overlay"
```

And similarly for all other utility imports:
```javascript
// Before (bare specifier)
import { csrfHeaders } from "utilities/editor_utils"
import ListenerManager from "utilities/listener_manager"
import { notify } from "utilities/notify"

// After (relative path)
import { csrfHeaders } from "../utilities/editor_utils"
import ListenerManager from "../utilities/listener_manager"
import { notify } from "../utilities/notify"
```

Also check utility files that import from each other — those become `./` relative imports:
```javascript
// In a utility file importing another utility
import { notify } from "./notify"
```

Run a search to find all bare specifier imports that need updating:
```bash
grep -rn '"utilities/' app/javascript/
grep -rn '"controllers/' app/javascript/
```

Update every match.

- [ ] **Step 3: Delete importmap artifacts**

Delete these files:
- `config/importmap.rb`
- `app/javascript/controllers/index.js`
- `app/javascript/controllers/application.js`

- [ ] **Step 4: Update layout to use bundled JS instead of importmap**

In `app/views/layouts/application.html.erb`, replace line 23:
```erb
<%= javascript_importmap_tags %>
```
with:
```erb
<%= javascript_include_tag "application", defer: true %>
```

- [ ] **Step 5: Build and verify**

Run:
```bash
npm run build
```
Expected: Build succeeds with no unresolved import errors.

Start the server and manually verify:
```bash
bin/rails server -p 3030
```
- Pages load, Stimulus controllers connect
- Recipe editor opens (plaintext + graphical modes)
- QuickBites editor opens
- Search overlay works (press `/`)
- No CSP violations in console

- [ ] **Step 6: Run tests**

Run:
```bash
bundle exec rake
```
Expected: All tests pass, 0 RuboCop offenses.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/ app/views/layouts/application.html.erb
git rm config/importmap.rb app/javascript/controllers/index.js app/javascript/controllers/application.js
git commit -m "build: migrate from importmap-rails to esbuild

Explicit controller registration in application.js. All import
paths updated from bare specifiers to relative. importmap.rb removed."
```

### Task 3: Update CI and Dockerfile for Node.js

**Files:**
- Modify: `.github/workflows/test.yml` (add Node setup + npm build)
- Modify: `Dockerfile:4-8,17-19` (add Node.js to builder stage)

- [ ] **Step 1: Update CI test workflow**

In `.github/workflows/test.yml`, add Node setup after the Ruby setup step (after line 29):
```yaml
      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - name: Install JS dependencies
        run: npm ci

      - name: Build JS
        run: npm run build
```

- [ ] **Step 2: Update Dockerfile builder stage**

In `Dockerfile`, replace lines 4-8 to add Node.js:
```dockerfile
FROM ruby:3.2-slim AS builder

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libsqlite3-dev libyaml-dev curl && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    rm -rf /var/lib/apt/lists/*
```

After the `COPY . .` line (line 17), before `assets:precompile`, add:
```dockerfile
RUN npm ci && npm run build
```

The existing `bin/rails assets:precompile` then picks up esbuild output from `app/assets/builds/`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml Dockerfile
git commit -m "ci: add Node.js to CI and Docker builder for esbuild"
```

## Chunk 2: CodeMirror Foundation

Build the shared editor setup, recipe classifier, and fold service. After this chunk, the CodeMirror infrastructure exists but is not yet wired into the UI.

### Task 4: Create shared editor setup

**Files:**
- Create: `app/javascript/codemirror/editor_setup.js`

- [ ] **Step 1: Write the editor setup factory**

Create `app/javascript/codemirror/editor_setup.js`:
```javascript
/**
 * Shared CodeMirror editor factory. Creates an EditorView with the common
 * extension stack used by both recipe and QuickBites plaintext editors.
 * Callers provide a classifier (ViewPlugin for syntax decorations) and an
 * optional fold service.
 *
 * - recipe_plaintext_controller: recipe editing
 * - quickbites_plaintext_controller: quick bites editing
 * - recipe_classifier.js: recipe syntax decorations
 * - quickbites_classifier.js: quick bites syntax decorations
 */
import { EditorView, keymap, highlightActiveLine,
         drawSelection, dropCursor, rectangularSelection,
         highlightSpecialChars, placeholder as cmPlaceholder } from "@codemirror/view"
import { EditorState } from "@codemirror/state"
import { defaultKeymap, history, historyKeymap,
         indentWithTab } from "@codemirror/commands"
import { syntaxHighlighting, defaultHighlightStyle, foldGutter,
         bracketMatching } from "@codemirror/language"
import { markdown } from "@codemirror/lang-markdown"

const baseTheme = EditorView.theme({
  "&": {
    fontSize: "0.85rem",
    fontFamily: "var(--font-mono)",
  },
  ".cm-content": {
    fontFamily: "var(--font-mono)",
    lineHeight: "1.6",
    padding: "1.5rem",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    borderRight: "none",
    color: "var(--text-soft)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "transparent",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--text) 5%, transparent)",
  },
  "&.cm-focused": {
    outline: "none",
  },
  ".cm-scroller": {
    overflow: "auto",
  },
  ".cm-foldGutter .cm-gutterElement": {
    cursor: "pointer",
    padding: "0 4px",
  },
  "&.cm-focused .cm-matchingBracket": {
    backgroundColor: "color-mix(in srgb, var(--accent) 25%, transparent)",
    outline: "1px solid color-mix(in srgb, var(--accent) 40%, transparent)",
  },
})

export function createEditor({ parent, doc, classifier, foldService: foldSvc,
                                placeholder, onUpdate, extraExtensions }) {
  const extensions = [
    baseTheme,
    highlightActiveLine(),
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    rectangularSelection(),
    bracketMatching(),
    EditorView.lineWrapping,
    markdown(),
    syntaxHighlighting(defaultHighlightStyle),
    keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
  ]

  if (classifier) extensions.push(classifier)
  if (foldSvc) {
    extensions.push(foldSvc)
    extensions.push(foldGutter())
  }
  if (placeholder) extensions.push(cmPlaceholder(placeholder))
  if (onUpdate) {
    extensions.push(EditorView.updateListener.of((update) => {
      if (update.docChanged) onUpdate(update)
    }))
  }
  if (extraExtensions) extensions.push(...extraExtensions)

  return new EditorView({
    state: EditorState.create({ doc: doc || "", extensions }),
    parent,
  })
}
```

- [ ] **Step 2: Verify it builds**

Run:
```bash
npm run build
```
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/codemirror/editor_setup.js
git commit -m "feat: add shared CodeMirror editor setup factory"
```

### Task 5: Create recipe classifier ViewPlugin

**Files:**
- Create: `app/javascript/codemirror/recipe_classifier.js`
- Create: `test/javascript/recipe_classifier_test.mjs`

- [ ] **Step 1: Write recipe classifier unit tests**

Create `test/javascript/recipe_classifier_test.mjs`:
```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import { classifyRecipeLine } from "../../app/javascript/codemirror/recipe_classifier.js"

test("title line", () => {
  const spans = classifyRecipeLine("# My Recipe", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 11, class: "hl-title" }])
})

test("step header", () => {
  const spans = classifyRecipeLine("## Make the sauce.", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 18, class: "hl-step-header" }])
})

test("ingredient with name only", () => {
  const spans = classifyRecipeLine("- Salt", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 6, class: "hl-ingredient-name" }])
})

test("ingredient with name and quantity", () => {
  const spans = classifyRecipeLine("- Flour, 250 g", { inFooter: false })
  assert.deepEqual(spans, [
    { from: 0, to: 7, class: "hl-ingredient-name" },
    { from: 7, to: 14, class: "hl-ingredient-qty" },
  ])
})

test("ingredient with name, quantity, and prep", () => {
  const spans = classifyRecipeLine("- Butter, 115 g: Softened.", { inFooter: false })
  assert.deepEqual(spans, [
    { from: 0, to: 9, class: "hl-ingredient-name" },
    { from: 9, to: 15, class: "hl-ingredient-qty" },
    { from: 15, to: 26, class: "hl-ingredient-prep" },
  ])
})

test("ingredient with name and prep, no quantity", () => {
  const spans = classifyRecipeLine("- Parmesan: Grated, for serving.", { inFooter: false })
  assert.deepEqual(spans, [
    { from: 0, to: 10, class: "hl-ingredient-name" },
    { from: 10, to: 32, class: "hl-ingredient-prep" },
  ])
})

test("cross-reference", () => {
  const spans = classifyRecipeLine("> @[Simple Tomato Sauce]", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 23, class: "hl-cross-ref" }])
})

test("divider sets inFooter", () => {
  const ctx = { inFooter: false }
  const spans = classifyRecipeLine("---", ctx)
  assert.deepEqual(spans, [{ from: 0, to: 3, class: "hl-divider" }])
  assert.equal(ctx.inFooter, true)
})

test("front matter — Serves", () => {
  const spans = classifyRecipeLine("Serves: 4", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 9, class: "hl-front-matter" }])
})

test("front matter — Tags", () => {
  const spans = classifyRecipeLine("Tags: quick, weeknight", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 22, class: "hl-front-matter" }])
})

test("footer prose uses front-matter class", () => {
  const spans = classifyRecipeLine("This is a note.", { inFooter: true })
  assert.deepEqual(spans, [{ from: 0, to: 15, class: "hl-front-matter" }])
})

test("prose with recipe link", () => {
  const spans = classifyRecipeLine("Try this with @[Simple Salad] sometime.", { inFooter: false })
  assert.deepEqual(spans, [
    { from: 0, to: 14, class: null },
    { from: 14, to: 29, class: "hl-recipe-link" },
    { from: 29, to: 39, class: null },
  ])
})

test("plain prose line", () => {
  const spans = classifyRecipeLine("Mix until smooth.", { inFooter: false })
  assert.deepEqual(spans, [{ from: 0, to: 17, class: null }])
})

test("blank line", () => {
  const spans = classifyRecipeLine("", { inFooter: false })
  assert.deepEqual(spans, [])
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
node --test test/javascript/recipe_classifier_test.mjs
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the recipe classifier**

Create `app/javascript/codemirror/recipe_classifier.js`:
```javascript
/**
 * CodeMirror ViewPlugin that classifies recipe lines and applies syntax
 * decorations. Mirrors the server-side LineClassifier token types using
 * the same patterns (title, step_header, ingredient, cross_reference,
 * front_matter, divider). Runs on visible lines only for performance.
 *
 * Exports classifyRecipeLine() as a pure function for unit testing.
 *
 * - editor_setup.js: included in the extension stack
 * - recipe_plaintext_controller: mounts the editor
 * - style.css (.hl-*): CSS classes applied by decorations
 * - lib/familyrecipes/line_classifier.rb: server-side equivalent
 */
import { ViewPlugin, Decoration } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"

const TITLE = /^# .+$/
const STEP_HEADER = /^## .+$/
const INGREDIENT = /^- .+$/
const CROSS_REF = /^\s*>\s*@\[.+$/
const DIVIDER = /^---\s*$/
const FRONT_MATTER = /^(Makes|Serves|Category|Tags):\s+.+$/

const decoCache = {}
function deco(className) {
  if (!decoCache[className]) {
    decoCache[className] = Decoration.mark({ class: className })
  }
  return decoCache[className]
}

export function classifyRecipeLine(line, ctx) {
  if (line.length === 0) return []

  if (TITLE.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-title" }]
  }
  if (STEP_HEADER.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-step-header" }]
  }
  if (INGREDIENT.test(line)) {
    return classifyIngredient(line)
  }
  if (CROSS_REF.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-cross-ref" }]
  }
  if (DIVIDER.test(line)) {
    ctx.inFooter = true
    return [{ from: 0, to: line.length, class: "hl-divider" }]
  }
  if (FRONT_MATTER.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-front-matter" }]
  }
  if (ctx.inFooter) {
    return [{ from: 0, to: line.length, class: "hl-front-matter" }]
  }
  return classifyProseLinks(line)
}

function classifyIngredient(line) {
  const colonIdx = line.indexOf(":", 2)
  let left = colonIdx !== -1 ? line.slice(0, colonIdx) : line
  const hasPrep = colonIdx !== -1

  const commaIdx = left.indexOf(",", 2)
  const nameEnd = commaIdx !== -1 ? commaIdx : left.length
  const hasQty = commaIdx !== -1

  const spans = [{ from: 0, to: nameEnd, class: "hl-ingredient-name" }]
  if (hasQty && hasPrep) {
    spans.push({ from: nameEnd, to: colonIdx, class: "hl-ingredient-qty" })
    spans.push({ from: colonIdx, to: line.length, class: "hl-ingredient-prep" })
  } else if (hasQty) {
    spans.push({ from: nameEnd, to: line.length, class: "hl-ingredient-qty" })
  } else if (hasPrep) {
    spans.push({ from: colonIdx, to: line.length, class: "hl-ingredient-prep" })
  }
  return spans
}

function classifyProseLinks(line) {
  const pattern = /@\[(.+?)\]/g
  const spans = []
  let lastIndex = 0
  let match

  while ((match = pattern.exec(line)) !== null) {
    if (match.index > lastIndex) {
      spans.push({ from: lastIndex, to: match.index, class: null })
    }
    spans.push({ from: match.index, to: pattern.lastIndex, class: "hl-recipe-link" })
    lastIndex = pattern.lastIndex
  }

  if (spans.length === 0) {
    return [{ from: 0, to: line.length, class: null }]
  }
  if (lastIndex < line.length) {
    spans.push({ from: lastIndex, to: line.length, class: null })
  }
  return spans
}

function buildDecorations(view) {
  const builder = new RangeSetBuilder()
  const ctx = { inFooter: false }

  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = view.state.doc.lineAt(pos)
      const spans = classifyRecipeLine(line.text, ctx)

      for (const span of spans) {
        if (span.class) {
          builder.add(line.from + span.from, line.from + span.to, deco(span.class))
        }
      }
      pos = line.to + 1
    }
  }
  return builder.finish()
}

export const recipeClassifier = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildDecorations(view)
    }
    update(update) {
      if (update.docChanged || update.viewportChanged) {
        this.decorations = buildDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
node --test test/javascript/recipe_classifier_test.mjs
```
Expected: All 14 tests pass.

- [ ] **Step 5: Verify esbuild still builds**

Run:
```bash
npm run build
```
Expected: Builds without errors.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/codemirror/recipe_classifier.js test/javascript/recipe_classifier_test.mjs
git commit -m "feat: add recipe line classifier ViewPlugin for CodeMirror

Mirrors LineClassifier patterns: title, step_header, ingredient
(name/qty/prep sub-spans), cross_reference, front_matter, divider,
recipe_link. Unit tests validate all token types."
```

### Task 6: Create QuickBites classifier ViewPlugin

**Files:**
- Create: `app/javascript/codemirror/quickbites_classifier.js`
- Create: `test/javascript/quickbites_classifier_test.mjs`

- [ ] **Step 1: Write QuickBites classifier unit tests**

Create `test/javascript/quickbites_classifier_test.mjs`:
```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import { classifyQuickBitesLine } from "../../app/javascript/codemirror/quickbites_classifier.js"

test("category header", () => {
  const spans = classifyQuickBitesLine("Snacks:")
  assert.deepEqual(spans, [{ from: 0, to: 7, class: "hl-category" }])
})

test("category header with trailing space", () => {
  const spans = classifyQuickBitesLine("Breakfast:  ")
  assert.deepEqual(spans, [{ from: 0, to: 12, class: "hl-category" }])
})

test("item without ingredients", () => {
  const spans = classifyQuickBitesLine("- String cheese")
  assert.deepEqual(spans, [{ from: 0, to: 15, class: "hl-item" }])
})

test("item with ingredients", () => {
  const spans = classifyQuickBitesLine("- Hummus with Pretzels: Hummus, Pretzels")
  assert.deepEqual(spans, [
    { from: 0, to: 22, class: "hl-item" },
    { from: 22, to: 40, class: "hl-ingredients" },
  ])
})

test("blank line", () => {
  const spans = classifyQuickBitesLine("")
  assert.deepEqual(spans, [])
})

test("plain text line", () => {
  const spans = classifyQuickBitesLine("Some note")
  assert.deepEqual(spans, [{ from: 0, to: 9, class: null }])
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
node --test test/javascript/quickbites_classifier_test.mjs
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the QuickBites classifier**

Create `app/javascript/codemirror/quickbites_classifier.js`:
```javascript
/**
 * CodeMirror ViewPlugin that classifies Quick Bites lines and applies
 * syntax decorations. Recognizes category headers (non-dash lines ending
 * with colon) and items (dash-prefixed, optionally with colon-separated
 * ingredients).
 *
 * Exports classifyQuickBitesLine() as a pure function for unit testing.
 *
 * - editor_setup.js: included in the extension stack
 * - quickbites_plaintext_controller: mounts the editor
 * - style.css (.hl-*): CSS classes applied by decorations
 */
import { ViewPlugin, Decoration } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"

const CATEGORY = /^[^-].+:\s*$/
const ITEM = /^\s*-\s+/

const decoCache = {}
function deco(className) {
  if (!decoCache[className]) {
    decoCache[className] = Decoration.mark({ class: className })
  }
  return decoCache[className]
}

export function classifyQuickBitesLine(line) {
  if (line.length === 0) return []

  if (CATEGORY.test(line)) {
    return [{ from: 0, to: line.length, class: "hl-category" }]
  }
  if (ITEM.test(line)) {
    return classifyItem(line)
  }
  return [{ from: 0, to: line.length, class: null }]
}

function classifyItem(line) {
  const dashIdx = line.indexOf("-")
  const colonIdx = line.indexOf(":", dashIdx + 2)
  if (colonIdx !== -1) {
    return [
      { from: 0, to: colonIdx, class: "hl-item" },
      { from: colonIdx, to: line.length, class: "hl-ingredients" },
    ]
  }
  return [{ from: 0, to: line.length, class: "hl-item" }]
}

function buildDecorations(view) {
  const builder = new RangeSetBuilder()

  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = view.state.doc.lineAt(pos)
      const spans = classifyQuickBitesLine(line.text)

      for (const span of spans) {
        if (span.class) {
          builder.add(line.from + span.from, line.from + span.to, deco(span.class))
        }
      }
      pos = line.to + 1
    }
  }
  return builder.finish()
}

export const quickbitesClassifier = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildDecorations(view)
    }
    update(update) {
      if (update.docChanged || update.viewportChanged) {
        this.decorations = buildDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
node --test test/javascript/quickbites_classifier_test.mjs
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/codemirror/quickbites_classifier.js test/javascript/quickbites_classifier_test.mjs
git commit -m "feat: add QuickBites line classifier ViewPlugin for CodeMirror"
```

### Task 7: Create recipe fold service

**Files:**
- Create: `app/javascript/codemirror/recipe_fold.js`
- Create: `test/javascript/recipe_fold_test.mjs`

- [ ] **Step 1: Write fold service unit tests**

Create `test/javascript/recipe_fold_test.mjs`. Tests the pure `findFoldRange` function:
```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import { findFoldRange } from "../../app/javascript/codemirror/recipe_fold.js"

const RECIPE = [
  "# My Recipe",          // 0
  "",                      // 1
  "A description.",        // 2
  "",                      // 3
  "Serves: 4",            // 4
  "Category: Basics",     // 5
  "Tags: quick",          // 6
  "",                      // 7
  "## Make the sauce.",   // 8
  "",                      // 9
  "- Tomatoes, 400 g",    // 10
  "- Garlic, 2 cloves: Minced.", // 11
  "",                      // 12
  "Cook until soft.",     // 13
  "",                      // 14
  "## Cook the pasta.",   // 15
  "",                      // 16
  "- Pasta, 400 g",       // 17
  "",                      // 18
  "Boil until al dente.", // 19
  "",                      // 20
  "---",                   // 21
  "",                      // 22
  "Enjoy!",               // 23
]

function lineOffset(lineNum) {
  let offset = 0
  for (let i = 0; i < lineNum; i++) offset += RECIPE[i].length + 1
  return offset
}

test("fold step block from header to next header", () => {
  const result = findFoldRange(RECIPE, 8)
  assert.ok(result, "should return a fold range")
  assert.equal(result.from, lineOffset(8) + RECIPE[8].length)
  assert.equal(result.to, lineOffset(13) + RECIPE[13].length)
})

test("fold last step block to divider", () => {
  const result = findFoldRange(RECIPE, 15)
  assert.ok(result, "should return a fold range")
  assert.equal(result.from, lineOffset(15) + RECIPE[15].length)
  assert.equal(result.to, lineOffset(19) + RECIPE[19].length)
})

test("fold front matter block from first FM line", () => {
  const result = findFoldRange(RECIPE, 4)
  assert.ok(result, "should return a fold range")
  assert.equal(result.from, lineOffset(4) + RECIPE[4].length)
  assert.equal(result.to, lineOffset(6) + RECIPE[6].length)
})

test("no fold on title line", () => {
  assert.equal(findFoldRange(RECIPE, 0), null)
})

test("no fold on prose line", () => {
  assert.equal(findFoldRange(RECIPE, 2), null)
})

test("no fold on divider", () => {
  assert.equal(findFoldRange(RECIPE, 21), null)
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
node --test test/javascript/recipe_fold_test.mjs
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the fold service**

Create `app/javascript/codemirror/recipe_fold.js`:
```javascript
/**
 * CodeMirror fold service for recipe documents. Provides two fold targets:
 * step blocks (## headers) fold to the next header or divider, and front
 * matter blocks (Serves/Makes/Category/Tags) fold as a group.
 *
 * Exports findFoldRange() as a pure function for unit testing.
 *
 * - editor_setup.js: included in the extension stack via foldService
 * - recipe_classifier.js: uses the same line patterns
 */
import { foldService } from "@codemirror/language"

const STEP_HEADER = /^## .+$/
const FRONT_MATTER = /^(Makes|Serves|Category|Tags):\s+.+$/
const DIVIDER = /^---\s*$/

export function findFoldRange(lines, lineIndex) {
  const line = lines[lineIndex]

  if (STEP_HEADER.test(line)) return foldStepBlock(lines, lineIndex)
  if (FRONT_MATTER.test(line)) return foldFrontMatter(lines, lineIndex)
  return null
}

function foldStepBlock(lines, startIndex) {
  let endIndex = startIndex
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (STEP_HEADER.test(lines[i]) || DIVIDER.test(lines[i])) break
    endIndex = i
  }
  if (endIndex === startIndex) return null

  while (endIndex > startIndex && lines[endIndex].trim() === "") endIndex--
  if (endIndex === startIndex) return null

  const fromOffset = computeOffset(lines, startIndex) + lines[startIndex].length
  const toOffset = computeOffset(lines, endIndex) + lines[endIndex].length
  return { from: fromOffset, to: toOffset }
}

function foldFrontMatter(lines, startIndex) {
  let blockStart = startIndex
  while (blockStart > 0 && FRONT_MATTER.test(lines[blockStart - 1])) blockStart--

  let blockEnd = startIndex
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (FRONT_MATTER.test(lines[i])) {
      blockEnd = i
    } else {
      break
    }
  }
  if (blockEnd === blockStart) return null

  const fromOffset = computeOffset(lines, blockStart) + lines[blockStart].length
  const toOffset = computeOffset(lines, blockEnd) + lines[blockEnd].length
  return { from: fromOffset, to: toOffset }
}

function computeOffset(lines, lineIndex) {
  let offset = 0
  for (let i = 0; i < lineIndex; i++) offset += lines[i].length + 1
  return offset
}

export const recipeFoldService = foldService.of((state, from) => {
  const line = state.doc.lineAt(from)
  const allLines = state.doc.toString().split("\n")

  return findFoldRange(allLines, line.number - 1)
})
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
node --test test/javascript/recipe_fold_test.mjs
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/codemirror/recipe_fold.js test/javascript/recipe_fold_test.mjs
git commit -m "feat: add recipe fold service for step blocks and front matter"
```

### Task 8: Add npm test script and CI step

**Files:**
- Modify: `package.json` (add test script)
- Modify: `.github/workflows/test.yml` (add JS test step)

- [ ] **Step 1: Add test script to package.json**

Add to the `"scripts"` section:
```json
"test": "node --test test/javascript/"
```

- [ ] **Step 2: Verify all JS tests pass**

Run:
```bash
npm test
```
Expected: All tests across 3 test files pass.

**Note:** The design spec calls for a shared YAML fixture file
(`test/fixtures/editor_classification.yml`) validated by both Ruby and JS
tests. This is deferred — the JS classifiers mirror the existing Ruby
`classifyLine` logic, and the inline test cases cover the same token types.
A shared fixture can be added later if the classifiers drift.

- [ ] **Step 3: Add JS test step to CI**

In `.github/workflows/test.yml`, add after the "Build JS" step:
```yaml
      - name: JS tests
        run: npm test
```

- [ ] **Step 4: Commit**

```bash
git add package.json .github/workflows/test.yml
git commit -m "ci: add JS test runner for CodeMirror classifier tests"
```

## Chunk 3: Editor Controller Swap

Wire CodeMirror into the actual editor UI, replacing the textarea + HighlightOverlay.

### Task 9: Wire CSP nonce to CodeMirror's style injection

**Files:**
- Modify: `app/javascript/codemirror/editor_setup.js` (add `EditorView.cspNonce` facet)
- Modify: `config/initializers/content_security_policy.rb:32` (extend nonce to style-src)

CodeMirror 6 injects `<style>` elements at runtime via `document.createElement`.
Rails' nonce helpers only apply to tags rendered server-side. CodeMirror provides
`EditorView.cspNonce.of(nonce)` — a facet that attaches the nonce attribute to
its dynamically created `<style>` tags. We read the nonce from the page's
`<meta>` tag (already present for script-src) and pass it to CodeMirror.

- [ ] **Step 1: Extend nonce directives to include style-src**

In `config/initializers/content_security_policy.rb`, replace line 32:
```ruby
  config.content_security_policy_nonce_directives = %w[script-src]
```
with:
```ruby
  config.content_security_policy_nonce_directives = %w[script-src style-src]
```

Update the header comment (lines 3-7) to mention CodeMirror:
```ruby
# Strict CSP: all directives use 'self' only, plus ws:/wss: for ActionCable
# and Google Fonts domains for style_src / font_src. Nonce generator uses the
# session ID so the bundled <script> tag and CodeMirror's runtime <style>
# injection pass their respective directives. No other inline styles. If you
# need to add external resources, update the policy here first.
```

This makes Rails include the nonce in the `style-src` CSP header and emit
a `<meta name="csp-nonce">` tag that CodeMirror can read.

- [ ] **Step 2: Add cspNonce facet to editor setup**

In `app/javascript/codemirror/editor_setup.js`, add to the `createEditor`
function, at the top of the extensions array:

```javascript
function getCspNonce() {
  return document.querySelector('meta[name="csp-nonce"]')?.content || ""
}
```

And in the extensions array, add as the first entry:
```javascript
  const extensions = [
    EditorView.cspNonce.of(getCspNonce()),
    baseTheme,
    // ... rest of extensions
  ]
```

Import `EditorView` is already present. The `cspNonce` facet is a property
on `EditorView` — no additional import needed.

- [ ] **Step 3: Run tests**

Run:
```bash
bundle exec rake test
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add config/initializers/content_security_policy.rb app/javascript/codemirror/editor_setup.js
git commit -m "security: wire CSP nonce to CodeMirror style injection

Extend nonce directives to style-src so Rails emits the nonce in the
CSP header. Read the nonce from the meta tag and pass it to CodeMirror
via EditorView.cspNonce facet, allowing its runtime <style> injection."
```

### Task 10: Swap recipe plaintext controller to CodeMirror

**Files:**
- Modify: `app/javascript/controllers/recipe_plaintext_controller.js` (full rewrite)
- Modify: `app/views/recipes/show.html.erb:50-56` (replace textarea with mount div)
- Modify: `app/javascript/codemirror/editor_setup.js` (ensure extraExtensions param works)

- [ ] **Step 1: Rewrite recipe_plaintext_controller.js**

Replace `app/javascript/controllers/recipe_plaintext_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"
import { createEditor } from "../codemirror/editor_setup"
import { recipeClassifier } from "../codemirror/recipe_classifier"
import { recipeFoldService } from "../codemirror/recipe_fold"
import { keymap } from "@codemirror/view"

/**
 * Plaintext recipe editor backed by CodeMirror 6. Mounts a CodeMirror
 * EditorView into the container div. The parent recipe_editor_controller
 * (coordinator) manages mode toggling and routes lifecycle events.
 *
 * - recipe_editor_controller: coordinator, routes lifecycle events
 * - editor_setup.js: shared CodeMirror factory
 * - recipe_classifier.js: syntax decorations
 * - recipe_fold.js: step/front-matter folding
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["mount"]

  mountTargetConnected(element) {
    this.editorView?.destroy()
    this.editorView = createEditor({
      parent: element,
      doc: "",
      classifier: recipeClassifier,
      foldService: recipeFoldService,
      placeholder: "# Recipe Title — Serves: 4 — ## Steps with - Ingredients",
      extraExtensions: [this.autoDashKeymap()],
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

  set content(markdown) {
    if (!this.editorView) return
    this.editorView.dispatch({
      changes: {
        from: 0,
        to: this.editorView.state.doc.length,
        insert: markdown || "",
      },
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }

  autoDashKeymap() {
    return keymap.of([{
      key: "Enter",
      run: (view) => {
        const { from } = view.state.selection.main
        const line = view.state.doc.lineAt(from)
        const text = line.text
        const cursorInLine = from - line.from

        if (cursorInLine < text.length) return false

        if (/^- $/.test(text.trimStart())) {
          view.dispatch({
            changes: { from: line.from, to: line.to, insert: "" },
          })
          return true
        }

        if (/^- .+/.test(text.trimStart())) {
          view.dispatch({
            changes: { from, to: from, insert: "\n- " },
            selection: { anchor: from + 3 },
          })
          return true
        }

        return false
      },
    }])
  }
}
```

- [ ] **Step 2: Update the recipe show view**

In `app/views/recipes/show.html.erb`, replace lines 50-56:
```erb
  <div class="editor-body" data-recipe-editor-target="plaintextContainer">
    <div data-controller="recipe-plaintext">
      <textarea class="editor-textarea" data-editor-target="textarea"
                data-recipe-plaintext-target="textarea" spellcheck="false"
                placeholder="Loading..."></textarea>
    </div>
  </div>
```
with:
```erb
  <div class="editor-body" data-recipe-editor-target="plaintextContainer">
    <div data-controller="recipe-plaintext">
      <div class="cm-mount cm-loading" data-recipe-plaintext-target="mount"></div>
    </div>
  </div>
```

- [ ] **Step 3: Update coordinator enableEditing() for missing textarea**

In both `app/javascript/controllers/recipe_editor_controller.js` and
`app/javascript/controllers/quickbites_editor_controller.js`, the
`enableEditing()` method (line 123) queries for `[data-editor-target='textarea']`
to clear the disabled/placeholder state. With the textarea gone, this
silently no-ops (guarded by `if (textarea)`). The save button enable still
works (line 129).

The "Loading..." UX is lost. Add a loading state to the CodeMirror mount
point. In both coordinators, update `handleContentLoaded` to remove a
`loading` CSS class from the plaintext container when content arrives:

In the coordinator's `connect()`, add after the dialog opens:
```javascript
// In handleContentLoaded, after setting content on the child:
this.plaintextContainerTarget.classList.remove("cm-loading")
```

And in the view, add `cm-loading` to the mount div:
```erb
<div class="cm-mount cm-loading" data-recipe-plaintext-target="mount"></div>
```

Add to `style.css`:
```css
.cm-mount.cm-loading {
  display: flex;
  align-items: center;
  justify-content: center;
}

.cm-mount.cm-loading::before {
  content: "Loading\2026";
  color: var(--text-soft);
  font-family: var(--font-mono);
  font-size: 0.85rem;
}

.cm-mount.cm-loading .cm-editor {
  display: none;
}
```

This gives loading feedback without depending on a textarea.

- [ ] **Step 4: Build and manually verify**

Run:
```bash
npm run build && bin/rails server -p 3030
```

Open a recipe, click Edit. Verify:
- "Loading..." appears briefly, then CodeMirror editor with syntax highlighting
- Step headers, ingredients (name/qty/prep), cross-references highlighted
- Fold gutters appear next to step headers
- Auto-dash on Enter works
- Undo/redo works (Ctrl+Z/Ctrl+Shift+Z)
- Content saves correctly
- Mode switching (plaintext to graphical and back) works
- No CSP errors in console

- [ ] **Step 4: Run all tests**

Run:
```bash
bundle exec rake && npm test
```
Expected: All Ruby and JS tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/recipe_plaintext_controller.js app/javascript/controllers/recipe_editor_controller.js app/views/recipes/show.html.erb app/assets/stylesheets/style.css
git commit -m "feat: replace recipe textarea editor with CodeMirror 6

CodeMirror EditorView with recipe classifier decorations, step/front-matter
folding, auto-dash keymap, and active-line highlight. Eliminates the
textarea+overlay desync bug (#246)."
```

### Task 11: Swap QuickBites plaintext controller to CodeMirror

**Files:**
- Modify: `app/javascript/controllers/quickbites_plaintext_controller.js` (full rewrite)
- Modify: `app/views/menu/show.html.erb:55-59` (replace textarea with mount div)

- [ ] **Step 1: Rewrite quickbites_plaintext_controller.js**

Replace `app/javascript/controllers/quickbites_plaintext_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"
import { createEditor } from "../codemirror/editor_setup"
import { quickbitesClassifier } from "../codemirror/quickbites_classifier"
import { keymap } from "@codemirror/view"

/**
 * Plaintext Quick Bites editor backed by CodeMirror 6. Mounts a CodeMirror
 * EditorView into the container div. The parent quickbites_editor_controller
 * (coordinator) manages mode toggling and routes lifecycle events.
 *
 * - quickbites_editor_controller: coordinator, routes lifecycle events
 * - editor_setup.js: shared CodeMirror factory
 * - quickbites_classifier.js: syntax decorations
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["mount"]

  mountTargetConnected(element) {
    this.editorView?.destroy()
    this.editorView = createEditor({
      parent: element,
      doc: "",
      classifier: quickbitesClassifier,
      placeholder: "Snacks: / - Item Name: Ingredient1, Ingredient2",
      extraExtensions: [this.autoDashKeymap()],
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
      changes: {
        from: 0,
        to: this.editorView.state.doc.length,
        insert: text || "",
      },
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }

  autoDashKeymap() {
    return keymap.of([{
      key: "Enter",
      run: (view) => {
        const { from } = view.state.selection.main
        const line = view.state.doc.lineAt(from)
        const text = line.text
        const cursorInLine = from - line.from

        if (cursorInLine < text.length) return false

        if (/^- $/.test(text.trimStart())) {
          view.dispatch({
            changes: { from: line.from, to: line.to, insert: "" },
          })
          return true
        }

        if (/^- .+/.test(text.trimStart())) {
          view.dispatch({
            changes: { from, to: from, insert: "\n- " },
            selection: { anchor: from + 3 },
          })
          return true
        }

        return false
      },
    }])
  }
}
```

- [ ] **Step 2: Update the menu show view**

In `app/views/menu/show.html.erb`, replace the QuickBites textarea block (lines 55-59):
```erb
  <div class="editor-body" data-quickbites-editor-target="plaintextContainer">
    <div data-controller="quickbites-plaintext">
      <textarea class="editor-textarea" data-editor-target="textarea"
                data-quickbites-plaintext-target="textarea" spellcheck="false"
                placeholder="Loading..."></textarea>
    </div>
  </div>
```
with:
```erb
  <div class="editor-body" data-quickbites-editor-target="plaintextContainer">
    <div data-controller="quickbites-plaintext">
      <div class="cm-mount cm-loading" data-quickbites-plaintext-target="mount"></div>
    </div>
  </div>
```

- [ ] **Step 3: Build and manually verify**

Run:
```bash
npm run build && bin/rails server -p 3030
```

Open the menu page, click Edit QuickBites. Verify:
- CodeMirror editor appears with syntax highlighting
- Category headers and items highlighted correctly
- Auto-dash on Enter works
- Content saves correctly
- Mode switching works

- [ ] **Step 4: Run all tests**

Run:
```bash
bundle exec rake && npm test
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/quickbites_plaintext_controller.js app/javascript/controllers/quickbites_editor_controller.js app/views/menu/show.html.erb
git commit -m "feat: replace QuickBites textarea editor with CodeMirror 6"
```

## Chunk 4: Cleanup and Polish

Remove dead code, update CSS, and update documentation.

### Task 12: Remove HighlightOverlay and dead CSS

**Files:**
- Delete: `app/javascript/utilities/highlight_overlay.js`
- Modify: `app/assets/stylesheets/style.css` (remove overlay CSS, add CodeMirror mount CSS)

- [ ] **Step 1: Delete HighlightOverlay**

Delete `app/javascript/utilities/highlight_overlay.js`.

Verify no remaining imports:
```bash
grep -r "highlight_overlay" app/javascript/
```
Expected: No matches.

- [ ] **Step 2: Remove dead CSS and add CodeMirror mount styling**

In `app/assets/stylesheets/style.css`, remove the `.hl-wrap`, `.hl-overlay`, `.hl-input`, `.hl-input::selection`, and `.hl-input::placeholder` rules (approximately lines 1836-1876).

Add CodeMirror mount styling in their place:
```css
.cm-mount {
  flex: 1;
  display: flex;
  min-height: 60vh;
}

.cm-mount .cm-editor {
  flex: 1;
}
```

Keep all `.hl-title`, `.hl-step-header`, `.hl-ingredient-*`, `.hl-cross-ref`, `.hl-recipe-link`, `.hl-front-matter`, `.hl-divider`, `.hl-category`, `.hl-item`, `.hl-ingredients` rules — still used by CodeMirror decorations.

- [ ] **Step 3: Build and verify styling**

Run:
```bash
npm run build && bin/rails server -p 3030
```

Verify both editors render correctly and fill their dialog space.

- [ ] **Step 4: Run all tests**

Run:
```bash
bundle exec rake && npm test
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git rm app/javascript/utilities/highlight_overlay.js
git add app/assets/stylesheets/style.css
git commit -m "refactor: remove HighlightOverlay and dead overlay CSS

Replace .hl-wrap/.hl-overlay/.hl-input rules with .cm-mount sizing.
All .hl-* highlight color classes retained for CodeMirror decorations."
```

### Task 13: Update CLAUDE.md and documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the **Hotwire stack** paragraph, replace importmap-rails references:
```
**Hotwire stack.** Turbo Drive + Turbo Streams, Stimulus controllers,
jsbundling-rails + esbuild for JS bundling.
- New JS modules go in `app/javascript/`; new Stimulus controllers must
  be imported and registered in `app/javascript/application.js`.
- `npm run build` bundles JS to `app/assets/builds/`; `bin/dev` runs
  both Puma and esbuild watcher via foreman.
```

In the **Editor dialogs** section, replace HighlightOverlay references:
```
- CodeMirror 6 powers syntax-highlighted plaintext editors for both
  recipes and Quick Bites. `ViewPlugin` classifiers in
  `app/javascript/codemirror/` apply `.hl-*` CSS decorations.
  `foldService` provides step block and front matter folding for recipes.
```

Add to the **Commands** section:
```bash
npm install                # install JS dependencies
npm run build              # bundle JS (esbuild)
npm test                   # run JS classifier tests
```

Add to the **Workflow** section:
```
**JS changes.** Adding npm packages requires `npm install`. Adding new
Stimulus controllers requires registering them in `application.js`.
The esbuild watcher (`bin/dev`) auto-rebuilds on file changes.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for esbuild + CodeMirror migration"
```

### Task 14: Update html_safe_allowlist if needed

**Files:**
- Possibly modify: `config/html_safe_allowlist.yml`

- [ ] **Step 1: Run html_safe audit**

Run:
```bash
bundle exec rake lint:html_safe
```

If any allowlist entries are stale due to CSS or view changes, update `config/html_safe_allowlist.yml`.

- [ ] **Step 2: Run full lint**

Run:
```bash
bundle exec rake lint
```
Expected: 0 offenses.

- [ ] **Step 3: Commit if changes were needed**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist after CSS cleanup"
```

### Task 15: Final verification

- [ ] **Step 1: Run full test suite**

Run:
```bash
bundle exec rake && npm test
```
Expected: All Ruby and JS tests pass, 0 RuboCop offenses.

- [ ] **Step 2: Manual end-to-end verification**

Start the dev server:
```bash
bin/dev
```

Verify:
1. Recipe edit — CodeMirror loads with syntax highlighting
2. Fold/unfold step blocks and front matter
3. Auto-dash on Enter for ingredients
4. Mode switch (plaintext to graphical and back) preserves content
5. Save — recipe updates correctly
6. QuickBites edit — syntax highlighting works
7. Search overlay (`/` key) works
8. No CSP errors in browser console
9. Active-line highlight visible
10. Bracket matching works

- [ ] **Step 3: Check production bundle size**

Run:
```bash
npm run build
ls -la app/assets/builds/
```
Verify minified output is reasonable (expect 200-350KB for application.js).

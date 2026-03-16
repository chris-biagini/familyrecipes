# CodeMirror 6 Editor Integration Design

**Issue:** #246 — Text and syntax layers become out of sync in text editor
**Date:** 2026-03-16
**Deferred:** #249 (QuickBites `##` header syntax), #250 (line-level syntax error reporting)

## Problem

The current text editor uses a transparent-textarea-over-pre overlay pattern
for syntax highlighting. The textarea cursor position drifts out of sync with
the highlight layer because font metrics, line wrapping, and scroll position
can diverge between the `<textarea>` and `<pre>` elements. This is a
fundamental limitation of the pattern — patching it is not viable.

## Decision

Replace the textarea+overlay pattern entirely with CodeMirror 6, a
production-grade composable editor framework. CodeMirror owns the full editing
surface — text, cursor, rendering, and syntax highlighting are a single
component. The desync bug is eliminated by design.

## Approach

**Full replacement (not hybrid).** The `<textarea>` goes away. CodeMirror
renders directly into the editor dialog body. `HighlightOverlay` is retired.
Plaintext controllers become thin wrappers around a CodeMirror `EditorView`.

A hybrid approach (CodeMirror for highlighting only, textarea for input) was
considered and rejected — it preserves the two-layer architecture that caused
the bug and gains almost none of CodeMirror's editing features.

## Build Tooling: importmap → jsbundling-rails + esbuild

CodeMirror 6 is distributed as ~30 small ES modules designed for tree-shaking
with a bundler. importmap-rails cannot handle this — it needs either a
pre-bundled blob or a CDN. A CDN violates the self-hosted/homelab design. A
vendored blob fights CodeMirror's composable architecture.

### What changes

- Add `jsbundling-rails` gem, `package.json` with CodeMirror packages + esbuild
- `bin/dev` becomes Procfile-based using `foreman` (the `jsbundling-rails`
  default): `Procfile.dev` runs Puma on port 3030 + esbuild in watch mode.
  Dockerfile unchanged — it only runs Puma in production; esbuild output is
  a static build artifact.
- Entrypoint: `app/javascript/application.js` → `app/assets/builds/application.js`
- All existing import paths updated from bare specifiers
  (`"utilities/highlight_overlay"`) to relative paths
  (`"../utilities/highlight_overlay"`) — esbuild uses Node module resolution,
  not importmap's bare specifier mapping
- `config/importmap.rb` removed; `<script>` tag switches to bundled output
- Stimulus controller registration switches from `@hotwired/stimulus-loading`
  (importmap-specific) to explicit `eagerLoadControllersFrom()` from
  `@hotwired/stimulus-loading/esbuild-loader` or manual registration in
  `application.js`
- Propshaft continues serving assets (including esbuild output in
  `app/assets/builds/`)

### Dockerfile / CI impact

- Node.js added to builder stage (not runtime — output is static JS)
- CI adds `npm install && npm run build` before `rake test`
- `npm run build`: `esbuild app/javascript/application.js --bundle --minify --sourcemap --outdir=app/assets/builds`

### Bundle size

CodeMirror 6 with the listed packages adds ~150-250KB minified (~50-80KB
gzipped). Acceptable for a homelab app. The `--minify` flag on the esbuild
command keeps production builds tight.

### What stays the same

- Propshaft for asset serving
- All existing JS logic — this is a packaging change

## CodeMirror Integration Architecture

### Packages

- `@codemirror/view` — editor view, DOM layer
- `@codemirror/state` — editor state, transactions
- `@codemirror/language` — language support, folding
- `@codemirror/commands` — standard keybindings
- `@codemirror/lang-markdown` — Markdown base language

### New JS modules

`app/javascript/codemirror/editor-setup.js` — Shared factory that creates an
`EditorView` with the common extension stack: theme (CSS variables), keybindings,
line wrapping, fold gutter, active-line highlight, matching-bracket highlight,
update listeners. Both recipe and quickbites controllers call this with their
classification function and fold config.

`app/javascript/codemirror/recipe-classifier.js` — A `ViewPlugin` that
produces `Decoration.mark()` ranges by classifying visible lines using the
same patterns as the server-side `LineClassifier`. Recognizes: title, step
headers, ingredient lines (with name/quantity/prep sub-spans), cross-references,
front matter, dividers, recipe links. Mirrors the comma/colon delimiters
that `IngredientParser` uses server-side.

`app/javascript/codemirror/quickbites-classifier.js` — Same pattern for
QuickBites: category headers, items, ingredients.

`app/javascript/codemirror/recipe-fold.js` — A `foldService` that identifies
step block and front matter boundaries for code folding.

### How syntax highlighting works

The recipe syntax is not a separate language embedded in Markdown — it IS
Markdown with semantic meaning on specific line patterns. A full Lezer grammar
overlay would be overkill. Instead, a `ViewPlugin` runs line-by-line
classification on the visible range and produces `Decoration.mark()` ranges
that apply the `.hl-*` CSS classes directly. This is the same approach as the
current `HighlightOverlay.classifyLine` — ported to CodeMirror's decoration
API rather than building a `<pre>` overlay.

The classifier runs on the visible viewport (CodeMirror provides the visible
range), so performance is bounded regardless of document size.

A line like `- Flour, 2 cups: Sifted.` gets classified as an IngredientLine,
with sub-ranges: `Flour` → `.hl-ingredient-name`, `2 cups` →
`.hl-ingredient-qty`, `Sifted.` → `.hl-ingredient-prep`. The classifier
uses the same comma-first/colon-second delimiter rules as `IngredientParser`.

### Code folding

A `foldService` callback (not a Lezer grammar) provides two fold targets:

- **Step blocks** — fold from `## Step Title` to the next step header or
  document end. A 200-line recipe becomes scannable at a glance.
- **Front matter** — fold the `Serves:`/`Makes:`/`Category:`/`Tags:` block.

Cross-reference folding deferred to a follow-up.

## Controller Refactoring

### Plaintext controllers

`recipe_plaintext_controller.js` — Currently owns `highlightFn` and delegates
to `HighlightOverlay`. Refactored to: instantiate a CodeMirror `EditorView`
with recipe classifier and fold config, mount into `plaintextContainer`, expose
`get content()` / `set content(markdown)` for the dialog lifecycle (matching
the existing controller API). Line classification moves into the ViewPlugin.

`quickbites_plaintext_controller.js` — Same transformation with quickbites
classifier.

### Coordinator (recipe_editor_controller / quickbites_editor_controller)

Interface stays the same — coordinator calls `content` getter/setter on
whichever child is active. Doesn't need to know it's talking to CodeMirror.
Mode switching continues via `/parse` and `/serialize` round-trips.

### Dialog lifecycle (editor_controller)

Currently reads `textarea.value` directly for simple dialogs (settings,
ordered lists). The `textarea` target and fallback behavior remains unchanged
for non-CodeMirror dialogs. For recipe/quickbites editors, the coordinator
already intercepts lifecycle events and sets `handled = true` — the
`editor_controller` never touches the textarea directly in those flows.

### Auto-dash on Enter

Currently `HighlightOverlay` inserts `- ` on Enter inside ingredient lists.
Becomes a CodeMirror keymap extension that checks the current line's
decoration type for ingredient context — cleaner than the current regex
approach.

### Placeholder text

Both plaintext controllers set multi-line placeholder text showing syntax
examples. CodeMirror's `placeholder()` extension supports only single-line
text. Options: simplify to a one-line hint ("Type a recipe — # Title, then
ingredients and steps"), or use a custom extension that renders the full
example when the document is empty. Start with the single-line approach;
revisit if users miss the detailed example.

### Features gained from CodeMirror

- Undo/redo with proper history grouping
- Multi-cursor editing
- Find/replace (Ctrl+F)
- Proper line wrapping without cursor drift
- Active-line highlight
- Matching-bracket highlight
- Strong ARIA accessibility support

## CSS and Theming

### CSP compatibility

CodeMirror's `EditorView.theme()` injects `<style>` elements into the document
head at runtime via `document.createElement("style")`. The current CSP has
`style-src: self` with no nonce, which blocks dynamically injected styles.

Fix: two-part approach. (1) Extend `content_security_policy_nonce_directives`
to include `style-src` so Rails emits the nonce in the CSP header and in a
`<meta name="csp-nonce">` tag. (2) Use CodeMirror's built-in
`EditorView.cspNonce.of(nonce)` facet — this attaches the nonce attribute to
all `<style>` tags CodeMirror creates. The editor setup reads the nonce from
the meta tag at initialization time.

### Theme strategy

A CodeMirror theme (via `EditorView.theme()`) maps structural classes to
existing CSS variables (`--text`, `--bg`, `--accent`, `--font-mono`). Visual
consistency without duplicating color values.

### Highlight colors

Existing `.hl-*` classes stay in `style.css`. The ViewPlugin's
`Decoration.mark()` calls apply these classes directly — same mechanism as
CSS class application, just through CodeMirror's decoration API instead of
a `<pre>` overlay.

### CSS removed

- `.hl-wrap` (overlay container)
- `.hl-overlay` (`<pre>` layer)
- `.hl-input` (transparent textarea hack)
- Textarea-specific sizing (`min-height: 60vh`, `resize: none`)

### CSS added

- `.cm-editor` sizing (flex: 1, min-height to fill dialog body)
- Fold gutter styling (fold arrows, hover state)
- Active-line highlight styling
- Matching-bracket highlight styling

### Dialog layout

Editor dialog body contains a `<div>` that CodeMirror mounts into. Flex
layout fills available space the same way the textarea did.

## Testing Strategy

### JS tests (new)

Add a Node-based test runner (e.g., `vitest` or plain Node + `assert`) for
the classifier modules. These are pure functions: given a line string, return
classified spans. No DOM or CodeMirror dependency needed for unit tests.

`npm test` runs classifier tests. CI runs `npm test` alongside `rake test`.

### Shared fixtures

A fixture file (`test/fixtures/editor_classification.yml`) contains Markdown
strings with expected token classifications. Both the Ruby tests (validating
`LineClassifier`) and JS tests (validating the ViewPlugin classifier) read
from this file. If the parser changes, the fixture breaks on both sides.

### Existing integration tests

Controller integration tests that submit recipe content via forms continue
to work — they POST markdown strings, not interact with CodeMirror's DOM.
The editor is a client-side concern; server-side tests are unaffected.

### Manual testing

CodeMirror inside `<dialog>`, Turbo morph protection, mode switching, and
fold behavior are best verified manually and via Playwright if the project
adds browser-level tests later. The migration path (step 1 = bundler swap
with no functional changes) provides a safe checkpoint for manual QA.

## Migration Path

### Order

1. **Bundler swap** — Add jsbundling-rails + esbuild + Node. Update import
   paths and Stimulus registration. Existing JS bundled instead of
   importmapped. No functional changes. Clean cut point — verify everything
   works before proceeding.
2. **CodeMirror foundation** — Install packages, build shared editor setup,
   recipe classifier ViewPlugin, fold service.
3. **Recipe editor swap** — `recipe_plaintext_controller` uses CodeMirror.
   Recipe editing works end-to-end.
4. **QuickBites editor swap** — Same pattern, quickbites classifier.
5. **Cleanup** — Remove `HighlightOverlay`, dead CSS, `importmap.rb`.
   Update CLAUDE.md (importmap references, HighlightOverlay references,
   CSP nonce note).

### Rollback

Steps are ordered so that each is independently revertible. If the bundler
swap (step 1) succeeds but CodeMirror integration hits issues, the app
continues working with the textarea+overlay pattern on esbuild. The old
editor code is not removed until step 5, after everything is verified.

### Classifier / LineClassifier sync

The ViewPlugin classifier and `LineClassifier` classify the same lines in
different languages. They can drift. Mitigation: shared YAML fixture file
validated by both Ruby and JS tests (see Testing Strategy).

### Risk: CodeMirror inside `<dialog>`

CodeMirror needs font measurements to render. If initialized while the dialog
is hidden (`display: none`), measurements are zero. Fix: initialize in the
`editor:content-loaded` handler, which fires after the dialog is open and
visible. The existing lifecycle already works this way.

### Risk: Turbo morph

The existing `turbo:before-morph-element` protection on open `<dialog>`
elements prevents morphs from touching the editor. CodeMirror's DOM lives
inside the dialog — protected by the same mechanism.

### Risk: Mode switching

The coordinator handles plaintext ↔ graphical via server round-trips.
CodeMirror's `content` getter/setter maps directly to what `textarea.value`
provided. The serialization contract doesn't change.

## Licensing

CodeMirror 6 is MIT-licensed. Free for any use. No attribution required in
the UI. Attribution in `package.json` and a LICENSE note is good practice.
No CDN or third-party dependency.

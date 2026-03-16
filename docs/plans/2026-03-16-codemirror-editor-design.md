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
- `bin/dev` becomes Procfile-based: Puma + esbuild watch
- Entrypoint: `app/javascript/application.js` → `app/assets/builds/application.js`
- Existing Stimulus controllers and utilities move unchanged — esbuild resolves
  imports the same way importmap did
- `config/importmap.rb` removed; `<script>` tag switches to bundled output
- Propshaft continues serving assets (including esbuild output)

### Dockerfile / CI impact

- Node.js added to builder stage (not runtime — output is static JS)
- CI adds `npm install && npm run build` before `rake test`
- `npm run build`: `esbuild app/javascript/application.js --bundle --outdir=app/assets/builds`

### What stays the same

- Propshaft for asset serving
- Stimulus controller autoloading (esbuild handles the directory)
- CSP configuration (everything self-hosted, no new domains)
- All existing JS logic — this is a packaging change

## CodeMirror Integration Architecture

### Packages

- `@codemirror/view` — editor view, DOM layer
- `@codemirror/state` — editor state, transactions
- `@codemirror/language` — language support, folding
- `@codemirror/commands` — standard keybindings
- `@codemirror/lang-markdown` — Markdown base language
- `@lezer/lr` — Lezer parser runtime for custom overlay grammar

### New JS modules

`app/javascript/codemirror/editor-setup.js` — Shared factory that creates an
`EditorView` with the common extension stack: theme (CSS variables), keybindings,
line wrapping, fold gutter, active-line highlight, matching-bracket highlight,
update listeners. Both recipe and quickbites controllers call this with their
language config.

`app/javascript/codemirror/recipe-language.js` — Configures Markdown language
with the recipe Lezer overlay grammar, fold definitions for step blocks and
front matter, and highlight style mappings.

`app/javascript/codemirror/quickbites-language.js` — Same pattern for QuickBites
syntax.

`app/javascript/codemirror/recipe-grammar.lezer` — Lezer grammar defining
recipe node types: StepHeader, IngredientLine (with Name, Quantity, Prep
sub-nodes), CrossReference, FrontMatter, RecipeLink, Divider. Overlays on top
of the Markdown grammar.

`app/javascript/codemirror/quickbites-grammar.lezer` — Lezer grammar for
QuickBites: CategoryHeader, Item, Ingredients.

### How the overlay works

Lezer's `parseMixed()` runs the Markdown parser first, then the recipe grammar
overlays recipe-specific classifications. A line like `- Flour, 2 cups: Sifted.`
gets parsed as a Markdown list item, then the overlay tags `Flour` as ingredient
name, `2 cups` as quantity, and `Sifted.` as prep — mirroring the same
comma/colon delimiters that `IngredientParser` uses server-side.

### Code folding

Two fold targets in this pass:

- **Step blocks** — fold from `## Step Title` to the next step header or
  document end. A 200-line recipe becomes scannable at a glance.
- **Front matter** — fold the `Serves:`/`Makes:`/`Category:`/`Tags:` block.

Cross-reference folding deferred to a follow-up.

## Controller Refactoring

### Plaintext controllers

`recipe_plaintext_controller.js` — Currently owns `highlightFn` and delegates
to `HighlightOverlay`. Refactored to: instantiate a CodeMirror `EditorView`
with recipe language config, mount into `plaintextContainer`, expose
`getValue()`/`setValue()` for the dialog lifecycle. Line classification moves
into the Lezer grammar.

`quickbites_plaintext_controller.js` — Same transformation with quickbites
language config.

### Coordinator (recipe_editor_controller / quickbites_editor_controller)

Interface stays the same — coordinator calls `getValue()`/`setValue()` on
whichever child is active. Doesn't need to know it's talking to CodeMirror.
Mode switching continues via `/parse` and `/serialize` round-trips.

### Dialog lifecycle (editor_controller)

Currently reads `textarea.value` directly. Abstracted to dispatch events that
the child controller responds to. Plaintext child reads/writes through
CodeMirror's API; graphical child continues as-is.

### Auto-dash on Enter

Currently `HighlightOverlay` inserts `- ` on Enter inside ingredient lists.
Becomes a CodeMirror keymap extension that checks the parse tree for ingredient
context — cleaner than the current regex approach.

### Features gained from CodeMirror

- Undo/redo with proper history grouping
- Multi-cursor editing
- Find/replace (Ctrl+F)
- Proper line wrapping without cursor drift
- Active-line highlight
- Matching-bracket highlight
- Strong ARIA accessibility support

## CSS and Theming

### Theme strategy

A CodeMirror theme (via `EditorView.theme()`) maps structural classes to
existing CSS variables (`--text`, `--bg`, `--accent`, `--font-mono`). Visual
consistency without duplicating color values. The theme generates CSS class
rules — no inline styles (CSP-safe).

### Highlight colors

Existing `.hl-*` classes stay in `style.css`. The Lezer grammar's
`HighlightStyle` maps node types to these same classes. Same colors, different
rendering engine.

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

## Migration Path

### Order

1. **Bundler swap** — Add jsbundling-rails + esbuild + Node. Existing JS
   bundled instead of importmapped. No functional changes. Clean cut point.
2. **CodeMirror foundation** — Install packages, build shared editor setup
   and recipe Lezer grammar.
3. **Recipe editor swap** — `recipe_plaintext_controller` uses CodeMirror.
   Recipe editing works end-to-end.
4. **QuickBites editor swap** — Same pattern, quickbites grammar.
5. **Cleanup** — Remove `HighlightOverlay`, dead CSS, `importmap.rb`.

### Lezer / LineClassifier sync

The Lezer grammar and `LineClassifier` classify the same lines in different
languages. They can drift. Mitigation: shared test fixture file (Markdown
strings with expected token types) validated by both Ruby and JS tests.

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
CodeMirror's `getValue()`/`setValue()` maps directly to what `textarea.value`
provided. The serialization contract doesn't change.

## Licensing

CodeMirror 6 is MIT-licensed. Free for any use. No attribution required in
the UI. Attribution in `package.json` and a LICENSE note is good practice.
No CDN or third-party dependency.

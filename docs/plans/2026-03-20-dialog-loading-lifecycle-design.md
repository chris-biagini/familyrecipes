# Dialog Loading Lifecycle Redesign

**Issue:** #260 — Frontend cleanup: polish dialog/editor loading lifecycle
**Date:** 2026-03-20

## Problem

Editor dialogs feel like they "load in pieces" — the dialog opens immediately
but content arrives asynchronously, causing visible layout transitions. Eight
editor dialogs (recipe edit, recipe new, quick bites, settings, aisles,
categories, tags, nutrition) use four different loading strategies. No
consistent preloading, no unified loading state.

## Design Decisions

### Turbo Frame unification

All editor dialogs load their body content via Turbo Frames. Preloading,
re-preloading on broadcast, and loading placeholders are handled natively by
Turbo — no custom JSON cache or preload logic in JS.

| Editor | Frame `src` set | Preload trigger | Frame response contains |
|--------|----------------|-----------------|------------------------|
| Recipe (edit) | At render time | Page load (eager) | Embedded markdown JSON + server-rendered graphical form |
| Recipe (new) | No `src` | None — starts empty | Empty template (CodeMirror mount + blank graphical form) |
| Quick Bites | At render time | Page load (eager) | Same pattern as recipe edit |
| Settings | At render time | Page load (eager) | Server-rendered settings form with current values |
| Aisles/Categories/Tags | At render time | Page load (eager) | Server-rendered list rows |
| Nutrition | Dynamically on hover | `pointerenter` | Server-rendered nutrition form (unchanged) |

**Preloading:** Frames with `src` at render time load eagerly. Content is
ready before the user clicks Edit.

**Re-preload on broadcast:** `Kitchen#broadcast_update` sends a Turbo refresh
stream. Turbo morphs the page, frames re-render and reload. Content stays
fresh automatically.

**Nutrition exception:** Stays hover-triggered because the URL is
per-ingredient (dynamic). Same Turbo Frame mechanism, different trigger timing.

### Shared dialog shell

`_editor_dialog.html.erb` becomes the universal shell for all editor dialogs.
It provides the `<dialog>` element, header (title + close button), error
display, footer (cancel + save buttons), and optional mode toggle. Each dialog
type provides its body content via `yield` — a Turbo Frame with
editor-specific content.

The three ordered list editors (aisles, categories, tags) migrate from custom
`<dialog>` markup to `render layout: 'shared/editor_dialog'`. Their body
becomes the yielded block.

### editor_controller changes

`editor_controller` remains the lifecycle owner for all dialogs. Changes:

- **Remove** `openWithRemoteContent()` — no more custom JSON fetch/cache.
- **Remove** `loadUrl`, `loadKey` values — Turbo handles loading.
- **Add** frame readiness check on `open()`. The current branch on
  `hasLoadUrlValue` is replaced by frame-state detection: if the body contains
  a Turbo Frame with no `src` (new recipe) or a frame whose content has
  already loaded, `showModal()` immediately. If the frame is still loading,
  disable Save and wait for `turbo:frame-load`.
- **Add** error handling: listen for frame load failures, show error message
  with "Try again" button that resets the frame `src`.
- **Keep** `openWithContent(data)` — AI import still provides caller-supplied
  data.
- **Keep** all lifecycle events: `editor:collect`, `editor:save`,
  `editor:modified`, `editor:reset`, `editor:content-loaded`,
  `editor:opened`.

### Ordered list editor becomes companion controller

`ordered_list_editor_controller` delegates lifecycle to `editor_controller`
(same pattern as `settings_editor_controller` and `nutrition_editor_controller`).

**Removed from ordered list controller (~100 lines):**
- `open()`, `close()`, `handleCancel()`, `handleBeforeVisit()`
- `loadItems()` fetch, `parseLoadedItems()` JSON-to-items transform
- `save()` — `editor_controller` handles `markSaving` and the success callback
  (`onSuccess: 'reload'`); the ordered list controller provides only a `saveFn`
  via `editor:save`, same pattern as settings/nutrition
- `connect()`/`disconnect()` listener setup for open button, cancel, Turbo visit
- `guardBeforeUnload`, `resetSaveButton()`

**Stays in ordered list controller (~130 lines):**
- `editor:content-loaded` — reads item names from server-rendered DOM rows
  (replaces `parseLoadedItems()` JSON parsing), takes snapshot for dirty
  detection
- `editor:collect` / `editor:save` — build payload from current items, provide
  `saveFn` to `editor_controller`
- `editor:modified` — compare current state to snapshot
- `editor:reset` — restore rows to initial state
- List manipulation: add, delete, rename, reorder, animate

The server renders initial list rows as HTML. All mutations (add, delete,
reorder, rename) happen client-side after frame load.

### Settings editor simplification

`settings_editor_controller` stops doing its own fetch and `showModal()`.
The server renders the settings form with current values in the Turbo Frame.
The controller handles `editor:collect`, `editor:save`, `editor:modified`,
`editor:reset` — same companion pattern it already uses, minus the custom
`openDialog()` and `disableFields()`.

**Timing note:** `storeOriginals()` for dirty detection must run on
`editor:content-loaded` (after `turbo:frame-load`), since form fields arrive
pre-populated from the server rather than being populated by JS after a JSON
fetch.

### Recipe/Quick Bites conversion to server-rendered frames

New server endpoint (e.g., `GET /recipes/:slug/editor`) returns a Turbo Frame
containing everything both editor modes need:

```html
<turbo-frame id="recipe-editor-content">
  <script type="application/json" data-editor-markdown>
    {"markdown_source": "## Steps\n1. Preheat oven..."}
  </script>

  <div data-dual-mode-editor-target="plaintextContainer" class="editor-body">
    <div data-controller="plaintext-editor" ...>
      <div class="cm-mount" data-plaintext-editor-target="mount"></div>
    </div>
  </div>

  <div data-dual-mode-editor-target="graphicalContainer" class="editor-body" hidden>
    <!-- Server-rendered graphical form: steps, ingredients, front matter -->
  </div>
</turbo-frame>
```

**Plaintext mode:** `plaintext_editor_controller` connects on frame load,
reads markdown from embedded `<script type="application/json">`, initializes
CodeMirror.

**Graphical mode:** Server-rendered ERB partials replace client-side DOM
construction. JS shrinks from "build entire DOM from structure hash" to "add
interactivity to existing DOM" (add/remove rows, reorder, inline editing).

**Mode switching** unchanged — `/parse` and `/serialize` endpoints still
convert between representations. Responses can return HTML fragments for the
graphical container instead of JSON structure hashes.

**New recipe dialog (homepage):** No Turbo Frame `src` — the dialog starts
with an empty template (blank CodeMirror mount + empty graphical form). This
is the same as today's `open()` path (no remote content). The frame element
is present in the markup but has no `src`, so no preload occurs. On open,
`editor_controller` sees a frame with no `src` (or an already-loaded empty
frame) and opens immediately.

**Quick Bites:** Same pattern as recipe edit — server renders graphical form +
embedded plaintext content in the frame.

### Unified loading state

**Happy path (frame loaded):** Dialog opens instantly. No loading indicator.

**Fallback (frame still loading):** Every frame contains the same placeholder:

```html
<turbo-frame id="..." src="...">
  <p class="loading-placeholder">Loading…</p>
</turbo-frame>
```

One CSS class, one visual treatment. `editor_controller` disables Save until
`turbo:frame-load` fires.

**Error case:** `editor_controller` detects frame load failure, replaces
placeholder with error message + "Try again" button. Retry resets frame `src`.

**Deleted:**
- `openWithRemoteContent()` loading/disabling/placeholder logic
- `disableFields(true/false)` in settings controller
- `loadItems()` fetch + disabled save in ordered list controller
- `.cm-mount.cm-loading` CSS (frame placeholder covers this)

## Scope notes

This redesign sets up the recipe graphical editor as server-rendered partials,
which aligns with a planned future overhaul of that editor. The graphical
editing experience becomes ERB templates + lightweight JS interactivity instead
of JS DOM construction — iteration happens in views and CSS, not createElement
chains.

The dinner picker dialog is out of scope — it uses client-side data with no
fetch, so there's no loading lifecycle to unify.

## Acceptance criteria

- All editor dialogs use `_editor_dialog.html.erb` (custom dialog markup
  removed from groceries and homepage views)
- All editor dialog bodies load via Turbo Frames
- Eager preloading on page load for all editors except nutrition
  (hover-prefetch)
- Re-preload on ActionCable broadcast via Turbo refresh morph
- Consistent loading placeholder across all dialogs
- Error-with-retry for frame load failures
- Ordered list editors delegate lifecycle to `editor_controller`
- Settings editor delegates open/fetch to Turbo Frame
- Recipe/Quick Bites graphical editors are server-rendered partials
- All existing editor lifecycle events continue to work
- All existing tests pass

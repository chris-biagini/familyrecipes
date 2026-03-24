# Editor Content Loading: Eliminate Baked-In Content

## Problem

The recipe edit dialog bakes `@recipe.markdown_source` into the textarea at
render time. Combined with Turbo Drive and broadcast morphing, this creates two
bugs:

1. **Stale content after navigation.** `data-turbo-permanent` (since removed)
   preserved the dialog across page navigations, so navigating Pizza → Pancakes
   showed Pizza's source in the editor. The current `turbo:before-morph-element`
   fix prevents this during morphs, but baked content is fundamentally fragile —
   any DOM preservation mechanism risks serving stale data.

2. **No defensive cleanup on Turbo lifecycle events.** Nothing closes open
   dialogs before Turbo caches the page or before Drive navigation. Browser
   back/forward while a modal is open can silently discard unsaved edits.

## Root Cause

The Quick Bites editor fetches content on open (`loadUrl`), so it always has
fresh data. The recipe editor is the only textarea-based editor that bakes
content into the HTML. This is legacy divergence, not a genuine difference —
both are simple text blobs loaded into a textarea.

## Solution

Two changes, one local and one global:

### A. Convert recipe editor to `loadUrl` pattern

Add a JSON endpoint that returns the recipe's markdown source. Wire the edit
dialog to use `editor_load_url` / `editor_load_key`. Remove the baked-in
textarea value. The generic editor controller's `openWithRemoteContent()` handles
the rest — no JS changes needed.

**New endpoint:** `GET /recipes/:slug/content` → `{ markdown_source: "..." }`

This mirrors the existing Quick Bites pattern:
`GET /menu/quick_bites_content` → `{ content: "..." }`

The **new recipe** editor on the homepage keeps its static template — it's not
user data and can't go stale.

### B. Add defensive Turbo lifecycle handlers

Two global handlers in `application.js` that protect all editors (including
future ones) from Turbo lifecycle edge cases:

1. **`turbo:before-cache`** — Close all open editor dialogs before Turbo
   snapshots the page. Prevents cached page restorations from showing open
   dialogs with stale state and detached event listeners.

2. **`turbo:before-visit`** — Close all open editor dialogs before Drive
   navigation. If a dialog has unsaved changes, cancel the navigation and show
   the existing "discard changes?" confirmation. This catches browser
   back/forward while a modal is open.

Both handlers use `dialog.close()` on `dialog.editor-dialog[open]` elements.
The `turbo:before-visit` handler additionally checks for modifications via the
editor controller's existing `isModified()` mechanism (dispatching
`editor:modified` on the dialog element and checking the result).

### Interaction with existing morph protection

The `turbo:before-morph-element` listener (added earlier this session) remains
unchanged. It protects open dialogs during broadcast refresh morphs. The new
handlers cover different lifecycle events:

| Event | Purpose | Scope |
|---|---|---|
| `turbo:before-morph-element` | Prevent morph of open dialogs | Broadcast refresh |
| `turbo:before-cache` | Close dialogs before page snapshot | All navigations |
| `turbo:before-visit` | Guard unsaved changes on navigation | Drive visits |

### What about ordered-list editors?

The aisle and category order editors are self-contained (own controller, own
lifecycle). They already fetch content on open. They don't use `editor-dialog`
class or the editor controller, so the `turbo:before-cache` handler needs to
target both `dialog.editor-dialog[open]` and any other open `<dialog>` elements.
Simplest approach: close ALL open `<dialog>` elements on `turbo:before-cache`.

For `turbo:before-visit`, the ordered-list editor should also participate. Since
it has its own `isModified()` method, we can dispatch a generic custom event on
the dialog and let each controller decide whether to block navigation.

Simpler alternative: put both handlers in the editor controller and the
ordered-list-editor controller separately. Each controller knows its own dialog
and its own dirty state. This avoids coupling between the two systems.

**Recommendation:** Each controller manages its own `turbo:before-visit`
listener. The `turbo:before-cache` handler is a simple global that closes all
open `<dialog>` elements — no controller coupling needed.

## Files Changed

- `app/controllers/recipes_controller.rb` — add `content` action
- `config/routes.rb` — add `GET recipes/:slug/content` route
- `app/views/recipes/show.html.erb` — add `editor_load_url`, `editor_load_key`,
  remove baked textarea value
- `app/javascript/application.js` — add `turbo:before-cache` handler
- `app/javascript/controllers/editor_controller.js` — add `turbo:before-visit`
  handler with unsaved-changes guard
- `app/javascript/controllers/ordered_list_editor_controller.js` — add
  `turbo:before-visit` handler with unsaved-changes guard
- `CLAUDE.md` — update Editor dialogs section
- Tests for the new endpoint and updated views

## Not Changed

- New recipe editor (homepage) — static template, not user data
- Quick Bites editor — already uses `loadUrl`
- Nutrition editor — Turbo Frame pattern, genuinely different
- Aisle/category editors — already fetch on open
- `turbo:before-morph-element` listener — unchanged

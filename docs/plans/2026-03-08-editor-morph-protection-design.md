# Editor Morph Protection & Cleanup Design

Fixes #199 (Quick Bites editor bugs) and hardens all editor dialogs against
Turbo morph interference. Extracts shared highlight overlay utility and merges
duplicate ordered-list editor controllers.

## Problem

`Kitchen#broadcast_update` fires `broadcast_refresh_to` which triggers a Turbo
morph on all connected clients — including the client that just saved. When a
dialog is open, the morph re-renders the page HTML (which has an empty or
server-rendered textarea) and replaces/disrupts the dialog's DOM state.

Three symptoms reported in #199:

1. **Quick Bites not saving** — content saves on server, but broadcast morph
   resets the textarea to empty while warnings keep the dialog open. User sees
   content vanish; saving again overwrites good content with empty string.
2. **Editor doesn't reload after bad syntax** — morph corrupts overlay wrapper
   and Stimulus controller state. Reopening fails to reinitialize.
3. **No syntax highlighting on second load** — `openWithRemoteContent` sets
   `textarea.value` programmatically, which doesn't fire `input` events.
   `highlight()` never runs for the new content.

## Affected Dialogs

| Dialog | Partial | onSuccess | id | Morph risk |
|--------|---------|-----------|-----|-----------|
| Quick Bites | shared | close | **none** | **High** |
| Nutrition (×2) | shared | close | nutrition-editor | Medium |
| Recipe (edit) | shared | redirect | recipe-editor | Low |
| Recipe (new) | shared | redirect | recipe-editor | Low |
| Category order | standalone | reload | **none** | Medium |
| Aisle order | standalone | reload | **none** | Medium |

"Redirect" and "reload" editors dodge the problem by navigating away, but are
still vulnerable if another client's broadcast arrives while their dialog is
open.

## Solution

### A. Morph protection — `data-turbo-permanent`

Add `data-turbo-permanent` + stable `id` to every `<dialog>`. Turbo morph
skips elements with this attribute, preserving the dialog DOM exactly as-is
during page refresh.

- **Shared partial** (`_editor_dialog.html.erb`): add the attribute; require
  `id` (currently optional). Covers 4 dialogs.
- **Standalone dialogs** (aisle order, category order): add `id` +
  `data-turbo-permanent` to each.
- **Quick Bites**: pass `id: 'quickbites-editor'` in render call.

### B. Highlight on content load

Extend the `MutationObserver` (which already watches `disabled` attribute) to
call `highlight()` when textarea transitions from disabled to enabled. This is
the moment `openWithRemoteContent` finishes loading content. Fixes the "no
highlight on second load" bug.

### C. Extract shared highlight overlay utility

`quickbites_editor_controller.js` and `recipe_editor_controller.js` share
~120 lines of identical code: `buildOverlay`, `teardownTextarea`,
`syncScroll`, `handleFocus`, `handleKeydown` (auto-dash), `MutationObserver`
setup, and `setPlaceholder`. Only `highlight()` (line classification) differs.

Extract to `utilities/highlight_overlay.js`:

```
HighlightOverlay class:
  constructor(textarea, highlightFn)
  attach()      — buildOverlay, bind events, MutationObserver
  detach()      — teardown, unbind, unwrap
  highlight()   — calls the injected highlightFn
  syncScroll()
  handleFocus()
  handleKeydown(e)  — auto-dash
```

Each editor controller instantiates `HighlightOverlay` in
`textareaTargetConnected`, passing its own `highlight` function, and calls
`detach()` in `textareaTargetDisconnected`.

### D. Merge aisle/category order editors

`aisle_order_editor_controller.js` (206 lines) and
`category_order_editor_controller.js` (200 lines) are structurally identical.
They differ only in:

- Data property name (`aisles` vs `categories`)
- Payload shape (aisle joins with `\n`, category does not)
- Target names for the "add" input
- Button selector for opening

Replace with a single `ordered_list_editor_controller.js` parameterized by
Stimulus values:

```
static values = {
  loadUrl: String,
  saveUrl: String,
  payloadKey: { type: String, default: "order" },
  joinWith: { type: String, default: "" },
  openSelector: String
}
```

Views configure via data attributes. `ordered_list_editor_utils.js` is
unchanged. Delete the two old controllers.

## Files Changed

**Create:**
- `app/javascript/utilities/highlight_overlay.js`
- `app/javascript/controllers/ordered_list_editor_controller.js`

**Modify:**
- `app/views/shared/_editor_dialog.html.erb` — add `data-turbo-permanent`
- `app/views/menu/show.html.erb` — add `id: 'quickbites-editor'`
- `app/views/groceries/show.html.erb` — replace aisle-order-editor with
  ordered-list-editor, add `id` + `data-turbo-permanent`
- `app/views/homepage/show.html.erb` — replace category-order-editor with
  ordered-list-editor, add `id` + `data-turbo-permanent`
- `app/javascript/controllers/quickbites_editor_controller.js` — use
  HighlightOverlay
- `app/javascript/controllers/recipe_editor_controller.js` — use
  HighlightOverlay
- `app/javascript/utilities/ordered_list_editor_utils.js` — update header
  comment

**Delete:**
- `app/javascript/controllers/aisle_order_editor_controller.js`
- `app/javascript/controllers/category_order_editor_controller.js`

## Testing

All changes are JavaScript-only — no Ruby model/controller changes. Existing
controller tests remain valid since they test HTTP endpoints, not JS behavior.
Manual verification:

1. Open Quick Bites editor, save with bad syntax → warnings show, content
   stays in textarea, overlay highlights correctly
2. Close and reopen → content loads, highlights render
3. Open Quick Bites editor on device A, save on device B → device A's dialog
   is not disrupted
4. Aisle and category editors work identically to before
5. Nutrition editor is not disrupted by morph during save

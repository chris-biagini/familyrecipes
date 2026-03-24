# Editor Framework Design

## Problem

The app has 4 editor dialogs across 3 views (recipe, groceries x2, ingredients) that share the same visual chrome and lifecycle but duplicate the HTML boilerplate. The nutrition editor diverged into its own JS file because it needed custom content (aisle selector), but the intent was always for all editors to share a pipeline. GitHub issue #95.

## Goals

- Single shared HTML partial for dialog chrome (header, errors, footer)
- Unified JS framework that owns lifecycle, dirty-checking, save transport, and error display
- Content area is wide open — no assumptions about what lives inside the dialog
- Simple textarea dialogs work with just data attributes (zero custom JS)
- Custom dialogs hook into the lifecycle via DOM events
- Framework-managed save transport with an escape hatch for custom save flows

## Non-goals

- Client-side post-save broadcasting (server-side ActionCable is sufficient)
- Changing the visual design of any dialog
- Adding new editor dialogs (this is infrastructure only)

## Event Contract

The framework dispatches lifecycle events on the `<dialog>` element. Each event has a `detail.handled` field. If no listener sets `handled = true`, the framework falls back to built-in textarea behavior.

| Event | When | `detail` fields | Default (unclaimed) behavior |
|---|---|---|---|
| `editor:setup` | Once during init | `{ handled }` | Wire up textarea + data-attribute config |
| `editor:opening` | Before `showModal()` | `{ handled }` | Snapshot textarea value as original |
| `editor:collect` | Save clicked | `{ handled, data }` | `{ [bodyKey]: textarea.value }` |
| `editor:save` | After collect | `{ handled, data, promise }` | `EditorUtils.saveRequest(url, method, data)` |
| `editor:modified` | Dirty-check | `{ handled, modified }` | Compare textarea to snapshot |
| `editor:reset` | Cancel/close confirmed | `{ handled }` | Restore textarea to snapshot |

Custom dialogs claim events by setting `e.detail.handled = true` and filling relevant fields. For `editor:save`, the listener provides a `promise` that resolves/rejects like the default fetch would.

## HTML Partial

`app/views/shared/_editor_dialog.html.erb` — renders as a layout, yields a block for content.

```erb
<%# locals: (title:, id: nil, dialog_data: {}, footer_extra: nil) %>
<dialog id="<%= id %>" class="editor-dialog" <%= tag.attributes(dialog_data) %>>
  <div class="editor-header">
    <h2><%= title %></h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <%= yield %>
  <div class="editor-footer">
    <%= footer_extra %>
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>
```

- `dialog_data` hash becomes `data-*` attributes via `tag.attributes`
- `footer_extra` is pre-rendered HTML (or nil) for extras like delete buttons or aisle selectors
- Content block: anything — textarea, form fields, custom UI

### Caller examples

Simple (groceries Quick Bites):
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Quick Bites',
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: groceries_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'reload',
                             editor_body_key: 'content' } } do %>
  <textarea class="editor-textarea" spellcheck="false"><%= @quick_bites_content %></textarea>
<% end %>
```

Custom (nutrition — no data attributes, fully event-driven):
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Nutrition',
              id: 'nutrition-editor',
              footer_extra: render('ingredients/aisle_selector', aisles: @available_aisles) } do %>
  <textarea id="nutrition-editor-textarea" class="editor-textarea" spellcheck="false"></textarea>
<% end %>
```

## JS Architecture

### editor-framework.js

Replaces `recipe-editor.js`. Auto-discovers all `.editor-dialog` elements on DOMContentLoaded. For each dialog:

1. Dispatch `editor:setup` — if unclaimed, wire up default textarea behavior
2. Find open trigger via `data-editor-open` — attach click handler
3. On open: dispatch `editor:opening`, handle lazy-load if `data-editor-load-url`, `showModal()`
4. On save: dispatch `editor:collect`, then `editor:save`, handle response
5. On close/cancel: dispatch `editor:modified`, confirm if dirty, dispatch `editor:reset`

Delete-recipe handling (`.editor-delete` button) remains generic — the framework discovers it in any dialog.

### nutrition-editor.js

Slims down to just event listeners on `#nutrition-editor`:

- `editor:setup` — wires custom open triggers (per-ingredient buttons), aisle select, reset buttons
- `editor:collect` — returns `{ label_text, aisle }`
- `editor:save` — custom POST to nutrition URL
- `editor:modified` — checks textarea + aisle changes
- `editor:reset` — restores textarea + aisle select

### editor-utils.js

Unchanged. Already provides `saveRequest`, `handleSave`, `closeWithConfirmation`, `getCsrfToken`.

### Script loading

No ordering constraints between `editor-framework.js` and custom dialog JS. Events are dispatched during user interactions (well after DOMContentLoaded). Only requirement: `editor-utils.js` loads before `editor-framework.js` (already the case).

## Migration Plan

### Phase 1 — Add new, change nothing
- Create `shared/_editor_dialog.html.erb`
- Create `editor-framework.js`

### Phase 2 — Migrate groceries dialogs
- Replace 2 inline dialogs with shared partial calls
- Switch from `recipe-editor.js` to `editor-framework.js`

### Phase 3 — Migrate recipe editor
- Replace `recipes/_editor_dialog.html.erb` with shared partial
- Extract delete button to `recipes/_editor_delete_button.html.erb`
- Mode logic moves to callers (recipe views pass different locals)

### Phase 4 — Migrate nutrition editor
- Replace inline dialog with shared partial
- Extract aisle selector to `ingredients/_aisle_selector.html.erb`
- Rewrite `nutrition-editor.js` to event-listener style

### Phase 5 — Cleanup
- Delete `recipe-editor.js` and `recipes/_editor_dialog.html.erb`
- Full test suite + lint pass

# Editor Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace 4 duplicated editor dialog implementations with a shared HTML partial and unified event-driven JS framework.

**Architecture:** A shared `_editor_dialog` partial renders dialog chrome (header, errors, footer) and yields a block for custom content. A new `editor-framework.js` auto-discovers `.editor-dialog` elements and manages lifecycle (open, save, dirty-check, close) via custom DOM events. Simple dialogs work with just data attributes; custom dialogs claim events to override defaults.

**Tech Stack:** Rails 8 ERB partials, vanilla JavaScript (no build step), Propshaft asset serving.

**Design doc:** `docs/plans/2026-02-25-editor-framework-design.md`

---

### Task 1: Create the shared editor dialog partial

**Files:**
- Create: `app/views/shared/_editor_dialog.html.erb`

**Step 1: Create the partial**

```erb
<%# locals: (title:, id: nil, dialog_data: {}, footer_extra: nil) %>
<%= tag.dialog id: id, class: 'editor-dialog', data: dialog_data do %>
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
<% end %>
```

Key details:
- `tag.dialog` omits `id` when nil, omits `data-*` when `dialog_data` is empty
- `dialog_data` hash keys use underscores (`editor_open`), Rails auto-converts to dashes (`data-editor-open`)
- `footer_extra` is pre-rendered HTML (`ActiveSupport::SafeBuffer`) or nil
- Block content via `yield` — callers use `render layout:` to pass their content block

**Step 2: Run tests to confirm nothing breaks**

Run: `rake test`
Expected: all existing tests pass (partial is created but not used yet)

**Step 3: Commit**

```bash
git add app/views/shared/_editor_dialog.html.erb
git commit -m "feat: add shared editor dialog partial (issue #95)"
```

---

### Task 2: Create editor-framework.js

**Files:**
- Create: `app/assets/javascripts/editor-framework.js`
- Reference: `app/assets/javascripts/editor-utils.js` (unchanged)
- Reference: `app/assets/javascripts/recipe-editor.js` (to replicate behavior)

**Step 1: Create the framework**

```js
// Unified editor dialog framework.
// Auto-discovers .editor-dialog elements and manages lifecycle via custom DOM events.
// Simple dialogs: configure entirely with data-editor-* attributes (no custom JS).
// Custom dialogs: listen for editor:* events on the dialog element and set detail.handled = true.
//
// Events dispatched on <dialog>:
//   editor:collect  — Save clicked.    detail: { handled, data }
//   editor:save     — After collect.   detail: { handled, data, saveFn }
//   editor:modified — Dirty-check.     detail: { handled, modified }
//   editor:reset    — Cancel/close.    detail: { handled }
//
// Depends on: editor-utils.js (must load first)

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.editor-dialog').forEach(initEditor);

  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});

function initEditor(dialog) {
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const deleteBtn = dialog.querySelector('.editor-delete');
  const textarea = dialog.querySelector('.editor-textarea');
  const errorsDiv = dialog.querySelector('.editor-errors');

  const openSelector = dialog.dataset.editorOpen;
  const actionUrl = dialog.dataset.editorUrl;
  const method = dialog.dataset.editorMethod || 'PATCH';
  const onSuccess = dialog.dataset.editorOnSuccess || 'redirect';
  const bodyKey = dialog.dataset.editorBodyKey || 'markdown_source';

  let originalContent = '';

  // --- Event helpers ---

  function dispatch(name, extra) {
    const detail = Object.assign({ handled: false }, extra);
    const event = new CustomEvent(name, { detail: detail, bubbles: false });
    dialog.dispatchEvent(event);
    return event.detail;
  }

  function isModified() {
    const result = dispatch('editor:modified', { modified: false });
    if (result.handled) return result.modified;
    return textarea ? textarea.value !== originalContent : false;
  }

  function resetContent() {
    const result = dispatch('editor:reset');
    if (!result.handled && textarea) textarea.value = originalContent;
    EditorUtils.clearErrors(errorsDiv);
  }

  function closeDialog() {
    EditorUtils.closeWithConfirmation(dialog, isModified, resetContent);
  }

  const guard = EditorUtils.guardBeforeUnload(dialog, isModified);

  // --- Open trigger (default behavior, skipped for custom dialogs without data-editor-open) ---

  if (openSelector) {
    const openBtn = document.querySelector(openSelector);
    if (openBtn) {
      openBtn.addEventListener('click', () => {
        EditorUtils.clearErrors(errorsDiv);

        const loadUrl = dialog.dataset.editorLoadUrl;
        if (loadUrl) {
          if (textarea) {
            textarea.value = '';
            textarea.disabled = true;
            textarea.placeholder = 'Loading\u2026';
          }
          dialog.showModal();

          fetch(loadUrl, {
            headers: { 'Accept': 'application/json', 'X-CSRF-Token': EditorUtils.getCsrfToken() }
          })
            .then(function(r) { return r.json(); })
            .then(function(data) {
              var key = dialog.dataset.editorLoadKey || 'content';
              if (textarea) {
                textarea.value = data[key] || '';
                originalContent = textarea.value;
                textarea.disabled = false;
                textarea.placeholder = '';
                textarea.focus();
              }
            })
            .catch(function() {
              if (textarea) {
                textarea.value = '';
                textarea.disabled = false;
                textarea.placeholder = '';
              }
              EditorUtils.showErrors(errorsDiv, ['Failed to load content. Close and try again.']);
            });
        } else {
          if (textarea) originalContent = textarea.value;
          dialog.showModal();
        }
      });
    }
  }

  // --- Close / Cancel ---

  if (closeBtn) closeBtn.addEventListener('click', closeDialog);
  if (cancelBtn) cancelBtn.addEventListener('click', closeDialog);

  dialog.addEventListener('cancel', function(event) {
    if (isModified()) {
      event.preventDefault();
      closeDialog();
    }
  });

  // --- Save ---

  if (saveBtn) {
    saveBtn.addEventListener('click', function() {
      var collectResult = dispatch('editor:collect', { data: null });
      var data = collectResult.handled ? collectResult.data : { [bodyKey]: textarea?.value };

      var saveResult = dispatch('editor:save', { data: data, saveFn: null });
      var saveFn = saveResult.handled && saveResult.saveFn
        ? saveResult.saveFn
        : function() { return EditorUtils.saveRequest(actionUrl, method, data); };

      EditorUtils.handleSave(saveBtn, errorsDiv, saveFn, function(responseData) {
        guard.markSaving();

        if (onSuccess === 'reload') {
          window.location.reload();
        } else {
          var redirectUrl = responseData.redirect_url;
          if (responseData.updated_references?.length > 0) {
            var param = encodeURIComponent(responseData.updated_references.join(', '));
            var separator = redirectUrl.includes('?') ? '&' : '?';
            redirectUrl += separator + 'refs_updated=' + param;
          }
          window.location = redirectUrl;
        }
      });
    });
  }

  // --- Delete (generic — works for any dialog containing .editor-delete) ---

  if (deleteBtn) {
    deleteBtn.addEventListener('click', async function() {
      var title = deleteBtn.dataset.recipeTitle;
      var referencing = JSON.parse(deleteBtn.dataset.referencingRecipes || '[]');

      var message;
      if (referencing.length > 0) {
        message = 'Delete "' + title + '"?\n\nCross-references in ' + referencing.join(', ') + ' will be converted to plain text.\n\nThis cannot be undone.';
      } else {
        message = 'Delete "' + title + '"?\n\nThis cannot be undone.';
      }

      if (!confirm(message)) return;

      deleteBtn.disabled = true;
      deleteBtn.textContent = 'Deleting\u2026';

      try {
        var response = await fetch(actionUrl, {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': EditorUtils.getCsrfToken()
          }
        });

        if (response.ok) {
          var data = await response.json();
          guard.markSaving();
          window.location = data.redirect_url;
        } else {
          EditorUtils.showErrors(errorsDiv, ['Failed to delete (' + response.status + '). Please try again.']);
          deleteBtn.disabled = false;
          deleteBtn.textContent = 'Delete';
        }
      } catch (err) {
        EditorUtils.showErrors(errorsDiv, ['Network error. Please check your connection and try again.']);
        deleteBtn.disabled = false;
        deleteBtn.textContent = 'Delete';
      }
    });
  }
}
```

**Step 2: Run tests**

Run: `rake test`
Expected: all pass (new file created but not loaded by any view yet)

**Step 3: Commit**

```bash
git add app/assets/javascripts/editor-framework.js
git commit -m "feat: add editor-framework.js with event-driven lifecycle (issue #95)"
```

---

### Task 3: Migrate groceries dialogs

**Files:**
- Modify: `app/views/groceries/show.html.erb:12-13` (script tags)
- Modify: `app/views/groceries/show.html.erb:95-133` (replace inline dialogs)

**Step 1: Switch script tag from recipe-editor to editor-framework**

In `app/views/groceries/show.html.erb`, change line 13:

```erb
# Before:
<%= javascript_include_tag 'recipe-editor', defer: true %>

# After:
<%= javascript_include_tag 'editor-framework', defer: true %>
```

**Step 2: Replace the two inline dialogs with shared partial calls**

Replace lines 95-133 (the `<% if current_kitchen.member?(current_user) %>` block containing both dialogs) with:

```erb
<% if current_kitchen.member?(current_user) %>
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Quick Bites',
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: groceries_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'reload',
                             editor_body_key: 'content' } } do %>
  <textarea class="editor-textarea" spellcheck="false"><%= @quick_bites_content %></textarea>
<% end %>

<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Aisle Order',
              dialog_data: { editor_open: '#edit-aisle-order-button',
                             editor_url: groceries_aisle_order_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'reload',
                             editor_body_key: 'aisle_order',
                             editor_load_url: groceries_aisle_order_content_path,
                             editor_load_key: 'aisle_order' } } do %>
  <textarea class="editor-textarea" spellcheck="false" placeholder="Loading..."></textarea>
<% end %>
<% end %>
```

**Step 3: Run tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: all pass. Key assertion to watch: `assert_select 'dialog[data-editor-open="#edit-aisle-order-button"]'` at line 138.

Run: `rake test`
Expected: full suite passes.

**Step 4: Commit**

```bash
git add app/views/groceries/show.html.erb
git commit -m "refactor: migrate groceries dialogs to shared editor partial (issue #95)"
```

---

### Task 4: Migrate recipe editor

**Files:**
- Create: `app/views/recipes/_editor_delete_button.html.erb`
- Modify: `app/views/recipes/show.html.erb:16-22` (script tags), `54-60` (dialog render)
- Modify: `app/views/homepage/show.html.erb:11-15` (script tags), `47-52` (dialog render)
- Delete: `app/views/recipes/_editor_dialog.html.erb` (old partial)

**Step 1: Create the delete button sub-partial**

```erb
<%# locals: (recipe:) %>
<button type="button" class="btn btn-danger editor-delete"
        data-recipe-title="<%= recipe.title %>"
        data-recipe-slug="<%= recipe.slug %>"
        data-referencing-recipes="<%= recipe.referencing_recipes.pluck(:title).to_json %>">Delete</button>
<span class="editor-footer-spacer"></span>
```

**Step 2: Update recipe show page**

In `app/views/recipes/show.html.erb`, change the script tag (line 21):

```erb
# Before:
<%= javascript_include_tag 'recipe-editor', defer: true %>

# After:
<%= javascript_include_tag 'editor-framework', defer: true %>
```

Replace the dialog render (lines 54-60) with:

```erb
<% if current_kitchen.member?(current_user) %>
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source' },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <textarea class="editor-textarea" spellcheck="false"><%= @recipe.markdown_source %></textarea>
<% end %>
<% end %>
```

**Step 3: Update homepage**

In `app/views/homepage/show.html.erb`, change the script tag (line 14):

```erb
# Before:
<%= javascript_include_tag 'recipe-editor', defer: true %>

# After:
<%= javascript_include_tag 'editor-framework', defer: true %>
```

Replace the dialog render (lines 47-52) with:

```erb
<% if current_kitchen.member?(current_user) %>
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source' } } do %>
  <textarea class="editor-textarea" spellcheck="false"><%= "# Recipe Title\n\nOptional description.\n\nCategory: \nMakes: \nServes: \n\n## Step Name (short summary)\n\n- Ingredient, quantity: prep note\n\nInstructions here.\n\n---\n\nOptional notes or source." %></textarea>
<% end %>
<% end %>
```

**Step 4: Delete old partial**

Delete `app/views/recipes/_editor_dialog.html.erb`.

**Step 5: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb && ruby -Itest test/integration/end_to_end_test.rb`

Key assertions to watch:
- `assert_select '#recipe-editor'` (show page, line 72)
- `assert_select '#recipe-editor[data-editor-method="POST"]'` (homepage, end_to_end line 133)
- `assert_select '.editor-textarea'` (both)

Run: `rake test`
Expected: full suite passes.

**Step 6: Commit**

```bash
git add app/views/recipes/_editor_delete_button.html.erb app/views/recipes/show.html.erb app/views/homepage/show.html.erb
git rm app/views/recipes/_editor_dialog.html.erb
git commit -m "refactor: migrate recipe editor to shared partial (issue #95)"
```

---

### Task 5: Migrate nutrition editor

**Files:**
- Create: `app/views/ingredients/_aisle_selector.html.erb`
- Modify: `app/views/ingredients/index.html.erb:58-86` (dialog + script tags)
- Modify: `app/assets/javascripts/nutrition-editor.js` (rewrite to event-listener style)

**Step 1: Create the aisle selector sub-partial**

```erb
<%# locals: (aisles:) %>
<select id="nutrition-editor-aisle" class="aisle-select" aria-label="Grocery aisle">
  <option value="">(none)</option>
  <%- aisles.each do |aisle| -%>
  <option value="<%= aisle %>"><%= aisle %></option>
  <%- end -%>
  <option disabled>&#x2500;&#x2500;&#x2500;</option>
  <option value="omit">Omit from Grocery List</option>
  <option disabled>&#x2500;&#x2500;&#x2500;</option>
  <option value="__other__">New aisle&hellip;</option>
</select>
<input type="text" id="nutrition-editor-aisle-input" class="aisle-input" placeholder="New aisle name" hidden>
<span class="editor-footer-spacer"></span>
```

**Step 2: Update ingredients view**

Replace lines 58-86 (the `<% if current_kitchen.member?(current_user) %>` block) with:

```erb
<% if current_kitchen.member?(current_user) %>
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Nutrition',
              id: 'nutrition-editor',
              footer_extra: render('ingredients/aisle_selector', aisles: @available_aisles) } do %>
  <textarea id="nutrition-editor-textarea" class="editor-textarea" spellcheck="false"></textarea>
<% end %>
<% end %>

<% content_for(:scripts) do %>
  <%= javascript_include_tag 'editor-utils', defer: true %>
  <%= javascript_include_tag 'editor-framework', defer: true %>
  <%= javascript_include_tag 'nutrition-editor', defer: true %>
<% end %>
```

Note: script tags move to `content_for(:scripts)` for consistency with other pages. They load outside the member check — the framework handles "no dialogs found" gracefully.

**Step 3: Rewrite nutrition-editor.js to event-listener style**

The new `nutrition-editor.js` claims lifecycle events on `#nutrition-editor` instead of reimplementing the entire dialog lifecycle:

```js
// Nutrition editor — extends editor-framework via lifecycle events.
// Handles: dynamic open triggers (per-ingredient buttons), aisle selector, reset buttons.
document.addEventListener('DOMContentLoaded', function() {
  var dialog = document.getElementById('nutrition-editor');
  if (!dialog) return;

  var textarea = document.getElementById('nutrition-editor-textarea');
  var titleEl = dialog.querySelector('.editor-header h2');
  var errorsDiv = dialog.querySelector('.editor-errors');
  var aisleSelect = document.getElementById('nutrition-editor-aisle');
  var aisleInput = document.getElementById('nutrition-editor-aisle-input');

  var currentIngredient = null;
  var originalContent = '';
  var originalAisle = '';

  function currentAisle() {
    return aisleSelect.value === '__other__' ? aisleInput.value.trim() : aisleSelect.value;
  }

  function nutritionUrl(name) {
    var slug = name.replace(/ /g, '-');
    var parts = window.location.pathname.split('/');
    var kitchensIdx = parts.indexOf('kitchens');
    var base = parts.slice(0, kitchensIdx + 2).join('/');
    return base + '/nutrition/' + encodeURIComponent(slug);
  }

  // --- Open triggers (per-ingredient edit buttons) ---

  document.querySelectorAll('.nutrition-edit-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
      currentIngredient = btn.dataset.ingredient;
      textarea.value = btn.dataset.nutritionText;
      originalContent = textarea.value;
      originalAisle = btn.dataset.aisle || '';
      aisleSelect.value = originalAisle;
      if (aisleSelect.value !== originalAisle) aisleSelect.value = '';
      aisleInput.hidden = true;
      aisleInput.value = '';
      titleEl.textContent = currentIngredient;
      EditorUtils.clearErrors(errorsDiv);
      dialog.showModal();
    });
  });

  // --- Aisle select behavior ---

  aisleSelect.addEventListener('change', function() {
    if (aisleSelect.value === '__other__') {
      aisleInput.hidden = false;
      aisleInput.value = '';
      aisleInput.focus();
    } else {
      aisleInput.hidden = true;
      aisleInput.value = '';
    }
  });

  aisleInput.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      aisleInput.hidden = true;
      aisleInput.value = '';
      aisleSelect.value = originalAisle || '';
    }
  });

  // --- Reset buttons (delete kitchen override) ---

  document.querySelectorAll('.nutrition-reset-btn').forEach(function(btn) {
    btn.addEventListener('click', async function() {
      var name = btn.dataset.ingredient;
      if (!confirm('Reset "' + name + '" to built-in nutrition data?')) return;

      btn.disabled = true;
      try {
        var response = await fetch(nutritionUrl(name), {
          method: 'DELETE',
          headers: { 'X-CSRF-Token': EditorUtils.getCsrfToken() }
        });

        if (response.ok) {
          window.location.reload();
        } else {
          btn.disabled = false;
          alert('Failed to reset. Please try again.');
        }
      } catch (err) {
        btn.disabled = false;
        alert('Network error. Please try again.');
      }
    });
  });

  // --- Lifecycle events (claimed by this editor) ---

  dialog.addEventListener('editor:collect', function(e) {
    e.detail.handled = true;
    var nutritionChanged = textarea.value !== originalContent;
    e.detail.data = {
      label_text: nutritionChanged ? textarea.value : '',
      aisle: currentAisle()
    };
  });

  dialog.addEventListener('editor:save', function(e) {
    e.detail.handled = true;
    e.detail.saveFn = function() {
      return EditorUtils.saveRequest(nutritionUrl(currentIngredient), 'POST', e.detail.data);
    };
  });

  dialog.addEventListener('editor:modified', function(e) {
    e.detail.handled = true;
    e.detail.modified = textarea.value !== originalContent || currentAisle() !== originalAisle;
  });

  dialog.addEventListener('editor:reset', function(e) {
    e.detail.handled = true;
    textarea.value = originalContent;
    aisleSelect.value = originalAisle || '';
    aisleInput.hidden = true;
    aisleInput.value = '';
  });
});
```

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: all pass. Key assertion: `assert_select '.editor-dialog', count: 0` for non-members (line 251) — still works because dialog is inside member check.

Also verify the nutrition editor's `onSuccess` behavior: the framework defaults to `'redirect'` when `data-editor-on-success` is absent, but the nutrition editor claims `editor:save` and the framework's `handleSave` callback calls `window.location.reload()` only when `onSuccess === 'reload'`. Wait — we need to handle this.

The nutrition editor currently calls `window.location.reload()` on success. But with the framework, the success callback checks `onSuccess` which defaults to `'redirect'`. The nutrition editor dialog has no `data-editor-on-success` attribute.

**Fix:** The nutrition editor needs to handle success itself. The simplest fix: add `data-editor-on-success="reload"` to the dialog. In the partial call, add it to `dialog_data`:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Nutrition',
              id: 'nutrition-editor',
              dialog_data: { editor_on_success: 'reload' },
              footer_extra: render('ingredients/aisle_selector', aisles: @available_aisles) } do %>
```

This way the framework's default success handler does `window.location.reload()`.

Run: `rake test`
Expected: full suite passes.

**Step 5: Commit**

```bash
git add app/views/ingredients/_aisle_selector.html.erb app/views/ingredients/index.html.erb app/assets/javascripts/nutrition-editor.js
git commit -m "refactor: migrate nutrition editor to editor framework (issue #95)"
```

---

### Task 6: Cleanup and final verification

**Files:**
- Delete: `app/assets/javascripts/recipe-editor.js`
- Modify: `CLAUDE.md` (update architecture section references if needed)

**Step 1: Delete old recipe-editor.js**

Verify no views still reference it:

Run: `grep -r 'recipe-editor' app/views/`
Expected: no matches (all views switched to `editor-framework` in prior tasks)

Delete `app/assets/javascripts/recipe-editor.js`.

**Step 2: Run full test suite and linter**

Run: `rake`
Expected: all tests pass, no lint violations.

**Step 3: Smoke test in browser**

Start dev server: `bin/dev`

Verify each editor dialog:
1. **Homepage** → click "+ New" → dialog opens, cancel works, save creates recipe
2. **Recipe page** → click "Edit" → dialog opens, edit + save works, delete works
3. **Groceries** → click "Edit Quick Bites" → dialog opens, edit + save reloads
4. **Groceries** → click "Edit Aisle Order" → dialog opens, lazy-loads content, save reloads
5. **Ingredients** → click "Edit"/"+ Add nutrition" → dialog opens with ingredient name as title, aisle selector works, save reloads
6. **Ingredients** → click "Reset" on a custom entry → confirms and reloads

**Step 4: Commit and close issue**

```bash
git rm app/assets/javascripts/recipe-editor.js
git add -A
git commit -m "refactor: remove old recipe-editor.js, complete editor framework migration

Closes #95"
```

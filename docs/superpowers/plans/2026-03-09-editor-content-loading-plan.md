# Editor Content Loading Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate baked-in editor content by converting the recipe editor to the `loadUrl` pattern, and add defensive Turbo lifecycle handlers to protect all editors from stale state.

**Architecture:** Add a JSON content endpoint to `RecipesController`, wire the recipe edit dialog to fetch content on open (matching Quick Bites), and add two global Turbo event listeners — `turbo:before-cache` to close dialogs before page snapshots, and `turbo:before-visit` in each editor controller to guard unsaved changes during navigation.

**Tech Stack:** Rails 8, Stimulus, Turbo Drive 8, Minitest

---

### Task 1: Add recipe content JSON endpoint

**Files:**
- Modify: `app/controllers/recipes_controller.rb:10` (add to `before_action`)
- Modify: `app/controllers/recipes_controller.rb:17` (add action after `show`)
- Modify: `config/routes.rb:24` (add route before `resources :recipes`)
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'content returns markdown source as JSON for members' do
  log_in
  get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :success
  body = response.parsed_body

  assert_equal @kitchen.recipes.find_by!(slug: 'focaccia').markdown_source, body['markdown_source']
end

test 'content returns 403 for non-members' do
  get recipe_content_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :forbidden
end

test 'content returns 404 for unknown recipe' do
  log_in
  get recipe_content_path('nonexistent', kitchen_slug: kitchen_slug)

  assert_response :not_found
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /content/`
Expected: Error — `recipe_content_path` is undefined.

**Step 3: Add the route**

In `config/routes.rb`, add inside the `scope` block, before the `resources :recipes` line:

```ruby
get 'recipes/:slug/content', to: 'recipes#content', as: :recipe_content
```

**Step 4: Add the controller action**

In `app/controllers/recipes_controller.rb`:

1. Add `:content` to the `require_membership` `before_action` (line 10):

```ruby
before_action :require_membership, only: %i[create update destroy content]
```

2. Add the action after `show` (after line 16):

```ruby
def content
  recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  render json: { markdown_source: recipe.markdown_source }
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /content/`
Expected: 3 tests, 3 assertions, 0 failures.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass, no regressions.

**Step 7: Commit**

```bash
git add app/controllers/recipes_controller.rb config/routes.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: add recipe content JSON endpoint for editor loading"
```

---

### Task 2: Convert recipe edit dialog to loadUrl

**Files:**
- Modify: `app/views/recipes/show.html.erb:40-50`
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Update the existing test**

The test `renders editor dialog with markdown source` (line 70) currently checks for the textarea with baked content. Update it to verify the `loadUrl` data attribute instead:

```ruby
test 'renders editor dialog with load URL' do
  log_in

  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_select '#recipe-editor[data-editor-load-url-value]'
  assert_select '#recipe-editor[data-editor-load-key-value="markdown_source"]'
  assert_select '.editor-textarea'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n "test_renders_editor_dialog_with_load_URL"`
Expected: FAIL — the dialog doesn't have `data-editor-load-url-value` yet.

**Step 3: Update the view**

In `app/views/recipes/show.html.erb`, change the recipe editor dialog (lines 40-50).

Add `editor_load_url` and `editor_load_key` to `dialog_data`:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'markdown_source',
                             editor_load_url: recipe_content_path(@recipe.slug),
                             editor_load_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
```

Remove the baked-in textarea value — change:

```erb
  <textarea class="editor-textarea" data-editor-target="textarea" data-recipe-editor-target="textarea" spellcheck="false"><%= @recipe.markdown_source %></textarea>
```

To:

```erb
  <textarea class="editor-textarea" data-editor-target="textarea" data-recipe-editor-target="textarea" spellcheck="false" placeholder="Loading..."></textarea>
```

This matches the Quick Bites editor pattern exactly.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n "test_renders_editor_dialog_with_load_URL"`
Expected: PASS.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass. The `full edit round-trip` test still works because it tests the PATCH endpoint, not the dialog content.

**Step 6: Commit**

```bash
git add app/views/recipes/show.html.erb test/controllers/recipes_controller_test.rb
git commit -m "refactor: recipe editor fetches content on open via loadUrl"
```

---

### Task 3: Add turbo:before-cache handler

**Files:**
- Modify: `app/javascript/application.js:19` (add after morph listener)

**Step 1: Add the handler**

In `app/javascript/application.js`, add after the `turbo:before-morph-element` listener (after line 19):

```javascript
// Close all open dialogs before Turbo caches the page. Prevents cached
// snapshots from restoring stale open dialogs with detached listeners.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("dialog[open]").forEach(dialog => dialog.close())
})
```

Note: This targets ALL open `<dialog>` elements (not just `.editor-dialog`), which also covers the ordered-list editors. Using `dialog.close()` is safe — it fires the `close` event, letting controllers clean up.

**Step 2: Verify manually**

This is a Turbo lifecycle handler that can't be meaningfully unit-tested in Minitest. Verification:

1. Start `bin/dev`
2. Navigate to a recipe page, open the editor
3. Click browser back — dialog should close before the page transitions
4. Click browser forward — the restored page should NOT show an open dialog

**Step 3: Run full test suite**

Run: `rake test`
Expected: All tests pass (no regressions from JS change).

**Step 4: Commit**

```bash
git add app/javascript/application.js
git commit -m "fix: close open dialogs before Turbo caches the page"
```

---

### Task 4: Add turbo:before-visit handler to editor controller

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js:31-51` (connect/disconnect)

**Step 1: Add the handler to connect()**

In `app/javascript/controllers/editor_controller.js`, add to the end of `connect()` (before the closing brace at line 45):

```javascript
this.boundBeforeVisit = this.handleBeforeVisit.bind(this)
document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
```

**Step 2: Add cleanup to disconnect()**

In `disconnect()`, add before the closing brace (line 51):

```javascript
if (this.boundBeforeVisit) document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
```

**Step 3: Add the handler method**

Add after `handleCancel` (after line 185):

```javascript
handleBeforeVisit(event) {
  if (!this.element.open) return
  if (this.isModified()) {
    event.preventDefault()
    this.close()
  } else {
    this.element.close()
  }
}
```

Logic:
- If the dialog isn't open, do nothing (let navigation proceed)
- If open with unsaved changes: cancel the navigation, show the confirmation dialog (via `this.close()` → `closeWithConfirmation`). If user confirms discard, the dialog closes and they can navigate again.
- If open without changes: just close the dialog silently and let navigation proceed

**Step 4: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/javascript/controllers/editor_controller.js
git commit -m "fix: guard unsaved editor changes on Turbo Drive navigation"
```

---

### Task 5: Add turbo:before-visit handler to ordered-list-editor controller

**Files:**
- Modify: `app/javascript/controllers/ordered_list_editor_controller.js:34-58` (connect/disconnect)

**Step 1: Add the handler to connect()**

In `ordered_list_editor_controller.js`, add to the end of `connect()` (before the closing brace at line 50):

```javascript
this.boundBeforeVisit = this.handleBeforeVisit.bind(this)
document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
```

**Step 2: Add cleanup to disconnect()**

In `disconnect()`, add before the closing brace (line 58):

```javascript
if (this.boundBeforeVisit) document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
```

**Step 3: Add the handler method**

Add after `handleCancel` (after line 124):

```javascript
handleBeforeVisit(event) {
  if (!this.element.open) return
  if (isModified(this.items, this.initialSnapshot)) {
    event.preventDefault()
    this.close()
  } else {
    this.element.close()
  }
}
```

Same logic as the editor controller, using the ordered-list `isModified()` utility.

**Step 4: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/javascript/controllers/ordered_list_editor_controller.js
git commit -m "fix: guard unsaved ordered-list editor changes on Turbo Drive navigation"
```

---

### Task 6: Update header comments and CLAUDE.md

**Files:**
- Modify: `app/javascript/application.js:1-6` (header comment)
- Modify: `app/javascript/controllers/editor_controller.js:8-16` (header comment)
- Modify: `CLAUDE.md:115` (Editor dialogs section)

**Step 1: Update application.js header comment**

Replace the existing header comment (lines 1-6) to reflect the new responsibilities:

```javascript
/**
 * JS entry point. Boots Turbo Drive + Stimulus (via controllers/index.js) and
 * registers the service worker. Also manages global Turbo lifecycle handlers:
 * morph protection for open dialogs (broadcast refresh) and pre-cache cleanup.
 * Pinned in config/importmap.rb as "application".
 */
```

**Step 2: Update editor_controller.js header comment**

Update to mention the `turbo:before-visit` guard:

```javascript
/**
 * Generic <dialog> lifecycle controller for editor modals. Handles open, save
 * (PATCH/POST via fetch), dirty-checking, close with confirmation, beforeunload
 * guards, and Turbo Drive navigation guards. Simple dialogs need zero custom
 * JS — just Stimulus data attributes on the <dialog>. Custom dialogs (nutrition
 * editor) hook in via lifecycle events: editor:collect, editor:save,
 * editor:modified, editor:reset.
 *
 * - editor_utils: CSRF tokens, error display, save requests, close-with-confirmation
 * - notify: toast notifications for save success/failure feedback
 */
```

**Step 3: Update CLAUDE.md**

Replace the Editor dialogs morph protection line (line 115) with:

```
Open `<dialog>` elements are protected from Turbo morph via a `turbo:before-morph-element` listener in `application.js`. A `turbo:before-cache` listener closes all open dialogs before page snapshots. Both editor controllers guard unsaved changes on `turbo:before-visit`. Do NOT use `data-turbo-permanent` on dialogs.
```

**Step 4: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

**Step 5: Commit**

```bash
git add app/javascript/application.js app/javascript/controllers/editor_controller.js CLAUDE.md
git commit -m "docs: update comments and CLAUDE.md for editor lifecycle handlers"
```

---

### Task 7: Manual verification

No code changes — this task verifies the complete implementation works end-to-end.

**Step 1: Start the dev server**

Run: `bin/dev`

**Step 2: Verify recipe editor loads content on open**

1. Navigate to any recipe page
2. Click "Edit" — editor should show "Loading..." briefly, then populate with markdown
3. Verify syntax highlighting appears after content loads
4. Edit content, save — recipe should update without full-page redirect
5. Open editor again — should show the saved content (fresh fetch)

**Step 3: Verify no stale content on navigation**

1. Navigate to Recipe A, open editor, note the content, close editor
2. Navigate to Recipe B, open editor — should show Recipe B's content
3. Navigate back to Recipe A, open editor — should show Recipe A's content

**Step 4: Verify turbo:before-cache cleanup**

1. Open editor on a recipe page
2. Click browser back — dialog should close, page should transition
3. Click browser forward — page should restore WITHOUT an open dialog

**Step 5: Verify turbo:before-visit unsaved changes guard**

1. Open editor, make changes
2. Click browser back — should see "unsaved changes" confirmation
3. Click Cancel — should stay on page with editor open
4. Click browser back again, confirm discard — should navigate away

**Step 6: Verify other editors still work**

1. Quick Bites editor on menu page — open, edit, save, verify
2. Nutrition editor on recipe page — click ingredient, edit, save, verify
3. Aisle order editor on groceries page — open, reorder, save, verify
4. Category order editor on homepage — open, reorder, save, verify
5. New recipe editor on homepage — open, fill template, save, verify redirect

**Step 7: Run full test suite one final time**

Run: `rake`
Expected: Lint clean, all tests pass.

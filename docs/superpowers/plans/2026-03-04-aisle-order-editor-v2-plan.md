# Aisle Order Editor v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the textarea-based Aisle Order editor with a rich list UI supporting reorder, inline rename, add, and delete — with staged-changeset visual states and server-side cascading of renames/deletes to IngredientCatalog entries.

**Architecture:** New `aisle-order-editor` Stimulus controller replaces the generic `editor` controller for the aisle order dialog. The shared `editor_dialog` layout is bypassed — the dialog HTML is rendered directly in the view since this editor doesn't use a textarea. The controller manages an internal state array of `{ originalName, currentName, deleted }` objects, renders the list UI via safe DOM methods, and serializes a `{ aisle_order, renames, deletes }` payload on save. Server-side, `GroceriesController#update_aisle_order` is extended to cascade renames/deletes to `IngredientCatalog`.

**Tech Stack:** Rails 8, Stimulus, importmap-rails, Minitest

**Design doc:** `docs/plans/2026-03-04-aisle-order-editor-v2-design.md`

---

### Task 0: Server-side — rename and delete cascading

The server endpoint is extended first so the new UI has something to talk to. The existing textarea UI continues to work (it sends no `renames`/`deletes` params).

**Files:**
- Modify: `app/controllers/groceries_controller.rb` (lines 40–50, `update_aisle_order` and `validate_aisle_order`)
- Test: `test/controllers/groceries_controller_test.rb`

**Step 1: Write failing tests for rename cascading**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
test 'update_aisle_order cascades renames to catalog entries' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bananas', aisle: 'Produce')
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: "Fruits & Vegetables\nDairy",
                  renames: { 'Produce' => 'Fruits & Vegetables' } },
        as: :json

  assert_response :success
  assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bananas').aisle
  assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
end
```

**Step 2: Write failing tests for delete cascading**

```ruby
test 'update_aisle_order clears aisle from catalog entries on delete' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: 'Dairy',
                  deletes: ['Produce'] },
        as: :json

  assert_response :success
  assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
end
```

**Step 3: Write failing test for combined rename + delete**

```ruby
test 'update_aisle_order handles renames and deletes together' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bread', aisle: 'Bakery')

  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: 'Fruits & Vegetables',
                  renames: { 'Produce' => 'Fruits & Vegetables' },
                  deletes: ['Bakery'] },
        as: :json

  assert_response :success
  assert_equal 'Fruits & Vegetables', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bread').aisle
end
```

**Step 4: Write failing test — renames don't touch other kitchens**

```ruby
test 'update_aisle_order rename does not affect other kitchens' do
  other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
  IngredientCatalog.create!(kitchen: other_kitchen, ingredient_name: 'Apples', aisle: 'Produce')

  log_in
  patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
        params: { aisle_order: 'Fruits',
                  renames: { 'Produce' => 'Fruits' } },
        as: :json

  assert_response :success
  assert_equal 'Produce', IngredientCatalog.find_by(kitchen: other_kitchen, ingredient_name: 'Apples').aisle
end
```

**Step 5: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n '/cascade|rename|delete.*catalog/'`
Expected: FAIL — renames/deletes not implemented yet

**Step 6: Implement cascading in the controller**

In `app/controllers/groceries_controller.rb`, replace `update_aisle_order`:

```ruby
def update_aisle_order
  current_kitchen.aisle_order = params[:aisle_order].to_s
  current_kitchen.normalize_aisle_order!

  errors = validate_aisle_order
  return render json: { errors: }, status: :unprocessable_content if errors.any?

  ActiveRecord::Base.transaction do
    cascade_aisle_renames
    cascade_aisle_deletes
    current_kitchen.save!
  end

  broadcast_meal_plan_refresh
  render json: { status: 'ok' }
end
```

Add private methods:

```ruby
def cascade_aisle_renames
  renames = params[:renames]
  return unless renames.is_a?(ActionController::Parameters)

  renames.each_pair do |old_name, new_name|
    current_kitchen.ingredient_catalogs.where(aisle: old_name).update_all(aisle: new_name)
  end
end

def cascade_aisle_deletes
  deletes = params[:deletes]
  return unless deletes.is_a?(Array)

  current_kitchen.ingredient_catalogs.where(aisle: deletes).update_all(aisle: nil)
end
```

Note: `current_kitchen.ingredient_catalogs` uses the `has_many` association which is already kitchen-scoped via `acts_as_tenant`. If the association doesn't exist, use `IngredientCatalog.where(kitchen: current_kitchen)` instead — check the Kitchen model first.

**Step 7: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: all pass

**Step 8: Verify existing tests still pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: all pass (the existing tests send no `renames`/`deletes`, so the new code is a no-op for them)

**Step 9: Commit**

```bash
git add app/controllers/groceries_controller.rb test/controllers/groceries_controller_test.rb
git commit -m "feat: cascade aisle renames and deletes to catalog entries"
```

---

### Task 1: Aisle Order Editor Stimulus controller

The core JavaScript: manages the state array, renders the list UI via safe DOM APIs (never innerHTML), handles user interactions, serializes the save payload. This replaces the textarea in the dialog.

**Files:**
- Create: `app/javascript/controllers/aisle_order_editor_controller.js`
- Modify: `config/importmap.rb` (only if `pin_all_from` doesn't auto-register — it should for `controllers/`)

**Step 1: Create the controller**

Create `app/javascript/controllers/aisle_order_editor_controller.js`. Key design notes:
- Uses `textContent` and `document.createElement` exclusively — never `innerHTML`
- Imports from `editor_utils`: `getCsrfToken`, `showErrors`, `clearErrors`, `closeWithConfirmation`, `saveRequest`, `guardBeforeUnload`, `handleSave`
- Targets: `list` (the aisle row container), `saveButton`, `errors`, `newAisleName`
- Values: `loadUrl` (GET endpoint), `saveUrl` (PATCH endpoint)
- State: `this.aisles` array of `{ originalName, currentName, deleted }` objects
- `this.initialSnapshot` — JSON string of initial state for dirty checking
- `render()` rebuilds the DOM from state on every change using `replaceChildren()`
- Row actions (`moveUp`, `moveDown`, `deleteAisle`, `undoDelete`, `startRename`) read the `data-aisle-index` from the event target
- `buildPayload()` computes `{ aisle_order, renames, deletes }` from the diff between original and current state
- Open button binding: hardcoded `#edit-aisle-order-button` selector in `connect()`

Full implementation is in the design doc and is ~280 lines. Core methods:

- `open()` → clear list via `replaceChildren()`, show modal, `loadAisles()`
- `close()` → `closeWithConfirmation()` from editor_utils
- `save()` → `handleSave()` from editor_utils with `buildPayload()`
- `loadAisles()` → fetch from `loadUrlValue`, parse newline-separated names into state array
- `render()` → build DOM nodes for each aisle, `listTarget.replaceChildren(fragment)`
- `buildRow()` → creates row div with name area + controls, applies state classes
- `startRename()` → replaces name element with input, blur/Enter finishes
- `buildPayload()` → diffs state to produce `{ aisle_order, renames, deletes }`

**Step 2: Verify controller auto-registers**

Check `config/importmap.rb` for `pin_all_from "app/javascript/controllers"`. If present, the controller auto-registers. No additional pinning needed.

**Step 3: Commit**

```bash
git add app/javascript/controllers/aisle_order_editor_controller.js
git commit -m "feat: add aisle-order-editor Stimulus controller"
```

---

### Task 2: Update the grocery page view

Replace the textarea-based editor dialog with the new list-based UI. Render the dialog directly (bypassing `shared/editor_dialog`) since this editor doesn't use the `editor` controller or a textarea.

**Files:**
- Modify: `app/views/groceries/show.html.erb` (lines 37–49, the editor dialog block)
- Test: `test/controllers/groceries_controller_test.rb` (line 164–171, dialog assertion)

**Step 1: Replace the editor dialog block**

Replace lines 37–49 in `app/views/groceries/show.html.erb` with:

```erb
<% if current_member? %>
<dialog class="editor-dialog"
        data-controller="aisle-order-editor"
        data-aisle-order-editor-load-url-value="<%= groceries_aisle_order_content_path %>"
        data-aisle-order-editor-save-url-value="<%= groceries_aisle_order_path %>">
  <div class="editor-header">
    <h2>Aisle Order</h2>
    <button type="button" class="btn editor-close" data-action="click->aisle-order-editor#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-aisle-order-editor-target="errors" hidden></div>
  <div class="aisle-order-body">
    <div class="aisle-list" data-aisle-order-editor-target="list"></div>
    <div class="aisle-add-row">
      <label for="new-aisle-input" class="sr-only">New aisle name</label>
      <input type="text" id="new-aisle-input" class="aisle-add-input" placeholder="Add an aisle..."
             data-aisle-order-editor-target="newAisleName"
             data-action="keydown->aisle-order-editor#addAisleOnEnter"
             maxlength="50">
      <button type="button" class="aisle-btn aisle-btn--add" aria-label="Add aisle"
              data-action="click->aisle-order-editor#addAisle">
        <svg viewBox="0 0 24 24" width="18" height="18">
          <line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          <line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
    </div>
  </div>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel" data-action="click->aisle-order-editor#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save" data-aisle-order-editor-target="saveButton" data-action="click->aisle-order-editor#save">Save</button>
  </div>
</dialog>
<% end %>
```

**Step 2: Update the existing controller test**

In `test/controllers/groceries_controller_test.rb`, update the dialog assertion:

```ruby
test 'renders aisle order editor dialog for members' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '#edit-aisle-order-button', 'Edit Aisle Order'
  assert_select 'dialog[data-controller="aisle-order-editor"]'
end
```

**Step 3: Run tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: all pass

**Step 4: Commit**

```bash
git add app/views/groceries/show.html.erb test/controllers/groceries_controller_test.rb
git commit -m "feat: replace textarea aisle order editor with list-based dialog"
```

---

### Task 3: CSS for the aisle order editor

Style the aisle rows, controls, and state indicators (renamed, deleted, new).

**Files:**
- Modify: `app/assets/stylesheets/style.css` (after the existing `.editor-footer-spacer` block, around line 851)

**Step 1: Add aisle order editor styles**

Add after the `.editor-footer-spacer` rule in `style.css`:

```css
/* Aisle Order Editor */
.aisle-order-body {
  flex: 1;
  overflow-y: auto;
  padding: 0.75rem 1.5rem;
}

.aisle-list {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.aisle-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem;
  background: var(--surface-alt);
  border: 1px solid #e0e0e0;
  border-radius: 6px;
}

.aisle-row--renamed {
  background: #fff8e1;
  border-color: #ffe082;
}

.aisle-row--deleted {
  opacity: 0.4;
  background: var(--surface-alt);
}

.aisle-row--deleted .aisle-name {
  text-decoration: line-through;
}

.aisle-row--new {
  background: #e8f5e9;
  border-color: #a5d6a7;
}

.aisle-name-area {
  flex: 1;
  min-width: 0;
}

.aisle-name {
  display: block;
  font-family: "Futura", sans-serif;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  text-align: left;
  color: var(--text-color);
  width: 100%;
}

.aisle-row--deleted .aisle-name {
  cursor: default;
}

button.aisle-name:hover {
  color: var(--accent-color);
}

.aisle-was {
  display: block;
  font-size: 0.7rem;
  color: var(--muted-text);
  font-style: italic;
  margin-top: 0.15rem;
}

.aisle-rename-input {
  font-family: "Futura", sans-serif;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  border: none;
  border-bottom: 2px solid var(--accent-color);
  background: transparent;
  padding: 0;
  outline: none;
  width: 100%;
  color: var(--text-color);
}

.aisle-controls {
  display: flex;
  gap: 0.35rem;
  flex-shrink: 0;
}

.aisle-btn {
  appearance: none;
  -webkit-appearance: none;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  padding: 0;
  background: none;
  color: var(--border-muted);
  border: 1px solid var(--border-light);
  border-radius: 50%;
  cursor: pointer;
  font-size: 1rem;
  line-height: 1;
}

.aisle-btn:hover:not(:disabled) {
  color: var(--muted-text);
  border-color: var(--border-muted);
}

.aisle-btn:disabled {
  opacity: 0.3;
  cursor: default;
}

.aisle-btn--delete:hover:not(:disabled) {
  color: var(--danger-color);
  border-color: var(--danger-color);
}

.aisle-btn--undo {
  font-size: 0.85rem;
}

.aisle-btn--add {
  appearance: none;
  -webkit-appearance: none;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  padding: 0;
  background: none;
  color: var(--border-muted);
  border: 1px solid var(--border-light);
  border-radius: 50%;
  cursor: pointer;
  flex-shrink: 0;
}

.aisle-btn--add:hover {
  color: var(--muted-text);
  border-color: var(--border-muted);
}

.aisle-add-row {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.75rem;
}

.aisle-add-input {
  flex: 1;
  padding: 0.5rem 0.75rem;
  font-family: inherit;
  font-size: 16px;
  border: 1px solid var(--border-light);
  border-radius: 4px;
}

.aisle-add-input:focus {
  outline: none;
  border-color: var(--border-muted);
}
```

**Step 2: Verify visually**

Run: `bin/dev` and open the grocery page. Click "Edit Aisle Order". Verify:
- Aisle rows load with grocery-page styling (uppercase Futura)
- Chevron buttons appear and work
- Renamed rows show amber tint with "was" annotation
- Deleted rows show strikethrough + fade + undo button
- Add new aisle works at the bottom
- Save closes the dialog

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add CSS for aisle order editor list UI"
```

---

### Task 4: Lint, allowlist, and full test suite

**Files:**
- Possibly modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

**Step 1: Run the html_safe audit**

Run: `bundle exec rake lint:html_safe`

**Step 2: If failures, update the allowlist**

Update `config/html_safe_allowlist.yml` with the new line numbers for any shifted entries.

**Step 3: Run full lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 4: Run all tests**

Run: `rake test`
Expected: all pass

**Step 5: Commit (if changes)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for aisle order editor view changes"
```

---

### Task 5: Manual smoke test

No code changes — verification only.

**Step 1: Start the server**

Run: `bin/dev`

**Step 2: Test these scenarios on the grocery page**

1. Open the Aisle Order editor — aisles load as styled rows
2. Click an aisle name — inline rename input appears
3. Rename an aisle — amber tint appears, "was" annotation shows
4. Rename back to original — amber tint clears
5. Click up/down chevrons — rows reorder, button focus follows
6. Click × on a row — row shows strikethrough + fade, undo button appears
7. Click ↩ on a deleted row — row restores
8. Type a new aisle name + click + — new row appears at bottom with green tint
9. Save — dialog closes, grocery page updates
10. Verify a renamed aisle cascaded: open Nutrition editor, check that affected ingredients now show the new aisle name
11. Close without saving (after making changes) — confirmation dialog appears
12. Press Escape with unsaved changes — confirmation dialog appears

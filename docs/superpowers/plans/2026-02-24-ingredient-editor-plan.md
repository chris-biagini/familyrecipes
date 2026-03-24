# Unified Ingredient Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Unify the nutrition and aisle editing experience into a single ingredient editor dialog with a shared JS utility module.

**Architecture:** Extract common editor JS into `editor-utils.js` (window global, no bundler). Add `Kitchen#all_aisles` as the canonical merged aisle source. Extend the nutrition editor dialog with an aisle dropdown. Extend `NutritionEntriesController#upsert` to accept aisle-only edits.

**Tech Stack:** Rails 8, vanilla JS, Propshaft, SQLite, ActionCable

**Design doc:** `docs/plans/2026-02-24-ingredient-editor-design.md`

---

### Task 1: Kitchen#all_aisles

Add the canonical merged aisle list method to Kitchen.

**Files:**
- Modify: `app/models/kitchen.rb:21-30`
- Test: `test/models/kitchen_test.rb`

**Step 1: Write the failing tests**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'all_aisles returns empty array when no aisles exist' do
  kitchen = Kitchen.create!(name: 'Empty', slug: 'empty')
  assert_equal [], kitchen.all_aisles
end

test 'all_aisles returns aisle_order entries' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-aisles', aisle_order: "Produce\nBaking")
  assert_equal %w[Produce Baking], kitchen.all_aisles
end

test 'all_aisles merges catalog aisles not in order' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-merge', aisle_order: "Produce")
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Salt', aisle: 'Spices', basis_grams: 6)

  aisles = kitchen.all_aisles

  assert_equal 'Produce', aisles.first
  assert_includes aisles, 'Baking'
  assert_includes aisles, 'Spices'
end

test 'all_aisles excludes omit sentinel' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-omit')
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Bay leaves', aisle: 'omit', basis_grams: 1)

  refute_includes kitchen.all_aisles, 'omit'
end

test 'all_aisles deduplicates across sources' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-dedup', aisle_order: "Baking")
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)

  assert_equal ['Baking'], kitchen.all_aisles
end

test 'all_aisles prefers kitchen catalog entries over global' do
  kitchen = Kitchen.create!(name: 'Test', slug: 'test-overlay')
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
  IngredientCatalog.create!(kitchen: kitchen, ingredient_name: 'Flour', aisle: 'Pantry', basis_grams: 30)

  assert_includes kitchen.all_aisles, 'Pantry'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/kitchen_test.rb -n /all_aisles/`
Expected: FAIL — `undefined method 'all_aisles'`

**Step 3: Implement Kitchen#all_aisles**

Add to `app/models/kitchen.rb` after `normalize_aisle_order!`:

```ruby
def all_aisles
  saved = parsed_aisle_order
  catalog_aisles = IngredientCatalog.lookup_for(self)
                                    .values
                                    .filter_map(&:aisle)
                                    .uniq
                                    .reject { |a| a == 'omit' }
                                    .sort

  saved + (catalog_aisles - saved)
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/kitchen_test.rb -n /all_aisles/`
Expected: All PASS

**Step 5: Commit**

```bash
git add app/models/kitchen.rb test/models/kitchen_test.rb
git commit -m "feat: add Kitchen#all_aisles for canonical aisle list"
```

---

### Task 2: Refactor GroceriesController to use Kitchen#all_aisles

Replace the inline aisle merge logic in `GroceriesController#build_aisle_order_text` with `Kitchen#all_aisles`.

**Files:**
- Modify: `app/controllers/groceries_controller.rb:83-94`
- Test: `test/controllers/groceries_controller_test.rb` (existing tests should still pass)

**Step 1: Run existing aisle order tests as baseline**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /aisle_order/`
Expected: All PASS

**Step 2: Refactor build_aisle_order_text**

Replace `GroceriesController#build_aisle_order_text` (lines 83–94) with:

```ruby
def build_aisle_order_text
  current_kitchen.all_aisles.join("\n")
end
```

**Step 3: Run existing tests to verify no regressions**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /aisle_order/`
Expected: All PASS (same behavior, less code)

**Step 4: Commit**

```bash
git add app/controllers/groceries_controller.rb
git commit -m "refactor: use Kitchen#all_aisles in groceries controller"
```

---

### Task 3: Shared JS editor utilities

Extract common behaviors from `nutrition-editor.js` and `recipe-editor.js` into `editor-utils.js`.

**Files:**
- Create: `app/assets/javascripts/editor-utils.js`
- Modify: `app/assets/javascripts/recipe-editor.js`
- Modify: `app/assets/javascripts/nutrition-editor.js`
- Modify: `app/views/ingredients/index.html.erb:69` (add script tag)
- Modify: `app/views/groceries/show.html.erb:12` (add script tag)
- Modify: `app/views/recipes/show.html.erb` (add script tag, if recipe-editor is loaded there)

**Step 1: Create editor-utils.js**

Create `app/assets/javascripts/editor-utils.js`:

```javascript
// Shared editor dialog utilities.
// Both recipe-editor.js and nutrition-editor.js depend on this file.
window.EditorUtils = (() => {
  function getCsrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content;
  }

  function showErrors(container, errors) {
    const list = document.createElement('ul');
    errors.forEach(msg => {
      const li = document.createElement('li');
      li.textContent = msg;
      list.appendChild(li);
    });
    container.replaceChildren(list);
    container.hidden = false;
  }

  function clearErrors(container) {
    container.replaceChildren();
    container.hidden = true;
  }

  // Attempt to close the dialog; prompts if content is modified.
  // resetFn is called to restore original state before closing.
  function closeWithConfirmation(dialog, isModified, resetFn) {
    if (isModified() && !confirm('You have unsaved changes. Discard them?')) return;
    resetFn();
    dialog.close();
  }

  // POST/PATCH/DELETE with JSON body. Returns the fetch Response.
  async function saveRequest(url, method, body) {
    return fetch(url, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': getCsrfToken()
      },
      body: JSON.stringify(body)
    });
  }

  // Sets up beforeunload guard. Returns a cleanup function.
  function guardBeforeUnload(dialog, isModified) {
    let saving = false;

    function handler(event) {
      if (!saving && dialog.open && isModified()) {
        event.preventDefault();
      }
    }

    window.addEventListener('beforeunload', handler);

    return {
      markSaving() { saving = true; },
      remove() { window.removeEventListener('beforeunload', handler); }
    };
  }

  // Standard save button flow: disable, show "Saving…", call saveFn,
  // handle success/422/error. Returns nothing — side-effects only.
  async function handleSave(saveBtn, errorsDiv, saveFn, onSuccess) {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors(errorsDiv);

    try {
      const response = await saveFn();

      if (response.ok) {
        onSuccess(await response.json());
      } else if (response.status === 422) {
        const data = await response.json();
        showErrors(errorsDiv, data.errors);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      } else {
        showErrors(errorsDiv, [`Server error (${response.status}). Please try again.`]);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      }
    } catch {
      showErrors(errorsDiv, ['Network error. Please check your connection and try again.']);
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  }

  return { getCsrfToken, showErrors, clearErrors, closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave };
})();
```

**Step 2: Refactor recipe-editor.js to use EditorUtils**

Replace the duplicated functions in `recipe-editor.js`. The `initEditor` function should use `EditorUtils.showErrors`, `EditorUtils.clearErrors`, `EditorUtils.closeWithConfirmation`, `EditorUtils.saveRequest`, `EditorUtils.handleSave`, and `EditorUtils.guardBeforeUnload` instead of its own inline versions.

Key changes:
- Remove local `showErrors`, `clearErrors`, `isModified`, `closeDialog` functions
- Remove local `csrfToken` lookup
- Remove local `beforeunload` handler
- Use `EditorUtils.handleSave` for save button click
- Use `EditorUtils.closeWithConfirmation` for close/cancel
- Keep: open logic (load URL, data attributes), delete button logic (recipe-specific)

See existing `recipe-editor.js` for the full refactored version. The delete button logic stays local since it's recipe-specific.

**Step 3: Refactor nutrition-editor.js to use EditorUtils**

Same pattern — replace duplicated functions with EditorUtils calls. Keep: open-button wiring (`data-ingredient`, `data-nutrition-text`), reset-button logic, `nutritionUrl` helper.

**Step 4: Add editor-utils.js script tags**

In every view that loads an editor JS file, add `editor-utils.js` **before** it:

- `app/views/ingredients/index.html.erb` — add before `nutrition-editor` tag
- `app/views/groceries/show.html.erb` — add before `recipe-editor` tag
- Any view loading `recipe-editor.js` for recipe editing (check `recipes/show.html.erb`)

**Step 5: Manual test**

Start `bin/dev`. Test that:
- Recipe editor (create/edit/delete) still works
- Nutrition editor (add/edit/reset) still works
- Aisle order editor and Quick Bites editor still work
- Unsaved changes warnings fire correctly

**Step 6: Run full test suite**

Run: `rake test`
Expected: All PASS

**Step 7: Commit**

```bash
git add app/assets/javascripts/editor-utils.js app/assets/javascripts/recipe-editor.js app/assets/javascripts/nutrition-editor.js app/views/ingredients/index.html.erb app/views/groceries/show.html.erb
git commit -m "refactor: extract shared editor utilities into editor-utils.js"
```

---

### Task 4: Aisle dropdown in ingredient editor dialog

Add the `<select>` to the nutrition editor dialog and wire up the JS to set/read its value.

**Files:**
- Modify: `app/controllers/ingredients_controller.rb:6` (add `@available_aisles`)
- Modify: `app/views/ingredients/index.html.erb` (add `data-aisle` to buttons, add `<select>` to dialog footer)
- Modify: `app/assets/javascripts/nutrition-editor.js` (wire dropdown open/read/save)
- Modify: `app/assets/stylesheets/style.css` (footer layout with dropdown)
- Test: `test/controllers/ingredients_controller_test.rb` (or add to existing)

**Step 1: Write failing test for @available_aisles in view**

Add to controller test (create file if needed):

```ruby
test 'index includes available aisles in the editor dialog' do
  IngredientCatalog.create!(kitchen: nil, ingredient_name: 'Flour', aisle: 'Baking', basis_grams: 30)
  create_recipe_with_ingredient('Flour')

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_select '#nutrition-editor select.aisle-select option[value="Baking"]'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n /available_aisles/`
Expected: FAIL

**Step 3: Add @available_aisles to controller**

In `app/controllers/ingredients_controller.rb`, inside `index`:

```ruby
def index
  @ingredients_with_recipes = build_ingredient_index
  @nutrition_lookup = IngredientCatalog.lookup_for(current_kitchen)
  @missing_ingredients = find_missing_ingredients
  @available_aisles = current_kitchen.all_aisles
end
```

**Step 4: Add data-aisle to edit/add buttons**

In `app/views/ingredients/index.html.erb`, add `data-aisle` to each edit button. For the "Add nutrition" button (line 29–30), add `data-aisle=""`. For the edit buttons (lines 33–35 and 39–41), add `data-aisle="<%= entry&.aisle %>"`.

**Step 5: Add aisle select to dialog footer**

Replace the dialog footer in `app/views/ingredients/index.html.erb` (around line 63–66):

```erb
<div class="editor-footer">
  <select id="nutrition-editor-aisle" class="aisle-select" aria-label="Grocery aisle">
    <option value="">(none)</option>
    <%- @available_aisles.each do |aisle| -%>
    <option value="<%= aisle %>"><%= aisle %></option>
    <%- end -%>
    <option value="omit">omit</option>
    <option disabled>───</option>
    <option value="__other__">Other…</option>
  </select>
  <input type="text" id="nutrition-editor-aisle-input" class="aisle-input" placeholder="New aisle name" hidden>
  <span class="editor-footer-spacer"></span>
  <button type="button" class="btn editor-cancel">Cancel</button>
  <button type="button" class="btn btn-primary editor-save">Save</button>
</div>
```

**Step 6: Add CSS for footer with dropdown**

Add to `app/assets/stylesheets/style.css` after `.editor-footer-spacer`:

```css
.aisle-select,
.aisle-input {
  font-size: 0.85rem;
  padding: 0.25rem 0.5rem;
  border: 1px solid var(--border-color);
  border-radius: 0.25rem;
  background: var(--content-background-color);
  color: var(--text-color);
  max-width: 12rem;
}
```

**Step 7: Wire aisle dropdown in nutrition-editor.js**

Add to `nutrition-editor.js`:
- On open: read `data-aisle` from button, set `aisleSelect.value`. If value not in options, it's a new one — select `(none)`.
- "Other..." handling: when select changes to `__other__`, hide select, show text input, focus it. On input Escape or blur-when-empty, swap back.
- Track original aisle value for `isModified` check.
- Include aisle in save payload.

**Step 8: Run test to verify it passes**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n /available_aisles/`
Expected: PASS

**Step 9: Manual test**

Start `bin/dev`. On the ingredients page:
- Open an ingredient with an existing aisle — dropdown should show it selected
- Open an ingredient without an aisle — dropdown should show "(none)"
- Select "Other...", type a name, verify it swaps to text input
- Cancel and reopen — verify original state restored

**Step 10: Commit**

```bash
git add app/controllers/ingredients_controller.rb app/views/ingredients/index.html.erb app/assets/javascripts/nutrition-editor.js app/assets/stylesheets/style.css
git commit -m "feat: add aisle dropdown to ingredient editor dialog"
```

---

### Task 5: Controller support for aisle saves

Extend `NutritionEntriesController#upsert` to handle the `aisle` parameter, including aisle-only edits.

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Test: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Write failing tests**

Add to `test/controllers/nutrition_entries_controller_test.rb`:

```ruby
test 'upsert saves aisle alongside nutrition data' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: VALID_LABEL, aisle: 'Baking' },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

  assert_equal 'Baking', entry.aisle
  assert_in_delta 110.0, entry.calories
end

test 'upsert saves aisle-only when label is blank skeleton' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: NutritionLabelParser.blank_skeleton, aisle: 'Baking' },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

  assert_equal 'Baking', entry.aisle
  assert_nil entry.basis_grams
end

test 'upsert saves aisle-only when label is empty' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: '', aisle: 'Produce' },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')

  assert_equal 'Produce', entry.aisle
end

test 'upsert appends new aisle to kitchen aisle_order' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: '', aisle: 'Deli' },
       as: :json

  assert_response :success
  assert_includes @kitchen.reload.parsed_aisle_order, 'Deli'
end

test 'upsert does not duplicate existing aisle in aisle_order' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: '', aisle: 'Baking' },
       as: :json

  assert_response :success
  assert_equal "Produce\nBaking", @kitchen.reload.aisle_order
end

test 'upsert broadcasts content_changed when aisle changes' do
  assert_broadcasts('grocery_list:test-kitchen', 1) do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { label_text: '', aisle: 'Produce' },
         as: :json
  end
end

test 'upsert returns error when both label invalid and no aisle' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { label_text: 'garbage', aisle: '' },
       as: :json

  assert_response :unprocessable_entity
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n /aisle/`
Expected: FAIL

**Step 3: Implement aisle support in upsert**

Rewrite `NutritionEntriesController#upsert`:

```ruby
def upsert
  aisle = params[:aisle].presence
  label_text = params[:label_text].to_s

  if blank_nutrition?(label_text)
    return render json: { errors: ['Nothing to save'] }, status: :unprocessable_entity unless aisle

    save_aisle_only(aisle)
  else
    result = NutritionLabelParser.parse(label_text)
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.success?

    save_full_entry(result, aisle)
  end
end
```

Add private helpers:

```ruby
def blank_nutrition?(text)
  stripped = text.lines.map(&:strip).reject(&:empty?).join("\n")
  skeleton = NutritionLabelParser.blank_skeleton.lines.map(&:strip).reject(&:empty?).join("\n")
  stripped.empty? || stripped == skeleton
end

def save_aisle_only(aisle)
  entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
  entry.aisle = aisle

  if entry.save
    sync_aisle_to_kitchen(aisle)
    broadcast_aisle_change
    render json: { status: 'ok' }
  else
    render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
  end
end

def save_full_entry(result, aisle)
  entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
  assign_parsed_attributes(entry, result)
  entry.aisle = aisle if aisle

  if entry.save
    sync_aisle_to_kitchen(aisle) if aisle
    broadcast_aisle_change if aisle
    recalculate_affected_recipes
    render json: { status: 'ok' }
  else
    render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
  end
end

def sync_aisle_to_kitchen(aisle)
  return if aisle == 'omit'
  return if current_kitchen.parsed_aisle_order.include?(aisle)

  existing = current_kitchen.aisle_order.to_s
  current_kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
end

def broadcast_aisle_change
  GroceryListChannel.broadcast_content_changed(current_kitchen)
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: All PASS (new and existing)

**Step 5: Run full test suite**

Run: `rake test`
Expected: All PASS

**Step 6: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: support aisle saves in nutrition entries controller

Closes #82"
```

---

### Task 6: End-to-end manual testing and polish

Verify the full flow works in the browser.

**Files:**
- Potentially touch: CSS, JS, or view files based on findings

**Step 1: Start dev server**

Run: `bin/dev`

**Step 2: Test aisle-only workflow**

1. Open ingredients page
2. Click "Add nutrition" on an ingredient with no data
3. Leave the textarea as the blank skeleton
4. Select an aisle from the dropdown (e.g., "Produce")
5. Click Save — should succeed and reload
6. Verify the ingredient now shows the aisle (you may want to check via the grocery page)

**Step 3: Test aisle + nutrition workflow**

1. Open an ingredient's editor
2. Enter valid nutrition label text
3. Select an aisle
4. Save — should succeed, both nutrition and aisle saved

**Step 4: Test "Other..." new aisle**

1. Open an ingredient's editor
2. Select "Other..." from dropdown
3. Type a new aisle name (e.g., "Deli")
4. Save
5. Open the groceries page — "Deli" should appear in the aisle order editor
6. Go back to ingredients — open another ingredient, "Deli" should now be in the dropdown

**Step 5: Test unsaved changes**

1. Open an ingredient editor
2. Change the aisle dropdown
3. Click Cancel — should prompt "You have unsaved changes"
4. Press Escape — same prompt
5. Navigate away — beforeunload should warn

**Step 6: Run full test suite one final time**

Run: `rake test && rake lint`
Expected: All PASS, no lint errors

**Step 7: Final commit (if any polish needed)**

```bash
git add -p
git commit -m "fix: polish ingredient editor styling and behavior"
```

# Nutrition Editor Retrofit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Retrofit the nutrition editor to use the shared `editor_dialog` layout, fix sodium validation, and consolidate CSS.

**Architecture:** The nutrition editor's standalone dialog becomes a companion Stimulus controller that hooks into the shared editor controller's lifecycle events (`editor:collect`, `editor:save`, `editor:modified`, `editor:reset`). The bespoke dialog HTML is replaced with `render layout: 'shared/editor_dialog'`.

**Tech Stack:** Rails 8, Stimulus, Turbo Frames, CSS

---

### Task 1: CSS consolidation — drop .nutrition-editor-dialog, promote sticky/scroll

CSS changes first so the view swap in Task 2 works immediately.

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Promote sticky header/footer and scrollable body to `.editor-dialog`**

Add to the existing `.editor-dialog` rules (after line 797). These are no-ops for textarea editors since the textarea handles its own scroll:

```css
.editor-header {
  position: sticky;
  top: 0;
  z-index: 1;
  background: var(--content-background-color);
}

.editor-footer {
  position: sticky;
  bottom: 0;
  background: var(--content-background-color);
}
```

Wait — `.editor-header` and `.editor-footer` already exist at lines 808 and 862. Just add the sticky properties to those existing rules rather than creating new ones.

At `.editor-header` (line 808), add:
```css
position: sticky;
top: 0;
z-index: 1;
background: var(--content-background-color);
```

At `.editor-footer` (line 862), add:
```css
position: sticky;
bottom: 0;
background: var(--content-background-color);
```

**Step 2: Add `#nutrition-editor` narrow width override**

Add after the `.editor-form` rules (~line 1214):

```css
#nutrition-editor {
  width: min(90vw, 550px);
}
```

**Step 3: Remove `.nutrition-editor-dialog` block**

Delete the entire `.nutrition-editor-dialog` section (lines 1174-1210):
- `.nutrition-editor-dialog` (base styles)
- `.nutrition-editor-dialog[open]`
- `.nutrition-editor-dialog::backdrop`
- `.nutrition-editor-dialog .editor-body`
- `.nutrition-editor-dialog .editor-header`
- `.nutrition-editor-dialog .editor-footer`

**Step 4: Remove `.editor-save-next` rules**

Delete lines 1497-1504 (`.editor-save-next` and `.editor-save-next span`) — this styled a button that was never added.

**Step 5: Update mobile fullscreen rule**

In the `@media (max-width: 640px)` block at line 1507, the `.nutrition-editor-dialog` fullscreen rule (lines 1508-1515) should be removed. The existing `.editor-dialog` mobile fullscreen at line 777 already handles it, but add `margin: 0; max-width: 100vw;` to that rule to match what `.nutrition-editor-dialog` had:

At line 777 (inside the main 640px media query), update:
```css
.editor-dialog {
  width: 100vw;
  max-height: 100vh;
  height: 100vh;
  border-radius: 0;
  margin: 0;
  max-width: 100vw;
}
```

Then delete lines 1508-1515 (the `.nutrition-editor-dialog` mobile override).

**Step 6: Update print media rule**

At line 1667-1668, change:
```css
  .editor-dialog,
  .nutrition-editor-dialog {
```
to just:
```css
  .editor-dialog {
```

**Step 7: Run lint**

```bash
bundle exec rubocop
```

Expected: PASS (CSS changes don't affect Ruby lint, but good to verify nothing broke).

**Step 8: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "refactor: consolidate nutrition editor CSS into shared editor-dialog"
```

---

### Task 2: View — replace bespoke dialog with shared editor_dialog layout

**Files:**
- Modify: `app/views/ingredients/index.html.erb`

**Step 1: Replace the dialog HTML**

Replace lines 24-50 (the bespoke `<dialog>` through `<% end %>`) with:

```erb
<% if current_member? %>
  <%= render layout: 'shared/editor_dialog',
      locals: { title: 'Edit Nutrition',
                id: 'nutrition-editor',
                dialog_data: { extra_controllers: 'nutrition-editor',
                               editor_on_success: 'close' },
                extra_data: {
                  'data-nutrition-editor-base-url-value' => nutrition_entry_upsert_path(ingredient_name: '__NAME__'),
                  'data-nutrition-editor-edit-url-value' => ingredient_edit_path(ingredient_name: '__NAME__')
                } } do %>
    <div class="editor-body">
      <turbo-frame id="nutrition-editor-form">
        <p class="loading-placeholder">Loading&hellip;</p>
      </turbo-frame>
    </div>
  <% end %>
<% end %>
```

Note: The `extra_data` keys need the `data-` prefix because `extra_data` is merged directly into the tag's `data:` hash. Actually — check how `extra_data` is merged. Looking at the shared layout line 13: `.compact.merge(extra_data)`. The `tag.dialog` helper's `data:` hash automatically prefixes keys with `data-`, so the keys should NOT have the `data-` prefix. Use:

```ruby
extra_data: {
  'nutrition-editor-base-url-value' => nutrition_entry_upsert_path(ingredient_name: '__NAME__'),
  'nutrition-editor-edit-url-value' => ingredient_edit_path(ingredient_name: '__NAME__')
}
```

**Step 2: Verify the rendered HTML**

Start the dev server and check that the ingredients page renders. The dialog won't fully function yet (JS not updated), but the HTML structure should be correct. Inspect the `<dialog>` element and verify:
- `data-controller="editor nutrition-editor"`
- `data-nutrition-editor-base-url-value` and `data-nutrition-editor-edit-url-value` are present
- `data-editor-on-success-value="close"` is present
- Header has "Edit Nutrition" and close button
- Footer has Cancel and Save buttons
- Body has the turbo-frame

**Step 3: Run tests**

```bash
ruby -Itest test/controllers/ingredients_controller_test.rb
```

Expected: PASS — tests check HTML rendering, not JS behavior.

**Step 4: Commit**

```bash
git add app/views/ingredients/index.html.erb
git commit -m "refactor: replace bespoke nutrition dialog with shared editor_dialog layout"
```

---

### Task 3: Validation fix — dynamic nutrient max from NutritionConstraints

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb`

**Step 1: Update the HTML max attribute and add data-nutrient-max**

In `_editor_form.html.erb`, inside the `NUTRIENT_DISPLAY.each` loop (line 23-28), change the `<input>` from:

```erb
<input type="number" id="editor-<%= key %>" class="field-narrow"
       value="<%= format_nutrient_value(entry.public_send(key)) if entry&.public_send(key) %>"
       inputmode="decimal" step="any" min="0" max="10000"
       data-nutrition-editor-target="nutrientField"
       data-nutrient-key="<%= key %>">
```

to:

```erb
<% nutrient_max = FamilyRecipes::NutritionConstraints::NUTRIENT_MAX[key.to_s] %>
<input type="number" id="editor-<%= key %>" class="field-narrow"
       value="<%= format_nutrient_value(entry.public_send(key)) if entry&.public_send(key) %>"
       inputmode="decimal" step="any" min="0" max="<%= nutrient_max %>"
       data-nutrition-editor-target="nutrientField"
       data-nutrient-key="<%= key %>"
       data-nutrient-max="<%= nutrient_max %>">
```

**Step 2: Run tests**

```bash
ruby -Itest test/controllers/ingredients_controller_test.rb
```

Expected: PASS.

**Step 3: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb
git commit -m "fix: use per-nutrient max from NutritionConstraints for sodium (50,000)"
```

---

### Task 4: JS — rewrite nutrition_editor_controller as companion

This is the main task. The controller keeps all form-management logic but delegates dialog lifecycle to the editor controller.

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

**Step 1: Rewrite the controller**

The new controller structure:

```javascript
import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, clearErrors } from "utilities/editor_utils"

/**
 * Companion controller for the nutrition editor dialog. Hooks into the shared
 * editor controller's lifecycle events to provide custom data collection,
 * validation, save logic, and dirty detection. Manages the structured form
 * (nutrients, density, portions, aisle, aliases) loaded via Turbo Frame.
 *
 * - editor_controller: dialog lifecycle (open/close, save button state, errors, beforeunload)
 * - editor_utils: CSRF tokens, error clearing
 * - NutritionEntriesController: JSON save endpoint and Turbo Frame edit partial
 * - CatalogWriteService (server): orchestrates upsert, aisle sync, and broadcast
 */
export default class extends Controller {
  static targets = [
    "formContent",
    "basisGrams", "nutrientField",
    "densityVolume", "densityUnit", "densityGrams",
    "portionList", "portionRow", "portionName", "portionGrams",
    "aisleSelect", "aisleInput",
    "aliasList", "aliasInput", "aliasChip"
  ]

  static values = {
    baseUrl: String,
    editUrl: String
  }

  connect() {
    this.currentIngredient = null
    this.originalSnapshot = null

    this.boundEditClick = (event) => {
      const btn = event.target.closest("[data-open-editor]")
      if (btn) this.openForIngredient(btn)
    }

    this.boundResetClick = (event) => {
      const btn = event.target.closest("[data-reset-ingredient]")
      if (btn) this.resetIngredient(btn)
    }

    this.boundPrefetch = (event) => {
      const row = event.target.closest("[data-open-editor]")
      if (row) this.prefetch(row.dataset.ingredientName)
    }

    this.boundFrameLoad = () => this.onFrameLoad()
    this.boundCollect = (e) => this.handleCollect(e)
    this.boundSave = (e) => this.handleSave(e)
    this.boundModified = (e) => this.handleModified(e)
    this.boundReset = (e) => this.handleReset(e)

    document.addEventListener("click", this.boundEditClick)
    document.addEventListener("click", this.boundResetClick)
    document.addEventListener("pointerenter", this.boundPrefetch, true)

    this.turboFrame.addEventListener("turbo:frame-load", this.boundFrameLoad)
    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:save", this.boundSave)
    this.element.addEventListener("editor:modified", this.boundModified)
    this.element.addEventListener("editor:reset", this.boundReset)
  }

  disconnect() {
    document.removeEventListener("click", this.boundEditClick)
    document.removeEventListener("click", this.boundResetClick)
    document.removeEventListener("pointerenter", this.boundPrefetch, true)
    this.turboFrame.removeEventListener("turbo:frame-load", this.boundFrameLoad)
    this.element.removeEventListener("editor:collect", this.boundCollect)
    this.element.removeEventListener("editor:save", this.boundSave)
    this.element.removeEventListener("editor:modified", this.boundModified)
    this.element.removeEventListener("editor:reset", this.boundReset)
  }

  // --- Open flow (nutrition controller owns this) ---

  openForIngredient(btn) {
    const name = btn.dataset.ingredientName
    this.currentIngredient = name
    this.element.querySelector(".editor-header h2").textContent = `Edit ${name}`

    this.turboFrame.src = this.editUrlFor(name)
    this.editorController.open()
  }

  prefetch(name) {
    if (this.prefetchedName === name) return
    this.prefetchedName = name
    fetch(this.editUrlFor(name), { headers: { Accept: "text/html" } })
  }

  // --- Editor lifecycle event handlers ---

  handleCollect(event) {
    event.detail.handled = true
    event.detail.data = this.collectFormData()
  }

  handleSave(event) {
    const data = event.detail.data
    event.detail.handled = true
    event.detail.saveFn = async () => {
      const errors = this.validateForm(data)
      if (errors.length > 0) {
        return new Response(JSON.stringify({ errors }), {
          status: 422,
          headers: { "Content-Type": "application/json" }
        })
      }
      return fetch(this.nutritionUrl(this.currentIngredient), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify(data)
      })
    }
  }

  handleModified(event) {
    event.detail.handled = true
    event.detail.modified = this.originalSnapshot !== null &&
      JSON.stringify(this.collectFormData()) !== this.originalSnapshot
  }

  handleReset(event) {
    event.detail.handled = true
    this.currentIngredient = null
    this.originalSnapshot = null
  }

  // --- Form interactions ---

  addPortion() {
    // (same DOM-building code as current, unchanged)
  }

  removePortion(event) {
    event.currentTarget.closest(".portion-row").remove()
  }

  addAlias() {
    // (same chip-building code as current, unchanged)
  }

  removeAlias(event) {
    event.currentTarget.closest(".alias-chip").remove()
  }

  aliasInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addAlias()
    }
  }

  aisleChanged() {
    if (this.aisleSelectTarget.value === "__other__") {
      this.aisleInputTarget.hidden = false
      this.aisleInputTarget.value = ""
      this.aisleInputTarget.focus()
    } else {
      this.aisleInputTarget.hidden = true
      this.aisleInputTarget.value = ""
    }
  }

  aisleInputKeydown(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    event.stopPropagation()
    this.aisleInputTarget.hidden = true
    this.aisleInputTarget.value = ""
    this.aisleSelectTarget.value = this.originalAisle || ""
  }

  async resetIngredient(btn) {
    const name = btn.dataset.ingredientName
    if (!confirm(`Reset "${name}" to built-in nutrition data?`)) return

    btn.disabled = true
    try {
      const response = await fetch(this.nutritionUrl(name), {
        method: "DELETE",
        headers: { "X-CSRF-Token": getCsrfToken() }
      })
      if (response.ok) {
        window.location.reload()
      } else {
        btn.disabled = false
      }
    } catch {
      btn.disabled = false
    }
  }

  // --- Data collection and validation ---

  collectFormData() {
    return {
      nutrients: this.collectNutrients(),
      density: this.collectDensity(),
      portions: this.collectPortions(),
      aisle: this.currentAisle(),
      aliases: this.collectAliases()
    }
  }

  validateForm(data) {
    const errors = []
    const hasAnyNutrient = Object.entries(data.nutrients)
      .some(([key, val]) => key !== "basis_grams" && val !== null)

    if (hasAnyNutrient && (!data.nutrients.basis_grams || data.nutrients.basis_grams <= 0)) {
      errors.push("Per (basis grams) must be greater than 0 when nutrients are provided.")
    }

    this.nutrientFieldTargets.forEach(input => {
      const key = input.dataset.nutrientKey
      const val = data.nutrients[key]
      const max = parseInt(input.dataset.nutrientMax, 10) || 10000
      if (val !== null && (val < 0 || val > max)) {
        errors.push(`${key.replace(/_/g, " ")} must be between 0 and ${max.toLocaleString()}.`)
      }
    })

    if (data.density) {
      if (!data.density.grams || data.density.grams <= 0) {
        errors.push("Density grams must be greater than 0 when volume is set.")
      }
    }

    const portionNames = Object.keys(data.portions)
    if (portionNames.length !== new Set(portionNames).size) {
      errors.push("Duplicate portion names are not allowed.")
    }

    Object.entries(data.portions).forEach(([name, grams]) => {
      if (!grams || grams <= 0) {
        errors.push(`Portion "${name === "~unitless" ? "each" : name}" must have grams greater than 0.`)
      }
    })

    return errors
  }

  // --- Private helpers ---

  get turboFrame() {
    return this.element.querySelector("turbo-frame")
  }

  get originalAisle() {
    return this._originalAisle
  }

  get editorController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "editor")
  }

  onFrameLoad() {
    this._originalAisle = this.currentAisle()
    this.originalSnapshot = JSON.stringify(this.collectFormData())
    if (this.hasBasisGramsTarget) this.basisGramsTarget.focus()
  }

  collectNutrients() {
    const nutrients = { basis_grams: parseFloatOrNull(this.basisGramsTarget.value) }
    this.nutrientFieldTargets.forEach(input => {
      nutrients[input.dataset.nutrientKey] = parseFloatOrNull(input.value)
    })
    return nutrients
  }

  collectDensity() {
    const volume = parseFloatOrNull(this.densityVolumeTarget.value)
    const unit = this.densityUnitTarget.value
    const grams = parseFloatOrNull(this.densityGramsTarget.value)
    if (!volume || !unit) return null
    return { volume, unit, grams }
  }

  collectPortions() {
    const portions = {}
    this.portionRowTargets.forEach(row => {
      const nameInput = row.querySelector("[data-nutrition-editor-target='portionName']")
      const gramsInput = row.querySelector("[data-nutrition-editor-target='portionGrams']")
      if (!nameInput || !gramsInput) return
      const rawName = nameInput.value.trim()
      if (!rawName) return
      const key = rawName.toLowerCase() === "each" ? "~unitless" : rawName
      const grams = parseFloatOrNull(gramsInput.value)
      if (grams !== null) portions[key] = grams
    })
    return portions
  }

  collectAliases() {
    return this.aliasChipTargets.map(chip =>
      chip.querySelector(".alias-chip-text").textContent.trim()
    )
  }

  currentAisle() {
    if (!this.hasAisleSelectTarget) return null
    const val = this.aisleSelectTarget.value
    if (val === "__other__") return this.aisleInputTarget.value.trim() || null
    return val || null
  }

  nutritionUrl(name) {
    return this.baseUrlValue.replace("__NAME__", encodeURIComponent(name))
  }

  editUrlFor(name) {
    return this.editUrlValue.replace("__NAME__", encodeURIComponent(name))
  }
}

function parseFloatOrNull(value) {
  if (!value || value.trim() === "") return null
  const num = parseFloat(value)
  return Number.isNaN(num) ? null : num
}
```

Key changes from current:
- Removed: `dialog`, `title`, `errors`, `saveButton` targets
- Removed: `close()`, `save()`, `performSave()`, `saveWithJson()`, `disableSaveButtons()`, `enableSaveButtons()`, `isModified()`
- Removed: `boundCancel` listener (editor controller handles cancel)
- Added: `editorController` getter via Stimulus cross-controller API
- Added: Four event listeners for `editor:collect`, `editor:save`, `editor:modified`, `editor:reset`
- Changed: `openForIngredient()` calls `this.editorController.open()` instead of `this.dialogTarget.showModal()`
- Changed: `validateForm()` reads `data-nutrient-max` per input instead of hardcoded 10,000
- Changed: `resetIngredient()` error display removed (just disables/re-enables button)

**Step 2: Run tests**

```bash
rake test
```

Expected: All existing tests PASS. The controller tests are integration tests that don't exercise JS, but this confirms no Ruby regressions.

**Step 3: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "refactor: nutrition editor controller as companion to shared editor"
```

---

### Task 5: Add server-side test for high sodium value

**Files:**
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Write the test**

Add after the existing `validates basis_grams` test (line 336):

```ruby
test 'upsert accepts sodium up to 50,000' do
  post nutrition_entry_upsert_path('salt', kitchen_slug: kitchen_slug),
       params: { nutrients: VALID_NUTRIENTS.merge(sodium: 38_758), density: nil, portions: {}, aisle: nil },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'salt')

  assert_in_delta 38_758.0, entry.sodium
end
```

**Step 2: Run the test**

```bash
ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n test_upsert_accepts_sodium_up_to_50_000
```

Expected: PASS — server already allows sodium up to 50,000 via `NutritionConstraints::NUTRIENT_MAX`.

**Step 3: Commit**

```bash
git add test/controllers/nutrition_entries_controller_test.rb
git commit -m "test: verify high sodium values accepted (GH #182)"
```

---

### Task 6: Full verification

**Step 1: Run lint**

```bash
bundle exec rubocop
```

Expected: 0 offenses.

**Step 2: Run full test suite**

```bash
rake test
```

Expected: All tests pass.

**Step 3: Check html_safe audit**

```bash
rake lint:html_safe
```

Expected: PASS — no new `.html_safe` or `raw()` calls.

**Step 4: Visual verification**

Start dev server (`bin/dev`), navigate to ingredients page, and verify:

1. Clicking an ingredient row opens the editor dialog
2. Dialog title shows "Edit {ingredient name}"
3. Form loads via Turbo Frame (nutrients, density, portions, aisle, aliases)
4. Cancel button closes dialog
5. Editing a field then clicking Cancel shows dirty confirmation
6. Save button submits; on success dialog closes and table updates via morph
7. Invalid data (e.g. negative calories) shows error message in the dialog
8. Sodium field accepts values up to 50,000
9. "Reset to built-in" works for custom entries
10. Dialog is narrow (550px) compared to recipe editor (50rem)
11. On mobile viewport (< 640px), dialog goes fullscreen
12. Prefetch on hover still works (check network tab)

**Step 5: Commit any fixups, then final commit**

```bash
git add -A && git commit -m "refactor: retrofit nutrition editor to shared dialog shell (GH #182)"
```

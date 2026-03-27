# Recipe Editor Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the graphical recipe editor's visual design — compact fields, better buttons, ingredient row cards, and small UX fixes.

**Architecture:** Pure CSS + JS changes. No model, controller, or routing changes. The shared `buildIconButton()` helper in `dom_builders.js` replaces inline button construction in both recipe and Quick Bites graphical controllers. CSS changes are all in `editor.css`.

**Tech Stack:** CSS, Stimulus controllers, SVG icon registry

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/javascript/utilities/icons.js` | Modify | Add `plus` icon to registry |
| `app/javascript/utilities/dom_builders.js` | Modify | Add `buildIconButton()` and `buildPillButton()` helpers |
| `app/javascript/utilities/graphical_editor_utils.js` | Modify | Use `buildIconButton()` in `buildCardActions()`, use `buildPillButton()` in `buildRowsSection()` |
| `app/javascript/controllers/recipe_graphical_controller.js` | Modify | Icon buttons for ingredient rows, ingredient card wrapper, category below-row, pill button for Add Step |
| `app/javascript/controllers/quickbites_graphical_controller.js` | Modify | Icon buttons for item rows (same pattern) |
| `app/javascript/controllers/tag_input_controller.js` | Modify | Add "+" button next to input |
| `app/views/recipes/_editor_frame.html.erb` | Modify | New-category row below dropdown, tag input row wrapper, compact field classes, pill Add Step button |
| `app/views/recipes/_graphical_step_card.html.erb` | Modify | Ingredient card wrappers, proportional input classes |
| `app/assets/stylesheets/editor.css` | Modify | All new CSS rules |

### Task 1: Add `plus` icon and shared button builders

**Files:**
- Modify: `app/javascript/utilities/icons.js:10-31`
- Modify: `app/javascript/utilities/dom_builders.js:10-17`

- [ ] **Step 1: Add `plus` icon to the registry**

In `icons.js`, add a `plus` entry to the `ICONS` object after the `undo` entry:

```javascript
  plus: {
    viewBox: "0 0 24 24",
    children: [
      { tag: "line", attrs: { x1: "12", y1: "5", x2: "12", y2: "19" } },
      { tag: "line", attrs: { x1: "5", y1: "12", x2: "19", y2: "12" } }
    ]
  }
```

- [ ] **Step 2: Add `buildIconButton()` to `dom_builders.js`**

Add this export after the existing `buildButton` function. This mirrors the private `buildIconButton` in `ordered_list_editor_utils.js` but is shared:

```javascript
import { buildIcon } from "./icons"

export function buildIconButton(iconName, onClick, { className = "", label = "", size = 14 } = {}) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = `btn-icon-round ${className}`.trim()
  if (label) btn.setAttribute("aria-label", label)
  btn.appendChild(buildIcon(iconName, size))
  btn.addEventListener("click", onClick)
  return btn
}
```

- [ ] **Step 3: Add `buildPillButton()` to `dom_builders.js`**

Add this export after `buildIconButton`:

```javascript
export function buildPillButton(text, onClick, className) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = className ? `btn-pill ${className}` : "btn-pill"
  btn.textContent = text
  btn.addEventListener("click", onClick)
  return btn
}
```

- [ ] **Step 4: Update the header comment in `dom_builders.js`**

Update the collaborators list to mention icons.js:

```javascript
/**
 * Shared DOM factory functions for graphical editors. Pure element
 * creators with no Stimulus or framework coupling.
 *
 * - icons: SVG icon builder (buildIcon) for icon buttons
 * - graphical_editor_utils: higher-level card/section builders
 * - recipe_graphical_controller: recipe step/ingredient editing
 * - quickbites_graphical_controller: category/item editing
 */
```

- [ ] **Step 5: Verify JS builds**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/utilities/icons.js app/javascript/utilities/dom_builders.js
git commit -m "Add plus icon and shared buildIconButton/buildPillButton helpers"
```

### Task 2: Upgrade step and item action buttons to icon rounds

**Files:**
- Modify: `app/javascript/utilities/graphical_editor_utils.js:12,95-102,127`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js:2,309-313`
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js:2,201-205`

- [ ] **Step 1: Update `graphical_editor_utils.js` — import and `buildCardActions()`**

Replace the import line:

```javascript
import { buildButton } from "./dom_builders"
```

with:

```javascript
import { buildIconButton, buildPillButton } from "./dom_builders"
```

Replace the `buildCardActions()` function body:

```javascript
export function buildCardActions(index, onMove, onRemove) {
  const actions = document.createElement("div")
  actions.className = "graphical-step-actions"

  const upBtn = buildIconButton("chevron", () => onMove(index, -1), { label: "Move up" })
  actions.appendChild(upBtn)

  const downBtn = buildIconButton("chevron", () => onMove(index, 1), { className: "aisle-icon--flipped", label: "Move down" })
  actions.appendChild(downBtn)

  actions.appendChild(buildIconButton("delete", () => onRemove(index), { className: "btn-danger", label: "Remove" }))
  return actions
}
```

- [ ] **Step 2: Update `graphical_editor_utils.js` — `buildRowsSection()` pill button**

In `buildRowsSection()`, replace the `buildButton` call:

```javascript
  headerRow.appendChild(buildButton("+ Add", onAdd, "graphical-btn--small"))
```

with:

```javascript
  headerRow.appendChild(buildPillButton("+ Add", onAdd))
```

- [ ] **Step 3: Update `recipe_graphical_controller.js` — ingredient row buttons**

Update the import line to include `buildIconButton`:

```javascript
import { buildButton, buildInput, buildFieldGroup, buildTextareaGroup, buildIconButton } from "../utilities/dom_builders"
```

In `buildIngredientRow()`, replace the actions section (lines ~309-313):

```javascript
    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    actions.appendChild(buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, -1), { label: "Move up" }))
    const downBtn = buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, 1), { className: "aisle-icon--flipped", label: "Move down" })
    actions.appendChild(downBtn)
    actions.appendChild(buildIconButton("delete", () => this.removeIngredient(stepIndex, ingIndex), { className: "btn-danger", label: "Remove" }))
    row.appendChild(actions)
```

- [ ] **Step 4: Update `quickbites_graphical_controller.js` — item row buttons**

Update the import line:

```javascript
import { buildButton, buildInput, buildFieldGroup, buildIconButton } from "../utilities/dom_builders"
```

In `buildItemRow()`, replace the actions section (lines ~201-205):

```javascript
    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    actions.appendChild(buildIconButton("chevron", () => this.moveItem(catIndex, itemIndex, -1), { label: "Move up" }))
    const downBtn = buildIconButton("chevron", () => this.moveItem(catIndex, itemIndex, 1), { className: "aisle-icon--flipped", label: "Move down" })
    actions.appendChild(downBtn)
    actions.appendChild(buildIconButton("delete", () => this.removeItem(catIndex, itemIndex), { className: "btn-danger", label: "Remove" }))
    row.appendChild(actions)
```

- [ ] **Step 5: Build and verify**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/utilities/graphical_editor_utils.js app/javascript/controllers/recipe_graphical_controller.js app/javascript/controllers/quickbites_graphical_controller.js
git commit -m "Replace text buttons with round icon buttons in graphical editors"
```

### Task 3: Ingredient row cards with proportional widths

**Files:**
- Modify: `app/javascript/controllers/recipe_graphical_controller.js:293-316`
- Modify: `app/views/recipes/_graphical_step_card.html.erb:33-39`
- Modify: `app/assets/stylesheets/editor.css:808-831`

- [ ] **Step 1: Update JS — wrap ingredient row in card div**

In `recipe_graphical_controller.js`, rewrite `buildIngredientRow()` to wrap
fields in a card container:

```javascript
  buildIngredientRow(stepIndex, ingIndex, ing) {
    const card = document.createElement("div")
    card.className = "graphical-ingredient-card"

    const fields = document.createElement("div")
    fields.className = "graphical-ingredient-fields"

    fields.appendChild(buildInput("Name", ing.name || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].name = val
    }, "graphical-ing-name"))

    fields.appendChild(buildInput("Qty", ing.quantity || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].quantity = val
    }, "graphical-ing-qty"))

    fields.appendChild(buildInput("Prep note", ing.prep_note || "", (val) => {
      this.steps[stepIndex].ingredients[ingIndex].prep_note = val
    }, "graphical-ing-prep"))

    card.appendChild(fields)

    const actions = document.createElement("div")
    actions.className = "graphical-ingredient-actions"
    actions.appendChild(buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, -1), { label: "Move up" }))
    const downBtn = buildIconButton("chevron", () => this.moveIngredient(stepIndex, ingIndex, 1), { className: "aisle-icon--flipped", label: "Move down" })
    actions.appendChild(downBtn)
    actions.appendChild(buildIconButton("delete", () => this.removeIngredient(stepIndex, ingIndex), { className: "btn-danger", label: "Remove" }))
    card.appendChild(actions)

    return card
  }
```

- [ ] **Step 2: Update server-rendered step card partial**

In `_graphical_step_card.html.erb`, replace the ingredient rows block
(lines 33-39):

```erb
            <% (step[:ingredients] || []).each do |ing| %>
              <div class="graphical-ingredient-card">
                <div class="graphical-ingredient-fields">
                  <input type="text" placeholder="Name" value="<%= ing[:name] %>" class="input-base graphical-ing-name" data-field="name">
                  <input type="text" placeholder="Qty" value="<%= ing[:quantity] %>" class="input-base graphical-ing-qty" data-field="quantity">
                  <input type="text" placeholder="Prep note" value="<%= ing[:prep_note] %>" class="input-base graphical-ing-prep" data-field="prep_note">
                </div>
              </div>
            <% end %>
```

Note: Action buttons are still omitted from server-rendered cards — JS adds
them during hydration, same as before.

- [ ] **Step 3: Update `readIngredientsFromCard()` selector**

In `recipe_graphical_controller.js`, update `readIngredientsFromCard()` to
query `.graphical-ingredient-card` instead of `.graphical-ingredient-row`:

```javascript
  readIngredientsFromCard(card) {
    const rows = card.querySelectorAll(".graphical-ingredient-card")
    return Array.from(rows).map(row => ({
      name: row.querySelector("[data-field='name']")?.value || "",
      quantity: row.querySelector("[data-field='quantity']")?.value || "",
      prep_note: row.querySelector("[data-field='prep_note']")?.value || ""
    }))
  }
```

- [ ] **Step 4: Add CSS for ingredient cards and proportional inputs**

In `editor.css`, replace the existing ingredient rules (the
`.graphical-ingredient-row` block, lines ~821-825) and add new rules after the
`.graphical-ingredient-rows` block:

```css
.graphical-ingredient-card {
  display: flex;
  gap: 6px;
  align-items: center;
  padding: 6px 8px;
  background: var(--surface-alt);
  border: 1px solid var(--rule-faint);
  border-radius: 6px;
}

.graphical-ingredient-fields {
  display: flex;
  gap: 6px;
  flex: 1;
  align-items: center;
  min-width: 0;
}

.graphical-ing-name { flex: 3; }
.graphical-ing-qty { flex: 1; min-width: 4.5rem; max-width: 6rem; text-align: center; }
.graphical-ing-prep { flex: 2; font-style: italic; border-color: var(--rule-faint); }
.graphical-ing-prep::placeholder { font-style: italic; }
```

Keep `.graphical-ingredient-row` in the CSS but mark with a comment that it is
used only by Quick Bites item rows (which don't get the card treatment).

- [ ] **Step 5: Build and run tests**

Run: `npm run build && bundle exec rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/recipe_graphical_controller.js app/views/recipes/_graphical_step_card.html.erb app/assets/stylesheets/editor.css
git commit -m "Add ingredient row card treatment with proportional field widths"
```

### Task 4: Compact front matter and new-category below dropdown

**Files:**
- Modify: `app/views/recipes/_editor_frame.html.erb:38-72`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js:147-170`
- Modify: `app/assets/stylesheets/editor.css:736-745`

- [ ] **Step 1: Update the ERB template**

Replace the front matter row and category input section (lines 38-72) in
`_editor_frame.html.erb`:

```erb
        <div class="graphical-front-matter-row">
          <div class="graphical-field-group graphical-fm-field graphical-fm-field--narrow">
            <label class="graphical-label" for="graphical-serves">Serves</label>
            <input type="text" id="graphical-serves" class="input-base"
                   data-recipe-graphical-target="serves"
                   placeholder="e.g. 4"
                   value="<%= structure.dig(:front_matter, :serves) %>">
          </div>

          <div class="graphical-field-group graphical-fm-field graphical-fm-field--narrow">
            <label class="graphical-label" for="graphical-makes">Makes</label>
            <input type="text" id="graphical-makes" class="input-base"
                   data-recipe-graphical-target="makes"
                   placeholder="e.g. 12 rolls"
                   value="<%= structure.dig(:front_matter, :makes) %>">
          </div>

          <div class="graphical-field-group graphical-fm-field graphical-fm-field--wide">
            <label class="graphical-label" for="graphical-category">Category</label>
            <select id="graphical-category" class="input-base"
                    data-recipe-graphical-target="categorySelect"
                    data-action="change->recipe-graphical#categoryChanged">
              <option value="">None</option>
              <% categories.each do |cat| %>
                <option value="<%= cat.name %>"
                  <%= 'selected' if structure.dig(:front_matter, :category) == cat.name %>><%= cat.name %></option>
              <% end %>
              <option value="__new__">New category...</option>
            </select>
          </div>
        </div>

        <div class="graphical-new-category-row" hidden
             data-recipe-graphical-target="categoryRow">
          <input type="text" class="input-base"
                 data-recipe-graphical-target="categoryInput"
                 data-action="keydown->recipe-graphical#categoryInputKeydown"
                 placeholder="New category name">
          <button type="button" class="btn-link"
                  data-action="click->recipe-graphical#cancelNewCategory">cancel</button>
        </div>
```

Note: The `categoryInput` is moved out of the dropdown's field group into its
own `.graphical-new-category-row` div. A new target `categoryRow` wraps the
entire row so we can show/hide it.

- [ ] **Step 2: Add `categoryRow` target and update JS**

In `recipe_graphical_controller.js`, add `"categoryRow"` to the targets array:

```javascript
  static targets = [
    "title", "description", "serves", "makes",
    "categorySelect", "categoryInput", "categoryRow",
    "stepsContainer", "footer"
  ]
```

Rewrite `showNewCategoryInput()`, `categoryChanged()`,
`categoryInputKeydown()`, and add `cancelNewCategory()`:

```javascript
  showNewCategoryInput(value) {
    this.categorySelectTarget.value = "__new__"
    if (!this.hasCategoryRowTarget) return
    this.categoryInputTarget.value = value || ""
    this.categoryRowTarget.hidden = false
  }

  categoryChanged() {
    if (!this.hasCategoryRowTarget) return
    if (this.categorySelectTarget.value === "__new__") {
      this.categoryRowTarget.hidden = false
      this.categoryInputTarget.focus()
    } else {
      this.categoryRowTarget.hidden = true
    }
  }

  categoryInputKeydown(event) {
    if (event.key !== "Escape") return
    this.cancelNewCategory()
  }

  cancelNewCategory() {
    if (!this.hasCategoryRowTarget) return
    this.categoryRowTarget.hidden = true
    this.categorySelectTarget.value = ""
  }
```

The select is no longer hidden — it stays visible showing "New category..."
while the input row appears below.

- [ ] **Step 3: Add CSS for compact front matter and new-category row**

In `editor.css`, replace the existing `.graphical-front-matter-row > *` rule
and add the new classes:

```css
.graphical-front-matter-row {
  display: flex;
  gap: 0.75rem;
  flex-wrap: wrap;
  align-items: flex-end;
}

.graphical-fm-field--narrow {
  flex: 0 0 auto;
  width: 5.5rem;
}

.graphical-fm-field--wide {
  flex: 1;
  min-width: 10rem;
}

.graphical-new-category-row {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  margin-top: 0.35rem;
}

.graphical-new-category-row .input-base {
  flex: 1;
}
```

Remove the old rule:

```css
.graphical-front-matter-row > * {
  min-width: 120px;
  flex: 1;
}
```

Also remove the `.graphical-field-group--inline` references if present (they
were in the old template but not in the CSS, so this may be a no-op).

- [ ] **Step 4: Update mobile responsive rule**

In the `@media (max-width: 600px)` block, the existing
`.graphical-front-matter-row { flex-direction: column; }` rule should still
work. Verify that `.graphical-fm-field--narrow` gets full width on mobile by
adding:

```css
@media (max-width: 600px) {
  .graphical-fm-field--narrow {
    width: auto;
    flex: 1;
  }
}
```

- [ ] **Step 5: Build and run tests**

Run: `npm run build && bundle exec rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/recipes/_editor_frame.html.erb app/javascript/controllers/recipe_graphical_controller.js app/assets/stylesheets/editor.css
git commit -m "Compact front matter fields and show new-category input below dropdown"
```

### Task 5: Tag editor Add button

**Files:**
- Modify: `app/javascript/controllers/tag_input_controller.js:21-28`
- Modify: `app/views/recipes/_editor_frame.html.erb:79-83`
- Modify: `app/assets/stylesheets/editor.css`

- [ ] **Step 1: Update tag input ERB template**

In `_editor_frame.html.erb`, replace the tag input container section:

```erb
          <div data-controller="tag-input"
               data-tag-input-all-tags-value="<%= current_kitchen.tags.left_joins(:recipe_tags).group(:name).order(:name).count.to_a.to_json %>"
               data-tag-input-tags-value="<%= (structure.dig(:front_matter, :tags) || []).to_json %>">
            <div class="tag-pills" data-tag-input-target="pills"></div>
            <div class="tag-input-row">
              <input type="text" class="tag-input-field input-base" placeholder="Add tag..."
                     data-tag-input-target="input"
                     data-action="input->tag-input#onInput keydown->tag-input#onKeydown">
              <button type="button" class="btn-icon-round" aria-label="Add tag"
                      data-action="click->tag-input#commitTag"
                      data-tag-input-target="addBtn"></button>
            </div>
            <div class="tag-autocomplete" data-tag-input-target="dropdown" hidden></div>
          </div>
```

Changes: removed the `tag-input-container` wrapper div, added `tag-input-row`
flex wrapper around input + button, added `input-base` class to the input,
added a `btn-icon-round` button with a `commitTag` action.

- [ ] **Step 2: Add `addBtn` target and `commitTag()` to the controller**

In `tag_input_controller.js`, add `"addBtn"` to targets:

```javascript
  static targets = ["pills", "input", "dropdown", "addBtn"]
```

Add the `commitTag()` method (called by the button click and reusable):

```javascript
  commitTag() {
    if (this.highlightedIndex >= 0) {
      this.selectHighlighted()
    } else {
      this.addCurrentInput()
    }
  }
```

Update `connect()` to build the plus icon into the button:

```javascript
  connect() {
    this.currentTags = [...this.tagsValue]
    this.originalTags = [...this.tagsValue]
    this.highlightedIndex = -1
    this.tagCounts = new Map(this.allTagsValue.map(([name, count]) => [name, count]))
    this.tagNames = this.allTagsValue.map(([name]) => name)
    this.loadSmartTags()
    this.renderPills()
    this.renderAddIcon()

    this.listeners = new ListenerManager()
    const editor = this.element.closest("[data-controller~='editor']")
    if (editor) this.listeners.add(editor, "editor:reset", () => this.reset())
  }

  renderAddIcon() {
    if (!this.hasAddBtnTarget) return
    const { buildIcon } = require("../utilities/icons")
    this.addBtnTarget.appendChild(buildIcon("plus", 14))
  }
```

Wait — we can't use `require` in an ES module. Instead, import `buildIcon` at
the top of the file:

```javascript
import { Controller } from "@hotwired/stimulus"
import ListenerManager from "../utilities/listener_manager"
import { buildIcon } from "../utilities/icons"
```

Then the method becomes:

```javascript
  renderAddIcon() {
    if (!this.hasAddBtnTarget) return
    this.addBtnTarget.appendChild(buildIcon("plus", 14))
  }
```

Also update `onKeydown` to delegate to `commitTag()` for the Enter/Tab case:

```javascript
    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      this.commitTag()
    }
```

- [ ] **Step 3: Add CSS for tag input row**

In `editor.css`, add:

```css
.tag-input-row {
  display: flex;
  gap: 0.35rem;
  align-items: center;
}

.tag-input-row .tag-input-field {
  flex: 1;
}
```

- [ ] **Step 4: Build and run tests**

Run: `npm run build && bundle exec rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/tag_input_controller.js app/views/recipes/_editor_frame.html.erb app/assets/stylesheets/editor.css
git commit -m "Add visible + button to tag editor input"
```

### Task 6: Subtle ingredient count, pill buttons, and CSS cleanup

**Files:**
- Modify: `app/assets/stylesheets/editor.css:788-790,842-870`
- Modify: `app/views/recipes/_editor_frame.html.erb:95-96`
- Modify: `app/views/recipes/_graphical_editor.html.erb:72`
- Modify: `app/views/menu/_quickbites_editor_frame.html.erb:24`
- Modify: `app/javascript/utilities/dom_builders.js` (remove unused `buildButton`)
- Modify: `app/javascript/utilities/graphical_editor_utils.js` (update header comment)

- [ ] **Step 1: Update ingredient summary CSS**

In `editor.css`, replace the `.graphical-step-summary` and
`.graphical-ingredient-summary` rules:

```css
.graphical-ingredient-summary {
  font-size: 0.7rem;
  color: var(--text-light);
  font-weight: 400;
}
```

Remove the old `.graphical-step-summary` rule (`opacity: 0.4;
font-size: 0.8em;`) — it is no longer used (the class was
`.graphical-ingredient-summary` in the actual DOM).

- [ ] **Step 2: Update all "Add" buttons to pill style**

In `_editor_frame.html.erb`, replace the Add Step button:

```erb
        <button type="button" class="btn-pill"
                data-action="click->recipe-graphical#addStep">+ Add Step</button>
```

In `_graphical_editor.html.erb`, make the same replacement (line 72).

In `menu/_quickbites_editor_frame.html.erb`, replace the Add Category button
(line 24) to use `btn-pill` instead of `graphical-btn--add-step`.

- [ ] **Step 3: Remove unused `buildButton` and CSS**

After Tasks 1-5, `buildButton()` is no longer called anywhere. Remove it from
`dom_builders.js` and update the imports in `graphical_editor_utils.js` (which
now only imports `buildIconButton` and `buildPillButton`).

In `editor.css`, remove these now-orphaned rules:
- `.graphical-btn` and `.graphical-btn:hover` and `.graphical-btn:focus-visible`
- `.graphical-btn-danger` and `.graphical-btn-danger:hover`

The classes `graphical-btn--icon`, `graphical-btn--small`, and
`graphical-btn--add-step` never had CSS rules — they were just class names
applied by JS/ERB with no corresponding selectors. No CSS to remove for those.

- [ ] **Step 4: Update header comment in `graphical_editor_utils.js`**

Update the comment to reflect the new imports:

```javascript
/**
 * Shared utilities for graphical list editors. Pure functions for accordion
 * behavior, collection management, and card DOM construction. Used by both
 * recipe_graphical_controller and quickbites_graphical_controller to avoid
 * duplicating identical DOM-building and list-manipulation patterns.
 *
 * - recipe_graphical_controller: recipe step/ingredient editing
 * - quickbites_graphical_controller: category/item editing
 * - dom_builders: low-level element factories (buildIconButton, buildPillButton, buildInput)
 */
```

- [ ] **Step 5: Build and run tests**

Run: `npm run build && bundle exec rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/editor.css app/views/recipes/_editor_frame.html.erb
git commit -m "Subtle ingredient counts and pill-style Add Step button"
```

### Task 7: Final cleanup and visual verification

**Files:**
- Modify: `app/assets/stylesheets/editor.css` (if cleanup needed)
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

- [ ] **Step 1: Run the html_safe lint**

Run: `bundle exec rake lint:html_safe`
Expected: Passes. If line number shifts broke the allowlist, update it.

- [ ] **Step 2: Run full lint and test suite**

Run: `bundle exec rake`
Expected: 0 RuboCop offenses, all tests pass.

- [ ] **Step 3: Visual verification**

Start the dev server (`bin/dev`), open a recipe editor, and verify:
1. Serves/Makes fields are compact (~5.5rem wide)
2. Category dropdown stays visible when "New category..." is selected
3. New category input appears in a row below with "cancel" link
4. Tag input has a visible "+" button
5. Step header shows ingredient count in lighter, smaller text
6. Step action buttons are round icon buttons (up/down/×)
7. Ingredient rows are cards with proportional field widths
8. "+ Add" buttons are pill-shaped
9. Quick Bites editor also has round icon buttons

- [ ] **Step 4: Commit any final cleanup**

If any cleanup was needed, commit it:

```bash
git add -A
git commit -m "Final cleanup for recipe editor visual polish"
```

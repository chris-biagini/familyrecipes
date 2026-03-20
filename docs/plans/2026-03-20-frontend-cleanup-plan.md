# Frontend Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify collapse/expand, input, and button patterns across the app; eliminate trivial controllers; document error display conventions.

**Architecture:** CSS-first approach — define new base classes, then migrate templates and JS references in feature-area batches. Each task is a self-contained commit touching one concern.

**Tech Stack:** CSS, Stimulus/JS, ERB templates, Minitest

**Spec:** `docs/plans/2026-03-20-frontend-cleanup-design.md`

---

### Task 1: Create feature branch and add CSS foundation

Add new base classes (`.input-base`, `.collapse-*`, button modifiers) to CSS
alongside existing classes. Nothing breaks — old classes still work.

**Files:**
- Modify: `app/assets/stylesheets/style.css`

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feature/frontend-cleanup
```

- [ ] **Step 2: Add `.input-base` and modifiers to `style.css`**

Add after the existing `.btn` block (around line 430), before any
component-specific sections. This is the new shared input foundation:

```css
/* ── Input base ────────────────────────────────────────────── */

.input-base {
  font-family: var(--font-body);
  font-size: 0.85rem;
  padding: 0.3rem 0.5rem;
  border: 1px solid var(--rule-faint);
  border-radius: 3px;
  background: var(--input-bg);
  color: var(--text);
  box-sizing: border-box;
  outline: none;
}

.input-base:focus {
  outline: 2px solid var(--red);
  outline-offset: -1px;
  border-color: var(--red);
}

.input-base::placeholder {
  color: var(--text-light);
}

.input-lg {
  font-size: 1rem;
  padding: 0.5rem 0.75rem;
}

.input-sm {
  width: 4.5rem;
  text-align: right;
}

.input-inline {
  padding: 0.25rem 0.4rem;
  font-size: 0.85rem;
}

.input-title {
  font-size: 1.15rem;
  font-weight: 600;
}

.input-short {
  max-width: 6rem;
}
```

- [ ] **Step 3: Add `.collapse-*` classes to `style.css`**

Add near the existing `.editor-collapse-*` block. These are the canonical
collapse classes that all collapse patterns will converge on:

```css
/* ── Collapse ──────────────────────────────────────────────── */

.collapse-header {
  list-style: none;
}

.collapse-header summary {
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  user-select: none;
}

.collapse-header summary::before {
  content: "";
  display: inline-block;
  width: 0;
  height: 0;
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
  border-left: 6px solid var(--text-light);
  transition: transform var(--duration-normal) ease;
  flex-shrink: 0;
}

.collapse-header[open] summary::before {
  transform: rotate(90deg);
}

.collapse-header summary::-webkit-details-marker {
  display: none;
}

.collapse-body {
  display: grid;
  grid-template-rows: 0fr;
  transition: grid-template-rows var(--duration-normal) ease;
}

.collapse-header[open] + .collapse-body,
.collapse-header[open] ~ .collapse-body {
  grid-template-rows: 1fr;
}

.collapse-inner {
  min-height: 0;
  overflow: hidden;
}
```

- [ ] **Step 4: Add new button modifiers to `style.css`**

Add alongside existing button definitions. New modifiers that don't exist yet:

```css
.btn-sm {
  font-size: 0.8rem;
  padding: 0.25rem 0.5rem;
  border-radius: 0.25rem;
}

.btn-link {
  all: unset;
  cursor: pointer;
  color: var(--red);
  text-decoration: underline dotted;
  font-family: var(--font-body);
}

.btn-link:hover {
  text-decoration-style: solid;
}

.btn-ghost {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-family: var(--font-body);
  font-size: 0.85rem;
  padding: 0.3rem 0.6rem;
  border: none;
  border-radius: 0.4rem;
  background: none;
  color: var(--text-light);
  cursor: pointer;
}

.btn-ghost:hover {
  color: var(--red);
  background: var(--hover-bg);
}

.btn-ghost:focus-visible {
  outline: 2px solid var(--red);
  outline-offset: 2px;
}

.btn-icon-round {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.75rem;
  height: 1.75rem;
  padding: 0;
  border: 1px solid var(--rule);
  border-radius: 50%;
  background: none;
  color: var(--text-light);
  cursor: pointer;
  font-size: 1rem;
  line-height: 1;
  transition: color var(--duration-fast) ease, border-color var(--duration-fast) ease;
}

.btn-icon-round:hover {
  color: var(--text-soft);
  border-color: var(--rule);
}

.btn-icon-round:disabled {
  opacity: 0.3;
  cursor: default;
}

.btn-icon-round.btn-danger:hover {
  color: var(--danger-color);
  border-color: var(--danger-color);
}

.btn-icon-round.btn-primary:hover {
  color: var(--red);
  border-color: var(--red);
}

.btn-icon-round.btn-icon-round-lg {
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
}

.btn-pill {
  padding: 0.25rem 0.75rem;
  border: 1px solid var(--rule);
  border-radius: 999px;
  background: transparent;
  font-size: 0.85rem;
  font-family: var(--font-body);
  color: var(--text);
  cursor: pointer;
  transition: background var(--duration-fast) ease, border-color var(--duration-fast) ease;
}

.btn-pill:hover {
  background: var(--hover-bg);
  border-color: var(--red);
}

.btn-pill.active {
  background: var(--red);
  color: white;
  border-color: var(--red);
}
```

- [ ] **Step 5: Verify nothing breaks**

```bash
rake test
npm test
```

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "Add CSS foundation: input-base, collapse, button modifiers

New base classes added alongside existing ones. No templates changed
yet — old classes still work. Resolves nothing on its own; subsequent
commits will migrate templates to use these.

Refs #261"
```

---

### Task 2: Migrate grocery on-hand collapse to `<details>` pattern

Convert the instant-hide `[hidden]` collapse to animated `<details>` + grid.
Update `grocery_ui_controller.js` to toggle `open` attr instead of `hidden`.

**Files:**
- Modify: `app/views/groceries/_shopping_list.html.erb`
- Modify: `app/assets/stylesheets/groceries.css`
- Modify: `app/javascript/controllers/grocery_ui_controller.js`
- Modify: `test/controllers/groceries_controller_test.rb`

- [ ] **Step 1: Read current files**

Read these files to understand the current structure:
- `app/views/groceries/_shopping_list.html.erb`
- `app/javascript/controllers/grocery_ui_controller.js`
- `app/assets/stylesheets/groceries.css`
- `test/controllers/groceries_controller_test.rb`

- [ ] **Step 2: Update `_shopping_list.html.erb`**

Replace the `.on-hand-divider` button + `.on-hand-items` div with a
`<details class="collapse-header">` + `.collapse-body` pattern. The
`<summary>` replaces the button. Keep all `data-*` and `aria-*` attributes
for the Stimulus controller.

Do the same for `.aisle-complete-header` sections.

- [ ] **Step 3: Update `groceries.css`**

Remove old `.on-hand-divider`, `.on-hand-items`, `.on-hand-arrow`,
`.aisle-complete-header` display/hidden rules. Replace with styling that
layers on top of the canonical `.collapse-*` classes (e.g., grocery-specific
padding, divider line, arrow rotation override if needed). The animation
comes from `.collapse-body` in `style.css`.

Keep the `.on-hand-arrow` rotation style but apply it via
`details[open] .on-hand-arrow` instead of `[aria-expanded="true"]`.

- [ ] **Step 4: Update `grocery_ui_controller.js`**

Change `bindOnHandToggle()` and related methods:
- Instead of `target.hidden = false/true`, toggle `details.open = true/false`
  on the parent `<details>` element
- `saveOnHandState()`: Read `details.open` instead of `aria-expanded`
- `restoreOnHandState()`: Set `details.open` instead of `target.hidden`
- `preserveOnHandStateOnRefresh()`: Adapt to read/write `open` attr
- Keep localStorage key format and data shape unchanged
- Update event delegation selectors if needed

- [ ] **Step 5: Update test assertions**

In `test/controllers/groceries_controller_test.rb`, update:
- `.on-hand-items[hidden]` → check that `<details>` does not have `[open]`
- `.on-hand-divider` → `summary` inside `details.collapse-header`
- `.aisle-complete-header` → `details.collapse-header` equivalent

- [ ] **Step 6: Run tests**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb
```

- [ ] **Step 7: Commit**

```bash
git add app/views/groceries/_shopping_list.html.erb \
       app/assets/stylesheets/groceries.css \
       app/javascript/controllers/grocery_ui_controller.js \
       test/controllers/groceries_controller_test.rb
git commit -m "Migrate grocery on-hand collapse to animated <details> pattern

Replaces instant [hidden] toggle with CSS grid-template-rows animation.
On-hand sections and aisle-complete headers now use the canonical
collapse-header/collapse-body classes. localStorage persistence
unchanged.

Refs #261"
```

---

### Task 3: Migrate graphical editor accordion to `<details>` pattern

Replace `accordion.js` utility with native `<details>` elements in step/category
cards. Delete `accordion.js`.

**Files:**
- Modify: `app/views/recipes/_graphical_step_card.html.erb`
- Modify: `app/views/menu/_quickbites_category_card.html.erb`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js`
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js`
- Modify: `app/assets/stylesheets/style.css` (graphical step card section)
- Delete: `app/javascript/utilities/accordion.js`

- [ ] **Step 1: Read current files**

Read all files listed above plus the current `accordion.js` to understand
how toggle/expand/collapse functions are called.

- [ ] **Step 2: Update `_graphical_step_card.html.erb`**

Replace the structure:
- `.graphical-step-header` div → `<details class="collapse-header graphical-step-card">` with `<summary>` containing the header content
- `.graphical-step-body[hidden]` → `.collapse-body > .collapse-inner` sibling
- Remove the `.graphical-step-toggle` button — `<summary>` handles the click
- Keep the toggle icon as a CSS `::before` on `<summary>` (comes from `.collapse-header`)
- First step should have `open` attribute by default

- [ ] **Step 3: Update `_quickbites_category_card.html.erb`**

Same structural migration as step cards. Category header becomes `<summary>`,
body wraps in `.collapse-body > .collapse-inner`.

- [ ] **Step 4: Update `recipe_graphical_controller.js`**

- Remove `import { toggleAccordionItem, expandAccordionItem, ... } from "../utilities/accordion"`
- Replace all `toggleAccordionItem(container, index)` calls with toggling
  `details.open` on the appropriate `<details>` element
- Replace `expandAccordionItem(container, index)` (first-open on init) with
  setting `details.open = true` on the first card
- Replace `collapseAllAccordionItems(container)` with
  `container.querySelectorAll("details[open]").forEach(d => d.open = false)`
- Remove `buildToggleButton()` usage from DOM construction code — the
  `<summary>` is the toggle target now
- When building new cards dynamically (addStep), create `<details>` +
  `<summary>` + `.collapse-body > .collapse-inner` structure instead of
  `.graphical-step-header` + `.graphical-step-body[hidden]`

- [ ] **Step 5: Update `quickbites_graphical_controller.js`**

Same changes as recipe controller: remove accordion import, replace
accordion function calls with `details.open` toggles, update DOM
construction for new card structure.

- [ ] **Step 6: Update CSS for graphical step cards**

In `style.css`, update the `.graphical-step-*` section:
- Remove `.graphical-step-body[hidden] { display: none }` — handled by
  `.collapse-body` grid animation
- Remove `.graphical-step-toggle` and `.graphical-step-toggle-icon` styles
- Keep `.graphical-step-card` container styling (border, margin, etc.)
- Keep `.graphical-step-header` content styling (padding, font, etc.) but
  apply it to `summary` within the card's `<details>`
- The card's collapse animation comes from the shared `.collapse-body` class

- [ ] **Step 7: Delete `accordion.js`**

```bash
rm app/javascript/utilities/accordion.js
```

- [ ] **Step 8: Run tests**

```bash
rake test
npm test
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Migrate graphical editor accordion to <details> pattern

Step and category cards now use native <details> with animated
grid-template-rows collapse. Deletes accordion.js utility.
buildToggleButton() replaced by <summary> elements.

Refs #261"
```

---

### Task 4: Rename existing collapse classes to canonical names

Rename `.editor-collapse-*` and `.availability-*` to `.collapse-*`.
Update CSS, templates, JS selectors, and test assertions.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (~15 selectors)
- Modify: `app/assets/stylesheets/menu.css` (~20 selectors)
- Modify: `app/views/ingredients/_editor_form.html.erb` (7 sections × 4 classes)
- Modify: `app/views/menu/_recipe_selector.html.erb` (4 class refs)
- Modify: `app/javascript/controllers/menu_controller.js` (2 selectors)
- Modify: `test/controllers/ingredients_controller_test.rb` (3 assertions)
- Modify: `test/controllers/menu_controller_test.rb` (2 assertions)

- [ ] **Step 1: Read all files to identify exact rename targets**

- [ ] **Step 2: Rename in `style.css`**

Find-and-replace:
- `.editor-collapse-header` → `.collapse-header` (but only the ingredient
  editor specific selectors — the canonical `.collapse-header` base is
  already defined in Task 1)
- `.editor-collapse-body` → `.collapse-body`
- `.editor-collapse-inner` → `.collapse-inner`
- `.editor-collapse` (container) → `.collapse`
- Remove duplicate rules that are now covered by the canonical base classes.
  Keep only ingredient-editor-specific overrides (e.g., padding, colors).

- [ ] **Step 3: Rename in `menu.css`**

Find-and-replace:
- `.availability-detail` → `.collapse-header`
- `.availability-ingredients` → `.collapse-body`
- `.availability-ingredients-inner` → `.collapse-inner`
- Use general sibling selector (`~`) for `.collapse-header[open] ~ .collapse-body`
  since there are intervening elements in the menu HTML.
- Keep menu-specific styling (opacity, badges, etc.) but apply to new class
  names.

- [ ] **Step 4: Rename in ERB templates**

Update `_editor_form.html.erb` — all 7 collapse sections:
- `editor-collapse-header` → `collapse-header`
- `editor-collapse-body` → `collapse-body`
- `editor-collapse-inner` → `collapse-inner`
- `editor-collapse` (container div) → `collapse`

Update `_recipe_selector.html.erb`:
- `availability-detail` → `collapse-header`
- `availability-ingredients` → `collapse-body`
- `availability-ingredients-inner` → `collapse-inner`

- [ ] **Step 5: Update JS selectors in `menu_controller.js`**

- `details.availability-detail[open]` → `details.collapse-header[open]`
- `details.availability-detail summary` → `details.collapse-header summary`

But wait — this is the menu page, and there may be other `details.collapse-header`
elements elsewhere on the page after the migration. Scope the selectors to the
recipe selector container. Check the current selectors to see if they're already
scoped (via `this.element.querySelectorAll`). If so, the rename is safe.

- [ ] **Step 6: Update test assertions**

`ingredients_controller_test.rb`:
- `details.editor-collapse-header` → `details.collapse-header`

`menu_controller_test.rb`:
- `details.availability-detail` → `details.collapse-header`

- [ ] **Step 7: Run tests**

```bash
rake test
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Rename editor-collapse and availability classes to collapse-*

All collapse patterns now use the canonical .collapse-header,
.collapse-body, .collapse-inner naming. Component-specific overrides
remain for ingredient editor and menu availability styling.

Refs #261"
```

---

### Task 5: Consolidate input styles

Replace all old input classes with `.input-base` + modifiers in CSS,
templates, JS, and tests.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (remove ~12 old input classes)
- Modify: `app/assets/stylesheets/groceries.css` (`#custom-input` styles)
- Modify: `app/views/ingredients/_editor_form.html.erb`
- Modify: `app/views/ingredients/_portion_row.html.erb`
- Modify: `app/views/ingredients/index.html.erb`
- Modify: `app/views/settings/_editor_frame.html.erb`
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Modify: `app/views/recipes/_editor_frame.html.erb`
- Modify: `app/views/recipes/_graphical_editor.html.erb`
- Modify: `app/views/recipes/_graphical_step_card.html.erb`
- Modify: `app/views/menu/_quickbites_category_card.html.erb`
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/groceries/_custom_items.html.erb`
- Modify: `app/javascript/utilities/dom_builders.js`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js`
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`
- Modify: `app/javascript/utilities/ordered_list_editor_utils.js`
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Read all template and JS files with input class references**

- [ ] **Step 2: Update `dom_builders.js`**

Update `buildInput()` to prepend `input-base` to the className:
```javascript
// Before
input.className = className
// After
input.className = `input-base ${className}`
```

Same for `buildTextareaGroup()`.

- [ ] **Step 3: Update ERB templates — graphical editor inputs**

In `_editor_frame.html.erb`, `_graphical_editor.html.erb`,
`_graphical_step_card.html.erb`, `_quickbites_category_card.html.erb`:
- `graphical-input` → `input-base`
- `graphical-input-title` → `input-base input-title`
- `graphical-input--short` → `input-base input-short`
- `graphical-textarea` → `input-base` (keep textarea-specific attributes)
- `graphical-select` → `input-base`

- [ ] **Step 4: Update ERB templates — other inputs**

- `_editor_form.html.erb`: `nf-input` → `input-base input-sm`,
  `field-narrow` → `input-base input-sm`, `field-unit-select` → `input-base`,
  `portion-name-input` → `input-base`, `usda-search-input` → `input-base input-lg`
- `_portion_row.html.erb`: `portion-name-input` → `input-base`,
  `portion-grams-input` → `input-base input-sm`
- `index.html.erb`: `ingredients-search` → `input-base input-lg`
- `_editor_frame.html.erb` (settings): `settings-input` → `input-base input-lg`
- `_recipe_content.html.erb`: `scale-input` → `input-base input-sm scale-input`
  (keep `scale-input` for center-alignment override)
- `show.html.erb` (homepage): `aisle-add-input` → `input-base input-inline`
- `show.html.erb` (groceries): `aisle-add-input` → `input-base input-inline`
- `_custom_items.html.erb`: `id="custom-input"` keeps the id,
  add `class="input-base input-lg"`, keep explicit `font-size: 16px` style

- [ ] **Step 5: Update JS controllers with hardcoded input classes**

In `recipe_graphical_controller.js` and `quickbites_graphical_controller.js`:
- Any direct class assignments like `el.className = "graphical-input"` →
  `el.className = "input-base"`

In `nutrition_editor_controller.js`:
- `nf-input` → `input-base input-sm`
- `field-narrow` → `input-base input-sm`

In `ordered_list_editor_utils.js`:
- `aisle-input` → `input-base input-inline`
- `aisle-select` → `input-base input-inline`
- `aisle-add-input` → `input-base input-inline`

- [ ] **Step 6: Clean up old input CSS**

In `style.css`, remove old class definitions that are now fully replaced by
`.input-base` + modifiers:
- `.graphical-input`, `.graphical-input-title`, `.graphical-input--short`
- `.graphical-textarea`, `.graphical-select`
- `.settings-input`
- `.ingredients-search`
- `.usda-search-input`
- `.nf-input`, `.field-narrow`, `.field-unit-select`
- `.portion-name-input`, `.portion-grams-input`
- `.aisle-add-input`, `.aisle-input`, `.aisle-select`

Keep only component-specific overrides that aren't covered by the base +
modifiers (e.g., `.scale-input` center alignment, textarea `resize`/`min-height`/
`max-height`, number input spinner hiding).

In `groceries.css`, update `#custom-input` to layer on top of `.input-base .input-lg`
(keep the iOS `font-size: 16px` as an explicit override).

- [ ] **Step 7: Update test assertions**

In `test/controllers/recipes_controller_test.rb`:
- `.scale-input` → check for `input.input-sm` or keep `.scale-input` if that
  class is preserved as an override

- [ ] **Step 8: Run tests**

```bash
rake test
npm test
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Consolidate input styles into .input-base + modifiers

Replaces 15+ one-off input classes with shared .input-base foundation.
Modifiers: .input-lg (search/settings), .input-sm (numeric), .input-inline
(aisle editor), .input-title, .input-short. dom_builders.js auto-prepends
input-base. Explicit 16px kept on grocery custom input for iOS.

Refs #261"
```

---

### Task 6: Consolidate button styles

Replace old button classes with the new modifier system in CSS, templates,
JS, and tests.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (remove/rename ~10 old button classes)
- Modify: `app/assets/stylesheets/menu.css` (dinner picker buttons)
- Modify: `app/assets/stylesheets/groceries.css` (`#custom-add`)
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/views/menu/show.html.erb`
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/groceries/_custom_items.html.erb`
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Modify: `app/views/recipes/_nutrition_table.html.erb`
- Modify: `app/views/ingredients/_editor_form.html.erb`
- Modify: `app/views/ingredients/_summary_bar.html.erb`
- Modify: `app/javascript/controllers/dinner_picker_controller.js`
- Modify: `app/javascript/utilities/ordered_list_editor_utils.js`
- Modify: `app/javascript/controllers/ordered_list_editor_controller.js`
- Modify: `test/controllers/ingredients_controller_test.rb`
- Modify: `test/controllers/recipes_controller_test.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

- [ ] **Step 1: Read all template and JS files with button class references**

- [ ] **Step 2: Update ERB templates — simple renames**

- `.btn-small` → `.btn-sm` everywhere
- `.btn-inline-link` → `.btn-link` everywhere
- `.edit-toggle` → `.btn-ghost` everywhere
- `.filter-pill` → `.btn-pill` everywhere

Specific locations:
- `_editor_form.html.erb`: `btn-small` → `btn-sm`
- `_nutrition_table.html.erb`: `btn-inline-link` → `btn-link`
- `homepage/show.html.erb`: `edit-toggle` → `btn-ghost` (4 locations)
- `groceries/show.html.erb`: `edit-toggle` → `btn-ghost`
- `menu/show.html.erb`: `edit-toggle` → `btn-ghost` (2 locations)
- `_recipe_content.html.erb`: `edit-toggle` → `btn-ghost`
- `_summary_bar.html.erb`: `filter-pill` → `btn-pill` (7 locations)

- [ ] **Step 3: Update ERB templates — button modifier combos**

- `_recipe_content.html.erb`:
  - `.scale-preset` → `btn btn-sm scale-preset` (keep `scale-preset` for
    pop animation and `.active` state)
  - `.scale-reset` → `btn-ghost btn-sm scale-reset` (keep `scale-reset` for
    the `[hidden]` layout-reservation override)
- `homepage/show.html.erb`:
  - `.aisle-btn .aisle-btn--add` → `btn-icon-round btn-icon-round-lg btn-primary`
  - `.aisle-btn .aisle-btn--delete` → `btn-icon-round btn-danger`
  - `.aisle-btn .aisle-btn--undo` → `btn-icon-round btn-primary`
- `groceries/show.html.erb`:
  - `.aisle-btn .aisle-btn--add` → `btn-icon-round btn-icon-round-lg btn-primary`
- `_custom_items.html.erb`:
  - `#custom-add` → add `class="btn-icon-round btn-icon-round-lg btn-primary"`

- [ ] **Step 4: Update JS controllers — button classes**

`dinner_picker_controller.js`:
- `dinner-picker-spin-btn` → `btn btn-primary`
- `result-accept-btn` → `btn btn-primary`
- `result-retry-btn` → `btn`

`ordered_list_editor_utils.js`:
- `aisle-btn` → `btn-icon-round`
- `aisle-btn--delete` → `btn-icon-round btn-danger`
- `aisle-btn--undo` → `btn-icon-round btn-primary`
- `aisle-btn--add` → `btn-icon-round btn-icon-round-lg btn-primary`
- Update any selectors that query by these classes

`ordered_list_editor_controller.js`:
- Update selectors if they reference `.aisle-btn`

- [ ] **Step 5: Clean up old button CSS**

In `style.css`, remove old class definitions:
- `.btn-small` (replaced by `.btn-sm`)
- `.btn-inline-link` (replaced by `.btn-link`)
- `.edit-toggle` (replaced by `.btn-ghost`)
- `.aisle-btn`, `.aisle-btn--delete`, `.aisle-btn--undo`, `.aisle-btn--add`
  (replaced by `.btn-icon-round` + color modifiers)
- `.filter-pill` (replaced by `.btn-pill`)

Trim `.scale-preset` and `.scale-reset` to only the component-specific
overrides (pop animation, active state, hidden layout reservation). Base
sizing comes from `.btn-sm` and `.btn-ghost`.

In `menu.css`, remove:
- `.dinner-picker-spin-btn` (replaced by `.btn .btn-primary`)
- `.result-accept-btn` (replaced by `.btn .btn-primary`)
- `.result-retry-btn` (replaced by `.btn`)

In `groceries.css`, remove:
- `#custom-add` styles (replaced by `.btn-icon-round`)

- [ ] **Step 6: Update test assertions**

`ingredients_controller_test.rb`:
- `button.filter-pill` → `button.btn-pill`

`recipes_controller_test.rb`:
- `.scale-preset` → `.scale-preset` (class kept as override, no test change)

`groceries_controller_test.rb`:
- Update any assertions on `.aisle-btn` classes

- [ ] **Step 7: Run tests**

```bash
rake test
npm test
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Consolidate button styles into unified modifier system

Renames: .btn-small → .btn-sm, .btn-inline-link → .btn-link,
.edit-toggle → .btn-ghost, .filter-pill → .btn-pill.
New: .btn-icon-round (circular), .btn-pill. Dinner picker buttons
now use standard .btn / .btn-primary. Scale preset/reset keep
component-specific overrides for animation and layout reservation.

Refs #261"
```

---

### Task 7: Delete trivial controllers and document error patterns

Delete `export_controller.js`, remove its registration, replace with
`onclick` confirm. Add error display convention comments.

**Files:**
- Delete: `app/javascript/controllers/export_controller.js`
- Modify: `app/javascript/application.js`
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/javascript/utilities/editor_utils.js`
- Modify: `app/javascript/utilities/notify.js`

- [ ] **Step 1: Read current files**

- [ ] **Step 2: Update export link in `homepage/show.html.erb`**

Replace:
```erb
data-controller="export" data-action="click->export#confirm"
```
With:
```erb
onclick="return confirm('Export all recipes and data as a ZIP file?')"
```
Keep `data-turbo="false"` and `download` attribute.

- [ ] **Step 3: Delete `export_controller.js`**

```bash
rm app/javascript/controllers/export_controller.js
```

- [ ] **Step 4: Remove registration from `application.js`**

Remove the import line and the `application.register("export", ...)` line.

- [ ] **Step 5: Add error display convention comments**

In `editor_utils.js`, add a brief note near the top (after the existing
architectural header comment) documenting when to use inline errors:
- Inline errors (`showErrors`): for dialog/form validation, contextual,
  cleared on re-open

In `notify.js`, add a brief note documenting when to use toasts:
- Toasts (`show`): for page-level mutations, ephemeral, auto-dismiss

- [ ] **Step 6: Run tests**

```bash
rake test
npm test
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Delete export_controller, document error display conventions

Export confirmation replaced with onclick confirm (data-turbo=false
makes data-turbo-confirm inert). Added convention comments to
editor_utils.js and notify.js explaining when to use inline errors
vs toasts.

Refs #261"
```

---

### Task 8: Final cleanup, lint, and full test run

Remove any dead CSS, verify lint passes, run full test suite.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (organize button section)
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

- [ ] **Step 1: Verify no orphaned CSS classes remain**

Grep for any old class names that should have been removed. Search templates
and JS for any remaining references to deleted classes.

- [ ] **Step 2: Organize button section in `style.css`**

Group all button styles together: base → color → size → shape → state.
Move any scattered button definitions into this section.

- [ ] **Step 3: Run lint**

```bash
bundle exec rubocop
rake lint:html_safe
```

Fix any issues (likely `html_safe_allowlist.yml` line number shifts).

- [ ] **Step 4: Run full test suite**

```bash
rake test
npm test
```

- [ ] **Step 5: Commit any cleanup**

```bash
git add -A
git commit -m "Final cleanup: organize button CSS, fix lint

Refs #261"
```

---

### Task 9: Update CLAUDE.md

Update any CLAUDE.md references to old class names or patterns.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read CLAUDE.md for stale references**

Check for mentions of:
- `editor-collapse-*` classes
- `accordion.js`
- `export_controller`
- Old button/input class names

- [ ] **Step 2: Update references**

Update any mentions to reflect the new canonical patterns.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md for unified frontend patterns

Refs #261"
```

---

### Task 10: Open PR

- [ ] **Step 1: Push branch and create PR**

```bash
git push -u origin feature/frontend-cleanup
gh pr create --title "Frontend cleanup: unify interaction patterns (#261)" \
  --body "$(cat <<'EOF'
## Summary
- Unified all collapse/expand patterns on animated `<details>` + `grid-template-rows`
- Extracted `.input-base` + modifiers replacing 15+ one-off input classes
- Consolidated buttons into `.btn` modifier system (`.btn-sm`, `.btn-ghost`, `.btn-icon-round`, `.btn-pill`, `.btn-link`)
- Deleted `accordion.js` and `export_controller.js`
- Documented error display conventions (inline vs toast)

## Test plan
- [ ] All existing tests pass (`rake test && npm test`)
- [ ] Manual verification: recipe page (scale panel, edit toggle, graphical editor)
- [ ] Manual verification: menu page (availability collapse, dinner picker, Quick Bites editor)
- [ ] Manual verification: groceries page (on-hand collapse, custom items, aisle editor)
- [ ] Manual verification: ingredients page (search, filter pills, nutrition editor collapse)
- [ ] Manual verification: settings dialog (input fields, reveal toggle)
- [ ] Manual verification: homepage (edit toggles, category/tag editors, export)

Resolves #261

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

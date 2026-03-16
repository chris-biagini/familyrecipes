# Graphical Editor Shared Utilities — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract duplicated DOM builder and accordion helpers from two graphical editor controllers into shared utility modules.

**Architecture:** Two new plain ES modules in `app/javascript/utilities/` — `dom_builders.js` (four DOM factory functions) and `accordion.js` (three accordion state functions + toggle button builder). Both graphical controllers import these instead of maintaining local copies. Pure extraction, no behavioral changes.

**Tech Stack:** Vanilla JS (ES modules), Stimulus controllers, esbuild bundling.

**Spec:** `docs/plans/2026-03-16-graphical-editor-utilities-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/javascript/utilities/dom_builders.js` | Create | `buildButton`, `buildInput`, `buildFieldGroup`, `buildTextareaGroup` |
| `app/javascript/utilities/accordion.js` | Create | `toggleAccordionItem`, `expandAccordionItem`, `collapseAllAccordionItems`, `buildToggleButton` |
| `app/javascript/controllers/recipe_graphical_controller.js` | Modify | Remove 8 local methods, import from both utility modules |
| `app/javascript/controllers/quickbites_graphical_controller.js` | Modify | Remove 7 local methods, import from both utility modules |

---

## Chunk 1: Create utility modules and refactor controllers

### Task 1: Create `dom_builders.js`

**Files:**
- Create: `app/javascript/utilities/dom_builders.js`

- [ ] **Step 1: Create the module with all four functions**

```js
/**
 * Shared DOM factory functions for graphical editors. Pure element
 * creators with no Stimulus or framework coupling. Used by both
 * recipe_graphical_controller and quickbites_graphical_controller.
 *
 * - recipe_graphical_controller: recipe step/ingredient editing
 * - quickbites_graphical_controller: category/item editing
 */

export function buildButton(text, onClick, className) {
  const btn = document.createElement("button")
  btn.type = "button"
  if (className) btn.className = className
  btn.textContent = text
  btn.addEventListener("click", onClick)
  return btn
}

export function buildInput(placeholder, value, onChange, className) {
  const input = document.createElement("input")
  input.type = "text"
  input.placeholder = placeholder
  input.value = value
  if (className) input.className = className
  input.addEventListener("input", () => onChange(input.value))
  return input
}

export function buildFieldGroup(labelText, type, value, onChange) {
  const group = document.createElement("div")
  group.className = "graphical-field-group"

  const label = document.createElement("label")
  label.textContent = labelText
  group.appendChild(label)

  const input = document.createElement("input")
  input.type = type
  input.value = value
  input.addEventListener("input", () => onChange(input.value))
  group.appendChild(input)

  return group
}

export function buildTextareaGroup(labelText, value, onChange) {
  const group = document.createElement("div")
  group.className = "graphical-field-group"

  const label = document.createElement("label")
  label.textContent = labelText
  group.appendChild(label)

  const textarea = document.createElement("textarea")
  textarea.value = value
  textarea.rows = 4
  textarea.addEventListener("input", () => onChange(textarea.value))
  group.appendChild(textarea)

  return group
}
```

- [ ] **Step 2: Verify esbuild picks it up**

Run: `npm run build`
Expected: Build succeeds (module is not imported yet, but no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add app/javascript/utilities/dom_builders.js
git commit -m "feat: extract shared DOM builder helpers from graphical editors"
```

---

### Task 2: Create `accordion.js`

**Files:**
- Create: `app/javascript/utilities/accordion.js`

- [ ] **Step 1: Create the module with all four functions**

```js
/**
 * Accordion collapse/expand behavior for graphical editor cards.
 * Operates on a container element whose direct children are cards,
 * each containing `.graphical-step-body` (collapsible) and
 * `.graphical-step-toggle-icon` (▶/▼ indicator). Pure DOM
 * manipulation, no Stimulus coupling.
 *
 * - recipe_graphical_controller: step cards
 * - quickbites_graphical_controller: category cards
 */

export function toggleAccordionItem(container, index) {
  const card = container.children[index]
  if (!card) return
  const body = card.querySelector(".graphical-step-body")
  const icon = card.querySelector(".graphical-step-toggle-icon")
  if (!body) return

  const isHidden = body.hidden
  body.hidden = !isHidden
  if (icon) icon.textContent = isHidden ? "\u25BC" : "\u25B6"
}

export function expandAccordionItem(container, index) {
  collapseAllAccordionItems(container)
  toggleAccordionItem(container, index)
}

export function collapseAllAccordionItems(container) {
  const cards = container.children
  for (let i = 0; i < cards.length; i++) {
    const body = cards[i].querySelector(".graphical-step-body")
    const icon = cards[i].querySelector(".graphical-step-toggle-icon")
    if (body) body.hidden = true
    if (icon) icon.textContent = "\u25B6"
  }
}

export function buildToggleButton(onToggle) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.className = "graphical-step-toggle"
  const icon = document.createElement("span")
  icon.className = "graphical-step-toggle-icon"
  icon.textContent = "\u25B6"
  btn.appendChild(icon)
  btn.addEventListener("click", onToggle)
  return btn
}
```

- [ ] **Step 2: Verify esbuild picks it up**

Run: `npm run build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/utilities/accordion.js
git commit -m "feat: extract shared accordion behavior from graphical editors"
```

---

### Task 3: Refactor `recipe_graphical_controller.js`

**Files:**
- Modify: `app/javascript/controllers/recipe_graphical_controller.js`

- [ ] **Step 1: Add imports at top of file**

Add after the Stimulus import (line 1):

```js
import { buildButton, buildInput, buildFieldGroup, buildTextareaGroup } from "../utilities/dom_builders"
import { toggleAccordionItem, expandAccordionItem, collapseAllAccordionItems, buildToggleButton } from "../utilities/accordion"
```

- [ ] **Step 2: Replace accordion method calls with utility calls**

Replace these call sites throughout the controller:

| Old call | New call |
|----------|----------|
| `this.toggleStep(index)` | `toggleAccordionItem(this.stepsContainerTarget, index)` |
| `this.expandStep(index)` | `expandAccordionItem(this.stepsContainerTarget, index)` |
| `this.collapseAllSteps()` | `collapseAllAccordionItems(this.stepsContainerTarget)` |

Call sites to update:
- `loadSteps` (line 142): `this.expandStep(0)` → `expandAccordionItem(this.stepsContainerTarget, 0)`
- `moveStep` (line 158): `this.expandStep(target)` → `expandAccordionItem(this.stepsContainerTarget, target)`
- `buildStepHeader` (line 254): `this.toggleStep(index)` → `toggleAccordionItem(this.stepsContainerTarget, index)`
- `buildToggleButton` call in `buildStepHeader` (line 257): `this.buildToggleButton(index)` → `buildToggleButton(() => toggleAccordionItem(this.stepsContainerTarget, index))`

- [ ] **Step 3: Replace DOM builder calls with utility imports**

Replace `this.buildButton(...)` with `buildButton(...)`, `this.buildInput(...)` with `buildInput(...)`, `this.buildFieldGroup(...)` with `buildFieldGroup(...)`, `this.buildTextareaGroup(...)` with `buildTextareaGroup(...)` throughout the controller. These are used in:

- `buildStepActions` (lines 295-297): three `this.buildButton` calls
- `buildStepBody` (lines 306, 313): `this.buildFieldGroup` and `this.buildTextareaGroup`
- `buildIngredientRow` (lines 359-375): three `this.buildInput` calls, three `this.buildButton` calls
- `buildIngredientsSection` (line 340): one `this.buildButton` call

- [ ] **Step 4: Delete the 10 local methods that are now imported**

Delete these methods from the controller class:
- `toggleStep` (lines 171-181)
- `expandStep` (lines 183-186)
- `collapseAllSteps` (lines 188-196)
- `buildToggleButton` (lines 264-273)
- `buildButton` (lines 445-452)
- `buildInput` (lines 454-461)
- `buildFieldGroup` (lines 464-478)
- `buildTextareaGroup` (lines 481-496)

Keep `findExpandedIndex` — only this controller uses it.

- [ ] **Step 5: Verify build and tests**

Run: `npm run build && rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/recipe_graphical_controller.js
git commit -m "refactor: recipe graphical controller uses shared utilities"
```

---

### Task 4: Refactor `quickbites_graphical_controller.js`

**Files:**
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js`

- [ ] **Step 1: Add imports at top of file**

Add after the Stimulus import (line 1):

```js
import { buildButton, buildInput, buildFieldGroup } from "../utilities/dom_builders"
import { toggleAccordionItem, expandAccordionItem, collapseAllAccordionItems, buildToggleButton } from "../utilities/accordion"
```

Note: no `buildTextareaGroup` import — quickbites doesn't use it.

- [ ] **Step 2: Replace accordion method calls with utility calls**

| Old call | New call |
|----------|----------|
| `this.toggleCategory(index)` | `toggleAccordionItem(this.categoriesContainerTarget, index)` |
| `this.expandCategory(index)` | `expandAccordionItem(this.categoriesContainerTarget, index)` |
| `this.collapseAllCategories()` | `collapseAllAccordionItems(this.categoriesContainerTarget)` |

Call sites to update:
- `loadStructure` (line 26): `this.expandCategory(0)` → `expandAccordionItem(this.categoriesContainerTarget, 0)`
- `addCategory` (line 40): `this.expandCategory(this.categories.length - 1)` → `expandAccordionItem(this.categoriesContainerTarget, this.categories.length - 1)`
- `moveCategory` (line 57): `this.expandCategory(target)` → `expandAccordionItem(this.categoriesContainerTarget, target)`
- `buildCategoryHeader` (line 177): `this.toggleCategory(index)` → `toggleAccordionItem(this.categoriesContainerTarget, index)`
- `buildToggleButton` call in `buildCategoryHeader` (line 180): `this.buildToggleButton(index)` → `buildToggleButton(() => toggleAccordionItem(this.categoriesContainerTarget, index))`

- [ ] **Step 3: Replace DOM builder calls with utility imports**

Replace `this.buildButton(...)` with `buildButton(...)`, `this.buildInput(...)` with `buildInput(...)`, `this.buildFieldGroup(...)` with `buildFieldGroup(...)` throughout the controller. Used in:

- `buildCategoryActions` (lines 218-220): three `this.buildButton` calls
- `buildCategoryBody` (line 229): one `this.buildFieldGroup` call
- `buildItemsSection` (line 258): one `this.buildButton` call
- `buildItemRow` (lines 276-289): two `this.buildInput` calls, three `this.buildButton` calls

- [ ] **Step 4: Delete the 8 local methods that are now imported**

Delete these methods from the controller class:
- `toggleCategory` (lines 69-79)
- `expandCategory` (lines 81-84)
- `collapseAllCategories` (lines 86-93)
- `buildToggleButton` (lines 187-197)
- `buildButton` (lines 304-311)
- `buildInput` (lines 313-320)
- `buildFieldGroup` (lines 322-338)

- [ ] **Step 5: Verify build and tests**

Run: `npm run build && rake test`
Expected: Build succeeds, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/quickbites_graphical_controller.js
git commit -m "refactor: quickbites graphical controller uses shared utilities"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run full test suite**

Run: `rake`
Expected: Lint passes, all tests pass.

- [ ] **Step 2: Verify line count reduction**

Run: `wc -l app/javascript/controllers/recipe_graphical_controller.js app/javascript/controllers/quickbites_graphical_controller.js app/javascript/utilities/dom_builders.js app/javascript/utilities/accordion.js`

Expected: recipe controller ~390 lines (was 497), quickbites controller ~230 lines (was 339), dom_builders ~50 lines, accordion ~40 lines. Net reduction ~120 lines of duplicated code.

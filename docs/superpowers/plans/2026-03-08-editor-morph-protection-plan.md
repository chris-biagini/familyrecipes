# Editor Morph Protection & Cleanup — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix #199 (Quick Bites editor bugs) by protecting all editor dialogs from Turbo morph interference, extracting a shared highlight overlay utility, and merging the duplicate ordered-list editor controllers.

**Architecture:** Add `data-turbo-permanent` + stable `id` to every `<dialog>` so Turbo morphs skip open dialogs. Extract the duplicated overlay/highlight/auto-dash code from quickbites and recipe editor controllers into a shared `HighlightOverlay` class. Merge the near-identical aisle-order and category-order editor controllers into one `ordered-list-editor` controller parameterized by Stimulus values.

**Tech Stack:** Stimulus, Turbo Drive (morph), importmap-rails, Minitest

---

## Milestone 1: Morph Protection (fixes #199)

### Task 1: Add `data-turbo-permanent` to shared editor dialog partial

**Files:**
- Modify: `app/views/shared/_editor_dialog.html.erb`
- Modify: `app/views/menu/show.html.erb`

**Step 1: Update the shared partial**

In `app/views/shared/_editor_dialog.html.erb`, change the locals comment to require `id` and add `data-turbo-permanent` to the dialog tag.

Change line 1 from:
```erb
<%# locals: (title:, id: nil, dialog_data: {}, footer_extra: nil, extra_data: {}) %>
```
to:
```erb
<%# locals: (title:, id:, dialog_data: {}, footer_extra: nil, extra_data: {}) %>
```

This makes `id` required (no default). All callers already pass it except Quick Bites.

Add `data: { turbo_permanent: true }` to the `tag.dialog` call. The existing `data:` hash uses `editor_*` keys. Add `turbo_permanent: true` into the same hash, before the `.compact.merge(extra_data)` chain. The final tag should look like:

```erb
<%= tag.dialog id: id,
    class: 'editor-dialog',
    data: {
      turbo_permanent: '',
      controller: ['editor', dialog_data[:extra_controllers]].compact.join(' '),
      ...existing keys...
    }.compact.merge(extra_data) do %>
```

Note: `turbo_permanent: ''` renders as `data-turbo-permanent=""` which is correct — it's a boolean attribute.

**Step 2: Add `id` to Quick Bites dialog**

In `app/views/menu/show.html.erb`, add `id: 'quickbites-editor'` to the render call (around line 41):

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit QuickBites',
              id: 'quickbites-editor',
              dialog_data: { ... } } do %>
```

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

All tests should pass — no Ruby logic changed, just HTML attributes.

**Step 4: Commit**

```bash
git add app/views/shared/_editor_dialog.html.erb app/views/menu/show.html.erb
git commit -m "fix: add data-turbo-permanent to shared editor dialogs (#199)

Turbo morph from broadcast_update was resetting open dialogs,
causing Quick Bites content to appear to revert after save."
```

### Task 2: Add morph protection to standalone dialogs

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/homepage/show.html.erb`

**Step 1: Update aisle order dialog**

In `app/views/groceries/show.html.erb`, add `id` and `data-turbo-permanent` to the aisle order `<dialog>` tag (around line 37):

```erb
<dialog id="aisle-order-editor" class="editor-dialog" data-turbo-permanent
        data-controller="aisle-order-editor"
        ...>
```

**Step 2: Update category order dialog**

In `app/views/homepage/show.html.erb`, add `id` and `data-turbo-permanent` to the category order `<dialog>` tag (around line 38):

```erb
<dialog id="category-order-editor" class="editor-dialog" data-turbo-permanent
        data-controller="category-order-editor"
        ...>
```

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 4: Commit**

```bash
git add app/views/groceries/show.html.erb app/views/homepage/show.html.erb
git commit -m "fix: add data-turbo-permanent to standalone editor dialogs

Protects aisle order and category order editors from Turbo morph
interference when another client broadcasts an update."
```

### Task 3: Fix highlight on content load (disabled→enabled transition)

**Files:**
- Modify: `app/javascript/controllers/quickbites_editor_controller.js`
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

**Step 1: Update quickbites-editor MutationObserver**

In `quickbites_editor_controller.js`, the `textareaTargetConnected` method has a MutationObserver (around line 42-45). Replace:

```js
this.observer = new MutationObserver(() => {
  if (this.textarea.disabled) this.cursorInitialized = false
})
```

with:

```js
this.observer = new MutationObserver(() => {
  if (this.textarea.disabled) {
    this.cursorInitialized = false
  } else {
    this.highlight()
  }
})
```

When `openWithRemoteContent` finishes loading, it sets `disabled = false`, which triggers this observer and calls `highlight()` to render the overlay for the newly loaded content.

**Step 2: Apply the same change to recipe-editor**

In `recipe_editor_controller.js`, the identical MutationObserver block (around line 48-51). Same replacement.

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 4: Commit**

```bash
git add app/javascript/controllers/quickbites_editor_controller.js app/javascript/controllers/recipe_editor_controller.js
git commit -m "fix: highlight overlay on content load (#199)

Call highlight() when textarea transitions from disabled to enabled,
which is when openWithRemoteContent finishes loading. Fixes syntax
highlighting not appearing on second editor open."
```

---

## Milestone 2: Extract Shared Highlight Overlay

### Task 4: Create `highlight_overlay.js` utility

**Files:**
- Create: `app/javascript/utilities/highlight_overlay.js`

**Step 1: Write the shared utility**

Create `app/javascript/utilities/highlight_overlay.js`. This class encapsulates the overlay lifecycle: build, teardown, event binding, auto-dash, scroll sync, focus handling, and the MutationObserver that triggers highlight on content load.

```js
/**
 * Transparent-textarea-over-pre overlay for syntax highlighting. Layers a
 * <pre> behind a transparent <textarea> so users see colored text while
 * typing into a real textarea. Handles scroll sync, cursor initialization,
 * auto-dash on Enter, and re-highlight when content loads asynchronously.
 *
 * Consumers provide a highlightFn(text) that returns a DocumentFragment
 * with styled spans. The overlay calls it on every input and content load.
 *
 * - quickbites_editor_controller: Quick Bites line classification
 * - recipe_editor_controller: recipe markdown line classification
 * - style.css (.hl-*): overlay positioning and highlight colors
 */
export default class HighlightOverlay {
  constructor(textarea, highlightFn) {
    this.textarea = textarea
    this.highlightFn = highlightFn
    this.overlay = null
    this.cursorInitialized = false
    this.bound = {}
  }

  attach() {
    this.buildOverlay()

    this.bound.input = () => this.highlight()
    this.bound.scroll = () => this.syncScroll()
    this.bound.keydown = (e) => this.handleKeydown(e)
    this.bound.focus = () => this.handleFocus()

    this.textarea.addEventListener("input", this.bound.input)
    this.textarea.addEventListener("scroll", this.bound.scroll)
    this.textarea.addEventListener("keydown", this.bound.keydown)
    this.textarea.addEventListener("focus", this.bound.focus)

    this.observer = new MutationObserver(() => {
      if (this.textarea.disabled) {
        this.cursorInitialized = false
      } else {
        this.highlight()
      }
    })
    this.observer.observe(this.textarea, { attributes: true, attributeFilter: ["disabled"] })

    this.highlight()
  }

  detach() {
    if (!this.textarea) return

    this.textarea.removeEventListener("input", this.bound.input)
    this.textarea.removeEventListener("scroll", this.bound.scroll)
    this.textarea.removeEventListener("keydown", this.bound.keydown)
    this.textarea.removeEventListener("focus", this.bound.focus)
    this.observer?.disconnect()

    const wrapper = this.textarea.closest(".hl-wrap")
    if (wrapper?.parentNode) {
      this.textarea.classList.remove("hl-input")
      wrapper.parentNode.insertBefore(this.textarea, wrapper)
      wrapper.remove()
    } else {
      this.overlay?.remove()
    }

    this.textarea = null
    this.overlay = null
    this.bound = {}
  }

  highlight() {
    const text = this.textarea.value
    if (!text) {
      this.overlay.replaceChildren()
      return
    }

    const fragment = this.highlightFn(text)
    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))
    this.overlay.replaceChildren(fragment)
  }

  // Private

  buildOverlay() {
    const wrapper = document.createElement("div")
    wrapper.classList.add("hl-wrap")

    this.overlay = document.createElement("pre")
    this.overlay.classList.add("hl-overlay")
    this.overlay.setAttribute("aria-hidden", "true")

    this.textarea.parentNode.insertBefore(wrapper, this.textarea)
    wrapper.appendChild(this.overlay)
    wrapper.appendChild(this.textarea)
    this.textarea.classList.add("hl-input")
  }

  syncScroll() {
    this.overlay.scrollTop = this.textarea.scrollTop
    this.overlay.scrollLeft = this.textarea.scrollLeft
  }

  handleFocus() {
    this.highlight()
    if (!this.cursorInitialized) {
      this.cursorInitialized = true
      this.textarea.selectionStart = 0
      this.textarea.selectionEnd = 0
      this.textarea.scrollTop = 0
      this.overlay.scrollTop = 0
    }
  }

  handleKeydown(e) {
    if (e.key !== "Enter") return

    const { selectionStart } = this.textarea
    const text = this.textarea.value
    const lineStart = text.lastIndexOf("\n", selectionStart - 1) + 1
    const currentLine = text.slice(lineStart, selectionStart)

    if (/^- $/.test(currentLine.trimStart())) {
      e.preventDefault()
      this.textarea.setRangeText("\n", lineStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
      return
    }

    if (/^- .+/.test(currentLine.trimStart())) {
      e.preventDefault()
      this.textarea.setRangeText("\n- ", selectionStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
```

**Step 2: Run lint**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

No imports have changed yet, so tests pass trivially. The importmap auto-pins utilities.

**Step 3: Commit**

```bash
git add app/javascript/utilities/highlight_overlay.js
git commit -m "feat: extract shared HighlightOverlay utility

Encapsulates the transparent-textarea-over-pre overlay pattern used
by both quickbites and recipe editor controllers."
```

### Task 5: Refactor `quickbites_editor_controller.js` to use HighlightOverlay

**Files:**
- Modify: `app/javascript/controllers/quickbites_editor_controller.js`

**Step 1: Rewrite the controller**

Replace the entire file. The controller now only owns: `highlight()` (Quick Bites line classification), `setPlaceholder()`, and HighlightOverlay lifecycle.

```js
import { Controller } from "@hotwired/stimulus"
import HighlightOverlay from "utilities/highlight_overlay"

/**
 * Syntax-highlighting overlay for the QuickBites textarea. Delegates overlay
 * lifecycle, auto-dash, and scroll sync to HighlightOverlay. This controller
 * provides only the Quick Bites line classification (categories bold/accent,
 * ingredients muted) and the placeholder text.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - highlight_overlay: overlay positioning, auto-dash, scroll sync
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  textareaTargetConnected(element) {
    this.setPlaceholder(element)
    this.hlOverlay = new HighlightOverlay(element, (text) => this.buildFragment(text))
    this.hlOverlay.attach()
  }

  textareaTargetDisconnected() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
  }

  buildFragment(text) {
    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))

      if (/^[^-].+:\s*$/.test(line)) {
        const span = document.createElement("span")
        span.classList.add("hl-category")
        span.textContent = line
        fragment.appendChild(span)
      } else if (/^\s*-\s+/.test(line)) {
        const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
        if (colonIdx !== -1) {
          const nameSpan = document.createElement("span")
          nameSpan.classList.add("hl-item")
          nameSpan.textContent = line.slice(0, colonIdx)
          fragment.appendChild(nameSpan)

          const ingSpan = document.createElement("span")
          ingSpan.classList.add("hl-ingredients")
          ingSpan.textContent = line.slice(colonIdx)
          fragment.appendChild(ingSpan)
        } else {
          const span = document.createElement("span")
          span.classList.add("hl-item")
          span.textContent = line
          fragment.appendChild(span)
        }
      } else {
        fragment.appendChild(document.createTextNode(line))
      }
    })

    return fragment
  }

  setPlaceholder(textarea) {
    if (!textarea.getAttribute("data-placeholder-set")) {
      textarea.placeholder = "Snacks:\n- Hummus with Pretzels: Hummus, Pretzels\n- String cheese\n\nBreakfast:\n- Cereal with Milk: Cereal, Milk"
      textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
```

**Step 2: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/quickbites_editor_controller.js
git commit -m "refactor: quickbites editor uses HighlightOverlay

Reduces from 182 to ~55 lines. Overlay lifecycle, auto-dash, scroll
sync, and content-load highlighting now come from shared utility."
```

### Task 6: Refactor `recipe_editor_controller.js` to use HighlightOverlay

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

**Step 1: Rewrite the controller**

The recipe editor keeps its own concerns: `highlight()` (recipe markdown classification), `setPlaceholder()`, category dropdown handling, and `editor:collect`/`editor:modified` event hooks. Replace the overlay boilerplate with HighlightOverlay.

```js
import { Controller } from "@hotwired/stimulus"
import HighlightOverlay from "utilities/highlight_overlay"

/**
 * Syntax-highlighting overlay and category dropdown for the recipe markdown
 * textarea. Delegates overlay lifecycle, auto-dash, and scroll sync to
 * HighlightOverlay. This controller provides recipe-specific line
 * classification (titles, steps, ingredients, cross-refs, front matter) and
 * participates in editor:collect/editor:modified events to include category
 * in the save payload and dirty checking.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - highlight_overlay: overlay positioning, auto-dash, scroll sync
 * - style.css (.hl-*): highlight colors
 */
export default class extends Controller {
  static targets = ["textarea", "categorySelect", "categoryInput"]

  connect() {
    this.boundCollect = (e) => this.handleCollect(e)
    this.boundModified = (e) => this.handleModified(e)
    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:modified", this.boundModified)
  }

  disconnect() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
    if (this.boundCollect) this.element.removeEventListener("editor:collect", this.boundCollect)
    if (this.boundModified) this.element.removeEventListener("editor:modified", this.boundModified)
  }

  textareaTargetConnected(element) {
    this.hlOverlay?.detach()
    this.setPlaceholder(element)
    this.hlOverlay = new HighlightOverlay(element, (text) => this.buildFragment(text))
    this.hlOverlay.attach()
  }

  textareaTargetDisconnected() {
    this.hlOverlay?.detach()
    this.hlOverlay = null
  }

  buildFragment(text) {
    const fragment = document.createDocumentFragment()
    this.inFooter = false

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))
      this.classifyLine(line, fragment)
    })

    return fragment
  }

  classifyLine(line, fragment) {
    if (/^# .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-title")
    } else if (/^## .+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-step-header")
    } else if (/^- .+$/.test(line)) {
      this.highlightIngredient(line, fragment)
    } else if (/^>>>\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-cross-ref")
    } else if (/^---\s*$/.test(line)) {
      this.inFooter = true
      this.appendSpan(fragment, line, "hl-divider")
    } else if (/^(Makes|Serves):\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else if (this.inFooter) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else {
      fragment.appendChild(document.createTextNode(line))
    }
  }

  highlightIngredient(line, fragment) {
    const colonIdx = line.indexOf(":", 2)
    let left = colonIdx !== -1 ? line.slice(0, colonIdx) : line
    const prep = colonIdx !== -1 ? line.slice(colonIdx) : null

    const commaIdx = left.indexOf(",", 2)
    const name = commaIdx !== -1 ? left.slice(0, commaIdx) : left
    const qty = commaIdx !== -1 ? left.slice(commaIdx) : null

    this.appendSpan(fragment, name, "hl-ingredient-name")
    if (qty) this.appendSpan(fragment, qty, "hl-ingredient-qty")
    if (prep) this.appendSpan(fragment, prep, "hl-ingredient-prep")
  }

  appendSpan(fragment, text, className) {
    const span = document.createElement("span")
    span.classList.add(className)
    span.textContent = text
    fragment.appendChild(span)
  }

  // Editor lifecycle hooks

  handleCollect(event) {
    event.detail.handled = true
    event.detail.data = {
      markdown_source: this.hasTextareaTarget ? this.textareaTarget.value : null,
      category: this.selectedCategory()
    }
  }

  handleModified(event) {
    if (this.hasCategorySelectTarget && this.originalCategory !== undefined) {
      if (this.selectedCategory() !== this.originalCategory) {
        event.detail.handled = true
        event.detail.modified = true
      }
    }
  }

  // Category dropdown

  selectedCategory() {
    if (!this.hasCategorySelectTarget) return null
    const val = this.categorySelectTarget.value
    if (val === "__new__") {
      return this.hasCategoryInputTarget ? this.categoryInputTarget.value.trim() : null
    }
    return val
  }

  categorySelectTargetConnected(element) {
    this.originalCategory = element.value
    element.addEventListener("change", () => this.handleCategoryChange())
  }

  handleCategoryChange() {
    if (!this.hasCategorySelectTarget || !this.hasCategoryInputTarget) return
    if (this.categorySelectTarget.value === "__new__") {
      this.categoryInputTarget.hidden = false
      this.categorySelectTarget.hidden = true
      this.categoryInputTarget.focus()
    }
  }

  categoryInputTargetConnected(element) {
    element.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        this.categoryInputTarget.hidden = true
        this.categorySelectTarget.hidden = false
        this.categorySelectTarget.value = this.originalCategory
      }
    })
  }

  setPlaceholder(textarea) {
    if (!textarea.getAttribute("data-placeholder-set")) {
      textarea.placeholder = [
        "# Recipe Title",
        "",
        "Serves: 4",
        "",
        "## First step.",
        "",
        "- Ingredient one, 1 cup: diced",
        "- Ingredient two",
        "",
        "Instructions for this step.",
        "",
        "## Second step.",
        "",
        "- More ingredients",
        "",
        "More instructions."
      ].join("\n")
      textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
```

**Step 2: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "refactor: recipe editor uses HighlightOverlay

Reduces from 273 to ~160 lines. Overlay lifecycle, auto-dash, scroll
sync, and content-load highlighting now come from shared utility."
```

---

## Milestone 3: Merge Ordered-List Editor Controllers

### Task 7: Create `ordered_list_editor_controller.js`

**Files:**
- Create: `app/javascript/controllers/ordered_list_editor_controller.js`

**Step 1: Write the unified controller**

This controller replaces both `aisle_order_editor_controller.js` and `category_order_editor_controller.js`. It's parameterized by Stimulus values so the same controller handles both aisle and category lists.

```js
import { Controller } from "@hotwired/stimulus"
import {
  getCsrfToken, showErrors, clearErrors,
  closeWithConfirmation, saveRequest, guardBeforeUnload, handleSave
} from "utilities/editor_utils"
import {
  createItem, buildPayload, takeSnapshot, isModified, checkDuplicate,
  renderRows, startInlineRename, swapItems, animateSwap
} from "utilities/ordered_list_editor_utils"

/**
 * Generic ordered-list editor dialog for managing named items with reorder,
 * rename, add, and delete. Parameterized via Stimulus values so one controller
 * handles both grocery aisles and recipe categories. Uses
 * ordered_list_editor_utils for shared list logic; this controller owns the
 * dialog lifecycle and server communication.
 *
 * - ordered_list_editor_utils: changeset, row rendering, animation, payload
 * - editor_utils: CSRF tokens, error display, save/close helpers
 * - GroceriesController / CategoriesController: backend load/save endpoints
 */
export default class extends Controller {
  static targets = ["list", "saveButton", "errors", "newItemName"]

  static values = {
    loadUrl: String,
    saveUrl: String,
    payloadKey: { type: String, default: "order" },
    joinWith: String,
    loadKey: { type: String, default: "items" },
    openSelector: String
  }

  connect() {
    this.items = []
    this.initialSnapshot = null

    if (this.hasOpenSelectorValue) {
      this.boundOpen = this.open.bind(this)
      this.openButton = document.querySelector(this.openSelectorValue)
      if (this.openButton) this.openButton.addEventListener("click", this.boundOpen)
    }

    this.guard = guardBeforeUnload(this.element, () => isModified(this.items, this.initialSnapshot))

    this.boundCancel = this.handleCancel.bind(this)
    this.element.addEventListener("cancel", this.boundCancel)
  }

  disconnect() {
    if (this.openButton && this.boundOpen) {
      this.openButton.removeEventListener("click", this.boundOpen)
    }
    if (this.guard) this.guard.remove()
    this.element.removeEventListener("cancel", this.boundCancel)
  }

  open() {
    this.listTarget.replaceChildren()
    clearErrors(this.errorsTarget)
    this.resetSaveButton()
    if (this.hasNewItemNameTarget) this.newItemNameTarget.value = ""
    this.element.showModal()
    this.loadItems()
  }

  close() {
    closeWithConfirmation(this.element, () => isModified(this.items, this.initialSnapshot), () => this.reset())
  }

  save() {
    this.guard.markSaving()
    handleSave(
      this.saveButtonTarget,
      this.errorsTarget,
      () => saveRequest(this.saveUrlValue, "PATCH", this.buildItemPayload()),
      () => {
        this.element.close()
        window.location.reload()
      }
    )
  }

  moveUp(index) {
    this.move(index, -1, "up")
  }

  moveDown(index) {
    this.move(index, 1, "down")
  }

  addItem() {
    const name = this.newItemNameTarget.value.trim()
    if (!name) return

    if (checkDuplicate(this.items, name)) {
      showErrors(this.errorsTarget, [`"${name}" already exists.`])
      return
    }

    clearErrors(this.errorsTarget)
    this.items.push(createItem(null, name))
    this.newItemNameTarget.value = ""
    this.render()
    this.newItemNameTarget.focus()
  }

  addItemOnEnter(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.addItem()
    }
  }

  // Private

  handleCancel(event) {
    if (isModified(this.items, this.initialSnapshot)) {
      event.preventDefault()
      this.close()
    }
  }

  loadItems() {
    this.saveButtonTarget.disabled = true

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        this.items = this.parseLoadedItems(data)
        this.initialSnapshot = takeSnapshot(this.items)
        this.render()
        this.saveButtonTarget.disabled = false
      })
      .catch(() => {
        showErrors(this.errorsTarget, ["Failed to load. Close and try again."])
      })
  }

  parseLoadedItems(data) {
    const raw = data[this.loadKeyValue]
    if (Array.isArray(raw)) return raw.map(item => createItem(item.name || item))
    if (typeof raw === "string") return raw.split("\n").filter(Boolean).map(name => createItem(name))
    return []
  }

  render() {
    renderRows(this.listTarget, this.items, this.rowCallbacks())
  }

  rowCallbacks() {
    return {
      onMoveUp: (index) => this.moveUp(index),
      onMoveDown: (index) => this.moveDown(index),
      onDelete: (index) => { this.items[index].deleted = true; this.render() },
      onUndo: (index) => { this.items[index].deleted = false; this.render() },
      onRename: (index) => {
        const row = this.listTarget.children[index]
        const nameBtn = row.querySelector(".aisle-name")
        startInlineRename(nameBtn, this.items[index], () => this.render())
      }
    }
  }

  move(index, direction, label) {
    const liveIndices = this.liveIndices()
    const livePos = liveIndices.indexOf(index)
    const targetPos = livePos + direction
    if (livePos < 0 || targetPos < 0 || targetPos >= liveIndices.length) return

    const swapIndex = liveIndices[targetPos]
    const rows = this.listTarget.children

    animateSwap(rows[index], rows[swapIndex], () => {
      swapItems(this.items, index, swapIndex)
      this.render()
      this.focusMoveButton(swapIndex, label)
    })
  }

  liveIndices() {
    return this.items
      .map((item, i) => item.deleted ? null : i)
      .filter(i => i !== null)
  }

  focusMoveButton(newIndex, direction) {
    const selector = direction === "up" ? ".aisle-btn--up" : ".aisle-btn--down"
    const row = this.listTarget.children[newIndex]
    if (row) {
      const btn = row.querySelector(selector)
      if (btn) btn.focus()
    }
  }

  buildItemPayload() {
    const payload = buildPayload(this.items, this.payloadKeyValue)
    if (this.hasJoinWithValue) {
      payload[this.payloadKeyValue] = payload[this.payloadKeyValue].join(this.joinWithValue)
    }
    return payload
  }

  reset() {
    this.items = []
    this.initialSnapshot = null
    clearErrors(this.errorsTarget)
  }

  resetSaveButton() {
    this.saveButtonTarget.disabled = false
    this.saveButtonTarget.textContent = "Save"
  }
}
```

**Step 2: Run tests to verify new file doesn't break anything**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/ordered_list_editor_controller.js
git commit -m "feat: add unified ordered-list-editor controller

Parameterized by Stimulus values (loadUrl, saveUrl, payloadKey,
joinWith, loadKey, openSelector) to handle both aisles and categories."
```

### Task 8: Migrate grocery aisle view to ordered-list-editor

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/controllers/groceries_controller.rb` (check load endpoint response shape)

**Step 1: Check the groceries controller load endpoint**

Read `app/controllers/groceries_controller.rb` to see how `aisle_order_content` returns data. The new controller's `parseLoadedItems` needs to handle the response format. The aisle controller currently does:

```js
const raw = data.aisle_order || ""
this.aisles = raw.split("\n").filter(Boolean).map(name => createItem(name))
```

So the endpoint returns `{ aisle_order: "Produce\nDairy\n..." }`. The unified controller uses `loadKey` value to find the data, and `parseLoadedItems` handles both string (split on newline) and array formats.

Set `loadKey: "aisle_order"`.

**Step 2: Update the grocery view**

In `app/views/groceries/show.html.erb`, replace the entire `<dialog>` block (lines 37-67). Change the controller name from `aisle-order-editor` to `ordered-list-editor` and update all data attribute prefixes:

```erb
<dialog id="aisle-order-editor" class="editor-dialog" data-turbo-permanent
        data-controller="ordered-list-editor"
        data-ordered-list-editor-load-url-value="<%= groceries_aisle_order_content_path %>"
        data-ordered-list-editor-save-url-value="<%= groceries_aisle_order_path %>"
        data-ordered-list-editor-payload-key-value="aisle_order"
        data-ordered-list-editor-join-with-value="<%= "\n" %>"
        data-ordered-list-editor-load-key-value="aisle_order"
        data-ordered-list-editor-open-selector-value="#edit-aisle-order-button">
  <div class="editor-header">
    <h2>Aisles</h2>
    <button type="button" class="btn editor-close" data-action="click->ordered-list-editor#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-ordered-list-editor-target="errors" hidden></div>
  <div class="aisle-order-body">
    <div class="aisle-list" data-ordered-list-editor-target="list"></div>
    <div class="aisle-add-row">
      <label for="new-aisle-input" class="sr-only">New aisle name</label>
      <input type="text" id="new-aisle-input" class="aisle-add-input" placeholder="Add an aisle..."
             data-ordered-list-editor-target="newItemName"
             data-action="keydown->ordered-list-editor#addItemOnEnter"
             maxlength="50">
      <button type="button" class="aisle-btn aisle-btn--add" aria-label="Add aisle"
              data-action="click->ordered-list-editor#addItem">
        <svg viewBox="0 0 24 24" width="18" height="18">
          <line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          <line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
    </div>
  </div>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel" data-action="click->ordered-list-editor#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save" data-ordered-list-editor-target="saveButton" data-action="click->ordered-list-editor#save">Save</button>
  </div>
</dialog>
```

Key changes:
- `data-controller` → `ordered-list-editor`
- All `data-aisle-order-editor-*` → `data-ordered-list-editor-*`
- `data-*-target="newAisleName"` → `data-*-target="newItemName"`
- `data-action="...aisle-order-editor#addAisleOnEnter"` → `...ordered-list-editor#addItemOnEnter`
- `data-action="...aisle-order-editor#addAisle"` → `...ordered-list-editor#addItem`
- Added `payload-key-value`, `join-with-value`, `load-key-value`, `open-selector-value`

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 4: Commit**

```bash
git add app/views/groceries/show.html.erb
git commit -m "refactor: grocery aisle editor uses ordered-list-editor controller"
```

### Task 9: Migrate category order view to ordered-list-editor

**Files:**
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/controllers/categories_controller.rb` (check load endpoint response shape)

**Step 1: Check the categories controller load endpoint**

The category order editor currently does:

```js
this.categories = (data.categories || []).map(c => createItem(c.name))
```

So the endpoint returns `{ categories: [{ name: "Dinner" }, ...] }`. The unified controller's `parseLoadedItems` handles arrays: `raw.map(item => createItem(item.name || item))`. Set `loadKey: "categories"`.

The payload key for categories uses `category_order` (from `buildPayload(this.categories, "category_order")`). The category payload does NOT join with newline — it sends an array. So omit `joinWith`.

**Step 2: Update the homepage view**

In `app/views/homepage/show.html.erb`, replace the category order `<dialog>` block (lines 38-68):

```erb
<dialog id="category-order-editor" class="editor-dialog" data-turbo-permanent
        data-controller="ordered-list-editor"
        data-ordered-list-editor-load-url-value="<%= categories_order_content_path %>"
        data-ordered-list-editor-save-url-value="<%= categories_order_path %>"
        data-ordered-list-editor-payload-key-value="category_order"
        data-ordered-list-editor-load-key-value="categories"
        data-ordered-list-editor-open-selector-value="#edit-categories-button">
  <div class="editor-header">
    <h2>Categories</h2>
    <button type="button" class="btn editor-close" data-action="click->ordered-list-editor#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-ordered-list-editor-target="errors" hidden></div>
  <div class="aisle-order-body">
    <div class="aisle-list" data-ordered-list-editor-target="list"></div>
    <div class="aisle-add-row">
      <label for="new-category-input" class="sr-only">New category name</label>
      <input type="text" id="new-category-input" class="aisle-add-input" placeholder="Add a category..."
             data-ordered-list-editor-target="newItemName"
             data-action="keydown->ordered-list-editor#addItemOnEnter"
             maxlength="50">
      <button type="button" class="aisle-btn aisle-btn--add" aria-label="Add category"
              data-action="click->ordered-list-editor#addItem">
        <svg viewBox="0 0 24 24" width="18" height="18">
          <line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          <line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
    </div>
  </div>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel" data-action="click->ordered-list-editor#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save" data-ordered-list-editor-target="saveButton" data-action="click->ordered-list-editor#save">Save</button>
  </div>
</dialog>
```

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 4: Commit**

```bash
git add app/views/homepage/show.html.erb
git commit -m "refactor: category editor uses ordered-list-editor controller"
```

### Task 10: Delete old controllers and update header comments

**Files:**
- Delete: `app/javascript/controllers/aisle_order_editor_controller.js`
- Delete: `app/javascript/controllers/category_order_editor_controller.js`
- Modify: `app/javascript/utilities/ordered_list_editor_utils.js` (update header comment)

**Step 1: Delete old controllers**

```bash
cd /home/claude/familyrecipes
rm app/javascript/controllers/aisle_order_editor_controller.js
rm app/javascript/controllers/category_order_editor_controller.js
```

**Step 2: Update `ordered_list_editor_utils.js` header comment**

Replace lines 7-8:

```js
 * - aisle_order_editor_controller: grocery aisle ordering
 * - category_order_editor_controller: recipe category ordering
```

with:

```js
 * - ordered_list_editor_controller: unified controller for aisles and categories
```

**Step 3: Run tests**

```bash
cd /home/claude/familyrecipes && bundle exec rake test
```

**Step 4: Commit**

```bash
git add -A  # includes deletions
git commit -m "refactor: delete old aisle/category order editor controllers

Both replaced by unified ordered-list-editor-controller. Removes
~400 lines of duplicate code."
```

---

## Milestone 4: Verify and Update Docs

### Task 11: Update html_safe allowlist line numbers

**Files:**
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted in edited views)

**Step 1: Run the allowlist lint**

```bash
cd /home/claude/familyrecipes && bundle exec rake lint:html_safe
```

If any failures, update `config/html_safe_allowlist.yml` with the new line numbers.

**Step 2: Run full test suite and lint**

```bash
cd /home/claude/familyrecipes && bundle exec rake
```

This runs both `rake lint` (RuboCop) and `rake test`. Everything should pass.

**Step 3: Commit (if allowlist changed)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist line numbers"
```

### Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the Architecture > Hotwire stack paragraph**

Add a sentence about `data-turbo-permanent` on editor dialogs. After the existing "Turbo's progress bar styles..." sentence, add:

> All `<dialog>` elements use `data-turbo-permanent` to prevent Turbo morph from disrupting open editors during `broadcast_refresh_to`.

**Step 2: Update the Architecture > Editor dialogs paragraph**

After "Use `render layout: 'shared/editor_dialog'`...", add:

> `HighlightOverlay` (shared utility) powers syntax-colored overlays for both Quick Bites and recipe editors.
> `ordered_list_editor_controller` is a single parameterized controller for both aisle and category list editors.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for editor morph protection and refactors"
```

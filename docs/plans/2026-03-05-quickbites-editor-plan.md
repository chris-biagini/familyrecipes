# QuickBites Editor Enhancement — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add syntax highlighting, auto-dash on Enter, and placeholder example to the QuickBites textarea editor.

**Architecture:** A new `quickbites-editor` Stimulus controller creates a `<pre>` overlay behind the textarea with colored spans for categories, item names, and ingredients. The textarea becomes transparent (text invisible, caret visible) so users type into the real textarea but see the highlighted overlay. Auto-dash intercepts Enter keydown. Placeholder is set as a standard textarea attribute.

**Tech Stack:** Stimulus controller, CSS overlay positioning, existing editor dialog infrastructure

---

### Task 1: Create the quickbites-editor Stimulus controller with highlighting

**Files:**
- Create: `app/javascript/controllers/quickbites_editor_controller.js`

**Step 1: Create the controller with overlay setup and highlight logic**

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Syntax-highlighting overlay and auto-dash for the QuickBites textarea.
 * Layers a <pre> behind the transparent textarea so users see colored text
 * (categories bold/accent, ingredients muted) while typing into a real textarea.
 * Auto-dash: pressing Enter on a `- ` line continues the list; Enter on an
 * empty `- ` line removes the dash.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - style.css (.qb-highlight-*): overlay positioning and highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    if (!this.hasTextareaTarget) return

    this.textarea = this.textareaTarget
    this.buildOverlay()
    this.setPlaceholder()
    this.highlight()

    this.textarea.addEventListener("input", this.boundHighlight = () => this.highlight())
    this.textarea.addEventListener("scroll", this.boundSync = () => this.syncScroll())
    this.textarea.addEventListener("keydown", this.boundKeydown = (e) => this.handleKeydown(e))
  }

  disconnect() {
    if (this.boundHighlight) this.textarea.removeEventListener("input", this.boundHighlight)
    if (this.boundSync) this.textarea.removeEventListener("scroll", this.boundSync)
    if (this.boundKeydown) this.textarea.removeEventListener("keydown", this.boundKeydown)
    this.overlay?.remove()
  }

  buildOverlay() {
    const wrapper = document.createElement("div")
    wrapper.classList.add("qb-highlight-wrap")

    this.overlay = document.createElement("pre")
    this.overlay.classList.add("qb-highlight-overlay")
    this.overlay.setAttribute("aria-hidden", "true")

    this.textarea.parentNode.insertBefore(wrapper, this.textarea)
    wrapper.appendChild(this.overlay)
    wrapper.appendChild(this.textarea)
    this.textarea.classList.add("qb-highlight-input")
  }

  highlight() {
    const text = this.textarea.value
    if (!text) {
      this.overlay.replaceChildren()
      return
    }

    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i, arr) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))

      if (/^[^-].+:\s*$/.test(line)) {
        const span = document.createElement("span")
        span.classList.add("qb-hl-category")
        span.textContent = line
        fragment.appendChild(span)
      } else if (/^\s*-\s+/.test(line)) {
        const colonIdx = line.indexOf(":", line.indexOf("-") + 2)
        if (colonIdx !== -1) {
          const nameSpan = document.createElement("span")
          nameSpan.classList.add("qb-hl-item")
          nameSpan.textContent = line.slice(0, colonIdx)
          fragment.appendChild(nameSpan)

          const ingSpan = document.createElement("span")
          ingSpan.classList.add("qb-hl-ingredients")
          ingSpan.textContent = line.slice(colonIdx)
          fragment.appendChild(ingSpan)
        } else {
          const span = document.createElement("span")
          span.classList.add("qb-hl-item")
          span.textContent = line
          fragment.appendChild(span)
        }
      } else {
        fragment.appendChild(document.createTextNode(line))
      }
    })

    // Trailing newline: textarea with a final \n needs an extra line in the
    // overlay so the pre height matches the textarea scroll height
    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))

    this.overlay.replaceChildren(fragment)
  }

  syncScroll() {
    this.overlay.scrollTop = this.textarea.scrollTop
    this.overlay.scrollLeft = this.textarea.scrollLeft
  }

  handleKeydown(e) {
    if (e.key !== "Enter") return

    const { selectionStart } = this.textarea
    const text = this.textarea.value
    const lineStart = text.lastIndexOf("\n", selectionStart - 1) + 1
    const currentLine = text.slice(lineStart, selectionStart)

    if (/^- $/.test(currentLine.trimStart())) {
      // Empty list item — remove the dash and leave a blank line
      e.preventDefault()
      this.textarea.setRangeText("\n", lineStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
      return
    }

    if (/^- .+/.test(currentLine.trimStart())) {
      // Continue the list
      e.preventDefault()
      this.textarea.setRangeText("\n- ", selectionStart, selectionStart, "end")
      this.textarea.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  setPlaceholder() {
    if (!this.textarea.getAttribute("data-placeholder-set")) {
      this.textarea.placeholder = "Snacks:\n- Hummus with Pretzels: Hummus, Pretzels\n- String cheese\n\nBreakfast:\n- Cereal with Milk: Cereal, Milk"
      this.textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
```

**Step 2: Verify the controller auto-registers**

The `pin_all_from 'app/javascript/controllers'` in `config/importmap.rb` auto-registers all controllers. No changes needed.

**Step 3: Commit**

```bash
git add app/javascript/controllers/quickbites_editor_controller.js
git commit -m "feat: add quickbites-editor Stimulus controller with highlighting and auto-dash"
```

---

### Task 2: Add CSS for the highlight overlay

**Files:**
- Modify: `app/assets/stylesheets/style.css` (after `.editor-textarea` block, ~line 870)

**Step 1: Add overlay and highlight styles**

Insert after the `.editor-textarea` rule (after line 870):

```css
/* QuickBites syntax-highlighting overlay */

.qb-highlight-wrap {
  position: relative;
  flex: 1;
  display: flex;
  min-height: 60vh;
}

.qb-highlight-overlay {
  position: absolute;
  inset: 0;
  padding: 1.5rem;
  margin: 0;
  font-family: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace;
  font-size: 0.85rem;
  line-height: 1.6;
  white-space: pre-wrap;
  overflow-wrap: break-word;
  overflow: hidden;
  pointer-events: none;
  color: var(--text-color);
  background: transparent;
  border: none;
}

.qb-highlight-input {
  color: transparent !important;
  caret-color: var(--text-color);
  background: transparent !important;
  position: relative;
  z-index: 1;
}

.qb-hl-category {
  font-weight: 700;
  color: var(--accent-color);
}

.qb-hl-item {
  color: var(--text-color);
}

.qb-hl-ingredients {
  color: var(--muted-text);
}
```

**Step 2: Verify `.editor-textarea` still provides correct base styles**

The `.editor-textarea` rule at line 858 sets `flex: 1`, `min-height: 60vh`, `padding: 1.5rem`, font family/size/line-height. Once the wrapper takes over flex layout, the textarea itself keeps `flex: 1` from `.editor-textarea` to fill the wrapper. The padding, font, and line-height must match between textarea and overlay exactly (they do — both use the same values).

The `min-height` moves from the textarea to the wrapper. Update `.editor-textarea` to remove `min-height` since the wrapper now controls it:

Actually, keep `min-height: 60vh` on `.editor-textarea` — it's the flex child that determines the wrapper's size. Both can have it without conflict, but the wrapper needs it to establish minimum height when the textarea has little content.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add QuickBites highlight overlay CSS"
```

---

### Task 3: Wire the controller to the menu page

**Files:**
- Modify: `app/views/menu/show.html.erb:39-51`

**Step 1: Add the quickbites-editor controller and target to the dialog content**

The textarea is currently:
```erb
<textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false" placeholder="Loading..."></textarea>
```

Wrap it with the quickbites-editor controller. The `editor_dialog` layout already wraps content in a `<dialog>` with the `editor` controller. We need to add `quickbites-editor` as an additional controller on the dialog, and mark the textarea as a target for both controllers.

Update the `render layout:` call in `app/views/menu/show.html.erb` to add the extra controller:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit QuickBites',
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: menu_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'content',
                             editor_load_url: menu_quick_bites_content_path,
                             editor_load_key: 'content',
                             extra_controllers: 'quickbites-editor' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" data-quickbites-editor-target="textarea" spellcheck="false" placeholder="Loading..."></textarea>
<% end %>
```

Note: the `editor_dialog` partial already supports `extra_controllers` — it joins them with the `editor` controller in `data-controller`.

**Step 2: Commit**

```bash
git add app/views/menu/show.html.erb
git commit -m "feat: wire quickbites-editor controller to menu page"
```

---

### Task 4: Handle editor load lifecycle (re-highlight after content loads)

**Files:**
- Modify: `app/javascript/controllers/quickbites_editor_controller.js`

**Step 1: Listen for content load completion**

The editor controller loads content asynchronously via `openWithRemoteContent()`. After loading, it sets the textarea value and dispatches focus. The quickbites-editor needs to re-highlight after content loads.

The simplest approach: use a MutationObserver on the textarea's `disabled` attribute. The editor controller sets `disabled = true` during load and `disabled = false` when done. Alternatively, just listen for the textarea's `input` event and also observe the `value` property.

Actually, the cleanest approach: the editor controller already sets `this.textareaTarget.value = data[...]` and then calls `.focus()`. We can listen for the `focus` event on the textarea to re-highlight after load:

Add to the `connect()` method:

```javascript
this.textarea.addEventListener("focus", this.boundFocus = () => this.highlight())
```

And clean up in `disconnect()`:

```javascript
if (this.boundFocus) this.textarea.removeEventListener("focus", this.boundFocus)
```

This works because focus fires after the editor sets the loaded content and calls `.focus()`.

**Step 2: Commit**

```bash
git add app/javascript/controllers/quickbites_editor_controller.js
git commit -m "fix: re-highlight QuickBites overlay after async content load"
```

---

### Task 5: Test manually and verify

**Step 1: Run linter**

```bash
bundle exec rubocop
rake lint:html_safe
```

Expected: no offenses. Check that the `html_safe_allowlist.yml` doesn't need updates (we didn't add any `.html_safe` calls — the overlay uses `textContent` and `createTextNode` only).

**Step 2: Run test suite**

```bash
rake test
```

Expected: all tests pass. No Ruby changes were made (the controller and CSS are new JS/CSS files), so existing tests should be unaffected.

**Step 3: Manual smoke test**

Start `bin/dev`, open the menu page, click "Edit QuickBites":

1. **Highlighting**: Category lines (`Snacks:`) appear bold and in accent color. Item names in normal color. Ingredients after `:` in muted color.
2. **Scroll sync**: scroll the textarea — the overlay scrolls in lockstep.
3. **Auto-dash**: type a line starting with `- Something`, press Enter — new line gets `- ` prefix. Press Enter again on empty `- ` — dash is removed, blank line remains.
4. **Placeholder**: clear all content — placeholder example appears showing the format.
5. **Save with warnings**: add a garbage line, save — warnings display, dialog stays open.
6. **Clean save**: fix the line, save — dialog closes.

**Step 4: Commit any fixes**

If any issues found during testing, fix and commit.

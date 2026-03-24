# Recipe Editor Syntax Highlighting — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add syntax highlighting, auto-dash continuation, and placeholder text to the recipe markdown editor textarea.

**Architecture:** New `recipe-editor` Stimulus controller using the same transparent-textarea-over-pre overlay technique as QuickBites. First rename the QuickBites overlay CSS to a shared `hl-` prefix so both editors share infrastructure, then add recipe-specific token classes and a new controller.

**Tech Stack:** Stimulus, CSS custom properties, importmap-rails (auto-registers new controllers via `pin_all_from`)

**Design doc:** `docs/plans/2026-03-05-recipe-editor-design.md`

---

### Task 0: Rename QB overlay CSS classes to shared `hl-` prefix

The QuickBites overlay positioning classes (`.qb-highlight-wrap`, `.qb-highlight-overlay`, `.qb-highlight-input`) are generic infrastructure that both editors need. Rename them to a shared prefix so the recipe editor can reuse them without duplication.

**Files:**
- Modify: `app/assets/stylesheets/style.css:949-1001`
- Modify: `app/javascript/controllers/quickbites_editor_controller.js`
- Modify: `app/views/menu/show.html.erb:50` (class on textarea)

**Step 1: Rename CSS classes in style.css**

In the `/* QuickBites syntax-highlighting overlay */` section (lines 949-1001), rename:

| Old class | New class |
|---|---|
| `.qb-highlight-wrap` | `.hl-wrap` |
| `.qb-highlight-overlay` | `.hl-overlay` |
| `.qb-highlight-input` | `.hl-input` |
| `.qb-highlight-input::placeholder` | `.hl-input::placeholder` |
| `.qb-hl-category` | `.hl-category` |
| `.qb-hl-item` | `.hl-item` |
| `.qb-hl-ingredients` | `.hl-ingredients` |

Update the section comment from `/* QuickBites syntax-highlighting overlay */` to `/* Syntax-highlighting overlay (shared) */`.

**Step 2: Update quickbites_editor_controller.js**

Replace all `qb-highlight-*` and `qb-hl-*` references:

- Line 62: `".qb-highlight-wrap"` → `".hl-wrap"`
- Line 64: `"qb-highlight-input"` → `"hl-input"`
- Line 81: `"qb-highlight-wrap"` → `"hl-wrap"`
- Line 84: `"qb-highlight-overlay"` → `"hl-overlay"`
- Line 90: `"qb-highlight-input"` → `"hl-input"`
- Line 107: `"qb-hl-category"` → `"hl-category"`
- Line 114: `"qb-hl-item"` → `"hl-item"`
- Line 119: `"qb-hl-ingredients"` → `"hl-ingredients"`
- Line 123: `"qb-hl-item"` → `"hl-item"`

Update the header comment to reference `style.css (.hl-*)` instead of `(.qb-highlight-*)`.

**Step 3: Run tests**

Run: `bundle exec rubocop && rake test`
Expected: All pass — no Ruby code changed, CSS/JS only.

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css app/javascript/controllers/quickbites_editor_controller.js
git commit -m "refactor: rename QB overlay CSS to shared hl- prefix"
```

---

### Task 1: Add recipe-specific highlight CSS classes

Add the CSS classes for recipe token types. These sit alongside the shared QB token classes (`.hl-category`, `.hl-item`, `.hl-ingredients`) which are already correct for QuickBites.

**Files:**
- Modify: `app/assets/stylesheets/style.css` (after the `.hl-ingredients` rule, before `.editor-footer`)

**Step 1: Add recipe highlight classes**

Insert after `.hl-ingredients { ... }` (around line 1001):

```css
/* Recipe token highlights */

.hl-title {
  font-weight: 700;
  color: var(--accent-color);
  text-decoration: underline;
}

.hl-step-header {
  font-weight: 700;
  color: var(--text-color);
  text-decoration: underline;
}

.hl-ingredient-name {
  color: var(--text-color);
  font-weight: 600;
}

.hl-ingredient-qty {
  color: var(--text-color);
}

.hl-ingredient-prep {
  color: var(--muted-text);
  font-style: italic;
}

.hl-cross-ref {
  font-weight: 600;
  color: var(--accent-color);
  font-style: italic;
}

.hl-front-matter {
  color: var(--muted-text);
}

.hl-divider {
  color: var(--muted-text);
}
```

**Step 2: Run lint**

Run: `bundle exec rubocop`
Expected: Pass (CSS only, no Ruby changes).

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: add recipe syntax highlight CSS classes"
```

---

### Task 2: Create recipe_editor_controller.js

New Stimulus controller that mirrors `quickbites_editor_controller.js` structure but classifies lines using recipe markdown patterns and splits ingredient lines into name/qty/prep spans.

**Files:**
- Create: `app/javascript/controllers/recipe_editor_controller.js`

**Reference files to read first:**
- `app/javascript/controllers/quickbites_editor_controller.js` — mirror its structure exactly
- `lib/familyrecipes/line_classifier.rb` — the regex patterns to mirror in JS
- `lib/familyrecipes/ingredient_parser.rb` — the split logic (first `:` then first `,`)

**Step 1: Create the controller**

Create `app/javascript/controllers/recipe_editor_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

/**
 * Syntax-highlighting overlay and auto-dash for the recipe markdown textarea.
 * Same transparent-textarea-over-pre technique as quickbites_editor_controller.
 * Classifies lines using patterns that mirror LineClassifier, with ingredient
 * lines split into name/qty/prep spans mirroring IngredientParser.
 *
 * - editor_controller: owns the dialog lifecycle; this controller is additive
 * - style.css (.hl-*): overlay positioning and highlight colors
 */
export default class extends Controller {
  static targets = ["textarea"]

  connect() {
    this.cursorInitialized = false
  }

  disconnect() {
    this.teardownTextarea()
  }

  textareaTargetConnected(element) {
    this.teardownTextarea()
    this.textarea = element
    this.buildOverlay()
    this.setPlaceholder()
    this.highlight()

    this.boundHighlight = () => this.highlight()
    this.boundSync = () => this.syncScroll()
    this.boundKeydown = (e) => this.handleKeydown(e)
    this.boundFocus = () => this.handleFocus()

    this.textarea.addEventListener("input", this.boundHighlight)
    this.textarea.addEventListener("scroll", this.boundSync)
    this.textarea.addEventListener("keydown", this.boundKeydown)
    this.textarea.addEventListener("focus", this.boundFocus)

    this.observer = new MutationObserver(() => {
      if (this.textarea.disabled) this.cursorInitialized = false
    })
    this.observer.observe(this.textarea, { attributes: true, attributeFilter: ["disabled"] })
  }

  textareaTargetDisconnected() {
    this.teardownTextarea()
  }

  teardownTextarea() {
    if (!this.textarea) return

    if (this.boundHighlight) this.textarea.removeEventListener("input", this.boundHighlight)
    if (this.boundSync) this.textarea.removeEventListener("scroll", this.boundSync)
    if (this.boundKeydown) this.textarea.removeEventListener("keydown", this.boundKeydown)
    if (this.boundFocus) this.textarea.removeEventListener("focus", this.boundFocus)
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
    this.boundHighlight = null
    this.boundSync = null
    this.boundKeydown = null
    this.boundFocus = null
  }

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

  highlight() {
    const text = this.textarea.value
    if (!text) {
      this.overlay.replaceChildren()
      return
    }

    const fragment = document.createDocumentFragment()

    text.split("\n").forEach((line, i) => {
      if (i > 0) fragment.appendChild(document.createTextNode("\n"))
      this.classifyLine(line, fragment)
    })

    if (text.endsWith("\n")) fragment.appendChild(document.createTextNode("\n"))

    this.overlay.replaceChildren(fragment)
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
      this.appendSpan(fragment, line, "hl-divider")
    } else if (/^(Category|Makes|Serves):\s+.+$/.test(line)) {
      this.appendSpan(fragment, line, "hl-front-matter")
    } else {
      fragment.appendChild(document.createTextNode(line))
    }
  }

  highlightIngredient(line, fragment) {
    // Mirror IngredientParser: split on first ":" for prep note,
    // then first "," on left side for quantity
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

  setPlaceholder() {
    if (!this.textarea.getAttribute("data-placeholder-set")) {
      this.textarea.placeholder = [
        "# Recipe Title",
        "",
        "Category: Dinner",
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
      this.textarea.setAttribute("data-placeholder-set", "true")
    }
  }
}
```

**Key differences from QuickBites controller:**
- `highlight()` delegates to `classifyLine()` which matches `LineClassifier` pattern order
- `highlightIngredient()` splits on `:` then `,` mirroring `IngredientParser`
- `appendSpan()` extracted as a helper to reduce repetition
- Placeholder shows recipe format instead of QuickBites format
- Auto-dash is identical (ingredient lines start with `- ` in both formats)

**Step 2: Verify importmap auto-registration**

No manual pin needed — `pin_all_from "app/javascript/controllers"` in `config/importmap.rb` auto-registers new controllers. Verify by checking:

Run: `grep pin_all_from config/importmap.rb`
Expected: `pin_all_from "app/javascript/controllers", under: "controllers"`

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: add recipe editor Stimulus controller with syntax highlighting"
```

---

### Task 3: Wire recipe-editor controller into views

Add the `recipe-editor` Stimulus controller to both recipe editor dialogs (edit existing + new recipe).

**Files:**
- Modify: `app/views/recipes/show.html.erb:24-34`
- Modify: `app/views/homepage/show.html.erb:29-38`

**Step 1: Update recipes/show.html.erb**

Add `extra_controllers: 'recipe-editor'` to `dialog_data` and add `data-recipe-editor-target="textarea"` to the textarea. Change from:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source' },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false"><%= @recipe.markdown_source %></textarea>
<% end %>
```

To:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" data-recipe-editor-target="textarea" spellcheck="false"><%= @recipe.markdown_source %></textarea>
<% end %>
```

**Step 2: Update homepage/show.html.erb**

Same pattern — add `extra_controllers` and the target attribute. Change from:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false"><%= "# Recipe Title\n\n..." %></textarea>
<% end %>
```

To:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" data-recipe-editor-target="textarea" spellcheck="false"><%= "# Recipe Title\n\n..." %></textarea>
<% end %>
```

Note: The new-recipe textarea has pre-filled content (the template string). The `recipe-editor` controller will highlight this content on connect and the placeholder will only show when the textarea is completely empty, so both work correctly together.

**Step 3: Run tests**

Run: `bundle exec rubocop && rake test`
Expected: All pass. No logic changes to Ruby, only data attributes added to ERB.

**Step 4: Commit**

```bash
git add app/views/recipes/show.html.erb app/views/homepage/show.html.erb
git commit -m "feat: wire recipe-editor controller into editor dialogs"
```

---

### Task 4: Manual test and commit

**Step 1: Start dev server**

Run: `bin/dev`

**Step 2: Verify QuickBites editor still works**

Navigate to the menu page, open the QuickBites editor. Confirm:
- Category headers are bold, accent, underlined
- Item names are bold
- Ingredient lists are muted, italic
- Auto-dash on Enter works
- Scroll sync works

**Step 3: Verify recipe editor highlighting**

Open an existing recipe and click Edit. Confirm each token type:
- `# Title` — bold, accent (red), underlined
- `## Step header` — bold, text-color, underlined
- `- Ingredient` — bold name, regular qty, muted italic prep note
- `>>> @[Recipe]` — accent, italic
- `Category: X` / `Makes: X` / `Serves: X` — muted
- `---` — muted
- Prose — plain text, no decoration

**Step 4: Verify new recipe editor**

From the homepage, click "Add New Recipe". Confirm:
- Template text gets highlighted on open
- Placeholder shows when content is cleared
- Auto-dash works on ingredient lines

**Step 5: Verify dark mode**

Toggle to dark mode (or use browser devtools). All highlight colors should use CSS variables and render correctly in both themes.

**Step 6: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: recipe editor polish from manual testing"
```

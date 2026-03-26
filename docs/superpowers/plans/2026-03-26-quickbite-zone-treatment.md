# QuickBite Zone Treatment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give QuickBites a visually distinct treatment on the menu page — indented zone with label, per-zone edit button that opens the existing editor focused on the clicked category.

**Architecture:** CSS-only visual zone (left border + label), HTML partial update for zone wrapper, JS plumbing to thread a category name from zone edit button through the editor open flow to both graphical and plaintext child controllers.

**Tech Stack:** Rails ERB, CSS, Stimulus JS, CodeMirror 6 (`foldAll`/`unfoldCode` from `@codemirror/language`)

**Spec:** `docs/superpowers/specs/2026-03-26-quickbite-zone-treatment-design.md`

---

### Task 1: CSS — QB Zone Styles

**Files:**
- Modify: `app/assets/stylesheets/menu.css:160-171` (replace `.quick-bites-list` block, add zone styles)

- [ ] **Step 1: Replace `.quick-bites-list` and `.quick-bite-item` with zone styles**

In `menu.css`, replace lines 160-171 (the `/* Quick Bites */` section) with:

```css
/* Quick Bites zone */
.qb-zone {
  margin-top: 0.5rem;
  padding-left: 0.75rem;
  border-left: 2px solid var(--rule-faint);
}

.qb-zone-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 0.25rem;
}

.qb-zone-label {
  font-size: 0.65rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--text-light);
}

.qb-zone-edit {
  background: none;
  border: none;
  color: var(--text-light);
  font-size: 0.7rem;
  font-family: var(--font-body);
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.1rem 0.3rem;
  border-radius: 3px;
}

.qb-zone-edit:hover {
  color: var(--red);
  background: var(--hover-bg);
}

.quick-bites-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.quick-bite-item {
  font-size: 0.9em;
}
```

- [ ] **Step 2: Add print CSS rule to hide edit buttons**

In the `@media print` block at the bottom of `menu.css`, add inside the existing print rules (after the `#recipe-selector .recipe-link` hide rule around line 372):

```css
  .qb-zone-edit {
    display: none;
  }
```

Also update the `.quick-bites-list:not(:has(input:checked))` print rule (line ~386) — it still works since `.quick-bites-list` class is retained.

- [ ] **Step 3: Verify no lint issues**

Run: `bundle exec rubocop` (CSS is not linted by RuboCop, but verify no unrelated breakage)

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Add QB zone CSS styles for menu page"
```

---

### Task 2: Partial — Zone Wrapper and Edit Button

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb` (wrap QB list in zone div)
- Modify: `app/views/menu/show.html.erb` (pass `editable:` local, add `.qb-edit-trigger` class to header button, change `editor_open` selector)

- [ ] **Step 1: Write failing test — zone markup present for members**

In `test/controllers/menu_controller_test.rb`, add:

```ruby
test 'menu shows qb zone wrapper around quick bites for members' do
  create_quick_bite('Goldfish', category_name: 'Snacks')
  log_in

  get menu_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.qb-zone' do
    assert_select '.qb-zone-header'
    assert_select '.qb-zone-label', text: 'Quick Bites'
    assert_select '.qb-zone-edit'
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /qb_zone_wrapper/`
Expected: FAIL — no `.qb-zone` element exists yet.

- [ ] **Step 4: Update `_recipe_selector.html.erb` — wrap QBs in zone div**

Replace the QB section (lines 39-76) with:

```erb
    <%- qbs = category.quick_bites.sort_by(&:position) -%>
    <%- if qbs.any? -%>
    <div class="qb-zone">
      <div class="qb-zone-header">
        <span class="qb-zone-label">Quick Bites</span>
        <%- if editable -%>
        <button type="button" class="qb-zone-edit qb-edit-trigger"
                data-category="<%= category.name %>">
          <%= icon(:edit, size: 10) %> edit
        </button>
        <%- end -%>
      </div>
      <ul class="quick-bites-list" data-type="quick_bite">
        <%- qbs.each do |item| -%>
          <li class="recipe-selector-item quick-bite-item">
            <input class="custom-checkbox" type="checkbox"
                   id="qb-<%= item.id %>-checkbox"
                   data-slug="<%= item.id %>"
                   data-title="<%= h item.title %>"
                   <%= 'checked' if selected_quick_bites.include?(item.id) %>>
            <label for="qb-<%= item.id %>-checkbox"><%= item.title %></label>
            <% info = availability[item.id] %>
            <% if info %>
              <% have_count = info[:ingredients].size - info[:missing] %>
              <% total = info[:ingredients].size %>
              <% fraction = total.positive? ? have_count.to_f / total : 0 %>
              <% opacity_step = (fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round %>
              <% if total == 1 %>
                <span class="availability-single<%= have_count == 1 ? ' on-hand' : ' not-on-hand' %> opacity-<%= opacity_step %>"><svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><% if have_count == 1 %><circle cx="5" cy="5" r="4.5" fill="currentColor"/><% else %><circle cx="5" cy="5" r="3.5" fill="none" stroke="currentColor" stroke-width="1.5"/><% end %></svg></span>
              <% else %>
                <details class="collapse-header<%= ' all-on-hand' if info[:missing].zero? %> opacity-<%= opacity_step %>">
                  <summary aria-label="Have <%= have_count %> of <%= total %><%= info[:missing_names].any? ? '; missing: ' + info[:missing_names].join(', ') : '' %>"><%= have_count %>/<%= total %></summary>
                </details>
              <% end %>
            <% end %>
            <% if info && info[:ingredients].size > 1 %>
              <div class="collapse-body">
                <div class="collapse-inner">
                  <% have = info[:ingredients] - info[:missing_names] %>
                  <% if have.any? %><div class="availability-have"><strong>Have</strong><span><%= have.join(', ') %></span></div><% end %>
                  <% if info[:missing_names].any? %><div class="availability-need"><strong>Missing</strong><span><%= info[:missing_names].join(', ') %></span></div><% end %>
                </div>
              </div>
            <% end %>
          </li>
        <%- end -%>
      </ul>
    </div>
    <%- end -%>
```

- [ ] **Step 5: Update locals declaration at top of `_recipe_selector.html.erb`**

Change line 1 from:
```erb
<%# locals: (categories:, selected_recipes: Set.new, selected_quick_bites: Set.new, availability: {}) %>
```
to:
```erb
<%# locals: (categories:, selected_recipes: Set.new, selected_quick_bites: Set.new, availability: {}, editable: false) %>
```

- [ ] **Step 6: Update `show.html.erb` — pass `editable:` local and change selector**

In `show.html.erb` line 34, change the render call to pass `editable:`:

```erb
  <%= render 'menu/recipe_selector', categories: @categories, selected_recipes: @selected_recipes, selected_quick_bites: @selected_quick_bites, availability: @availability, editable: current_member? %>
```

Add `.qb-edit-trigger` class to the header button (line 21):

```erb
    <button type="button" id="edit-quick-bites-button" class="btn-ghost qb-edit-trigger">
```

Change the editor dialog's `editor_open` selector (line 43) from `'#edit-quick-bites-button'` to `'.qb-edit-trigger'`:

```ruby
              dialog_data: { editor_open: '.qb-edit-trigger',
```

- [ ] **Step 7: Run the test**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /qb_zone_wrapper/`
Expected: PASS

- [ ] **Step 8: Run full menu test suite**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb app/views/menu/show.html.erb test/controllers/menu_controller_test.rb
git commit -m "Wrap QuickBites in zone div with label and per-zone edit button"
```

---

### Task 3: JS — Thread Category Through Editor Open Flow

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js:36-82` (capture category from click, include in event detail)
- Modify: `app/javascript/controllers/dual_mode_editor_controller.js:143-175` (forward category to child)
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js` (add `focusCategory` method)
- Modify: `app/javascript/controllers/plaintext_editor_controller.js` (add `focusCategory` method)

- [ ] **Step 1: Modify `editor_controller.js` — capture category from click event**

In the `connect()` method, change the click handler (lines 40-44) from:

```javascript
    if (this.hasOpenSelectorValue) {
      this.listeners.add(document, "click", (event) => {
        if (event.target.closest(this.openSelectorValue)) this.open()
      })
    }
```

to:

```javascript
    if (this.hasOpenSelectorValue) {
      this.listeners.add(document, "click", (event) => {
        const trigger = event.target.closest(this.openSelectorValue)
        if (!trigger) return
        this.focusCategory = trigger.dataset.category || null
        this.open()
      })
    }
```

- [ ] **Step 2: Modify `editor_controller.js` — include category in content-loaded events**

In the `open()` method (line 80), change:
```javascript
      this.dispatchEditorEvent("editor:content-loaded", {})
```
to:
```javascript
      this.dispatchEditorEvent("editor:content-loaded", { category: this.focusCategory })
```

In `onFrameReady()` (line 94), change:
```javascript
    this.dispatchEditorEvent("editor:content-loaded", {})
```
to:
```javascript
    this.dispatchEditorEvent("editor:content-loaded", { category: this.focusCategory })
```

In `openWithContent(data)` (line 89), change:
```javascript
    this.dispatchEditorEvent("editor:content-loaded", data)
```
to:
```javascript
    this.dispatchEditorEvent("editor:content-loaded", { ...data, category: this.focusCategory })
```

Add cleanup: after each dispatch of `editor:content-loaded`, add:
```javascript
    this.focusCategory = null
```

Actually, to keep it clean, clear `focusCategory` once at the top of `open()` after stashing it in a local. Better approach — stash it before the `open()` call in the click handler and consume it inside `open()`:

Revised approach for `open()`:
```javascript
  open() {
    this.clearErrorDisplay()
    this.resetSaveButton()
    const category = this.focusCategory
    this.focusCategory = null

    if (this.hasFrameTarget && !this.frameLoaded) {
      if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = true
      this.element.showModal()
      this.frameTarget.addEventListener("turbo:frame-load", () => {
        this.onFrameReady(category)
      }, { once: true })
    } else {
      if (this.hasTextareaTarget) this.originalContent = this.textareaTarget.value
      this.element.showModal()
      this.dispatchEditorEvent("editor:content-loaded", { category })
      this.dispatchEditorEvent("editor:opened")
    }
  }

  openWithContent(data) {
    this.clearErrorDisplay()
    this.resetSaveButton()
    this.element.showModal()
    this.dispatchEditorEvent("editor:content-loaded", { ...data, category: this.focusCategory })
    this.focusCategory = null
  }

  onFrameReady(category) {
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = false
    this.dispatchEditorEvent("editor:content-loaded", { category })
    this.dispatchEditorEvent("editor:opened")
  }
```

Note: `onFrameReady` gains a `category` parameter. It was previously called without arguments from the event listener.

- [ ] **Step 3: Modify `dual_mode_editor_controller.js` — forward category to child**

In `handleContentLoaded(event)` (line 143), after the existing logic that sets `originalContent`/`originalStructure` and calls `showActiveMode()`, add a call to the active child's `focusCategory`.

At the end of `handleContentLoaded`, before the `return` statements, add:

```javascript
    this.applyFocusCategory(data.category)
```

Add a new method:

```javascript
  applyFocusCategory(category) {
    if (!category) return
    if (this.mode === "graphical") {
      this.graphicalController.focusCategory?.(category)
    } else {
      this.plaintextController.focusCategory?.(category)
    }
  }
```

Place this method after `enableEditing()`.

Important: `handleContentLoaded` has three exit paths (lines 147-175). The `applyFocusCategory` call must go at the end of each path, right after `showActiveMode()`. There are three places where `showActiveMode()` is called in `handleContentLoaded`:

1. Line 153: `this.showActiveMode()` → add `this.applyFocusCategory(data.category)` after
2. Line 161: `this.showActiveMode()` → add `this.applyFocusCategory(data.category)` after
3. Line 174: `this.showActiveMode()` → add `this.applyFocusCategory(data.category)` after

Actually, looking at the code more carefully, `data` is set to `event.detail` at line 145. But `event.detail` includes `handled`, the content key, and now `category`. The `category` field must be read from `event.detail` directly since `data` is reassigned. Let's use `event.detail.category`:

Revised: At line 145, stash the category:

```javascript
    const category = event.detail.category
```

Then at each of the three exit paths, after `this.showActiveMode()`, add:

```javascript
    this.applyFocusCategory(category)
```

- [ ] **Step 4: Add `focusCategory` to `quickbites_graphical_controller.js`**

Add this method to the controller. Note: after `rebuildCategories()`, the DOM
is JS-built (no `data-field` attributes). Match against the in-memory
`this.categories` array by name instead:

```javascript
  focusCategory(name) {
    const index = this.categories.findIndex(cat => cat.name === name)
    if (index >= 0) {
      expandItem(this.categoriesContainerTarget, index)
    }
  }
```

This uses the existing `expandItem` utility (imported at line 5) which calls `collapseAll` then expands the target card.

- [ ] **Step 5: Add `focusCategory` to `plaintext_editor_controller.js`**

Add imports at the top of the file:

```javascript
import { foldAll, unfoldCode } from "@codemirror/language"
```

Add this method to the controller. Deferred via `requestAnimationFrame` because CodeMirror's
fold service needs the language state to be ready (it parses asynchronously).
A single rAF is sufficient since the editor has already rendered by this point
and the fold service runs synchronously once the tree is available:

```javascript
  focusCategory(name) {
    if (!this.editorView) return
    const view = this.editorView

    requestAnimationFrame(() => {
      foldAll(view)

      const doc = view.state.doc
      const target = `## ${name}`
      for (let i = 1; i <= doc.lines; i++) {
        const line = doc.line(i)
        if (line.text.trimEnd() === target) {
          view.dispatch({ selection: { anchor: line.from } })
          unfoldCode(view)
          return
        }
      }
    })
  }
```

- [ ] **Step 6: Build JS to verify no syntax errors**

Run: `npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 7: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/editor_controller.js app/javascript/controllers/dual_mode_editor_controller.js app/javascript/controllers/quickbites_graphical_controller.js app/javascript/controllers/plaintext_editor_controller.js
git commit -m "Thread category focus from zone edit button through editor open flow"
```

---

### Task 4: Update Header Comment and Verify

**Files:**
- Modify: `app/assets/stylesheets/menu.css` (update comment if needed)
- Verify: Full lint + test pass

- [ ] **Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 3: Run JS build**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 4: Check html_safe allowlist**

Run: `rake lint:html_safe`
Expected: No new violations (the zone edit button uses `icon()` helper which is already allowlisted; no new `.html_safe` calls)

- [ ] **Step 5: Commit any fixups if needed**

Only commit if there were issues to fix. Otherwise skip.

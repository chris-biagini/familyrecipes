# Editor Controller Consolidation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ~230 lines of near-identical code by consolidating the recipe and Quick Bites plaintext editors into one parameterized controller, and the two dual-mode coordinators into another.

**Architecture:** Four editor controllers (two coordinators + two plaintext wrappers) collapse into two parameterized Stimulus controllers. A classifier registry bridges Stimulus string values to imported CodeMirror plugins. The auto-dash keymap moves to a shared CodeMirror extension. A backend key inconsistency is fixed to enable a single `contentKey` parameter.

**Tech Stack:** Stimulus (JS controllers), CodeMirror 6, Rails ERB views, Minitest

**Spec:** `docs/plans/2026-03-15-ai-recipe-import-design.md` is unrelated. Design was discussed inline in the conversation.

---

## File Structure

### New files
- `app/javascript/codemirror/auto_dash.js` — Shared keymap extension for `- ` bullet continuation
- `app/javascript/codemirror/registry.js` — Maps string keys to classifier/fold-service objects
- `app/javascript/controllers/plaintext_editor_controller.js` — Unified CodeMirror plaintext editor
- `app/javascript/controllers/dual_mode_editor_controller.js` — Unified coordinator for plaintext ↔ graphical mode switching

### Modified files
- `app/controllers/recipes_controller.rb:42-44` — Fix serialize response key
- `test/controllers/recipes_controller_test.rb:843` — Update serialize test assertion
- `app/javascript/application.js` — Swap 4 old registrations for 2 new ones
- `app/views/recipes/show.html.erb:33-58` — Update data attributes for edit recipe dialog
- `app/views/homepage/show.html.erb:123-164` — Update data attributes for new recipe dialog
- `app/views/menu/show.html.erb:38-63` — Update data attributes for quickbites dialog
- `app/javascript/codemirror/editor_setup.js:7-8` — Update header comment collaborators
- `app/javascript/codemirror/recipe_classifier.js:9` — Update header comment collaborator
- `app/javascript/codemirror/quickbites_classifier.js:7` — Update header comment collaborator
- `app/javascript/controllers/recipe_graphical_controller.js:9` — Update header comment collaborator
- `app/javascript/controllers/quickbites_graphical_controller.js:10` — Update header comment collaborator
- `CLAUDE.md:172-173` — Update coordinator controller names in editor architecture docs

### Deleted files
- `app/javascript/controllers/recipe_editor_controller.js`
- `app/javascript/controllers/recipe_plaintext_controller.js`
- `app/javascript/controllers/quickbites_editor_controller.js`
- `app/javascript/controllers/quickbites_plaintext_controller.js`

---

## Task 1: Extract auto-dash keymap

**Files:**
- Create: `app/javascript/codemirror/auto_dash.js`

The auto-dash keymap is duplicated verbatim in both plaintext controllers. Extract it to a shared module.

- [ ] **Step 1: Create `auto_dash.js`**

```js
/**
 * CodeMirror keymap for auto-continuing bulleted lists. On Enter at the end
 * of a "- text" line, inserts a new "- " bullet. On Enter on a bare "- "
 * line, clears the dash (exits list mode).
 *
 * - plaintext_editor_controller: consumes as an extra extension
 * - editor_setup.js: added via extraExtensions option
 */
import { keymap } from "@codemirror/view"

export const autoDashKeymap = keymap.of([{
  key: "Enter",
  run(view) {
    const { state } = view
    const { head } = state.selection.main
    const line = state.doc.lineAt(head)

    if (head !== line.to) return false

    if (line.text === "- ") {
      view.dispatch({ changes: { from: line.from, to: line.to, insert: "" } })
      return true
    }

    if (/^- .+$/.test(line.text)) {
      view.dispatch({
        changes: { from: head, insert: "\n- " },
        selection: { anchor: head + 3 }
      })
      return true
    }

    return false
  }
}])
```

- [ ] **Step 2: Build to verify no syntax errors**

Run: `npm run build`
Expected: Clean build, no errors

- [ ] **Step 3: Commit**

```
feat: extract auto-dash keymap to shared CodeMirror module
```

---

## Task 2: Create classifier/fold-service registry

**Files:**
- Create: `app/javascript/codemirror/registry.js`

Maps string keys (usable as Stimulus values) to imported CodeMirror plugins.

- [ ] **Step 1: Create `registry.js`**

```js
/**
 * Registry mapping string keys to CodeMirror classifier and fold-service
 * extensions. Bridges the gap between Stimulus values (strings) and the
 * JavaScript objects that createEditor() needs.
 *
 * - plaintext_editor_controller: looks up classifier/foldService by key
 * - recipe_classifier.js: provides recipeClassifier ViewPlugin
 * - quickbites_classifier.js: provides quickbitesClassifier ViewPlugin
 * - recipe_fold.js: provides recipeFoldService
 */
import { recipeClassifier } from "./recipe_classifier"
import { quickbitesClassifier } from "./quickbites_classifier"
import { recipeFoldService } from "./recipe_fold"

export const classifiers = {
  recipe: recipeClassifier,
  quickbites: quickbitesClassifier
}

export const foldServices = {
  recipe: recipeFoldService
}
```

- [ ] **Step 2: Build to verify**

Run: `npm run build`
Expected: Clean build

- [ ] **Step 3: Commit**

```
feat: add classifier/fold-service registry for plaintext editors
```

---

## Task 3: Create unified plaintext editor controller

**Files:**
- Create: `app/javascript/controllers/plaintext_editor_controller.js`

Replaces `recipe_plaintext_controller.js` and `quickbites_plaintext_controller.js` with one parameterized controller. Uses Stimulus values to select classifier and fold service from the registry.

- [ ] **Step 1: Create `plaintext_editor_controller.js`**

```js
/**
 * Unified CodeMirror 6 plaintext editor for both recipes and Quick Bites.
 * Parameterized via Stimulus values: the classifier and fold service are
 * looked up by name from the codemirror registry, so the same controller
 * serves any content type that has a registered classifier.
 *
 * - dual_mode_editor_controller: coordinator, calls .content and .isModified()
 * - editor_setup.js: shared CodeMirror factory
 * - registry.js: maps string keys to classifier/fold-service extensions
 * - auto_dash.js: shared bullet-continuation keymap
 */
import { Controller } from "@hotwired/stimulus"
import { createEditor } from "../codemirror/editor_setup"
import { classifiers, foldServices } from "../codemirror/registry"
import { autoDashKeymap } from "../codemirror/auto_dash"

export default class extends Controller {
  static targets = ["mount"]
  static values = {
    classifier: String,
    foldService: String,
    placeholder: String,
    initial: String
  }

  mountTargetConnected(element) {
    this.editorView?.destroy()
    element.classList.remove("cm-loading")

    this.editorView = createEditor({
      parent: element,
      doc: this.hasInitialValue ? this.initialValue : "",
      classifier: classifiers[this.classifierValue],
      foldService: this.hasFoldServiceValue ? foldServices[this.foldServiceValue] : null,
      placeholder: this.hasPlaceholderValue ? this.placeholderValue : "",
      extraExtensions: [autoDashKeymap]
    })
  }

  mountTargetDisconnected() {
    this.editorView?.destroy()
    this.editorView = null
  }

  disconnect() {
    this.editorView?.destroy()
    this.editorView = null
  }

  get content() {
    return this.editorView?.state.doc.toString() || ""
  }

  set content(text) {
    if (!this.editorView) return

    this.editorView.dispatch({
      changes: { from: 0, to: this.editorView.state.doc.length, insert: text }
    })
  }

  isModified(originalContent) {
    return this.content !== originalContent
  }
}
```

- [ ] **Step 2: Build to verify**

Run: `npm run build`
Expected: Clean build (controller not yet registered or used in views)

- [ ] **Step 3: Commit**

```
feat: add unified plaintext-editor controller
```

---

## Task 4: Create unified dual-mode editor controller

**Files:**
- Create: `app/javascript/controllers/dual_mode_editor_controller.js`

Replaces `recipe_editor_controller.js` and `quickbites_editor_controller.js`. Parameterized via Stimulus values for content key and graphical controller identity. Includes the `handleOpened()` method that was missing from the quickbites coordinator.

- [ ] **Step 1: Create `dual_mode_editor_controller.js`**

```js
/**
 * Coordinator for dual-mode editing (plaintext ↔ graphical). Manages the
 * mode toggle, routes editor lifecycle events to the active child controller,
 * and handles mode-switch serialization via server-side parse/serialize
 * endpoints. Parameterized by Stimulus values so the same controller serves
 * both recipes and Quick Bites.
 *
 * - editor_controller: dialog lifecycle (parent)
 * - plaintext_editor_controller: child, plaintext mode (always "plaintext-editor")
 * - recipe_graphical_controller / quickbites_graphical_controller: child, graphical mode
 */
import { Controller } from "@hotwired/stimulus"
import { csrfHeaders } from "../utilities/editor_utils"

export default class extends Controller {
  static targets = ["plaintextContainer", "graphicalContainer", "modeToggle"]
  static values = {
    parseUrl: String,
    serializeUrl: String,
    contentKey: String,
    graphicalId: String
  }

  connect() {
    this.mode = localStorage.getItem("editorMode") || "graphical"
    this.originalContent = null
    this.originalStructure = null

    this.boundCollect = (e) => this.handleCollect(e)
    this.boundModified = (e) => this.handleModified(e)
    this.boundContentLoaded = (e) => this.handleContentLoaded(e)
    this.boundOpened = (e) => this.handleOpened(e)

    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:modified", this.boundModified)
    this.element.addEventListener("editor:content-loaded", this.boundContentLoaded)
    this.element.addEventListener("editor:opened", this.boundOpened)
  }

  disconnect() {
    this.element.removeEventListener("editor:collect", this.boundCollect)
    this.element.removeEventListener("editor:modified", this.boundModified)
    this.element.removeEventListener("editor:content-loaded", this.boundContentLoaded)
    this.element.removeEventListener("editor:opened", this.boundOpened)
  }

  toggleMode() {
    const newMode = this.mode === "plaintext" ? "graphical" : "plaintext"
    this.switchTo(newMode)
  }

  async switchTo(newMode) {
    if (newMode === this.mode) return
    const key = this.contentKeyValue

    if (newMode === "plaintext") {
      const structure = this.graphicalController.toStructure()
      const response = await fetch(this.serializeUrlValue, {
        method: "POST",
        headers: { ...csrfHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ structure })
      })
      const data = await response.json()
      this.plaintextController.content = data[key]
    } else {
      const content = this.plaintextController.content
      const response = await fetch(this.parseUrlValue, {
        method: "POST",
        headers: { ...csrfHeaders(), "Content-Type": "application/json" },
        body: JSON.stringify({ [key]: content })
      })
      const ir = await response.json()
      this.graphicalController.loadStructure(ir)
    }

    this.mode = newMode
    localStorage.setItem("editorMode", newMode)
    this.showActiveMode()
  }

  showActiveMode() {
    const isPlaintext = this.mode === "plaintext"
    if (this.hasPlaintextContainerTarget) {
      this.plaintextContainerTarget.hidden = !isPlaintext
    }
    if (this.hasGraphicalContainerTarget) {
      this.graphicalContainerTarget.hidden = isPlaintext
    }
    if (this.hasModeToggleTarget) {
      this.modeToggleTarget.title = isPlaintext
        ? "Switch to graphical editor"
        : "Switch to plaintext editor"
    }
  }

  handleCollect(event) {
    event.detail.handled = true
    if (this.mode === "plaintext") {
      event.detail.data = { [this.contentKeyValue]: this.plaintextController.content }
    } else {
      event.detail.data = { structure: this.graphicalController.toStructure() }
    }
  }

  handleModified(event) {
    event.detail.handled = true
    if (this.mode === "plaintext") {
      event.detail.modified = this.plaintextController.isModified(this.originalContent)
    } else {
      event.detail.modified = this.graphicalController.isModified(this.originalStructure)
    }
  }

  handleOpened() {
    if (this.originalContent !== null) return
    this.originalContent = this.plaintextController.content
    this.showActiveMode()
  }

  handleContentLoaded(event) {
    event.detail.handled = true
    const data = event.detail

    this.originalContent = data[this.contentKeyValue]
    this.originalStructure = data.structure

    this.plaintextController.content = data[this.contentKeyValue]
    if (data.structure) {
      this.graphicalController.loadStructure(data.structure)
    }

    this.enableEditing()
    this.showActiveMode()
  }

  enableEditing() {
    const textarea = this.element.querySelector("[data-editor-target='textarea']")
    if (textarea) {
      textarea.disabled = false
      textarea.placeholder = ""
    }
    const saveBtn = this.element.querySelector("[data-editor-target='saveButton']")
    if (saveBtn) saveBtn.disabled = false
  }

  get plaintextController() {
    const el = this.plaintextContainerTarget.querySelector('[data-controller~="plaintext-editor"]')
    return this.application.getControllerForElementAndIdentifier(el, "plaintext-editor")
  }

  get graphicalController() {
    const id = this.graphicalIdValue
    const el = this.graphicalContainerTarget.querySelector(`[data-controller~="${id}"]`)
    return this.application.getControllerForElementAndIdentifier(el, id)
  }
}
```

- [ ] **Step 2: Build to verify**

Run: `npm run build`
Expected: Clean build

- [ ] **Step 3: Commit**

```
feat: add unified dual-mode-editor coordinator controller
```

---

## Task 5: Fix backend serialize key inconsistency

**Files:**
- Modify: `app/controllers/recipes_controller.rb:42-44`
- Modify: `test/controllers/recipes_controller_test.rb:843`

The recipe serialize endpoint returns `{ markdown: }` while everything else uses `markdown_source`. Fix for consistency.

- [ ] **Step 1: Update controller**

In `app/controllers/recipes_controller.rb`, change the serialize action from:
```ruby
def serialize
  markdown = FamilyRecipes::RecipeSerializer.serialize(structure_params)
  render json: { markdown: }
end
```

To:
```ruby
def serialize
  markdown_source = FamilyRecipes::RecipeSerializer.serialize(structure_params)
  render json: { markdown_source: }
end
```

- [ ] **Step 2: Update test assertion**

In `test/controllers/recipes_controller_test.rb`, change the serialize test from:
```ruby
assert_includes body['markdown'], '# Test'
assert_includes body['markdown'], '## Mix.'
assert_includes body['markdown'], '- Flour'
```

To:
```ruby
assert_includes body['markdown_source'], '# Test'
assert_includes body['markdown_source'], '## Mix.'
assert_includes body['markdown_source'], '- Flour'
```

- [ ] **Step 3: Run the serialize test to verify**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n "test_serialize_returns_markdown_from_IR"`
Expected: PASS

- [ ] **Step 4: Run full controller tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```
fix: use consistent markdown_source key in recipe serialize endpoint
```

---

## Task 6: Wire up new controllers and update views

**Files:**
- Modify: `app/javascript/application.js`
- Modify: `app/views/recipes/show.html.erb:33-58`
- Modify: `app/views/homepage/show.html.erb:123-164`
- Modify: `app/views/menu/show.html.erb:38-63`
- Modify: `app/javascript/codemirror/editor_setup.js:7-8`
- Modify: `app/javascript/codemirror/recipe_classifier.js:9`
- Modify: `app/javascript/codemirror/quickbites_classifier.js:7`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js:9`
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js:10`
- Modify: `CLAUDE.md:172-173`

This is the integration step: register new controllers, update all view data attributes, update header comments for files that referenced the old controller names.

- [ ] **Step 1: Update `application.js`**

Replace the 4 old imports and registrations:
```js
import QuickbitesEditorController from "./controllers/quickbites_editor_controller"
import QuickbitesPlaintextController from "./controllers/quickbites_plaintext_controller"
import RecipeEditorController from "./controllers/recipe_editor_controller"
import RecipePlaintextController from "./controllers/recipe_plaintext_controller"
```
```js
application.register("quickbites-editor", QuickbitesEditorController)
application.register("quickbites-plaintext", QuickbitesPlaintextController)
application.register("recipe-editor", RecipeEditorController)
application.register("recipe-plaintext", RecipePlaintextController)
```

With the 2 new imports and registrations:
```js
import DualModeEditorController from "./controllers/dual_mode_editor_controller"
import PlaintextEditorController from "./controllers/plaintext_editor_controller"
```
```js
application.register("dual-mode-editor", DualModeEditorController)
application.register("plaintext-editor", PlaintextEditorController)
```

Keep the alphabetical ordering of imports and registrations.

- [ ] **Step 2: Update `recipes/show.html.erb` (edit recipe dialog)**

Change the editor dialog block (lines 33-58) from:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'markdown_source',
                             editor_load_url: recipe_content_path(@recipe.slug),
                             editor_load_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' },
              extra_data: {
                'recipe-editor-parse-url-value' => recipe_parse_path,
                'recipe-editor-serialize-url-value' => recipe_serialize_path
              },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <div class="editor-body" data-recipe-editor-target="plaintextContainer">
    <div data-controller="recipe-plaintext">
      <div class="cm-mount cm-loading" data-recipe-plaintext-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-recipe-editor-target="graphicalContainer" hidden>
    <%= render 'recipes/graphical_editor' %>
  </div>
<% end %>
```

To:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: "Editing: #{@recipe.title}",
              id: 'recipe-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#edit-button',
                             editor_url: recipe_path(@recipe.slug),
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'markdown_source',
                             editor_load_url: recipe_content_path(@recipe.slug),
                             editor_load_key: 'markdown_source',
                             extra_controllers: 'dual-mode-editor' },
              extra_data: {
                'dual-mode-editor-parse-url-value' => recipe_parse_path,
                'dual-mode-editor-serialize-url-value' => recipe_serialize_path,
                'dual-mode-editor-content-key-value' => 'markdown_source',
                'dual-mode-editor-graphical-id-value' => 'recipe-graphical'
              },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <div class="editor-body" data-dual-mode-editor-target="plaintextContainer">
    <div data-controller="plaintext-editor"
         data-plaintext-editor-classifier-value="recipe"
         data-plaintext-editor-fold-service-value="recipe"
         data-plaintext-editor-placeholder-value="Paste or type a recipe…">
      <div class="cm-mount cm-loading" data-plaintext-editor-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-dual-mode-editor-target="graphicalContainer" hidden>
    <%= render 'recipes/graphical_editor' %>
  </div>
<% end %>
```

- [ ] **Step 3: Update `homepage/show.html.erb` (new recipe dialog)**

Change the new recipe dialog block (lines 123-164) from:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' },
              extra_data: {
                'recipe-editor-parse-url-value' => recipe_parse_path,
                'recipe-editor-serialize-url-value' => recipe_serialize_path
              } } do %>
  <div class="editor-body" data-recipe-editor-target="plaintextContainer">
    <%# template = "..." block is unchanged and sits here %>
    <div data-controller="recipe-plaintext" data-recipe-plaintext-initial-value="<%= template %>">
      <div class="cm-mount cm-loading" data-recipe-plaintext-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-recipe-editor-target="graphicalContainer" hidden>
    <%= render 'recipes/graphical_editor' %>
  </div>
<% end %>
```

To:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source',
                             extra_controllers: 'dual-mode-editor' },
              extra_data: {
                'dual-mode-editor-parse-url-value' => recipe_parse_path,
                'dual-mode-editor-serialize-url-value' => recipe_serialize_path,
                'dual-mode-editor-content-key-value' => 'markdown_source',
                'dual-mode-editor-graphical-id-value' => 'recipe-graphical'
              } } do %>
  <div class="editor-body" data-dual-mode-editor-target="plaintextContainer">
    <%# template = "..." block is unchanged and sits here %>
    <div data-controller="plaintext-editor"
         data-plaintext-editor-classifier-value="recipe"
         data-plaintext-editor-fold-service-value="recipe"
         data-plaintext-editor-placeholder-value="Paste or type a recipe…"
         data-plaintext-editor-initial-value="<%= template %>">
      <div class="cm-mount cm-loading" data-plaintext-editor-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-dual-mode-editor-target="graphicalContainer" hidden>
    <%= render 'recipes/graphical_editor' %>
  </div>
<% end %>
```

Note: the `<% template = "..." %>` block before this is unchanged.

- [ ] **Step 4: Update `menu/show.html.erb` (quickbites dialog)**

Change the quickbites dialog block (lines 38-63) from:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit QuickBites',
              id: 'quickbites-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: menu_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'content',
                             editor_load_url: menu_quick_bites_content_path,
                             editor_load_key: 'content',
                             extra_controllers: 'quickbites-editor' },
              extra_data: {
                'quickbites-editor-parse-url-value' => menu_parse_quick_bites_path,
                'quickbites-editor-serialize-url-value' => menu_serialize_quick_bites_path
              } } do %>
  <div class="editor-body" data-quickbites-editor-target="plaintextContainer">
    <div data-controller="quickbites-plaintext">
      <div class="cm-mount cm-loading" data-quickbites-plaintext-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-quickbites-editor-target="graphicalContainer" hidden>
    <%= render 'menu/quickbites_graphical_editor' %>
  </div>
<% end %>
```

To:
```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit QuickBites',
              id: 'quickbites-editor',
              mode_toggle: true,
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: menu_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'content',
                             editor_load_url: menu_quick_bites_content_path,
                             editor_load_key: 'content',
                             extra_controllers: 'dual-mode-editor' },
              extra_data: {
                'dual-mode-editor-parse-url-value' => menu_parse_quick_bites_path,
                'dual-mode-editor-serialize-url-value' => menu_serialize_quick_bites_path,
                'dual-mode-editor-content-key-value' => 'content',
                'dual-mode-editor-graphical-id-value' => 'quickbites-graphical'
              } } do %>
  <div class="editor-body" data-dual-mode-editor-target="plaintextContainer">
    <div data-controller="plaintext-editor"
         data-plaintext-editor-classifier-value="quickbites"
         data-plaintext-editor-placeholder-value="Snacks:&#10;- Hummus with Pretzels: Hummus, Pretzels">
      <div class="cm-mount cm-loading" data-plaintext-editor-target="mount"></div>
    </div>
  </div>
  <div class="editor-body" data-dual-mode-editor-target="graphicalContainer" hidden>
    <%= render 'menu/quickbites_graphical_editor' %>
  </div>
<% end %>
```

Note: the multiline placeholder uses `&#10;` for the newline character in the HTML attribute.

- [ ] **Step 5: Update header comments in collaborating files**

In `app/javascript/codemirror/editor_setup.js`, change lines 7-8 from:
```js
 * - recipe_plaintext_controller: recipe editing
 * - quickbites_plaintext_controller: quick bites editing
```
To:
```js
 * - plaintext_editor_controller: unified plaintext editing (recipe + quick bites)
```

In `app/javascript/codemirror/recipe_classifier.js`, change line 9 from:
```js
 * - recipe_plaintext_controller.js: original pattern source (classifyLine, highlightIngredient, highlightProseLinks)
```
To:
```js
 * - plaintext_editor_controller.js: consumes recipeClassifier via registry
```

In `app/javascript/codemirror/quickbites_classifier.js`, change lines 7-8 from:
```js
 * - quickbites_plaintext_controller.js: mirrors classification logic for the
 *   legacy textarea overlay (kept until the CM swap lands)
```
To:
```js
 * - plaintext_editor_controller.js: consumes quickbitesClassifier via registry
```

In `app/javascript/controllers/recipe_graphical_controller.js`, change line 9 from:
```js
 * - recipe_editor_controller: coordinator, routes lifecycle events
```
To:
```js
 * - dual_mode_editor_controller: coordinator, routes lifecycle events
```

In `app/javascript/controllers/quickbites_graphical_controller.js`, change line 10 from:
```js
 * - quickbites_editor_controller: coordinator, routes lifecycle events
```
To:
```js
 * - dual_mode_editor_controller: coordinator, routes lifecycle events
```

In `CLAUDE.md`, change lines 172-173 from:
```
  `editor_controller` (dialog lifecycle) → coordinator (`recipe_editor_controller`
  / `quickbites_editor_controller`) → plaintext or graphical child controller.
```
To:
```
  `editor_controller` (dialog lifecycle) → `dual_mode_editor_controller`
  (coordinator) → `plaintext_editor_controller` or graphical child controller.
```

- [ ] **Step 6: Build JS**

Run: `npm run build`
Expected: Clean build, no errors (old controllers are no longer imported but still exist on disk — no build error)

- [ ] **Step 7: Run full test suite**

Run: `rake test`
Expected: All tests pass. Tests assert on dialog IDs (`#recipe-editor`, `#quickbites-editor`) and data attributes like `data-editor-load-url-value` which are unchanged. The `data-controller` attribute values changed from `editor recipe-editor` to `editor dual-mode-editor`, but no tests assert on that.

- [ ] **Step 8: Commit**

```
refactor: wire up unified editor controllers in views and application.js
```

---

## Task 7: Delete old controller files

**Files:**
- Delete: `app/javascript/controllers/recipe_editor_controller.js`
- Delete: `app/javascript/controllers/recipe_plaintext_controller.js`
- Delete: `app/javascript/controllers/quickbites_editor_controller.js`
- Delete: `app/javascript/controllers/quickbites_plaintext_controller.js`

- [ ] **Step 1: Delete the 4 replaced controller files**

```bash
git rm app/javascript/controllers/recipe_editor_controller.js
git rm app/javascript/controllers/recipe_plaintext_controller.js
git rm app/javascript/controllers/quickbites_editor_controller.js
git rm app/javascript/controllers/quickbites_plaintext_controller.js
```

- [ ] **Step 2: Build to verify no broken imports**

Run: `npm run build`
Expected: Clean build (no remaining references to deleted files)

- [ ] **Step 3: Run full test suite**

Run: `rake test`
Expected: All pass

- [ ] **Step 4: Run JS tests**

Run: `npm test`
Expected: All pass (classifier and fold tests don't reference controllers)

- [ ] **Step 5: Commit**

```
refactor: remove superseded plaintext and coordinator controllers
```

---

## Task 8: Smoke test in browser

Manual verification that both editors work correctly after the consolidation.

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`

- [ ] **Step 2: Test recipe editing**

1. Navigate to homepage, click "Add Recipe"
2. Verify the plaintext editor opens with template content and syntax highlighting
3. Toggle to graphical mode — verify fields populate
4. Toggle back to plaintext — verify content round-trips
5. Save a new recipe, verify redirect

- [ ] **Step 3: Test recipe editing (existing)**

1. Navigate to a recipe, click "Edit"
2. Verify content loads with syntax highlighting and fold gutters
3. Toggle modes, verify round-trip
4. Make a change, verify dirty detection (close prompts "unsaved changes")
5. Save, verify dialog closes

- [ ] **Step 4: Test Quick Bites editing**

1. Navigate to Menu page, click "Edit QuickBites"
2. Verify content loads with category/item highlighting
3. Toggle modes, verify round-trip
4. Save, verify dialog closes

- [ ] **Step 5: Stop dev server and commit any fixes**

If any issues were found, fix and commit before proceeding.

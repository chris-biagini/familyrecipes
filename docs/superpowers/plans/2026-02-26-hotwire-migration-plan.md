# Hotwire Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Introduce Stimulus + Turbo (Hotwire) to replace all vanilla JS with structured controllers, enable Turbo Drive for instant navigation, and add Turbo Streams so grocery content changes update live instead of requiring a full page reload.

**Architecture:** Hybrid approach — existing GrocerySync version-polling stays for list state changes (selection, check-offs, custom items). Turbo Streams added only for content changes (quick bites, aisle order). All JS converted to Stimulus controllers with importmap-rails. No build step, no Node.

**Tech Stack:** Rails 8, importmap-rails, turbo-rails, stimulus-rails, Propshaft, Solid Cable, ActionCable

**Design doc:** `docs/plans/2026-02-26-hotwire-migration-design.md`

---

## Task 0: Take Baseline Screenshots

Before any code changes, capture the visual state of every page for regression comparison.

**Step 1: Start the dev server**

```bash
pkill -f puma; rm -f tmp/pids/server.pid
bin/dev &
```

Wait for server to boot on port 3030.

**Step 2: Take baseline screenshots of every page state**

Use Playwright to capture:
- Homepage (logged in)
- Recipe page (any recipe with nutrition)
- Recipe page scaled (x2)
- Ingredients page
- Groceries page (empty state)
- Groceries page (recipes selected, shopping list visible)
- Groceries page (items checked off, aisles collapsed)
- Groceries page (custom items added)
- Editor dialog open (any page)

Save all screenshots to `~/screenshots/baseline/` with descriptive names.

**Step 3: Record page weights**

```bash
curl -s -o /dev/null -w '%{size_download}' http://localhost:3030/ > ~/screenshots/baseline/page-weights.txt
curl -s -o /dev/null -w '%{size_download}' http://localhost:3030/groceries >> ~/screenshots/baseline/page-weights.txt
```

**Step 4: Run existing tests to confirm clean baseline**

```bash
rake test
rake lint
```

Expected: all pass.

---

## Task 1: Install Hotwire Gems and Importmap

**Files:**
- Modify: `Gemfile`
- Create: `config/importmap.rb`
- Create: `app/javascript/application.js`
- Create: `app/javascript/controllers/application.js`
- Create: `app/javascript/controllers/index.js`
- Modify: `app/views/layouts/application.html.erb`

**Step 1: Add gems to Gemfile**

Add these three gems after the `solid_cable` line (line 15 of `Gemfile`):

```ruby
gem 'importmap-rails'
gem 'stimulus-rails'
gem 'turbo-rails'
```

**Step 2: Bundle install**

```bash
bundle install
```

**Step 3: Run the importmap installer**

```bash
bin/rails importmap:install
```

This creates `config/importmap.rb`, `app/javascript/application.js`, `bin/importmap`, and `vendor/javascript/.keep`. It may also try to modify the layout — check what it does and adjust.

**Step 4: Run the Turbo installer**

```bash
bin/rails turbo:install
```

This pins `@hotwired/turbo-rails` in `config/importmap.rb` and adds the import to `app/javascript/application.js`.

**Step 5: Run the Stimulus installer**

```bash
bin/rails stimulus:install
```

This creates `app/javascript/controllers/application.js`, `app/javascript/controllers/index.js`, pins Stimulus in `config/importmap.rb`, and adds `import "controllers"` to `app/javascript/application.js`.

**Step 6: Verify importmap.rb**

`config/importmap.rb` should contain:

```ruby
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
```

**Step 7: Verify application.js**

`app/javascript/application.js` should contain:

```javascript
import "@hotwired/turbo-rails"
import "controllers"
```

**Step 8: Verify controllers/application.js**

`app/javascript/controllers/application.js` should contain:

```javascript
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false
window.Stimulus = application

export { application }
```

**Step 9: Verify controllers/index.js**

`app/javascript/controllers/index.js` should contain:

```javascript
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
```

**Step 10: Update the layout to load importmap alongside existing scripts**

In `app/views/layouts/application.html.erb`, add the importmap tags. The layout currently has `javascript_include_tag 'sw-register'` on line 14. Add the importmap tags right before it. Both the old script tags AND importmap will load during the transition period.

The `<head>` section should look like:

```erb
<%= csrf_meta_tags %>
<%= stylesheet_link_tag 'style' %>
<link rel="icon" type="image/svg+xml" href="<%= asset_path('favicon.svg') %>">
<link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32.png') %>">
<link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon.png') %>">
<link rel="manifest" href="/manifest.json">
<%= javascript_importmap_tags %>
<%= javascript_include_tag 'sw-register', defer: true %>
<%= yield :head %>
```

**Step 11: Restart the server and verify**

```bash
pkill -f puma; rm -f tmp/pids/server.pid
bin/dev &
```

Visit the site in Playwright. Verify:
- All pages load without JS errors (check browser console)
- Turbo Drive is active (clicking links should not trigger full page reload — check network tab or look for `turbo:load` events)
- Existing JS still works (editor dialogs, grocery page, recipe scaling)
- No visual changes

**Step 12: Run tests**

```bash
rake test && rake lint
```

**Step 13: Commit**

```bash
git add -A
git commit -m "feat: install Hotwire (importmap-rails, turbo-rails, stimulus-rails)"
```

---

## Task 2: Convert Notify to ES Module

**Files:**
- Create: `app/javascript/utilities/notify.js`
- Modify: `config/importmap.rb` (add pin)

The Notify module is used by wake-lock, grocery sync, and editor-framework. Convert it to an ES module first so other controllers can import it.

**Step 1: Create the utility module**

Create `app/javascript/utilities/notify.js`. This is a direct port of `app/assets/javascripts/notify.js` (90 lines) to ES module syntax. The IIFE wrapper becomes named exports. Key changes:
- Remove the IIFE wrapper
- Export `show` and `dismiss` as named exports
- Keep the same DOM construction logic (createElement, not innerHTML — CSP safe)
- Keep the same transition animation logic

```javascript
let container = null
let timer = null

function getContainer() {
  if (!container) {
    container = document.createElement('div')
    container.className = 'notify-bar'
    container.hidden = true
    document.body.appendChild(container)
  }
  return container
}

export function dismiss(instant) {
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
  const bar = container
  if (!bar || bar.hidden) return
  if (instant) {
    bar.hidden = true
    bar.classList.remove('notify-visible')
    return
  }
  bar.classList.remove('notify-visible')
  let dismissed = false
  bar.addEventListener('transitionend', function handler() {
    bar.removeEventListener('transitionend', handler)
    if (!dismissed) { dismissed = true; bar.hidden = true }
  })
  setTimeout(() => {
    if (!dismissed) { dismissed = true; bar.hidden = true }
  }, 400)
}

export function show(message, options = {}) {
  dismiss(true)

  const bar = getContainer()
  bar.textContent = ''
  bar.hidden = false

  const msg = document.createElement('span')
  msg.className = 'notify-message'
  msg.textContent = message
  bar.appendChild(msg)

  const actions = document.createElement('span')
  actions.className = 'notify-actions'

  if (options.action) {
    const actionBtn = document.createElement('button')
    actionBtn.type = 'button'
    actionBtn.textContent = options.action.label
    actionBtn.className = 'btn'
    actionBtn.addEventListener('click', () => {
      options.action.callback()
      dismiss()
    })
    actions.appendChild(actionBtn)
  }

  const dismissBtn = document.createElement('button')
  dismissBtn.type = 'button'
  dismissBtn.className = 'notify-dismiss'
  dismissBtn.textContent = '\u00d7'
  dismissBtn.setAttribute('aria-label', 'Dismiss')
  dismissBtn.addEventListener('click', () => dismiss())
  actions.appendChild(dismissBtn)

  if (!options.persistent) {
    timer = setTimeout(() => dismiss(), 5000)
  }

  bar.appendChild(actions)
  bar.offsetHeight
  bar.classList.add('notify-visible')
}
```

**Step 2: Pin the utility in importmap**

Add to `config/importmap.rb`:

```ruby
pin_all_from "app/javascript/utilities", under: "utilities"
```

This makes it importable as `import { show, dismiss } from "utilities/notify"`.

**Step 3: Verify the module loads**

In Playwright, open the browser console and check for import errors. The module won't be used yet (nothing imports it), but it should be available in the importmap.

**Step 4: Commit**

```bash
git add app/javascript/utilities/notify.js config/importmap.rb
git commit -m "feat: convert Notify to ES module"
```

---

## Task 3: Convert Editor Utils to ES Module

**Files:**
- Create: `app/javascript/utilities/editor_utils.js`

Port `app/assets/javascripts/editor-utils.js` (86 lines) to an ES module. This is a direct translation — the `window.EditorUtils` object becomes named exports.

**Step 1: Create the utility module**

Create `app/javascript/utilities/editor_utils.js`:

```javascript
export function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

export function showErrors(container, errors) {
  const list = document.createElement('ul')
  errors.forEach(msg => {
    const li = document.createElement('li')
    li.textContent = msg
    list.appendChild(li)
  })
  container.replaceChildren(list)
  container.hidden = false
}

export function clearErrors(container) {
  container.replaceChildren()
  container.hidden = true
}

export function closeWithConfirmation(dialog, isModified, resetFn) {
  if (isModified() && !confirm('You have unsaved changes. Discard them?')) return
  resetFn()
  dialog.close()
}

export async function saveRequest(url, method, body) {
  return fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': getCsrfToken()
    },
    body: JSON.stringify(body)
  })
}

export function guardBeforeUnload(dialog, isModified) {
  let saving = false

  function handler(event) {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault()
    }
  }

  window.addEventListener('beforeunload', handler)

  return {
    markSaving() { saving = true },
    remove() { window.removeEventListener('beforeunload', handler) }
  }
}

export async function handleSave(saveBtn, errorsDiv, saveFn, onSuccess) {
  saveBtn.disabled = true
  saveBtn.textContent = 'Saving\u2026'
  clearErrors(errorsDiv)

  try {
    const response = await saveFn()

    if (response.ok) {
      onSuccess(await response.json())
    } else if (response.status === 422) {
      const data = await response.json()
      showErrors(errorsDiv, data.errors)
      saveBtn.disabled = false
      saveBtn.textContent = 'Save'
    } else {
      showErrors(errorsDiv, [`Server error (${response.status}). Please try again.`])
      saveBtn.disabled = false
      saveBtn.textContent = 'Save'
    }
  } catch {
    showErrors(errorsDiv, ['Network error. Please check your connection and try again.'])
    saveBtn.disabled = false
    saveBtn.textContent = 'Save'
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/utilities/editor_utils.js
git commit -m "feat: convert EditorUtils to ES module"
```

---

## Task 4: Convert Wake Lock to Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/wake_lock_controller.js`
- Modify: `app/views/groceries/show.html.erb` (add `data-controller`)
- Modify: `app/views/recipes/show.html.erb` (add `data-controller`)

**Step 1: Create the controller**

Create `app/javascript/controllers/wake_lock_controller.js`. This controller attaches to any element where wake lock is desired. It replaces the self-executing IIFE in `app/assets/javascripts/wake-lock.js`.

Key difference from vanilla version: `connect()` starts the timer, `disconnect()` cleans up. This makes it Turbo Drive safe — navigating away releases the lock automatically.

```javascript
import { Controller } from "@hotwired/stimulus"
import { show as notifyShow, dismiss as notifyDismiss } from "utilities/notify"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 600000 },
    warning: { type: Number, default: 480000 }
  }

  connect() {
    if (!('wakeLock' in navigator)) return

    this.lock = null
    this.acquiring = false
    this.inactivityTimer = null
    this.warningTimer = null
    this.warningShown = false

    this.boundOnActivity = this.onActivity.bind(this)
    this.boundOnVisibility = this.onVisibilityChange.bind(this)

    window.addEventListener('scroll', this.boundOnActivity, { passive: true })
    document.addEventListener('pointerdown', this.boundOnActivity)
    document.addEventListener('change', this.boundOnActivity)
    document.addEventListener('visibilitychange', this.boundOnVisibility)

    this.resetTimer()
  }

  disconnect() {
    this.clearTimers()
    this.releaseLock()

    if (this.warningShown) {
      notifyDismiss(true)
      this.warningShown = false
    }

    window.removeEventListener('scroll', this.boundOnActivity)
    document.removeEventListener('pointerdown', this.boundOnActivity)
    document.removeEventListener('change', this.boundOnActivity)
    document.removeEventListener('visibilitychange', this.boundOnVisibility)
  }

  acquire() {
    if (this.lock || this.acquiring) return
    this.acquiring = true
    navigator.wakeLock.request('screen').then(sentinel => {
      this.lock = sentinel
      this.acquiring = false
      this.lock.addEventListener('release', () => { this.lock = null })
    }).catch(() => { this.acquiring = false })
  }

  releaseLock() {
    if (this.lock) {
      this.lock.release().catch(() => {})
      this.lock = null
    }
  }

  clearTimers() {
    if (this.inactivityTimer) { clearTimeout(this.inactivityTimer); this.inactivityTimer = null }
    if (this.warningTimer) { clearTimeout(this.warningTimer); this.warningTimer = null }
  }

  resetTimer() {
    this.clearTimers()
    if (this.warningShown) {
      notifyDismiss(true)
      this.warningShown = false
    }
    if (!this.lock) this.acquire()

    this.warningTimer = setTimeout(() => {
      this.warningShown = true
      notifyShow('Screen will sleep soon \u2014 tap anywhere to stay awake', {
        persistent: true,
        action: { label: 'Stay awake', callback: () => this.resetTimer() }
      })
    }, this.warningValue)

    this.inactivityTimer = setTimeout(() => {
      if (this.warningShown) {
        notifyDismiss(true)
        this.warningShown = false
      }
      this.releaseLock()
    }, this.timeoutValue)
  }

  onActivity() {
    this.resetTimer()
  }

  onVisibilityChange() {
    if (document.visibilityState === 'visible') {
      this.resetTimer()
    } else {
      this.clearTimers()
      if (this.warningShown) {
        notifyDismiss(true)
        this.warningShown = false
      }
      this.releaseLock()
    }
  }
}
```

**Step 2: Add controller to grocery page**

In `app/views/groceries/show.html.erb`, the `#groceries-app` div (line 33) already has data attributes. Add `data-controller="wake-lock"` to it. Later when we add the grocery controllers, they'll share this element.

**Step 3: Add controller to recipe page**

In `app/views/recipes/show.html.erb`, add `data-controller="wake-lock"` to the `<article class="recipe">` element (line 24).

**Step 4: Remove old wake-lock script tags**

In `app/views/groceries/show.html.erb` line 10, remove:
```erb
<%= javascript_include_tag 'wake-lock', defer: true %>
```

In `app/views/recipes/show.html.erb` line 18, remove:
```erb
<%= javascript_include_tag 'wake-lock', defer: true %>
```

**Step 5: Verify in Playwright**

Open the groceries page and recipe page. Verify no console errors. The wake lock behavior is hard to test visually but confirm the controller connects (check `Stimulus.debug = true` in console or look for the controller in `document.querySelector('[data-controller="wake-lock"]')`).

**Step 6: Run tests**

```bash
rake test && rake lint
```

**Step 7: Commit**

```bash
git add app/javascript/controllers/wake_lock_controller.js
git add app/views/groceries/show.html.erb app/views/recipes/show.html.erb
git commit -m "feat: convert wake-lock to Stimulus controller"
```

---

## Task 5: Convert Editor Framework to Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/editor_controller.js`
- Modify: `app/views/shared/_editor_dialog.html.erb` (add Stimulus attributes)
- Modify: All views with editor dialogs (homepage, recipe, groceries, ingredients)

This is the most broadly-used controller — it handles all 4 editor dialogs across the app.

**Step 1: Create the editor controller**

Create `app/javascript/controllers/editor_controller.js`. This replaces `app/assets/javascripts/editor-framework.js` (202 lines). The controller attaches to each `<dialog>` element.

Key mapping from the vanilla version:
- `data-editor-open` → `data-editor-open-selector-value`
- `data-editor-url` → `data-editor-url-value`
- `data-editor-method` → `data-editor-method-value`
- `data-editor-on-success` → `data-editor-on-success-value`
- `data-editor-body-key` → `data-editor-body-key-value`
- `data-editor-load-url` → `data-editor-load-url-value`
- `data-editor-load-key` → `data-editor-load-key-value`
- `.editor-textarea` → `data-editor-target="textarea"`
- `.editor-save` → `data-editor-target="saveButton"`
- `.editor-cancel` → `data-editor-target="cancelButton"` with `data-action="click->editor#close"`
- `.editor-close` → `data-editor-target="closeButton"` with `data-action="click->editor#close"`
- `.editor-delete` → `data-editor-target="deleteButton"` with `data-action="click->editor#delete"`
- `.editor-errors` → `data-editor-target="errors"`

The controller must:
1. In `connect()`: find the open trigger button using `openSelectorValue`, bind its click handler. Set up the beforeunload guard. Check for `refs_updated` query param.
2. `open()`: Load content if `loadUrlValue` set, snapshot `originalContent`, show modal.
3. `close()`: Dirty-check via `isModified()`, confirm if needed, reset content, close dialog.
4. `save()`: Dispatch `editor:collect` and `editor:save` custom events for custom dialogs. Fall back to default textarea submission.
5. `delete()`: Confirm with recipe title and referencing recipes, send DELETE, redirect.
6. `disconnect()`: Remove beforeunload listener.

The custom event dispatch pattern (`editor:collect`, `editor:save`, `editor:modified`, `editor:reset`) stays exactly the same — the nutrition-editor controller will listen for these events.

Implementation should be a faithful port of the 202-line `editor-framework.js` into Stimulus patterns. The `refs_updated` query param handling moves to a `connect()` check.

**Step 2: Update the shared dialog partial**

Modify `app/views/shared/_editor_dialog.html.erb` to use Stimulus attributes instead of `data-editor-*`:

```erb
<%# locals: (title:, id: nil, dialog_data: {}, footer_extra: nil) %>
<%= tag.dialog id: id,
    class: 'editor-dialog',
    data: {
      controller: 'editor',
      editor_url_value: dialog_data[:editor_url],
      editor_method_value: dialog_data[:editor_method] || 'PATCH',
      editor_on_success_value: dialog_data[:editor_on_success] || 'redirect',
      editor_body_key_value: dialog_data[:editor_body_key] || 'markdown_source',
      editor_open_selector_value: dialog_data[:editor_open],
      editor_load_url_value: dialog_data[:editor_load_url],
      editor_load_key_value: dialog_data[:editor_load_key]
    }.compact do %>
  <div class="editor-header">
    <h2><%= title %></h2>
    <button type="button" class="btn editor-close" data-editor-target="closeButton" data-action="click->editor#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-editor-target="errors" hidden></div>
  <%= yield %>
  <div class="editor-footer">
    <%= footer_extra %>
    <button type="button" class="btn editor-cancel" data-editor-target="cancelButton" data-action="click->editor#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save" data-editor-target="saveButton" data-action="click->editor#save">Save</button>
  </div>
<% end %>
```

**Step 3: Update views that render editor dialogs**

Each view passes `dialog_data` to the partial. The keys need to change from the `data-editor-*` HTML attribute convention to the Ruby hash keys that `tag.dialog` will convert.

Update the `dialog_data` hashes in:
- `app/views/homepage/show.html.erb` (lines 48-55)
- `app/views/recipes/show.html.erb` (lines 55-63)
- `app/views/groceries/show.html.erb` (lines 96-116)
- `app/views/ingredients/index.html.erb` (lines 59-63)

Each view's `dialog_data` hash keys should match the new partial's expected keys (`:editor_url`, `:editor_method`, `:editor_on_success`, `:editor_body_key`, `:editor_open`, `:editor_load_url`, `:editor_load_key`).

Also add `data-editor-target="textarea"` to each `<textarea>` inside the dialogs. For the ingredients page, the textarea has `id="nutrition-editor-textarea"` — it keeps that id but also gets the target attribute.

**Step 4: Add `data-editor-target="deleteButton"` and action to delete buttons**

In `app/views/recipes/_editor_delete_button.html.erb`, add `data-editor-target="deleteButton"` and `data-action="click->editor#delete"` to the delete button.

**Step 5: Remove old script tags from all views**

Remove `javascript_include_tag 'editor-utils'` and `javascript_include_tag 'editor-framework'` from:
- `app/views/groceries/show.html.erb` (lines 12-13)
- `app/views/recipes/show.html.erb` (lines 20-21)
- `app/views/homepage/show.html.erb` (lines 13-14)
- `app/views/ingredients/index.html.erb` (lines 69-70)

**Step 6: Verify every editor dialog on every page**

Use Playwright to test on each page:
1. Click the open button — dialog opens
2. Type something — dirty state tracked
3. Press Escape — confirmation dialog appears ("Unsaved changes?")
4. Click Cancel — confirmation dialog appears
5. Click Save — request sent, success handled (redirect or reload)
6. For recipe page: delete button works with confirmation

**Step 7: Run tests**

```bash
rake test && rake lint
```

**Step 8: Commit**

```bash
git add app/javascript/controllers/editor_controller.js
git add app/views/shared/_editor_dialog.html.erb
git add app/views/homepage/show.html.erb app/views/recipes/show.html.erb
git add app/views/groceries/show.html.erb app/views/ingredients/index.html.erb
git commit -m "feat: convert editor framework to Stimulus controller"
```

---

## Task 6: Convert Nutrition Editor to Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/nutrition_editor_controller.js`
- Modify: `app/views/ingredients/index.html.erb` (add controller attribute, targets)

**Step 1: Create the controller**

Create `app/javascript/controllers/nutrition_editor_controller.js`. Port `app/assets/javascripts/nutrition-editor.js` (127 lines).

This controller attaches to the `#nutrition-editor` dialog alongside the editor controller (multi-controller on one element). It listens for `editor:collect`, `editor:save`, `editor:modified`, and `editor:reset` custom events dispatched by the editor controller.

Key elements:
- Per-ingredient edit buttons (`.nutrition-edit-btn`) open the dialog with ingredient-specific data
- Aisle selector with "Other" option showing a text input
- Reset buttons (`.nutrition-reset-btn`) send DELETE requests
- The controller stores `currentIngredient`, `originalContent`, `originalAisle` state
- Custom event handlers override the editor controller's defaults via `detail.handled = true`

Import `getCsrfToken` from `utilities/editor_utils` for the reset button's DELETE request.

**Step 2: Update the ingredients view**

Add `data-controller="nutrition-editor"` to the `#nutrition-editor` dialog (it already has `data-controller="editor"` from Task 5 — use space-separated values: `data-controller="editor nutrition-editor"`).

Add Stimulus targets to the textarea, aisle select, aisle input, and title elements inside the dialog.

Add `data-action` attributes to the `.nutrition-edit-btn` and `.nutrition-reset-btn` buttons. These are dynamically created per-ingredient, so use event delegation or add the attributes in the ERB loop.

**Step 3: Remove old script tag**

Remove `javascript_include_tag 'nutrition-editor'` from `app/views/ingredients/index.html.erb` (line 71).

**Step 4: Verify in Playwright**

On the ingredients page:
1. Click "Edit" on an ingredient — dialog opens with correct data
2. Change the aisle selector — dirty state detected
3. Select "Other" aisle — text input appears
4. Save — request succeeds, page reloads with updated data
5. Click "Reset" on a custom ingredient — confirmation, DELETE request, page reloads

**Step 5: Run tests**

```bash
rake test && rake lint
```

**Step 6: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git add app/views/ingredients/index.html.erb
git commit -m "feat: convert nutrition editor to Stimulus controller"
```

---

## Task 7: Convert Recipe State Manager to Stimulus Controller

**Files:**
- Create: `app/javascript/utilities/vulgar_fractions.js`
- Create: `app/javascript/controllers/recipe_state_controller.js`
- Modify: `app/views/recipes/show.html.erb` (add controller attribute)

**Step 1: Extract vulgar fraction utilities**

Create `app/javascript/utilities/vulgar_fractions.js` with the `VULGAR_FRACTIONS` table, `formatVulgar()`, and `isVulgarSingular()` functions from lines 1-21 of `recipe-state-manager.js`:

```javascript
const VULGAR_FRACTIONS = [
  [1/2, '\u00BD'], [1/3, '\u2153'], [2/3, '\u2154'],
  [1/4, '\u00BC'], [3/4, '\u00BE'],
  [1/8, '\u215B'], [3/8, '\u215C'], [5/8, '\u215D'], [7/8, '\u215E']
]

export function formatVulgar(value) {
  if (Number.isInteger(value)) return String(value)
  const intPart = Math.floor(value)
  const fracPart = value - intPart
  const match = VULGAR_FRACTIONS.find(([v]) => Math.abs(fracPart - v) < 0.001)
  if (match) return intPart === 0 ? match[1] : `${intPart}${match[1]}`
  const rounded = Math.round(value * 100) / 100
  return String(rounded)
}

export function isVulgarSingular(value) {
  if (Math.abs(value - 1) < 0.001) return true
  if (value <= 0 || value >= 1) return false
  return VULGAR_FRACTIONS.some(([v]) => Math.abs(value - v) < 0.001)
}
```

**Step 2: Create the recipe state controller**

Create `app/javascript/controllers/recipe_state_controller.js`. Port the `RecipeStateManager` class (lines 23-272 of `recipe-state-manager.js`).

The controller attaches to `<article class="recipe">` or `<body>`. It reads `data-recipe-id` and `data-version-hash` from the body element (set via `content_for(:body_attrs)` in the recipe view).

Key mapping:
- `constructor()` + `init()` → `connect()`
- `DOMContentLoaded` handler → removed (Stimulus handles this)
- `setupEventListeners()` → called in `connect()`
- `setupScaleButton()` → called in `connect()`
- All localStorage persistence stays the same
- Import `formatVulgar` and `isVulgarSingular` from `utilities/vulgar_fractions`

**Step 3: Update recipe view**

In `app/views/recipes/show.html.erb`, add `data-controller="recipe-state"` to the `<article class="recipe">` element (line 24). The controller reads body data attributes for `recipeId` and `versionHash`.

**Step 4: Remove old script tag**

Remove `javascript_include_tag 'recipe-state-manager'` from `app/views/recipes/show.html.erb` (line 19).

**Step 5: Verify in Playwright**

On any recipe page:
1. Click an ingredient — it crosses off
2. Click a step header — all items in section toggle
3. Reload the page — crossed-off state is preserved
4. Click Scale button — prompt appears, enter "2"
5. Verify quantities double
6. Reload — scale factor preserved
7. Navigate to a different recipe and back — state is independent per recipe

**Step 6: Run tests**

```bash
rake test && rake lint
```

**Step 7: Commit**

```bash
git add app/javascript/utilities/vulgar_fractions.js
git add app/javascript/controllers/recipe_state_controller.js
git add app/views/recipes/show.html.erb
git commit -m "feat: convert recipe state manager to Stimulus controller"
```

---

## Task 8: Convert Grocery Sync to Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/grocery_sync_controller.js`
- Modify: `app/views/groceries/show.html.erb` (add controller)

This is the highest-risk conversion. The GrocerySync object (~210 lines) handles ActionCable subscription, version tracking, heartbeat polling, pending action queue, and localStorage caching. Port it faithfully — no logic changes.

**Step 1: Create the grocery sync controller**

Create `app/javascript/controllers/grocery_sync_controller.js`. Port the `GrocerySync` object from `app/assets/javascripts/groceries.js` lines 8-209.

Key mapping:
- `GrocerySync.init(app)` → `connect()`. Read URLs and kitchen slug from element data attributes.
- `GrocerySync.subscribe(slug)` → called in `connect()`. Create ActionCable consumer and subscription.
- `GrocerySync.startHeartbeat()` → called in `connect()`. Start 30-second interval.
- `disconnect()` → unsubscribe from ActionCable, clear heartbeat interval, clear timers.
- `GrocerySync.fetchState()` → method that GETs `/groceries/state` and calls the UI controller's `applyState()`.
- `GrocerySync.sendAction(url, params)` → method called by the UI controller for mutations.
- localStorage caching and pending queue stay the same.

The sync controller needs to call methods on the grocery UI controller. Use `this.application.getControllerForElementAndIdentifier(this.element, 'grocery-ui')` to get a reference.

Import `show` from `utilities/notify` for the "List updated from another device" notification.

The `ActionCable` global is available because `turbo-rails` bundles its own ActionCable client. If it's not available as a global, import it: `import { createConsumer } from "@rails/actioncable"`. Check which approach `turbo-rails` uses — it may expose `Turbo.cable` or the consumer may need to be created from `@rails/actioncable`. If `turbo-rails` includes ActionCable, you can use `import consumer from "channels/consumer"` or create one directly.

**Important**: The existing code uses `ActionCable.createConsumer()` as a global. With turbo-rails, ActionCable is bundled inside turbo.min.js. You may need to access it via `window.Turbo` or create a consumer utility. Research the exact import path and document it.

**Step 2: Add controller to groceries view**

Add `grocery-sync` to the `data-controller` attribute on `#groceries-app` (which already has `wake-lock` from Task 4):

```erb
data-controller="wake-lock grocery-sync grocery-ui"
```

**Step 3: Verify ActionCable subscription**

In Playwright, open the groceries page. Check the browser console for ActionCable subscription messages. Verify the controller connects by checking `Stimulus.debug = true` output.

**Step 4: Do NOT remove old script tags yet**

The old `groceries.js` still provides `GroceryUI`. Both systems will coexist until Task 9.

**Step 5: Run tests**

```bash
rake test && rake lint
```

**Step 6: Commit**

```bash
git add app/javascript/controllers/grocery_sync_controller.js
git add app/views/groceries/show.html.erb
git commit -m "feat: convert GrocerySync to Stimulus controller"
```

---

## Task 9: Convert Grocery UI to Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/grocery_ui_controller.js`
- Modify: `app/views/groceries/show.html.erb` (update controller list)

**Step 1: Create the grocery UI controller**

Create `app/javascript/controllers/grocery_ui_controller.js`. Port the `GroceryUI` object from `app/assets/javascripts/groceries.js` lines 215-703.

Key mapping:
- `GroceryUI.init(app)` → `connect()`. Bind recipe checkboxes, custom item input, shopping list events.
- `GroceryUI.applyState(state)` → `applyState(state)` method called by the sync controller.
- All DOM rendering methods (`renderShoppingList`, `renderCustomItems`, `syncCheckedOff`, `renderItemCount`, etc.) become controller methods.
- Aisle collapse animation methods stay the same.
- `formatAmounts()` utility stays as a private method.
- The `hidden-until-js` class removal moves to `connect()`.

The UI controller gets a reference to the sync controller for sending actions:
```javascript
get syncController() {
  return this.application.getControllerForElementAndIdentifier(this.element, 'grocery-sync')
}
```

Checkbox change handlers call `this.syncController.sendAction(url, params)` instead of `GrocerySync.sendAction(...)`.

**Step 2: Remove old groceries.js script tag and related tags**

In `app/views/groceries/show.html.erb`, remove from the `content_for(:scripts)` block:
- `javascript_include_tag 'actioncable'` (ActionCable now bundled with Turbo)
- `javascript_include_tag 'notify'` (now an ES module)
- `javascript_include_tag 'groceries'` (replaced by Stimulus controllers)

If the `content_for(:scripts)` block is now empty, remove it entirely.

**Step 3: Take comparison screenshots**

Use Playwright to screenshot the groceries page in all baseline states:
- Empty state
- Recipes selected
- Items checked off
- Aisles collapsed
- Custom items added

Compare with `~/screenshots/baseline/` screenshots. They should be pixel-identical.

**Step 4: Functional verification in Playwright**

1. Select a recipe checkbox — shopping list appears
2. Check off an item — it's marked, item count updates
3. Check off all items in an aisle — aisle auto-collapses with animation
4. Add a custom item — appears in custom items list
5. Remove a custom item — disappears
6. Click Clear — everything resets
7. Open in a second tab — changes in one tab appear in the other (via ActionCable)

**Step 5: Run tests**

```bash
rake test && rake lint
```

**Step 6: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git add app/views/groceries/show.html.erb
git commit -m "feat: convert GroceryUI to Stimulus controller"
```

---

## Task 10: Convert SW Register and Clean Up Old Files

**Files:**
- Modify: `app/javascript/application.js` (add sw-register import)
- Delete: `app/assets/javascripts/sw-register.js`
- Delete: `app/assets/javascripts/notify.js`
- Delete: `app/assets/javascripts/wake-lock.js`
- Delete: `app/assets/javascripts/editor-framework.js`
- Delete: `app/assets/javascripts/editor-utils.js`
- Delete: `app/assets/javascripts/nutrition-editor.js`
- Delete: `app/assets/javascripts/recipe-state-manager.js`
- Delete: `app/assets/javascripts/groceries.js`
- Modify: All views — remove any remaining `content_for(:scripts)` blocks

**Step 1: Move service worker registration into application.js**

The current `sw-register.js` is 3 lines. Add the registration to `app/javascript/application.js`:

```javascript
import "@hotwired/turbo-rails"
import "controllers"

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/service-worker.js')
}
```

**Step 2: Remove the old sw-register script tag from layout**

In `app/views/layouts/application.html.erb`, remove line 14:
```erb
<%= javascript_include_tag 'sw-register', defer: true %>
```

**Step 3: Remove the old notify script tags from all views**

Remove `javascript_include_tag 'notify'` from:
- `app/views/groceries/show.html.erb`
- `app/views/recipes/show.html.erb` (line 17)
- `app/views/homepage/show.html.erb` (line 12)

**Step 4: Remove all remaining `content_for(:scripts)` blocks**

Check every view file. Remove any `content_for(:scripts)` blocks that are now empty or only contain removed script tags. Also remove `<%= yield :scripts %>` from `app/views/layouts/application.html.erb` (line 22) if no view still uses it.

**Step 5: Delete all old JS files**

```bash
rm app/assets/javascripts/sw-register.js
rm app/assets/javascripts/notify.js
rm app/assets/javascripts/wake-lock.js
rm app/assets/javascripts/editor-framework.js
rm app/assets/javascripts/editor-utils.js
rm app/assets/javascripts/nutrition-editor.js
rm app/assets/javascripts/recipe-state-manager.js
rm app/assets/javascripts/groceries.js
```

Verify `app/assets/javascripts/` is now empty (or only contains `actioncable.js` if it was a standalone file — check).

**Step 6: Verify every page works**

Use Playwright to visit every page and verify no console errors:
- Homepage
- Recipe page
- Ingredients page
- Groceries page

**Step 7: Run tests**

```bash
rake test && rake lint
```

**Step 8: Commit**

```bash
git add -A
git commit -m "chore: remove legacy vanilla JS, complete Stimulus migration"
```

---

## Task 11: Extract Grocery Page Server-Side Partials

**Files:**
- Create: `app/views/groceries/_recipe_selector.html.erb`
- Create: `app/views/groceries/_shopping_list.html.erb`
- Create: `app/views/groceries/_custom_items.html.erb`
- Modify: `app/views/groceries/show.html.erb` (render partials)
- Modify: `app/controllers/groceries_controller.rb` (pass shopping list to view)

This task prepares for Turbo Streams by extracting partials. No Turbo Stream broadcasting yet — just restructuring.

**Step 1: Extract the recipe selector partial**

Move lines 43-78 of `app/views/groceries/show.html.erb` (the `#recipe-selector` div and everything inside it) into `app/views/groceries/_recipe_selector.html.erb`.

The partial needs:
- `categories` local (array of categories with recipes)
- `quick_bites_by_subsection` local (hash of subsection → items)
- `grocery_list` local (to render correct checkbox states)

The partial wraps its content in `<div id="recipe-selector" data-type="recipe">` so Turbo Streams can target it.

Update `show.html.erb` to render it:
```erb
<%= render 'recipe_selector',
    categories: @categories,
    quick_bites_by_subsection: @quick_bites_by_subsection,
    grocery_list: @grocery_list %>
```

**Step 2: Create the shopping list partial**

Create `app/views/groceries/_shopping_list.html.erb`. This is NEW — the shopping list is currently rendered entirely in JavaScript. The partial must produce HTML identical to what `GroceryUI.renderShoppingList()` produces.

The partial needs:
- `shopping_list` local (ordered hash of aisle name → array of {name:, amounts:})
- `checked_off` local (array of checked item names)

The HTML structure must match exactly what the JS renders:
- `<div id="shopping-list">` wrapper
- `<div class="shopping-list-header">` with `<h2>Shopping List</h2>` and `<span id="item-count">`
- `<details class="aisle" data-aisle="...">` for each aisle
  - `<summary>` with aisle name and count
  - `<ul>` with `<li data-item="...">` for each item
    - `<span class="check-off"><input type="checkbox" data-item="..."></span>`
    - `<span class="item-name">...</span>`
    - `<span class="item-amounts">...</span>`

**Important**: Study `GroceryUI.renderShoppingList()` carefully and match every class, attribute, and structure exactly. Playwright screenshots will catch any differences.

**Step 3: Create the custom items partial**

Create `app/views/groceries/_custom_items.html.erb`. The partial renders the `<ul id="custom-items-list">` contents.

Needs:
- `custom_items` local (array of strings)

Each item renders as `<li><span>item name</span><button class="custom-item-remove" data-item="...">×</button></li>`.

**Step 4: Update the controller to pass data to the view**

In `app/controllers/groceries_controller.rb`, the `show` action (lines 8-12) currently doesn't load the grocery list or shopping list — those are fetched via the JSON `state` endpoint. For server-side rendering, the show action needs to load them:

```ruby
def show
  @categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
  @quick_bites_by_subsection = load_quick_bites_by_subsection
  @quick_bites_content = current_kitchen.quick_bites_content || ''
  @grocery_list = GroceryList.for_kitchen(current_kitchen)
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, grocery_list: @grocery_list).build
end
```

**Step 5: Update show.html.erb to render partials**

Replace the inline recipe selector with the partial render. Replace `<div id="shopping-list"></div>` (line 91) with:

```erb
<%= render 'shopping_list',
    shopping_list: @shopping_list,
    checked_off: @grocery_list.state.fetch('checked_off', []) %>
```

Replace `<ul id="custom-items-list"></ul>` (line 88) with:

```erb
<%= render 'custom_items',
    custom_items: @grocery_list.state.fetch('custom_items', []) %>
```

**Step 6: Verify visual parity**

Take Playwright screenshots of the groceries page in multiple states and compare with baseline. The server-rendered shopping list must look identical to what JS was rendering.

**Step 7: Verify JS still works**

The grocery UI controller still re-renders the shopping list client-side on state changes. Verify that selecting a recipe updates the list, checking items works, etc. The initial render is now server-side, but subsequent updates are still client-side.

**Step 8: Run tests**

```bash
rake test && rake lint
```

**Step 9: Commit**

```bash
git add app/views/groceries/_recipe_selector.html.erb
git add app/views/groceries/_shopping_list.html.erb
git add app/views/groceries/_custom_items.html.erb
git add app/views/groceries/show.html.erb
git add app/controllers/groceries_controller.rb
git commit -m "feat: extract grocery page server-side partials"
```

---

## Task 12: Add Turbo Streams for Content Changes

**Files:**
- Modify: `app/views/groceries/show.html.erb` (add `turbo_stream_from`)
- Modify: `app/controllers/groceries_controller.rb` (broadcast Turbo Streams)
- Modify: `app/javascript/controllers/grocery_sync_controller.js` (remove content_changed handler)
- Modify: `app/javascript/controllers/grocery_ui_controller.js` (restore aisle collapse after stream replace)

**Step 1: Add Turbo Stream subscription to the groceries view**

In `app/views/groceries/show.html.erb`, add near the top (after the header, before `#groceries-app`):

```erb
<%= turbo_stream_from current_kitchen, "groceries" %>
```

This renders a `<turbo-cable-stream-source>` element that subscribes to `Turbo::StreamsChannel` with a signed stream name derived from the kitchen + "groceries".

**Step 2: Broadcast Turbo Streams when quick bites are edited**

In `app/controllers/groceries_controller.rb`, modify `update_quick_bites` (lines 56-64). After saving, instead of (or in addition to) `broadcast_content_changed`, broadcast a Turbo Stream that replaces the recipe selector:

```ruby
def update_quick_bites
  content = params[:content].to_s
  return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

  current_kitchen.update!(quick_bites_content: content)

  broadcast_grocery_update
  render json: { status: 'ok' }
end
```

Create a private helper method:

```ruby
def broadcast_grocery_update
  list = GroceryList.for_kitchen(current_kitchen)
  shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, grocery_list: list).build
  quick_bites_by_subsection = load_quick_bites_by_subsection
  categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })

  Turbo::StreamsChannel.broadcast_replace_to(
    current_kitchen, 'groceries',
    target: 'recipe-selector',
    partial: 'groceries/recipe_selector',
    locals: {
      categories: categories,
      quick_bites_by_subsection: quick_bites_by_subsection,
      grocery_list: list
    }
  )

  Turbo::StreamsChannel.broadcast_replace_to(
    current_kitchen, 'groceries',
    target: 'shopping-list',
    partial: 'groceries/shopping_list',
    locals: {
      shopping_list: shopping_list,
      checked_off: list.state.fetch('checked_off', [])
    }
  )
end
```

**Step 3: Broadcast Turbo Streams when aisle order is edited**

In `update_aisle_order` (lines 66-79), replace the version broadcast with the Turbo Stream broadcast. The shopping list needs to re-render with new aisle ordering:

```ruby
def update_aisle_order
  current_kitchen.aisle_order = params[:aisle_order].to_s
  current_kitchen.normalize_aisle_order!

  errors = validate_aisle_order
  return render json: { errors: }, status: :unprocessable_content if errors.any?

  current_kitchen.save!

  broadcast_grocery_update
  render json: { status: 'ok' }
end
```

**Step 4: Remove content_changed handling from grocery sync controller**

In `app/javascript/controllers/grocery_sync_controller.js`, the ActionCable subscription handler currently checks for `data.type === 'content_changed'` and shows a persistent "Reload" notification. Remove that branch — Turbo Streams handle content updates now.

Keep the `data.version` handling (for list state changes from other devices).

**Step 5: Restore aisle collapse state after Turbo Stream replace**

When Turbo replaces `#shopping-list`, the `<details>` open/closed state is lost. The grocery UI controller needs to re-apply it.

Add a `turbo:before-stream-render` event listener in the grocery UI controller's `connect()` that, after a stream targeting `shopping-list` renders, re-applies the aisle collapse state from localStorage and re-syncs checked-off state.

Alternatively, listen for the Turbo Stream `turbo:after-stream-render` event (if available) or use a `MutationObserver` on `#shopping-list`.

The simplest approach may be a custom `turbo:before-stream-render` handler that wraps the default render to call `restoreAisleCollapse()` after:

```javascript
document.addEventListener('turbo:before-stream-render', (event) => {
  const originalRender = event.detail.render
  event.detail.render = async (streamElement) => {
    await originalRender(streamElement)
    // After the stream renders, restore client-side state
    this.restoreAisleCollapse()
    this.renderItemCount()
  }
})
```

**Step 6: Update the editor success handler**

The quick bites and aisle order editor dialogs currently use `editor_on_success: 'reload'` which triggers `window.location.reload()`. Since Turbo Streams now update the page live, the editor should close the dialog without reloading. Change the `editor_on_success` to `'close'` and add handling in the editor controller for this new mode (just close the dialog).

Alternatively, keep the reload for the editing user — it's a simple approach and ensures their view is fully consistent. The Turbo Stream broadcast handles OTHER users' views. This is safer for the first pass.

**Step 7: Also keep the GroceryListChannel.broadcast_version call**

The `broadcast_grocery_update` replaces content via Turbo Streams, but the version broadcast is still needed for clients that are tracking state via the sync controller. Keep both:

```ruby
def broadcast_grocery_update
  list = GroceryList.for_kitchen(current_kitchen)
  # ... Turbo Stream broadcasts ...

  GroceryListChannel.broadcast_version(current_kitchen, list.lock_version)
end
```

This way, clients that receive the Turbo Stream get live HTML updates, and the version broadcast keeps the sync controller's version tracking accurate.

**Step 8: Remove GroceryListChannel.broadcast_content_changed**

Since we're no longer using the `content_changed` message type, remove it from:
- `app/channels/grocery_list_channel.rb` (lines 15-17)
- Any remaining call sites

Keep `broadcast_version` — it's still used for list state changes.

**Step 9: Verify in Playwright — the key test**

This is the critical verification:

1. Open groceries page in two browser tabs
2. In tab 1, edit quick bites (add a new item)
3. Verify: tab 2's recipe selector updates live (new checkbox appears) WITHOUT a page reload and WITHOUT a "Reload" notification
4. In tab 1, edit aisle order (reorder aisles)
5. Verify: tab 2's shopping list re-renders with new aisle order WITHOUT a page reload
6. Verify: aisle collapse state is preserved in tab 2 after the update
7. Verify: checked-off items are still checked after the update

**Step 10: Run tests**

```bash
rake test && rake lint
```

**Step 11: Commit**

```bash
git add app/views/groceries/show.html.erb
git add app/controllers/groceries_controller.rb
git add app/channels/grocery_list_channel.rb
git add app/javascript/controllers/grocery_sync_controller.js
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: add Turbo Streams for grocery content changes"
```

---

## Task 13: Update Tests for Hotwire

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `test/channels/grocery_list_channel_test.rb`
- Modify: `test/integration/end_to_end_test.rb`
- Possibly create: `test/controllers/turbo_stream_test.rb`

**Step 1: Update grocery controller tests**

The `update_quick_bites` and `update_aisle_order` actions now broadcast Turbo Streams. Add assertions that verify:
- The Turbo Stream broadcast is sent (use `assert_broadcast_on` or check that `Turbo::StreamsChannel` receives the broadcast)
- The `content_changed` broadcast is removed (test that the old message type is NOT sent)

**Step 2: Update channel tests**

Remove the test for `broadcast_content_changed` if we removed that method. Add a test verifying Turbo Stream broadcasts go to the correct stream name.

**Step 3: Verify integration tests still pass**

The end-to-end tests check page structure (CSS selectors, content). Since we've changed the groceries page to server-render the shopping list, some assertions may need updating if they relied on the empty `#shopping-list` div being empty on page load.

Check `test_groceries_page_renders_recipe_checkboxes_grouped_by_category` and `test_groceries_page_includes_noscript_fallback` — these should still pass since the recipe selector structure is unchanged.

**Step 4: Test Turbo Drive doesn't break navigation**

Add an integration test that verifies Turbo Drive meta tags are present:
- `<meta name="turbo-visit-control">` (if set)
- The importmap script tag is present

**Step 5: Run full test suite**

```bash
rake test && rake lint
```

**Step 6: Commit**

```bash
git add test/
git commit -m "test: update tests for Hotwire migration"
```

---

## Task 14: Visual Regression Check

**Step 1: Take post-migration screenshots**

Re-take all baseline screenshots using Playwright, saved to `~/screenshots/post-migration/`.

**Step 2: Compare with baseline**

Compare each screenshot pair. Document any differences:
- If a difference is a bug fix or clear improvement, note it
- If a difference is unexpected, investigate and fix
- The goal is pixel-identical except for intentional changes

**Step 3: Check page weights**

Compare pre/post JS payload sizes. The Turbo + Stimulus overhead should be ~20KB gzipped. Document the delta.

**Step 4: Run full test suite one more time**

```bash
rake test && rake lint
```

---

## Task 15: Stress Test

Repeat the multi-agent concurrent stress test on the grocery page to verify the hybrid approach (Turbo Streams + existing sync) handles concurrency correctly.

**Step 1: Design the stress test**

Multiple Playwright browser contexts, each logged in as a different user (or the same user in different tabs), performing rapid concurrent operations:

- Context A: rapidly selecting/deselecting recipes (every 200-500ms)
- Context B: rapidly checking/unchecking items (every 200-500ms)
- Context C: adding and removing custom items (every 300-500ms)
- Context D: editing quick bites content (every 2-3 seconds)
- Context E: editing aisle order (every 2-3 seconds)

Run for 30-60 seconds.

**Step 2: Verify success criteria**

After the stress test:
1. Each context's groceries page should show consistent state (no corruption)
2. Fetch `/groceries/state` — the state should be internally consistent
3. No 500 errors in the Rails log
4. No unhandled JS exceptions in any browser context
5. The Turbo Stream updates (from D and E) should have been applied without "Reload" notifications

**Step 3: Document results**

Record pass/fail and any observations.

**Step 4: Final commit**

If any fixes were needed during the stress test, commit them. Otherwise, commit a note or update to the design doc.

---

## Task 16: Update CLAUDE.md and Service Worker

**Files:**
- Modify: `CLAUDE.md` (document new JS architecture)
- Modify: `public/service-worker.js` (if needed for importmap assets)

**Step 1: Update CLAUDE.md**

Add a section about the Hotwire stack:
- Stimulus controllers in `app/javascript/controllers/`
- Utility modules in `app/javascript/utilities/`
- Importmap configuration in `config/importmap.rb`
- Turbo Drive enabled app-wide
- Turbo Streams used for grocery content changes
- How to add a new Stimulus controller

Update the "HTML, CSS, and JavaScript" section to reflect the new architecture.

**Step 2: Check service worker compatibility**

The importmap loads JS modules from `/assets/`. The service worker's cache-first strategy for `/assets/*` should handle these correctly since they're Propshaft-fingerprinted. Verify in the browser that Stimulus/Turbo assets are being cached by the SW.

**Step 3: Run final test suite**

```bash
rake test && rake lint
```

**Step 4: Commit**

```bash
git add CLAUDE.md public/service-worker.js
git commit -m "docs: update CLAUDE.md for Hotwire architecture"
```

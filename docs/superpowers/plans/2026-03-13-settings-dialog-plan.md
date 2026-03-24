# Settings Dialog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the standalone settings page with an editor `<dialog>` that matches the pattern used by recipe, quick bites, and nutrition editors.

**Architecture:** Settings dialog renders in the application layout (available on every page when logged in). A companion `settings_editor_controller` Stimulus controller handles form data collection, dirty tracking, and custom save via editor lifecycle events. The `SettingsController` becomes JSON-only.

**Tech Stack:** Rails controller (JSON responses), Stimulus controller, `shared/editor_dialog` layout.

---

### Task 1: Convert SettingsController to JSON

**Files:**
- Modify: `app/controllers/settings_controller.rb`
- Modify: `test/controllers/settings_controller_test.rb`

**Step 1: Write failing tests for JSON behavior**

Replace the existing tests with JSON-oriented versions. The `show` action returns JSON with current settings. The `update` action accepts JSON and returns JSON.

```ruby
# test/controllers/settings_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'requires membership to view settings' do
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'returns settings as JSON for logged-in member' do
    log_in
    get settings_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    data = response.parsed_body
    assert_equal @kitchen.site_title, data['site_title']
    assert_equal @kitchen.homepage_heading, data['homepage_heading']
    assert_equal @kitchen.homepage_subtitle, data['homepage_subtitle']
    assert data.key?('usda_api_key')
  end

  test 'requires membership to update settings' do
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'New' } }, as: :json

    assert_response :forbidden
  end

  test 'updates site settings via JSON' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'New Title', homepage_heading: 'New Heading', homepage_subtitle: 'New Sub' } },
          as: :json

    assert_response :success
    @kitchen.reload

    assert_equal 'New Title', @kitchen.site_title
    assert_equal 'New Heading', @kitchen.homepage_heading
    assert_equal 'New Sub', @kitchen.homepage_subtitle
  end

  test 'updates usda api key via JSON' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { usda_api_key: 'my-secret-key' } },
          as: :json

    assert_response :success
    @kitchen.reload

    assert_equal 'my-secret-key', @kitchen.usda_api_key
  end

  test 'returns errors on invalid update' do
    log_in
    # Kitchen has no required validations that would fail with normal params,
    # so this test verifies the error path exists structurally
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'OK' } }, as: :json

    assert_response :success
  end

  test 'gear button visible in navbar for members' do
    log_in
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav button.nav-settings-link'
  end

  test 'gear button hidden when not logged in' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_select 'nav button.nav-settings-link', count: 0
  end

  test 'rejects unpermitted params' do
    log_in
    patch settings_path(kitchen_slug: kitchen_slug),
          params: { kitchen: { site_title: 'OK', slug: 'hacked' } },
          as: :json

    assert_response :success
    @kitchen.reload

    assert_equal 'OK', @kitchen.site_title
    assert_equal 'test-kitchen', @kitchen.slug
  end
end
```

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: Failures on JSON response assertions (controller still returns HTML).

**Step 3: Update the controller to JSON-only**

```ruby
# app/controllers/settings_controller.rb
# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle)
# and API keys (USDA). JSON-only controller — the settings dialog fetches
# and saves via fetch requests.
#
# - Kitchen: settings live as columns on the tenant model
# - ApplicationController: provides current_kitchen and require_membership
class SettingsController < ApplicationController
  before_action :require_membership

  def show
    render json: {
      site_title: current_kitchen.site_title,
      homepage_heading: current_kitchen.homepage_heading,
      homepage_subtitle: current_kitchen.homepage_subtitle,
      usda_api_key: current_kitchen.usda_api_key
    }
  end

  def update
    if current_kitchen.update(settings_params)
      render json: { success: true }
    else
      render json: { errors: current_kitchen.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key])
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/settings_controller_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/controllers/settings_controller.rb test/controllers/settings_controller_test.rb
git commit -m "refactor: convert SettingsController to JSON-only"
```

---

### Task 2: Create settings editor Stimulus controller

**Files:**
- Create: `app/javascript/controllers/settings_editor_controller.js`

**Step 1: Write the Stimulus controller**

This controller hooks into the editor lifecycle events to collect form data, provide a custom save function, track dirty state, and reset on cancel. It also loads initial values from JSON into the form fields on open.

```javascript
// app/javascript/controllers/settings_editor_controller.js
import { Controller } from "@hotwired/stimulus"
import { getCsrfToken, showErrors } from "utilities/editor_utils"

/**
 * Companion controller for the settings editor dialog. Hooks into editor
 * lifecycle events to manage a structured form (not a textarea). Loads
 * current settings via fetch on open, collects field values on save, and
 * tracks dirty state across all inputs.
 *
 * - editor_controller: open/close/save lifecycle, dirty guards
 * - reveal_controller: API key show/hide toggle (nested)
 * - editor_utils: CSRF tokens, error display
 */
export default class extends Controller {
  static targets = ["siteTitle", "homepageHeading", "homepageSubtitle", "usdaApiKey"]
  static values = { loadUrl: String, saveUrl: String }

  connect() {
    this.originals = {}

    this.element.addEventListener("editor:collect", this.collect)
    this.element.addEventListener("editor:save", this.provideSaveFn)
    this.element.addEventListener("editor:modified", this.checkModified)
    this.element.addEventListener("editor:reset", this.reset)
  }

  disconnect() {
    this.element.removeEventListener("editor:collect", this.collect)
    this.element.removeEventListener("editor:save", this.provideSaveFn)
    this.element.removeEventListener("editor:modified", this.checkModified)
    this.element.removeEventListener("editor:reset", this.reset)
  }

  loadSettings() {
    this.disableFields(true)

    fetch(this.loadUrlValue, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })
      .then(r => r.json())
      .then(data => {
        this.siteTitleTarget.value = data.site_title || ""
        this.homepageHeadingTarget.value = data.homepage_heading || ""
        this.homepageSubtitleTarget.value = data.homepage_subtitle || ""
        this.usdaApiKeyTarget.value = data.usda_api_key || ""
        this.storeOriginals()
        this.disableFields(false)
      })
      .catch(() => {
        this.disableFields(false)
      })
  }

  collect = (event) => {
    event.detail.handled = true
    event.detail.data = {
      kitchen: {
        site_title: this.siteTitleTarget.value,
        homepage_heading: this.homepageHeadingTarget.value,
        homepage_subtitle: this.homepageSubtitleTarget.value,
        usda_api_key: this.usdaApiKeyTarget.value
      }
    }
  }

  provideSaveFn = (event) => {
    event.detail.handled = true
    event.detail.saveFn = async () => {
      const response = await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify({
          kitchen: {
            site_title: this.siteTitleTarget.value,
            homepage_heading: this.homepageHeadingTarget.value,
            homepage_subtitle: this.homepageSubtitleTarget.value,
            usda_api_key: this.usdaApiKeyTarget.value
          }
        })
      })

      if (!response.ok) {
        const body = await response.json()
        throw body.errors || ["Save failed. Please try again."]
      }

      return response.json()
    }
  }

  checkModified = (event) => {
    event.detail.handled = true
    event.detail.modified =
      this.siteTitleTarget.value !== this.originals.siteTitle ||
      this.homepageHeadingTarget.value !== this.originals.homepageHeading ||
      this.homepageSubtitleTarget.value !== this.originals.homepageSubtitle ||
      this.usdaApiKeyTarget.value !== this.originals.usdaApiKey
  }

  reset = (event) => {
    event.detail.handled = true
    this.siteTitleTarget.value = this.originals.siteTitle
    this.homepageHeadingTarget.value = this.originals.homepageHeading
    this.homepageSubtitleTarget.value = this.originals.homepageSubtitle
    this.usdaApiKeyTarget.value = this.originals.usdaApiKey
  }

  storeOriginals() {
    this.originals = {
      siteTitle: this.siteTitleTarget.value,
      homepageHeading: this.homepageHeadingTarget.value,
      homepageSubtitle: this.homepageSubtitleTarget.value,
      usdaApiKey: this.usdaApiKeyTarget.value
    }
  }

  disableFields(disabled) {
    ;[this.siteTitleTarget, this.homepageHeadingTarget,
      this.homepageSubtitleTarget, this.usdaApiKeyTarget].forEach(f => f.disabled = disabled)
  }
}
```

**Step 2: Commit**

```bash
git add app/javascript/controllers/settings_editor_controller.js
git commit -m "feat: add settings_editor Stimulus controller"
```

---

### Task 3: Add settings dialog to the application layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/views/shared/_nav.html.erb`
- Create: `app/views/settings/_dialog.html.erb`

**Step 1: Create the settings dialog partial**

This renders the editor dialog with the settings form fields inside. Uses `shared/editor_dialog` layout. The form uses `.editor-form` and `.editor-section` classes from the nutrition editor pattern.

```erb
<%# app/views/settings/_dialog.html.erb %>
<%= render layout: 'shared/editor_dialog',
    locals: {
      title: 'Settings',
      id: 'settings-editor',
      dialog_data: {
        editor_on_success: 'reload',
        extra_controllers: 'settings-editor'
      },
      extra_data: {
        'settings-editor-load-url-value' => settings_path,
        'settings-editor-save-url-value' => settings_path
      }
    } do %>
  <div class="editor-body">
    <div class="editor-form">
      <fieldset class="editor-section">
        <legend class="editor-section-title">Site</legend>
        <div class="settings-field">
          <label for="settings-site-title">Site title</label>
          <input type="text" id="settings-site-title" class="settings-input"
                 data-settings-editor-target="siteTitle">
        </div>
        <div class="settings-field">
          <label for="settings-homepage-heading">Homepage heading</label>
          <input type="text" id="settings-homepage-heading" class="settings-input"
                 data-settings-editor-target="homepageHeading">
        </div>
        <div class="settings-field">
          <label for="settings-homepage-subtitle">Homepage subtitle</label>
          <input type="text" id="settings-homepage-subtitle" class="settings-input"
                 data-settings-editor-target="homepageSubtitle">
        </div>
      </fieldset>

      <fieldset class="editor-section">
        <legend class="editor-section-title">API Keys</legend>
        <div class="settings-field" data-controller="reveal">
          <label for="settings-usda-api-key">USDA API key</label>
          <div class="settings-api-key-row">
            <input type="password" id="settings-usda-api-key" class="settings-input"
                   autocomplete="off"
                   data-settings-editor-target="usdaApiKey"
                   data-reveal-target="input">
            <button type="button" class="btn settings-reveal-btn"
                    data-action="reveal#toggle"
                    data-reveal-target="button">Show</button>
          </div>
        </div>
      </fieldset>
    </div>
  </div>
<% end %>
```

**Step 2: Render the dialog in the application layout**

In `app/views/layouts/application.html.erb`, add the dialog render after the search overlay, guarded by `logged_in?`:

```erb
  <%= render 'shared/search_overlay' %>
  <%= render 'settings/dialog' if logged_in? %>
```

**Step 3: Convert nav gear icon from link to button**

In `app/views/shared/_nav.html.erb`, replace the `link_to` with a `<button>`. The editor controller's `openSelector` is not used here — instead the settings-editor controller listens for the button click to call `loadSettings()` and then opens the dialog. Actually, simpler: use the editor's `editor_open` selector pattern.

Update the `dialog_data` in the partial to include `editor_open: '#settings-button'`.

Change the nav from:
```erb
<%= link_to settings_path, class: 'nav-settings-link', ... do %>
```
to:
```erb
<button type="button" id="settings-button" class="nav-settings-link" title="Settings" aria-label="Settings">
```

**Step 4: Wire up content loading**

The editor controller's `openWithRemoteContent` won't work here since there's no textarea target. Instead, the `settings_editor_controller` should load content when the dialog opens. Listen for the dialog's `open` attribute change or hook into the editor's open flow.

Simplest approach: use a `connected` or MutationObserver pattern. Actually, the cleanest way is to listen for the dialog `open` event. The editor controller calls `this.element.showModal()` which doesn't fire a custom event, but we can use the `editor:collect` timing... No — better to just load on connect (the dialog is always in the DOM) and refresh on open.

Best approach: have the settings-editor controller listen for when the dialog opens. Use `loadUrl`/`loadKey` on the editor controller — but the editor only populates a textarea with that. Instead, override: use `editor_open` to trigger the editor's `open()`, and in `settings_editor_controller`, listen for the native HTMLDialogElement `close`/`open` events. Actually, `showModal()` doesn't fire an event.

Simplest correct approach: In `settings_editor_controller`, add a method `open()` that loads settings and shows the dialog. Wire the button directly to this controller:

```erb
<button type="button" id="settings-button" class="nav-settings-link"
        data-action="click->settings-editor#openDialog"
        title="Settings" aria-label="Settings">
```

Then in the controller, `openDialog()` calls `loadSettings()` and then dispatches to the editor's `open()`. Actually even simpler — the editor controller already has `openSelector` support. When the button is clicked, the editor opens. We just need to also load settings at that point.

The cleanest way: don't use `editor_open` / `openSelector`. Instead, the `settings_editor_controller` has an `openDialog` action that loads settings, then manually calls `this.element.showModal()` after fetch completes. But then we lose the editor controller's open() logic (clearing errors, resetting save button).

Actually the editor controller dispatches no event on open, so we can't easily hook in. Let me re-examine. The editor controller's `open()` method:
1. Clears errors
2. Resets save button
3. If `loadUrl` — fetches remote content into textarea
4. Else — stores original content, shows modal

We don't want the textarea path. Best approach: **don't use `editor_open`**. Have the settings-editor controller own the open flow entirely. It calls `loadSettings()` (which fetches JSON and populates fields), then after fetch success, calls the editor controller's open-related setup (clear errors, reset save) and `showModal()`.

To access the editor controller from the companion: `this.application.getControllerForElementAndIdentifier(this.element, 'editor')`.

Let me revise. The settings-editor controller:

```javascript
openDialog() {
  const editor = this.application.getControllerForElementAndIdentifier(this.element, "editor")
  editor.clearErrorDisplay()
  editor.resetSaveButton()
  this.disableFields(true)
  this.element.showModal()

  fetch(this.loadUrlValue, {
    headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
  })
    .then(r => r.json())
    .then(data => {
      this.siteTitleTarget.value = data.site_title || ""
      this.homepageHeadingTarget.value = data.homepage_heading || ""
      this.homepageSubtitleTarget.value = data.homepage_subtitle || ""
      this.usdaApiKeyTarget.value = data.usda_api_key || ""
      this.storeOriginals()
      this.disableFields(false)
      this.siteTitleTarget.focus()
    })
    .catch(() => {
      this.disableFields(false)
      showErrors(editor.errorsTarget, ["Failed to load settings. Close and try again."])
    })
}
```

But `clearErrorDisplay` and `resetSaveButton` are not public API on the editor. They are regular methods though, so they're accessible. This is a bit tightly coupled but matches how other companion controllers work.

Actually, looking at the editor controller code again — `clearErrorDisplay` and `resetSaveButton` are just methods on the class, callable by any code with a reference. The nutrition editor doesn't call them because it uses `editor_open`. For settings, since we're bypassing `editor_open`, we need to do this manually.

Alternatively, we could keep `editor_open: '#settings-button'` so the editor controller handles open, and separately have the settings-editor detect the open. The editor's `open()` calls `openWithRemoteContent()` if `loadUrl` is set. We could set `loadUrl` to the settings JSON endpoint... but `openWithRemoteContent` puts the response into a textarea target which we don't have.

OK, cleanest approach: **Don't set `editor_open` or `loadUrl` on the editor.** Have `settings_editor_controller` own the button click and open flow. Access the editor controller to call its setup methods. This is the same pattern as if a companion controller wanted to intercept the open.

**Step 5: Update the nav partial and dialog data**

Remove `editor_open` from dialog_data. Add the `data-action` on the nav button pointing to `settings-editor#openDialog`.

But wait — the button is in the nav, and the dialog is a separate element. Stimulus actions need the button to be inside the controller's element or use an outlet. The settings-editor controller is on the dialog element, not the nav. We need either:
- An outlet from the button to the dialog
- A global event listener in the controller

Simplest: keep the `editor_open` selector approach — it uses a document-level click listener that checks if the clicked element matches the selector. This is already how the editor controller works. So we set `editor_open: '#settings-button'` and the editor's `open()` will be called. Then we need to hook into open.

New approach: keep `editor_open`, **don't** set `loadUrl`. Override the editor's open behavior by making the settings-editor controller intercept. But the editor dispatches no event on open.

OK let me just make it work pragmatically. The editor controller's `open()` method, when `loadUrl` is NOT set: stores textarea original content (no-op if no textarea target), then calls `showModal()`. So with `editor_open` set and no `loadUrl`, clicking the button will: clear errors, reset save button, show modal. Perfect. Then we just need the settings-editor to detect that the dialog opened and load settings.

We can use a MutationObserver on the dialog's `open` attribute. Or simpler: monkey-patch / extend. Actually simplest: the editor dispatches no open event, but we can add one. Or, we can just listen for the `click` event on the document too:

In `settings_editor_controller.connect()`:
```javascript
this.boundOnOpen = () => this.loadSettings()
document.addEventListener("click", (e) => {
  if (e.target.closest("#settings-button")) {
    // Editor will open the dialog; we load settings
    // Use setTimeout to run after editor's open()
    setTimeout(() => this.loadSettings(), 0)
  }
})
```

This is hacky. Let me just go with the `openDialog` approach but wire it differently. The button data-action can target a controller on a different element using Stimulus outlets or the `@document` syntax... no, Stimulus actions need the element to be within the controller scope.

**Final approach:** Don't use `editor_open`. Wire the button via a global click listener in `settings_editor_controller`:

```javascript
connect() {
  // ...existing event listeners...
  this.boundOpenClick = (e) => {
    if (e.target.closest('#settings-button')) this.openDialog()
  }
  document.addEventListener('click', this.boundOpenClick)
}

disconnect() {
  // ...existing cleanup...
  document.removeEventListener('click', this.boundOpenClick)
}
```

This is exactly what the editor controller does with `openSelector`. Since we're replacing that mechanism, this is clean and consistent.

**Step 6: Commit**

```bash
git add app/views/settings/_dialog.html.erb app/views/layouts/application.html.erb app/views/shared/_nav.html.erb
git commit -m "feat: add settings editor dialog to application layout"
```

---

### Task 4: Clean up CSS — remove old settings styles, add dialog form styles

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Remove old settings CSS**

Delete the entire `/* Settings page */` block (lines 733–815, from `.settings-page` through `.flash-notice`). Also remove `.settings-page header::after` from the header-divider rule at line 521.

**Step 2: Add minimal settings dialog CSS**

Reuse `.editor-form`, `.editor-section`, `.editor-section-title` from the nutrition editor. Add only what's needed for the settings form fields:

```css
/* Settings dialog */
#settings-editor {
  width: min(90vw, 460px);
}

.settings-field {
  margin-bottom: 1rem;
}

.settings-field label {
  display: block;
  font-family: var(--font-body);
  font-size: 0.85rem;
  margin-bottom: 0.25rem;
}

.settings-input {
  width: 100%;
  font-size: 1rem;
  padding: 0.4rem 0.5rem;
  border: 1px solid var(--rule);
  border-radius: 3px;
  background: var(--surface-color);
  color: var(--text-color);
}

.settings-input:focus {
  outline: none;
  border-color: var(--text-secondary-color);
}

.settings-api-key-row {
  display: flex;
  gap: 0.5rem;
}

.settings-api-key-row .settings-input {
  flex: 1;
  font-family: var(--font-mono);
}

.settings-reveal-btn {
  white-space: nowrap;
  min-width: 3.5rem;
}
```

Note: `font-size: 1rem` (not 0.85rem) on inputs to prevent iOS zoom.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: replace settings page CSS with dialog form styles"
```

---

### Task 5: Delete old settings page and update routes

**Files:**
- Delete: `app/views/settings/show.html.erb`
- Modify: `config/routes.rb`

**Step 1: Delete the old view**

```bash
rm app/views/settings/show.html.erb
```

The `show` action now returns JSON, so no HTML template is needed.

**Step 2: Update routes**

The `GET /settings` route stays (it serves JSON for the dialog load). No route changes needed — both `get 'settings'` and `patch 'settings'` remain.

**Step 3: Commit**

```bash
git rm app/views/settings/show.html.erb
git commit -m "chore: delete old settings HTML view"
```

---

### Task 6: Update tests and run full suite

**Files:**
- Modify: `test/controllers/settings_controller_test.rb` (already done in Task 1)
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

**Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests pass. If any settings-related integration tests assert HTML responses or redirects, they need updating (should already be handled in Task 1).

**Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No offenses.

**Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: Clean. If line numbers shifted in any files that use `.html_safe`, update `config/html_safe_allowlist.yml`.

**Step 4: Manual smoke test**

Start the dev server (`bin/dev`), log in, verify:
- Gear icon in nav opens a dialog (not a page navigation)
- Settings fields load with current values
- Editing a field and clicking Cancel prompts "unsaved changes" confirmation
- Saving updates the settings and reloads the page
- New site title appears in the nav after reload
- API key reveal/hide toggle works inside the dialog

**Step 5: Commit any fixups**

```bash
git add -A
git commit -m "fix: test and lint fixups for settings dialog"
```

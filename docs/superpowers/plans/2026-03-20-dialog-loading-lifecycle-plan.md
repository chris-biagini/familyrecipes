# Dialog Loading Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify all editor dialogs onto Turbo Frames with eager preloading, shared dialog shell, and consistent loading states.

**Architecture:** Every editor dialog uses `_editor_dialog.html.erb` as its shell and loads body content via a Turbo Frame. Frames with `src` set at render time preload eagerly; the nutrition editor keeps hover-triggered `src`. `editor_controller` detects frame readiness on open and falls back to a loading indicator when the frame hasn't loaded yet. Ordered list and settings editors become companion controllers delegating lifecycle to `editor_controller`.

**Tech Stack:** Rails 8, Turbo Frames, Stimulus, Minitest

**Spec:** `docs/plans/2026-03-20-dialog-loading-lifecycle-design.md`

---

## File Structure

### New files

| File | Purpose |
|------|---------|
| `app/views/settings/_editor_frame.html.erb` | Turbo Frame: settings form with current values |
| `app/views/groceries/_aisle_order_frame.html.erb` | Turbo Frame: rendered aisle list rows |
| `app/views/categories/_order_frame.html.erb` | Turbo Frame: rendered category list rows |
| `app/views/tags/_content_frame.html.erb` | Turbo Frame: rendered tag list rows |
| `app/views/shared/_ordered_list_rows.html.erb` | Shared partial: list rows for aisle/category/tag editors |
| `app/views/recipes/_editor_frame.html.erb` | Turbo Frame: recipe editor (markdown JSON + graphical form) |
| `app/views/recipes/_graphical_step_card.html.erb` | Partial: server-rendered step card with ingredients |
| `app/views/menu/_quickbites_editor_frame.html.erb` | Turbo Frame: Quick Bites editor |

### Modified files

| File | Changes |
|------|---------|
| `config/routes.rb` | Add `editor_frame` routes for settings, recipe, quick bites |
| `app/controllers/settings_controller.rb` | Add `editor_frame` action returning HTML |
| `app/controllers/groceries_controller.rb` | Change `aisle_order_content` to render Turbo Frame HTML |
| `app/controllers/categories_controller.rb` | Change `order_content` to render Turbo Frame HTML |
| `app/controllers/tags_controller.rb` | Change `content` to render Turbo Frame HTML |
| `app/controllers/recipes_controller.rb` | Add `editor_frame` action returning HTML |
| `app/controllers/menu_controller.rb` | Add `quickbites_editor_frame` action returning HTML |
| `app/views/shared/_editor_dialog.html.erb` | Remove `editor_load_url_value`/`editor_load_key_value` wiring |
| `app/views/settings/_dialog.html.erb` | Add Turbo Frame in body, remove load-url data attrs |
| `app/views/groceries/show.html.erb` | Replace custom `<dialog>` with `render layout: 'shared/editor_dialog'` |
| `app/views/homepage/show.html.erb` | Replace custom `<dialog>` elements with shared dialog shell |
| `app/views/recipes/show.html.erb` | Add Turbo Frame src for recipe editor |
| `app/views/menu/show.html.erb` | Add Turbo Frame src for Quick Bites editor |
| `app/javascript/controllers/editor_controller.js` | Add frame readiness check, error-with-retry, remove `openWithRemoteContent` |
| `app/javascript/controllers/ordered_list_editor_controller.js` | Become companion: remove lifecycle, add editor event handlers |
| `app/javascript/controllers/settings_editor_controller.js` | Remove `openDialog`/`disableFields`, add `editor:content-loaded` handler |
| `app/javascript/controllers/dual_mode_editor_controller.js` | Handle frame-delivered content (embedded JSON + pre-rendered graphical form) |
| `app/javascript/controllers/plaintext_editor_controller.js` | Read initial content from embedded `<script>` JSON when no `initial` value |
| `app/javascript/controllers/recipe_graphical_controller.js` | Add `initFromRenderedDOM()` to read state from server-rendered cards |
| `app/assets/stylesheets/style.css` | Remove `.cm-mount.cm-loading`, unify `.loading-placeholder` |
| `test/controllers/settings_controller_test.rb` | Test new `editor_frame` action |
| `test/controllers/groceries_controller_test.rb` | Update aisle content tests for HTML response |
| `test/controllers/categories_controller_test.rb` | Update order content tests for HTML response |
| `test/controllers/tags_controller_test.rb` | Update content tests for HTML response |
| `test/controllers/recipes_controller_test.rb` | Test new `editor_frame` action |
| `test/controllers/menu_controller_test.rb` | Test new `quickbites_editor_frame` action |

---

## Task 1: editor_controller — Turbo Frame readiness support

Add frame readiness detection to `editor_controller`. This is additive — the existing
`openWithRemoteContent()` stays until all editors are migrated.

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js`

- [ ] **Step 1: Add `frameTarget` and frame readiness detection**

Add a new optional target and a helper to detect whether the frame has loaded:

```javascript
// In static targets, add "frame"
static targets = ["textarea", "saveButton", "deleteButton", "errors", "frame"]

// Add to static values:
// (no new values needed — frame readiness is detected from DOM state)
```

Add a method that checks whether the Turbo Frame's content has been loaded (i.e., the
frame no longer contains just the loading placeholder):

```javascript
get frameLoaded() {
  if (!this.hasFrameTarget) return true
  // Frame with no src (e.g., new recipe) is always "loaded"
  if (!this.frameTarget.src) return true
  // Turbo sets the `complete` attribute after successful load
  return this.frameTarget.complete
}
```

Note: Turbo Frames expose a `complete` property that is `true` after the frame
has successfully loaded its `src` content. Check this in the Turbo source if
needed — if `complete` is not available, fall back to checking whether the
frame still contains only the `.loading-placeholder` element.

- [ ] **Step 2: Add frame-aware `open()` logic**

Modify `open()` to handle Turbo Frame–based dialogs:

```javascript
open() {
  this.clearErrorDisplay()
  this.resetSaveButton()

  if (this.hasLoadUrlValue) {
    // Legacy path — used until all editors migrate to frames
    this.openWithRemoteContent()
  } else if (this.hasFrameTarget && !this.frameLoaded) {
    // Frame hasn't loaded yet — open with loading state, wait for frame
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = true
    this.element.showModal()
    this.frameTarget.addEventListener("turbo:frame-load", () => {
      this.onFrameReady()
    }, { once: true })
  } else {
    // Frame loaded (or no frame) — open immediately
    if (this.hasTextareaTarget) this.originalContent = this.textareaTarget.value
    this.element.showModal()
    this.dispatchEditorEvent("editor:content-loaded", {})
    this.dispatchEditorEvent("editor:opened")
  }
}
```

- [ ] **Step 3: Add `onFrameReady()` and error handling**

```javascript
onFrameReady() {
  if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = false
  this.dispatchEditorEvent("editor:content-loaded", {})
  this.dispatchEditorEvent("editor:opened")
}
```

Add error handling — listen for `turbo:frame-missing` to show a retry message:

```javascript
connect() {
  // ... existing setup ...
  if (this.hasFrameTarget) {
    this.listeners.add(this.frameTarget, "turbo:fetch-request-error", () => this.showFrameError())
  }
}

showFrameError() {
  if (!this.hasErrorsTarget) return
  const retryBtn = document.createElement("button")
  retryBtn.className = "btn"
  retryBtn.textContent = "Try again"
  retryBtn.addEventListener("click", () => {
    clearErrors(this.errorsTarget)
    this.frameTarget.reload()
  })
  showErrors(this.errorsTarget, ["Failed to load. "])
  this.errorsTarget.querySelector("li")?.appendChild(retryBtn)
}
```

- [ ] **Step 4: Verify existing editors still work**

Run the full test suite to confirm the additive changes don't break anything:

```bash
rake test
```

Expected: all tests pass. The existing `openWithRemoteContent()` path is untouched.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/editor_controller.js
git commit -m "Add Turbo Frame readiness detection to editor_controller (#260)

Additive change: frame target + readiness check on open().
Legacy openWithRemoteContent() stays for backward compat."
```

---

## Task 2: Settings editor — Migrate to Turbo Frame

Convert the settings editor from JSON fetch to a server-rendered Turbo Frame.
This is the simplest migration — one form, no dual-mode, already a companion.

**Files:**
- Create: `app/views/settings/_editor_frame.html.erb`
- Modify: `app/controllers/settings_controller.rb`
- Modify: `app/views/settings/_dialog.html.erb`
- Modify: `app/javascript/controllers/settings_editor_controller.js`
- Modify: `config/routes.rb`
- Test: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Write controller test for the new frame endpoint**

```ruby
# In test/controllers/settings_controller_test.rb
test "editor_frame returns turbo frame with form values" do
  log_in @user

  get settings_editor_frame_path(kitchen_slug: kitchen_slug), as: :html

  assert_response :success
  assert_select "turbo-frame#settings-editor-frame"
  assert_select "input[data-settings-editor-target='siteTitle']" do |inputs|
    assert_equal @kitchen.site_title, inputs.first["value"]
  end
end

test "editor_frame requires membership" do
  get settings_editor_frame_path(kitchen_slug: kitchen_slug), as: :html

  assert_response :forbidden
end
```

- [ ] **Step 2: Run test — confirm it fails**

```bash
ruby -Itest test/controllers/settings_controller_test.rb -n /editor_frame/
```

Expected: error — route not found.

- [ ] **Step 3: Add route**

```ruby
# In config/routes.rb, inside the scope block:
get 'settings/editor_frame', to: 'settings#editor_frame', as: :settings_editor_frame
```

- [ ] **Step 4: Add controller action**

```ruby
# In app/controllers/settings_controller.rb
def editor_frame
  render partial: 'settings/editor_frame', locals: {
    kitchen: current_kitchen
  }, layout: false
end
```

Ensure `editor_frame` is covered by the existing `require_membership` before_action.

- [ ] **Step 5: Create the frame partial**

`app/views/settings/_editor_frame.html.erb`:

```erb
<turbo-frame id="settings-editor-frame">
  <div class="editor-body settings-form">
    <!-- Reuse existing settings form fields from _dialog.html.erb,
         but now server-rendered with current values -->
    <div class="settings-field">
      <label for="settings-site-title">Site Title</label>
      <input type="text" id="settings-site-title"
             data-settings-editor-target="siteTitle"
             value="<%= kitchen.site_title %>">
    </div>
    <!-- ... remaining fields with values pre-populated ... -->
  </div>
</turbo-frame>
```

Mirror the exact form structure from the current `_dialog.html.erb` body, but with
`value=` attributes pre-populated from the `kitchen` local. Move the form fields
OUT of `_dialog.html.erb` and INTO this frame partial.

- [ ] **Step 6: Run test — confirm it passes**

```bash
ruby -Itest test/controllers/settings_controller_test.rb -n /editor_frame/
```

Expected: PASS.

- [ ] **Step 7: Update `_dialog.html.erb` view to use Turbo Frame**

In `app/views/settings/_dialog.html.erb`, replace the inline form body with:

```erb
<turbo-frame id="settings-editor-frame"
             src="<%= settings_editor_frame_path %>"
             data-editor-target="frame">
  <p class="loading-placeholder">Loading&hellip;</p>
</turbo-frame>
```

Remove `settings-editor-load-url-value` and `settings-editor-save-url-value` from
the `dialog_data` hash (save URL stays as `editor_url`). The Turbo Frame replaces the
JSON fetch.

- [ ] **Step 8: Simplify `settings_editor_controller.js`**

Remove:
- `openDialog()` method (editor_controller handles open via `openSelector`)
- `disableFields()` method
- The document click listener for `#settings-button`
- `loadUrl` static value

Add:
- `editor:content-loaded` handler that calls `storeOriginals()` — form fields
  arrive pre-populated from the server, so just snapshot the current values.

The controller should now only handle: `editor:collect`, `editor:save`,
`editor:modified`, `editor:reset`, `editor:content-loaded` (for `storeOriginals`).

Wire the open button through `editor_controller`'s `openSelector` value
instead of the settings controller's own click listener.

- [ ] **Step 9: Run full test suite**

```bash
rake test
```

Expected: all tests pass.

- [ ] **Step 10: Commit**

```bash
git add config/routes.rb app/controllers/settings_controller.rb \
  app/views/settings/ app/javascript/controllers/settings_editor_controller.js
git commit -m "Migrate settings editor to Turbo Frame (#260)

Server-rendered form via eager Turbo Frame. Settings controller
delegates lifecycle to editor_controller, removing custom
openDialog/disableFields."
```

---

## Task 3: Ordered list editors — Server-rendered frame endpoints

Create Turbo Frame endpoints for aisles, categories, and tags. The ordered list
rows are rendered server-side.

**Files:**
- Create: `app/views/shared/_ordered_list_rows.html.erb`
- Create: `app/views/groceries/_aisle_order_frame.html.erb`
- Create: `app/views/categories/_order_frame.html.erb`
- Create: `app/views/tags/_content_frame.html.erb`
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `app/controllers/categories_controller.rb`
- Modify: `app/controllers/tags_controller.rb`
- Modify: `config/routes.rb` (if new routes needed)
- Test: `test/controllers/groceries_controller_test.rb`
- Test: `test/controllers/categories_controller_test.rb`
- Test: `test/controllers/tags_controller_test.rb`

- [ ] **Step 1: Write tests for frame endpoints**

For each of the three controllers, add tests that:
1. Return a Turbo Frame with the correct ID
2. Contain rendered list rows (one per item)
3. Enforce membership where required (aisles + tags require membership; categories are public)

Example for aisles:

```ruby
test "aisle_order_content returns turbo frame with rendered rows" do
  log_in @user

  get groceries_aisle_order_content_path(kitchen_slug: kitchen_slug), as: :html

  assert_response :success
  assert_select "turbo-frame#aisle-order-frame"
  assert_select "[data-ordered-list-editor-target='list']"
  assert_select ".aisle-row"  # rendered rows present
end
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb -n /turbo_frame/
ruby -Itest test/controllers/categories_controller_test.rb -n /turbo_frame/
ruby -Itest test/controllers/tags_controller_test.rb -n /turbo_frame/
```

- [ ] **Step 3: Create shared `_ordered_list_rows.html.erb` partial**

`app/views/shared/_ordered_list_rows.html.erb`:

```erb
<%# locals: (items:, list_target_attr:) %>
<div class="aisle-list" <%= list_target_attr %>>
  <% items.each do |item| %>
    <div class="aisle-row" data-name="<%= item[:name] %>">
      <span class="aisle-name"><%= item[:name] %></span>
    </div>
  <% end %>
</div>
```

The exact row structure must match what `ordered_list_editor_utils.js`'s
`renderRows()` produces. Read `app/javascript/utilities/ordered_list_editor_utils.js`
to verify the DOM structure — the server-rendered rows should have the same
classes and data attributes. Note: the JS controller will RE-render these rows
via `renderRows()` on `editor:content-loaded` (after reading item names from
the DOM), so the server-rendered rows are primarily for the initial visual
display and for extracting item names. They don't need action buttons.

- [ ] **Step 4: Create frame partials for each list type**

`app/views/groceries/_aisle_order_frame.html.erb`:

```erb
<%# locals: (items:) %>
<turbo-frame id="aisle-order-frame">
  <%= render 'shared/ordered_list_rows',
    items: items,
    list_target_attr: 'data-ordered-list-editor-target="list"'.html_safe %>
</turbo-frame>
```

Same pattern for `categories/_order_frame.html.erb` and `tags/_content_frame.html.erb`
with appropriate frame IDs.

- [ ] **Step 5: Modify controller actions to render HTML**

Change each content action to respond to HTML format with the frame partial.
Keep JSON response for backward compat during migration (the JS controller
hasn't been migrated yet):

```ruby
# In groceries_controller.rb, modify aisle_order_content:
def aisle_order_content
  items = current_kitchen.aisle_order_with_defaults.map { |name| { name: name } }

  respond_to do |format|
    format.html { render partial: 'groceries/aisle_order_frame', locals: { items: items }, layout: false }
    format.json { render json: { aisle_order: current_kitchen.aisle_order_with_defaults.join("\n") } }
  end
end
```

Same pattern for categories and tags. Read the existing actions to understand
what data each returns, then build the `items` array for the partial.

- [ ] **Step 6: Run tests — confirm they pass**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb
ruby -Itest test/controllers/categories_controller_test.rb
ruby -Itest test/controllers/tags_controller_test.rb
```

Expected: both new frame tests and existing JSON tests pass (dual format).

- [ ] **Step 7: Commit**

```bash
git add app/views/shared/_ordered_list_rows.html.erb \
  app/views/groceries/ app/views/categories/ app/views/tags/ \
  app/controllers/groceries_controller.rb \
  app/controllers/categories_controller.rb \
  app/controllers/tags_controller.rb \
  test/controllers/
git commit -m "Add Turbo Frame endpoints for ordered list editors (#260)

Server-rendered list rows for aisles, categories, and tags.
Dual format (HTML + JSON) for backward compat during migration."
```

---

## Task 4: Ordered list editors — Views + companion controller migration

Migrate the three custom `<dialog>` elements to the shared shell and convert
`ordered_list_editor_controller` to a companion.

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/javascript/controllers/ordered_list_editor_controller.js`
- Modify: `app/javascript/application.js` (if registration changes needed)

- [ ] **Step 1: Migrate aisle editor in groceries/show.html.erb**

Replace the custom `<dialog>` (lines 37-71) with:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Aisles',
              id: 'aisle-order-editor',
              dialog_data: { extra_controllers: 'ordered-list-editor',
                             editor_open: '#edit-aisle-order-button',
                             editor_url: groceries_aisle_order_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'reload' },
              extra_data: {
                'ordered-list-editor-save-url-value' => groceries_aisle_order_path,
                'ordered-list-editor-payload-key-value' => 'aisle_order',
                'ordered-list-editor-join-with-value' => "\n"
              } } do %>
  <div class="editor-body aisle-order-body">
    <turbo-frame id="aisle-order-frame"
                 src="<%= groceries_aisle_order_content_path %>"
                 data-editor-target="frame">
      <p class="loading-placeholder">Loading&hellip;</p>
    </turbo-frame>
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
<% end %>
```

- [ ] **Step 2: Migrate category + tag editors in homepage/show.html.erb**

Same pattern. Replace the two custom `<dialog>` blocks (lines 58-127) with
`render layout: 'shared/editor_dialog'` calls. Each gets its own Turbo Frame
with eager `src`:

- Category: `id: 'category-order-editor'`, frame `src: categories_order_content_path`
- Tags: `id: 'tag-order-editor'`, frame `src: tags_content_path`,
  `'ordered-list-editor-orderable-value' => 'false'`

- [ ] **Step 3: Migrate `ordered_list_editor_controller.js` to companion pattern**

Remove lifecycle methods that `editor_controller` now owns:
- `open()`, `close()`, `handleCancel()`, `handleBeforeVisit()`
- `loadItems()`, `parseLoadedItems()`
- `connect()` open-button listener, cancel listener, beforeVisit listener
- `guardBeforeUnload`, `resetSaveButton()`
- `loadUrl`, `loadKey`, `openSelector` static values

Keep these static values (used by the companion's event handlers):
- `saveUrl` — used in `handleSave` saveFn
- `payloadKey` — used by `buildItemPayload()`
- `joinWith` — used by `buildItemPayload()`
- `orderable` — used by `render()` to show/hide reorder buttons

Add editor lifecycle event listeners in `connect()`:
```javascript
connect() {
  this.items = []
  this.initialSnapshot = null
  this.listeners = new ListenerManager()

  this.listeners.add(this.element, "editor:content-loaded", () => this.handleContentLoaded())
  this.listeners.add(this.element, "editor:collect", (e) => this.handleCollect(e))
  this.listeners.add(this.element, "editor:save", (e) => this.handleSave(e))
  this.listeners.add(this.element, "editor:modified", (e) => this.handleModified(e))
  this.listeners.add(this.element, "editor:reset", (e) => this.handleReset(e))
}
```

`handleContentLoaded()`: read item names from server-rendered DOM rows in the
Turbo Frame, create items via `createItem()`, take snapshot:
```javascript
handleContentLoaded() {
  const rows = this.listTarget.querySelectorAll(".aisle-row")
  this.items = Array.from(rows).map(row => createItem(row.dataset.name))
  this.initialSnapshot = takeSnapshot(this.items)
  this.render()  // Re-render with full interactive controls
}
```

`handleCollect(e)`: set `handled = true`, `data = this.buildItemPayload()`.

`handleSave(e)`: set `handled = true`, provide `saveFn`:
```javascript
handleSave(event) {
  event.detail.handled = true
  event.detail.saveFn = () => saveRequest(this.saveUrlValue, "PATCH", this.buildItemPayload())
}
```

`handleModified(e)`: set `handled = true`, `modified = isModified(...)`.

`handleReset(e)`: set `handled = true`, clear items and snapshot.

- [ ] **Step 4: Run full test suite**

```bash
rake test
```

Expected: all tests pass.

- [ ] **Step 5: Lint**

```bash
bundle exec rubocop
```

- [ ] **Step 6: Commit**

```bash
git add app/views/groceries/show.html.erb app/views/homepage/show.html.erb \
  app/javascript/controllers/ordered_list_editor_controller.js
git commit -m "Migrate ordered list editors to shared dialog shell + companion pattern (#260)

Aisles, categories, tags now use _editor_dialog.html.erb with Turbo
Frame bodies. ordered_list_editor_controller delegates lifecycle to
editor_controller."
```

---

## Task 5: Recipe editor — Server-rendered frame endpoint

Create the Turbo Frame endpoint that returns both the graphical form (server-
rendered with current recipe data) and the embedded markdown JSON for CodeMirror.

**Files:**
- Create: `app/views/recipes/_editor_frame.html.erb`
- Create: `app/views/recipes/_graphical_step_card.html.erb`
- Modify: `app/controllers/recipes_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write controller test for the frame endpoint**

```ruby
test "editor_frame returns turbo frame with markdown JSON and graphical form" do
  log_in @user

  get recipe_editor_frame_path(@recipe.slug, kitchen_slug: kitchen_slug), as: :html

  assert_response :success
  assert_select "turbo-frame#recipe-editor-content"
  assert_select "script[type='application/json'][data-editor-markdown]"
  assert_select "[data-dual-mode-editor-target='graphicalContainer']"
  assert_select ".graphical-step-card"  # server-rendered steps
end

test "editor_frame requires membership" do
  get recipe_editor_frame_path(@recipe.slug, kitchen_slug: kitchen_slug), as: :html

  assert_response :forbidden
end
```

- [ ] **Step 2: Run test — confirm it fails**

```bash
ruby -Itest test/controllers/recipes_controller_test.rb -n /editor_frame/
```

- [ ] **Step 3: Add route**

```ruby
# In config/routes.rb, inside the scope block:
get 'recipes/:slug/editor_frame', to: 'recipes#editor_frame', as: :recipe_editor_frame
```

- [ ] **Step 4: Add controller action**

```ruby
# In app/controllers/recipes_controller.rb
def editor_frame
  recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
  markdown = FamilyRecipes::RecipeSerializer.serialize(ir)

  render partial: 'recipes/editor_frame', locals: {
    recipe: recipe,
    markdown_source: markdown,
    structure: ir
  }, layout: false
end
```

This replicates the data preparation from the existing `content` action (lines 20-31).

- [ ] **Step 5: Create `_graphical_step_card.html.erb` partial**

This partial renders a single step card matching the DOM structure that
`recipe_graphical_controller.js`'s `buildStepCard()` produces:

```erb
<%# locals: (step:, index:, step_count:) %>
<% if step[:cross_reference] %>
  <div class="graphical-step-card graphical-step-card--crossref">
    <div class="graphical-step-header">
      <span class="graphical-crossref-label">
        Imports from <%= step[:cross_reference][:target_title] %>
        <% if step[:cross_reference][:multiplier] &&
              (step[:cross_reference][:multiplier] - 1.0).abs > 0.0001 %>
          &times;<%= step[:cross_reference][:multiplier] %>
        <% end %>
      </span>
      <span class="graphical-crossref-hint">edit in &lt;/&gt; mode</span>
      <%# Step action buttons (move up/down, remove) rendered by JS on hydration %>
    </div>
  </div>
<% else %>
  <div class="graphical-step-card" data-step-index="<%= index %>">
    <div class="graphical-step-header">
      <span class="graphical-step-title"><%= step[:tldr].presence || "Step #{index + 1}" %></span>
      <span class="graphical-ingredient-summary">
        <%= pluralize((step[:ingredients] || []).size, 'ingredient') if (step[:ingredients] || []).any? %>
      </span>
    </div>
    <div class="graphical-step-body" hidden>
      <div class="graphical-field-group">
        <label class="graphical-label">Step name</label>
        <input type="text" class="graphical-input"
               data-field="tldr"
               value="<%= step[:tldr] %>">
      </div>
      <div class="graphical-ingredients-section">
        <div class="graphical-ingredients-header">
          <span>Ingredients</span>
        </div>
        <div class="graphical-ingredient-rows" data-step-index="<%= index %>">
          <% (step[:ingredients] || []).each do |ing| %>
            <div class="graphical-ingredient-row">
              <input class="graphical-input graphical-input--name"
                     data-field="name" value="<%= ing[:name] %>"
                     placeholder="Name">
              <input class="graphical-input graphical-input--qty"
                     data-field="quantity" value="<%= ing[:quantity] %>"
                     placeholder="Qty">
              <input class="graphical-input graphical-input--prep"
                     data-field="prep_note" value="<%= ing[:prep_note] %>"
                     placeholder="Prep note">
            </div>
          <% end %>
        </div>
      </div>
      <div class="graphical-field-group">
        <label class="graphical-label">Instructions</label>
        <textarea class="graphical-input graphical-textarea"
                  data-field="instructions"><%= step[:instructions] %></textarea>
      </div>
    </div>
  </div>
<% end %>
```

**IMPORTANT:** Read `recipe_graphical_controller.js`'s `buildStepCard()`,
`buildStepHeader()`, `buildStepBody()`, `buildIngredientRow()` methods carefully.
The server-rendered HTML must match the CSS class names and DOM hierarchy exactly.
The action buttons (move up/down, remove, add ingredient) can be omitted from the
server-rendered HTML — the JS controller will add them when it hydrates the DOM
via its existing `rebuildSteps()` method on `editor:content-loaded`.

- [ ] **Step 6: Create `_editor_frame.html.erb`**

```erb
<%# locals: (recipe:, markdown_source:, structure:) %>
<turbo-frame id="recipe-editor-content">
  <script type="application/json" data-editor-markdown>
    <%= { markdown_source: markdown_source }.to_json.html_safe %>
  </script>

  <div class="editor-body" data-dual-mode-editor-target="plaintextContainer">
    <div data-controller="plaintext-editor"
         data-plaintext-editor-classifier-value="recipe"
         data-plaintext-editor-fold-service-value="recipe"
         data-plaintext-editor-placeholder-value="Paste or type a recipe…">
      <div class="cm-mount" data-plaintext-editor-target="mount"></div>
    </div>
  </div>

  <div class="editor-body" data-dual-mode-editor-target="graphicalContainer" hidden>
    <div data-controller="recipe-graphical"
         data-recipe-graphical-categories-value="<%= recipe.kitchen.categories.ordered.pluck(:name).to_json %>">
      <div class="graphical-form">
        <%# Front matter fields — same as current _graphical_editor.html.erb
            but with values pre-populated from the structure hash %>
        <div class="graphical-field-group">
          <label class="graphical-label" for="graphical-title">Title</label>
          <input type="text" id="graphical-title" class="graphical-input"
                 data-recipe-graphical-target="title"
                 value="<%= structure[:title] %>"
                 placeholder="Recipe title">
        </div>
        <%# ... description, serves, makes, category, tags fields
            pre-populated from structure[:front_matter] ... %>
        <div data-recipe-graphical-target="stepsContainer" class="graphical-steps-container">
          <% (structure[:steps] || []).each_with_index do |step, i| %>
            <%= render 'recipes/graphical_step_card',
                  step: step, index: i,
                  step_count: (structure[:steps] || []).size %>
          <% end %>
        </div>
        <button type="button" class="btn graphical-btn--add-step"
                data-action="click->recipe-graphical#addStep">+ Add Step</button>
        <%# Footer field %>
      </div>
    </div>
  </div>
</turbo-frame>
```

**Note on the embedded JSON:** The `to_json.html_safe` is safe here because we
control the data — it's a serialized recipe, not user-supplied HTML. However,
check `config/html_safe_allowlist.yml` and add the line if needed. The pattern
matches the existing embedded JSON approach used by search data and smart tags
(see `SearchDataHelper`).

- [ ] **Step 7: Run test — confirm it passes**

```bash
ruby -Itest test/controllers/recipes_controller_test.rb -n /editor_frame/
```

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/recipes_controller.rb \
  app/views/recipes/_editor_frame.html.erb \
  app/views/recipes/_graphical_step_card.html.erb \
  test/controllers/recipes_controller_test.rb
git commit -m "Add recipe editor Turbo Frame endpoint (#260)

Server-rendered graphical form + embedded markdown JSON.
Step cards rendered via ERB partial matching existing DOM structure."
```

---

## Task 6: Recipe editor — JS migration

Wire the recipe editor views and JS controllers to use the Turbo Frame instead
of JSON fetch.

**Files:**
- Modify: `app/views/recipes/show.html.erb`
- Modify: `app/javascript/controllers/dual_mode_editor_controller.js`
- Modify: `app/javascript/controllers/plaintext_editor_controller.js`
- Modify: `app/javascript/controllers/recipe_graphical_controller.js`

- [ ] **Step 1: Update `recipes/show.html.erb` to use Turbo Frame**

Replace the recipe editor dialog body (lines 33-63) with a Turbo Frame:

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
                             extra_controllers: 'dual-mode-editor' },
              extra_data: {
                'dual-mode-editor-parse-url-value' => recipe_parse_path,
                'dual-mode-editor-serialize-url-value' => recipe_serialize_path,
                'dual-mode-editor-content-key-value' => 'markdown_source',
                'dual-mode-editor-graphical-id-value' => 'recipe-graphical'
              },
              footer_extra: render('recipes/editor_delete_button', recipe: @recipe) } do %>
  <turbo-frame id="recipe-editor-content"
               src="<%= recipe_editor_frame_path(@recipe.slug) %>"
               data-editor-target="frame">
    <p class="loading-placeholder">Loading&hellip;</p>
  </turbo-frame>
<% end %>
```

Note: the `editor_load_url` and `editor_load_key` values are removed — no more
JSON fetch. The Turbo Frame handles content loading.

- [ ] **Step 2: Update `plaintext_editor_controller.js` to read from embedded JSON**

When the controller lives inside a Turbo Frame, its `initial` value won't be
set from the view (it was previously set by the JS after JSON fetch). Instead,
it reads the embedded `<script>` JSON:

```javascript
mountTargetConnected(element) {
  this.editorView?.destroy()
  element.classList.remove("cm-loading")

  // Read initial content: prefer explicit value, then embedded JSON, then empty
  let doc = ""
  if (this.hasInitialValue) {
    doc = this.initialValue
  } else {
    const jsonEl = this.element.closest("turbo-frame")
      ?.querySelector("script[data-editor-markdown]")
    if (jsonEl) {
      const data = JSON.parse(jsonEl.textContent)
      doc = data.markdown_source || ""
    }
  }

  this.editorView = createEditor({
    parent: element,
    doc,
    classifier: classifiers[this.classifierValue],
    foldService: this.hasFoldServiceValue ? foldServices[this.foldServiceValue] : null,
    placeholder: this.hasPlaceholderValue ? this.placeholderValue : "",
    extraExtensions: [autoDashKeymap]
  })
}
```

- [ ] **Step 3: Update `dual_mode_editor_controller.js` for frame-delivered content**

Modify `handleContentLoaded()` — when content arrives via Turbo Frame (no
`data.markdown_source` in the event detail), read the initial state from the
rendered DOM instead of from the event:

```javascript
handleContentLoaded(event) {
  event.detail.handled = true
  const data = event.detail

  // Frame-delivered content: read from embedded JSON + existing graphical DOM
  if (!data[this.contentKeyValue]) {
    const jsonEl = this.element.querySelector("script[data-editor-markdown]")
    if (jsonEl) {
      const parsed = JSON.parse(jsonEl.textContent)
      this.originalContent = parsed[this.contentKeyValue] || ""
      this.plaintextController.content = this.originalContent
    }
    // Graphical form is already server-rendered — read structure from it
    this.originalStructure = this.graphicalController.toStructure()
    this.enableEditing()
    this.showActiveMode()
    return
  }

  // Legacy path: JSON-delivered content (AI import, etc.)
  this.originalContent = data[this.contentKeyValue]
  this.originalStructure = data.structure
  this.plaintextController.content = data[this.contentKeyValue]
  if (data.structure) {
    this.graphicalController.loadStructure(data.structure)
  }
  this.enableEditing()
  this.showActiveMode()
}
```

- [ ] **Step 4: Update `recipe_graphical_controller.js` for server-rendered initial state**

The graphical controller needs to handle two cases:
1. **Initial load from Turbo Frame:** Step cards are already rendered. Call
   `initFromRenderedDOM()` to read the existing DOM into `this.steps`, then
   `rebuildSteps()` to add interactive controls (action buttons, event listeners).
2. **Mode switch from plaintext:** `loadStructure(ir)` builds DOM from scratch
   (unchanged from today).

Add `initFromRenderedDOM()`:

```javascript
initFromRenderedDOM() {
  const cards = this.stepsContainerTarget.children
  this.steps = Array.from(cards).map(card => this.readStepFromCard(card))
  this.rebuildSteps()  // Re-render with full interactivity (buttons, events)
  if (this.steps.length > 0) expandAccordionItem(this.stepsContainerTarget, 0)
}

readStepFromCard(card) {
  if (card.classList.contains("graphical-step-card--crossref")) {
    // Read cross-reference data from the rendered label
    const label = card.querySelector(".graphical-crossref-label")?.textContent || ""
    // Parse title from "Imports from Title" or "Imports from Title ×2"
    const match = label.match(/Imports from (.+?)(?:\s*×([\d.]+))?$/)
    return {
      cross_reference: {
        target_title: match?.[1]?.trim() || "",
        multiplier: match?.[2] ? parseFloat(match[2]) : null
      }
    }
  }

  const body = card.querySelector(".graphical-step-body")
  return {
    tldr: body?.querySelector("[data-field='tldr']")?.value || "",
    ingredients: this.readIngredientsFromCard(card),
    instructions: body?.querySelector("[data-field='instructions']")?.value || "",
    cross_reference: null
  }
}

readIngredientsFromCard(card) {
  const rows = card.querySelectorAll(".graphical-ingredient-row")
  return Array.from(rows).map(row => ({
    name: row.querySelector("[data-field='name']")?.value || "",
    quantity: row.querySelector("[data-field='quantity']")?.value || "",
    prep_note: row.querySelector("[data-field='prep_note']")?.value || ""
  }))
}
```

Call `initFromRenderedDOM()` when the graphical controller detects it has
pre-rendered content (step cards already in the container on `connect()`):

```javascript
connect() {
  this.steps = []
  // If steps are already rendered (Turbo Frame), hydrate from DOM
  if (this.stepsContainerTarget.children.length > 0) {
    this.initFromRenderedDOM()
  }
}
```

- [ ] **Step 5: Run full test suite**

```bash
rake test
npm test
```

- [ ] **Step 6: Manual browser verification**

Start the dev server and verify:
1. Recipe show page → click Edit → dialog opens with content pre-loaded
2. Mode toggle works (plaintext ↔ graphical)
3. Graphical editor: add/remove/reorder steps and ingredients work
4. Save works from both modes
5. Dirty detection and close-with-confirmation work
6. AI import still works (uses `openWithContent`)

```bash
bin/dev
```

- [ ] **Step 7: Commit**

```bash
git add app/views/recipes/show.html.erb \
  app/javascript/controllers/dual_mode_editor_controller.js \
  app/javascript/controllers/plaintext_editor_controller.js \
  app/javascript/controllers/recipe_graphical_controller.js
git commit -m "Wire recipe editor to Turbo Frame (#260)

Editor opens with pre-loaded content from eager Turbo Frame.
Graphical controller hydrates from server-rendered step cards.
Plaintext controller reads markdown from embedded JSON."
```

---

## Task 7: Quick Bites editor — Migration

Same pattern as the recipe editor. Quick Bites uses `dual_mode_editor_controller`
with `quickbites_graphical_controller`.

**Files:**
- Create: `app/views/menu/_quickbites_editor_frame.html.erb`
- Modify: `app/controllers/menu_controller.rb`
- Modify: `app/views/menu/show.html.erb`
- Modify: `app/javascript/controllers/quickbites_graphical_controller.js`
- Modify: `config/routes.rb`
- Test: `test/controllers/menu_controller_test.rb`

- [ ] **Step 1: Write controller test for the frame endpoint**

```ruby
test "quickbites_editor_frame returns turbo frame" do
  log_in @user

  get menu_quickbites_editor_frame_path(kitchen_slug: kitchen_slug), as: :html

  assert_response :success
  assert_select "turbo-frame#quickbites-editor-content"
  assert_select "script[type='application/json'][data-editor-markdown]"
end
```

- [ ] **Step 2: Run test — confirm it fails**

```bash
ruby -Itest test/controllers/menu_controller_test.rb -n /quickbites_editor_frame/
```

- [ ] **Step 3: Add route + controller action**

```ruby
# config/routes.rb:
get 'menu/quickbites_editor_frame', to: 'menu#quickbites_editor_frame',
    as: :menu_quickbites_editor_frame

# menu_controller.rb:
def quickbites_editor_frame
  content = current_kitchen.quick_bites_content || ''
  result = FamilyRecipes.parse_quick_bites_content(content)
  structure = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)

  render partial: 'menu/quickbites_editor_frame', locals: {
    content: content,
    structure: structure
  }, layout: false
end
```

This replicates the data preparation from the existing `quick_bites_content`
action (lines 37-42 of `menu_controller.rb`).

- [ ] **Step 4: Create the frame partial**

`app/views/menu/_quickbites_editor_frame.html.erb`:

Same pattern as recipe: embedded `<script>` JSON with the plaintext content,
plus the server-rendered graphical form for Quick Bites. Read the existing
`_quickbites_graphical_editor.html.erb` partial and `quickbites_graphical_controller.js`
to understand the graphical form structure.

- [ ] **Step 5: Update `quickbites_graphical_controller.js`**

Add `initFromRenderedDOM()` and `readFromCard()` methods — same pattern as
`recipe_graphical_controller`. Read the controller to understand its structure
(sections with items, different from recipe steps).

- [ ] **Step 6: Update `menu/show.html.erb`**

Replace the Quick Bites editor dialog body with a Turbo Frame:

```erb
<turbo-frame id="quickbites-editor-content"
             src="<%= menu_quickbites_editor_frame_path %>"
             data-editor-target="frame">
  <p class="loading-placeholder">Loading&hellip;</p>
</turbo-frame>
```

Remove `editor_load_url` and `editor_load_key` from `dialog_data`.

- [ ] **Step 7: Run tests**

```bash
ruby -Itest test/controllers/menu_controller_test.rb
rake test
```

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/menu_controller.rb \
  app/views/menu/ app/javascript/controllers/quickbites_graphical_controller.js \
  test/controllers/menu_controller_test.rb
git commit -m "Migrate Quick Bites editor to Turbo Frame (#260)

Server-rendered graphical form + embedded plaintext content."
```

---

## Task 8: Cleanup — Remove legacy code + unify loading CSS

Remove `openWithRemoteContent()` and all related dead code now that every
editor uses Turbo Frames. Unify the loading state CSS.

**Files:**
- Modify: `app/javascript/controllers/editor_controller.js`
- Modify: `app/views/shared/_editor_dialog.html.erb`
- Modify: `app/assets/stylesheets/style.css`
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

- [ ] **Step 1: Remove `openWithRemoteContent()` and related code**

From `editor_controller.js`, delete:
- `openWithRemoteContent()` method (lines 239-271)
- `loadUrl` and `loadKey` from static values
- The `hasLoadUrlValue` branch in `open()`

From `_editor_dialog.html.erb`, remove:
- `editor_load_url_value` data attribute wiring
- `editor_load_key_value` data attribute wiring

- [ ] **Step 2: Remove JSON format from ordered list endpoints**

Now that the JS companion reads from the Turbo Frame, the JSON `respond_to`
branch in aisles/categories/tags content actions can be removed. Keep only the
HTML format.

- [ ] **Step 3: Unify loading state CSS**

In `style.css`, remove:
- `.cm-mount.cm-loading` styles (around line 2078-2093) — the CodeMirror mount
  now lives inside the Turbo Frame; the frame's loading placeholder handles
  the pre-load state.

Ensure `.loading-placeholder` has consistent styling:
```css
.loading-placeholder {
  color: var(--text-soft);
  font-style: italic;
  padding: 2rem;
  text-align: center;
}
```

- [ ] **Step 4: Run lint**

```bash
bundle exec rubocop
rake lint:html_safe
```

Update `config/html_safe_allowlist.yml` if `.html_safe` calls shifted line
numbers. The embedded JSON in `_editor_frame.html.erb` uses `.to_json.html_safe`
— add it to the allowlist.

- [ ] **Step 5: Run full test suite**

```bash
rake test
npm test
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/editor_controller.js \
  app/views/shared/_editor_dialog.html.erb \
  app/assets/stylesheets/style.css \
  app/controllers/ config/html_safe_allowlist.yml
git commit -m "Remove legacy JSON fetch code, unify loading CSS (#260)

Delete openWithRemoteContent(), loadUrl/loadKey values, cm-loading
CSS. All editors now use Turbo Frame loading exclusively."
```

---

## Verification Checklist

After all tasks are complete, verify these acceptance criteria:

- [ ] All editor dialogs use `_editor_dialog.html.erb` (no custom `<dialog>` markup)
- [ ] All dialog bodies load via Turbo Frames
- [ ] Eager preloading on page load (except nutrition hover-prefetch)
- [ ] Re-preload on broadcast: trigger a save from another tab, verify the editor
      picks up fresh content on next open
- [ ] Loading placeholder visible if frame hasn't loaded yet (throttle network
      in devtools to test)
- [ ] Error + retry works (block the frame URL in devtools, open editor, click retry)
- [ ] Ordered list editors use shared shell + companion pattern
- [ ] Settings editor uses shared shell + Turbo Frame
- [ ] Recipe editor graphical form is server-rendered
- [ ] Mode toggle (plaintext ↔ graphical) works in recipe and Quick Bites editors
- [ ] AI import still works (homepage new-recipe → AI import button)
- [ ] New recipe dialog (homepage) opens with empty template (no Turbo Frame src)
- [ ] Dirty detection and close-with-confirmation work for all editors
- [ ] `rake test` and `bundle exec rubocop` pass clean

# Menu / Groceries Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Split the monolithic Groceries page into a Menu page (meal planning) and a Groceries page (shopping list), renaming GroceryList to MealPlan.

**Architecture:** Rename the `grocery_lists` table to `meal_plans` via migration. Create a new `MenuController` for selection/quick-bites actions, slim `GroceriesController` to shopping-list-only actions. Split the JS controllers accordingly. Both pages share the same `MealPlan` model and `MealPlanChannel` for real-time sync.

**Tech Stack:** Rails 8, SQLite, Stimulus, ActionCable, Turbo Streams

---

### Task 0: Create worktree for isolated development

**Step 1: Create worktree**

Use the `EnterWorktree` tool with name `menu-groceries-split`.

**Step 2: Verify clean state**

Run: `git status`
Expected: clean working tree on a new branch

---

### Task 1: Rename GroceryList model to MealPlan

**Files:**
- Create: `db/migrate/008_rename_grocery_lists_to_meal_plans.rb`
- Create: `app/models/meal_plan.rb` (copy from `app/models/grocery_list.rb`, rename class)
- Delete: `app/models/grocery_list.rb`
- Modify: `app/models/kitchen.rb:10` — change `has_one :grocery_list` to `has_one :meal_plan`
- Modify: `app/services/shopping_list_builder.rb:4` — change `grocery_list:` param to `meal_plan:`
- Modify: `app/services/shopping_list_builder.rb` — all `@grocery_list` references to `@meal_plan`
- Modify: `app/controllers/groceries_controller.rb` — all `GroceryList` to `MealPlan`
- Modify: `app/controllers/recipes_controller.rb` — `GroceryListChannel` to `MealPlanChannel`
- Modify: `app/controllers/nutrition_entries_controller.rb` — `GroceryListChannel` to `MealPlanChannel`
- Create: `test/models/meal_plan_test.rb` (copy from `test/models/grocery_list_test.rb`, rename)
- Delete: `test/models/grocery_list_test.rb`
- Modify: `test/services/shopping_list_builder_test.rb` — all `GroceryList` to `MealPlan`, `grocery_list:` to `meal_plan:`
- Modify: `test/controllers/groceries_controller_test.rb` — all `GroceryList` to `MealPlan`, stale error message update

**Step 1: Create the migration**

```ruby
# frozen_string_literal: true

class RenameGroceryListsToMealPlans < ActiveRecord::Migration[8.1]
  def change
    rename_table :grocery_lists, :meal_plans
  end
end
```

**Step 2: Create MealPlan model**

Copy `app/models/grocery_list.rb` to `app/models/meal_plan.rb`. Change `class GroceryList` to `class MealPlan`. Update the stale-error rescue message in the controller at the same time.

**Step 3: Update Kitchen association**

In `app/models/kitchen.rb:10`, change:
```ruby
has_one :grocery_list, dependent: :destroy
```
to:
```ruby
has_one :meal_plan, dependent: :destroy
```

**Step 4: Update ShoppingListBuilder**

In `app/services/shopping_list_builder.rb`:
- Change `def initialize(kitchen:, grocery_list:)` to `def initialize(kitchen:, meal_plan:)`
- Change `@grocery_list = grocery_list` to `@meal_plan = meal_plan`
- Change all `@grocery_list` references to `@meal_plan` (lines 29, 37, 92)

**Step 5: Update GroceriesController**

In `app/controllers/groceries_controller.rb`:
- Change all `GroceryList` to `MealPlan` (lines 15, 16, 40, 50, 75, 88)
- Change `GroceryListChannel` to `MealPlanChannel` (lines 52, 77, 92)
- Change `grocery_list: list` to `meal_plan: list` (line 16)
- Change the stale record error message from "Grocery list" to "Meal plan" (line 97)

**Step 6: Update other controllers**

In `app/controllers/recipes_controller.rb`, replace `GroceryListChannel` with `MealPlanChannel` (lines 20, 47, 62).
In `app/controllers/nutrition_entries_controller.rb`, replace `GroceryListChannel` with `MealPlanChannel` (line 99).

**Step 7: Rename and update tests**

- Copy `test/models/grocery_list_test.rb` to `test/models/meal_plan_test.rb`, change class name to `MealPlanTest`, replace all `GroceryList` with `MealPlan`.
- Delete `test/models/grocery_list_test.rb`.
- In `test/services/shopping_list_builder_test.rb`, replace `GroceryList` with `MealPlan` and `grocery_list:` with `meal_plan:`.
- In `test/controllers/groceries_controller_test.rb`, replace `GroceryList` with `MealPlan` and `GroceryListChannel` with `MealPlanChannel`. Update the stale record error message assertion.

**Step 8: Run migration and tests**

Run: `rails db:migrate && rake`
Expected: All tests pass, migration renames table successfully.

**Step 9: Commit**

```bash
git add -A && git commit -m "refactor: rename GroceryList to MealPlan (#110)"
```

---

### Task 2: Rename GroceryListChannel to MealPlanChannel

**Files:**
- Create: `app/channels/meal_plan_channel.rb` (copy from `app/channels/grocery_list_channel.rb`, rename class)
- Delete: `app/channels/grocery_list_channel.rb`
- Modify: `app/javascript/controllers/grocery_sync_controller.js:162` — change channel name
- Create: `test/channels/meal_plan_channel_test.rb` (copy from `test/channels/grocery_list_channel_test.rb`, rename)
- Delete: `test/channels/grocery_list_channel_test.rb`

**Step 1: Create MealPlanChannel**

Copy `app/channels/grocery_list_channel.rb` to `app/channels/meal_plan_channel.rb`. Change `class GroceryListChannel` to `class MealPlanChannel`.

**Step 2: Update JS subscription**

In `app/javascript/controllers/grocery_sync_controller.js:162`, change:
```javascript
{ channel: "GroceryListChannel", kitchen_slug: slug },
```
to:
```javascript
{ channel: "MealPlanChannel", kitchen_slug: slug },
```

**Step 3: Update and rename tests**

Copy `test/channels/grocery_list_channel_test.rb` to `test/channels/meal_plan_channel_test.rb`. Change class name to `MealPlanChannelTest`, replace all `GroceryListChannel` with `MealPlanChannel`.
Delete `test/channels/grocery_list_channel_test.rb`.

**Step 4: Delete old files**

Delete `app/channels/grocery_list_channel.rb` and `test/channels/grocery_list_channel_test.rb`.

**Step 5: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add -A && git commit -m "refactor: rename GroceryListChannel to MealPlanChannel (#110)"
```

---

### Task 3: Create MenuController and routes

**Files:**
- Create: `app/controllers/menu_controller.rb`
- Modify: `config/routes.rb` — add menu routes, remove select/quick_bites/clear from groceries
- Modify: `app/controllers/groceries_controller.rb` — remove `select`, `update_quick_bites`, `clear`, and their helpers

**Step 1: Write the MenuController test**

Create `test/controllers/menu_controller_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MenuControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
  end

  # --- Access control ---

  test 'show requires membership' do
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'select requires membership' do
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :forbidden
  end

  test 'clear requires membership' do
    delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :forbidden
  end

  test 'update_quick_bites requires membership' do
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :forbidden
  end

  # --- Show ---

  test 'renders the menu page with recipe checkboxes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    log_in
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select 'h1', 'Menu'
    assert_select 'input[type=checkbox][data-slug="focaccia"]'
  end

  # --- Select ---

  test 'select adds recipe and returns version' do
    log_in
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :json

    assert_response :success
    assert_operator response.parsed_body['version'], :>, 0
  end

  test 'select broadcasts version' do
    log_in
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :json
    end
  end

  # --- Clear ---

  test 'clear resets selections only, not custom items or checked off' do
    log_in
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('custom_items', item: 'candles', action: 'add')
    plan.apply_action('check', item: 'flour', checked: true)

    delete menu_clear_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    plan.reload
    assert_empty plan.state.fetch('selected_recipes', [])
    assert_empty plan.state.fetch('selected_quick_bites', [])
    assert_includes plan.state['custom_items'], 'candles'
    assert_includes plan.state['checked_off'], 'flour'
  end

  # --- Quick Bites ---

  test 'update_quick_bites saves valid content' do
    @kitchen.update!(quick_bites_content: 'old content')

    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json

    assert_response :success
    assert_equal "## Snacks\n  - Goldfish", @kitchen.reload.quick_bites_content
  end

  test 'update_quick_bites rejects blank content' do
    log_in
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '' },
          as: :json

    assert_response :unprocessable_entity
  end

  test 'update_quick_bites broadcasts recipe selector replacement' do
    log_in

    assert_turbo_stream_broadcasts [@kitchen, 'menu_content'] do
      patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
            params: { content: "## Snacks\n  - Goldfish" },
            as: :json
    end
  end
end
```

**Step 2: Add menu routes**

In `config/routes.rb`, inside the `scope '(/kitchens/:kitchen_slug)'` block, add menu routes and remove the moved groceries routes:

```ruby
scope '(/kitchens/:kitchen_slug)' do
  resources :recipes, only: %i[show create update destroy], param: :slug
  get 'ingredients', to: 'ingredients#index', as: :ingredients
  get 'menu', to: 'menu#show', as: :menu
  patch 'menu/select', to: 'menu#select', as: :menu_select
  delete 'menu/clear', to: 'menu#clear', as: :menu_clear
  patch 'menu/quick_bites', to: 'menu#update_quick_bites', as: :menu_quick_bites
  get 'groceries', to: 'groceries#show', as: :groceries
  get 'groceries/state', to: 'groceries#state', as: :groceries_state
  patch 'groceries/check', to: 'groceries#check', as: :groceries_check
  patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
  patch 'groceries/aisle_order', to: 'groceries#update_aisle_order', as: :groceries_aisle_order
  get 'groceries/aisle_order_content', to: 'groceries#aisle_order_content', as: :groceries_aisle_order_content
  post 'nutrition/:ingredient_name', to: 'nutrition_entries#upsert', as: :nutrition_entry_upsert
  delete 'nutrition/:ingredient_name', to: 'nutrition_entries#destroy', as: :nutrition_entry_destroy
end
```

Note: `groceries_select`, `groceries_clear`, and `groceries_quick_bites` routes are removed.

**Step 3: Create MenuController**

Create `app/controllers/menu_controller.rb`:

```ruby
# frozen_string_literal: true

class MenuController < ApplicationController
  before_action :require_membership

  rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record

  def show
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = current_kitchen.quick_bites_content || ''
  end

  def select
    apply_and_respond('select',
                      type: params[:type],
                      slug: params[:slug],
                      selected: params[:selected])
  end

  def clear
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { plan.clear_selections! }
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)

    broadcast_recipe_selector_update
    render json: { status: 'ok' }
  end

  private

  def apply_and_respond(action_type, **action_params)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry do
      plan.apply_action(action_type, **action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end

  def load_quick_bites_by_subsection
    content = current_kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
  end

  def broadcast_recipe_selector_update
    Turbo::StreamsChannel.broadcast_replace_to(
      current_kitchen, 'menu_content',
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: {
        categories: recipe_selector_categories,
        quick_bites_by_subsection: load_quick_bites_by_subsection
      }
    )
  end
end
```

**Step 4: Add `clear_selections!` to MealPlan**

In `app/models/meal_plan.rb`, add after the existing `clear!` method:

```ruby
def clear_selections!
  ensure_state_keys
  state['selected_recipes'] = []
  state['selected_quick_bites'] = []
  save!
end
```

**Step 5: Remove moved actions from GroceriesController**

From `app/controllers/groceries_controller.rb`, remove:
- `select` action (lines 25-30)
- `clear` action (lines 49-54)
- `update_quick_bites` action (lines 56-64)
- `load_quick_bites_by_subsection` private method (lines 117-123)
- `recipe_selector_categories` private method (lines 125-127)
- `broadcast_recipe_selector_update` private method (lines 129-139)

Also remove `@categories`, `@quick_bites_by_subsection`, `@quick_bites_content` from the `show` action since the recipe selector moves to the menu page.

**Step 6: Update GroceriesController tests**

In `test/controllers/groceries_controller_test.rb`:
- Remove tests for `select`, `clear`, `update_quick_bites` actions (they move to `MenuControllerTest`)
- Remove tests for recipe selector rendering (e.g., `renders the groceries page with recipe checkboxes`, `groups recipes by category`, `renders Quick Bites section`, `recipe selector has data-type attribute`)
- Remove the `select broadcasts version`, `clear broadcasts version`, `update_quick_bites broadcasts` tests
- Remove the `select returns 409` and `clear returns 409` stale-lock tests
- Keep: `show requires membership`, `state` tests, `check` tests, `custom_items` tests, `aisle_order` tests
- Update `renders the groceries page` test to assert `h1` is "Groceries" without checking for recipe checkboxes
- Remove the old `groceries_select_path` and `groceries_clear_path` references from any remaining tests (the `state includes selected_recipes` test that calls select should move to MenuControllerTest or be reworked to set state directly)

**Step 7: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 8: Commit**

```bash
git add -A && git commit -m "feat: create MenuController, move selection actions from Groceries (#110)"
```

---

### Task 4: Create Menu page view

**Files:**
- Create: `app/views/menu/show.html.erb`
- Move: `app/views/groceries/_recipe_selector.html.erb` → `app/views/menu/_recipe_selector.html.erb`
- Create: `app/assets/stylesheets/menu.css`

**Step 1: Create the menu view**

Create `app/views/menu/show.html.erb`:

```erb
<% content_for(:title) { "#{current_kitchen.name}: Menu" } %>

<% content_for(:head) do %>
  <%= stylesheet_link_tag 'menu', "data-turbo-track": "reload" %>
  <%= stylesheet_link_tag 'groceries', "data-turbo-track": "reload" %>
<% end %>

<% content_for(:extra_nav) do %>
  <div>
    <button type="button" id="edit-aisle-order-button" class="btn">Edit Aisle Order</button>
    <button type="button" id="edit-quick-bites-button" class="btn">Edit Quick Bites</button>
  </div>
<% end %>

<%= turbo_stream_from current_kitchen, "menu_content" %>

<header id="menu-header">
  <h1>Menu</h1>
  <p class="subtitle">What's on the menu? Pick recipes and quick bites that you want to have available.</p>
</header>

<noscript>
  <p><em>This page requires JavaScript to sync your selections.</em></p>
</noscript>

<div id="menu-app" class="hidden-until-js"
     data-controller="menu"
     data-kitchen-slug="<%= current_kitchen.slug %>"
     data-select-url="<%= menu_select_path %>"
     data-clear-url="<%= menu_clear_path %>"
     data-state-url="<%= groceries_state_path %>">

  <%= render 'menu/recipe_selector', categories: @categories, quick_bites_by_subsection: @quick_bites_by_subsection %>

  <div id="menu-actions">
    <button type="button" data-action="menu#clear" class="btn btn-clear">Clear All</button>
  </div>
</div>

<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Quick Bites',
              dialog_data: { editor_open: '#edit-quick-bites-button',
                             editor_url: menu_quick_bites_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'content' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false"><%= @quick_bites_content %></textarea>
<% end %>

<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Aisle Order',
              dialog_data: { editor_open: '#edit-aisle-order-button',
                             editor_url: groceries_aisle_order_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'aisle_order',
                             editor_load_url: groceries_aisle_order_content_path,
                             editor_load_key: 'aisle_order' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false" placeholder="Loading..."></textarea>
<% end %>
```

**Step 2: Move recipe selector partial**

Move `app/views/groceries/_recipe_selector.html.erb` to `app/views/menu/_recipe_selector.html.erb`. No content changes needed.

**Step 3: Create menu.css**

Create `app/assets/stylesheets/menu.css` with styles for the menu page header, subtitle, and clear button. The recipe selector styles stay in `groceries.css` for now (they're shared via the CSS link tag).

```css
/* Menu page */
#menu-header {
  text-align: center;
  margin-bottom: 1.5rem;
}

#menu-header .subtitle {
  font-size: 0.95rem;
  font-style: italic;
  margin-top: 0.25rem;
}

#menu-actions {
  text-align: center;
  margin-top: 1.5rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border-light);
}

.btn-clear {
  font-size: 0.85rem;
  padding: 0.4rem 1rem;
  border: 1px solid var(--border-light);
  border-radius: 4px;
  background: none;
  cursor: pointer;
  color: var(--muted-text);
}

.btn-clear:hover {
  color: var(--danger-color);
  border-color: var(--danger-color);
}

/* Menu print: show selected recipes in 2-column layout */
@media print {
  #menu-actions,
  #menu-header .subtitle,
  noscript {
    display: none !important;
  }

  #recipe-selector input[type="checkbox"],
  #recipe-selector .recipe-link {
    display: none;
  }

  #recipe-selector .category li:has(input:not(:checked)),
  #recipe-selector .quick-bites .subsection li:has(input:not(:checked)) {
    display: none;
  }

  #recipe-selector .category:not(:has(input:checked)),
  #recipe-selector .quick-bites .subsection:not(:has(input:checked)),
  #recipe-selector .quick-bites:not(:has(input:checked)) {
    display: none;
  }

  #recipe-selector {
    display: grid;
    grid-template-columns: 1fr 1fr;
    column-gap: 2rem;
    align-items: start;
  }

  #recipe-selector .category {
    break-inside: avoid;
  }

  #recipe-selector .quick-bites {
    grid-column: 1 / -1;
  }

  #recipe-selector .quick-bites .subsections {
    grid-template-columns: 1fr 1fr;
  }
}
```

**Step 4: Run tests**

Run: `rake`
Expected: All tests pass (menu controller test verifies the view renders correctly).

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: create Menu page view with recipe selector (#110)"
```

---

### Task 5: Create menu Stimulus controller

**Files:**
- Create: `app/javascript/controllers/menu_controller.js`

**Step 1: Create menu_controller.js**

```javascript
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { show as notifyShow } from "utilities/notify"

export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.storageKey = `menu-state-${slug}`
    this.version = 0
    this.state = {}
    this.awaitingOwnAction = false
    this.initialFetch = true

    this.urls = {
      state: this.element.dataset.stateUrl,
      select: this.element.dataset.selectUrl,
      clear: this.element.dataset.clearUrl
    }

    this.loadCache()
    if (this.state && Object.keys(this.state).length > 0) {
      this.syncCheckboxes(this.state)
    }

    this.fetchState()
    this.subscribe(slug)
    this.startHeartbeat()

    this.bindRecipeCheckboxes()

    this.boundHandleStreamRender = this.handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
  }

  disconnect() {
    if (this.fetchController) this.fetchController.abort()
    if (this.heartbeatId) {
      clearInterval(this.heartbeatId)
      this.heartbeatId = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.boundHandleStreamRender) {
      document.removeEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
    }
  }

  handleStreamRender(event) {
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      if (this.state && Object.keys(this.state).length > 0) {
        this.syncCheckboxes(this.state)
      }
    }
  }

  fetchState() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.urls.state, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        if (data.version >= this.version) {
          const isRemoteUpdate = data.version > this.version
            && this.version > 0
            && !this.awaitingOwnAction
            && !this.initialFetch
          this.awaitingOwnAction = false
          this.initialFetch = false
          this.version = data.version
          this.state = data
          this.saveCache()
          this.syncCheckboxes(data)
          if (isRemoteUpdate) {
            notifyShow("Menu updated.")
          }
        }
      })
      .catch(() => {})
  }

  syncCheckboxes(state) {
    this.element.classList.remove("hidden-until-js")

    const selectedRecipes = state.selected_recipes || []
    const selectedQuickBites = state.selected_quick_bites || []

    this.element.querySelectorAll("#recipe-selector input[type=\"checkbox\"]").forEach(cb => {
      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      if (!typeEl || !slug) return

      if (typeEl.dataset.type === "quick_bite") {
        cb.checked = selectedQuickBites.indexOf(slug) !== -1
      } else {
        cb.checked = selectedRecipes.indexOf(slug) !== -1
      }
    })
  }

  sendAction(url, params) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')
    const method = url === this.urls.clear ? "DELETE" : "PATCH"

    this.awaitingOwnAction = true

    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken ? csrfToken.content : ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) throw new Error("action failed")
        return response.json()
      })
      .then(() => {
        this.fetchState()
      })
      .catch(() => {
        this.awaitingOwnAction = false
      })
  }

  subscribe(slug) {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "MealPlanChannel", kitchen_slug: slug },
      {
        received: (data) => {
          if (data.version && data.version > this.version && !this.awaitingOwnAction) {
            this.fetchState()
          }
        }
      }
    )
  }

  startHeartbeat() {
    this.heartbeatId = setInterval(() => this.fetchState(), 30000)
  }

  bindRecipeCheckboxes() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      this.sendAction(this.urls.select, { type, slug, selected: cb.checked })
    })
  }

  clear() {
    this.sendAction(this.urls.clear, {})
  }

  saveCache() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({
        version: this.version,
        state: this.state
      }))
    } catch { /* localStorage full or unavailable */ }
  }

  loadCache() {
    try {
      const raw = localStorage.getItem(this.storageKey)
      if (!raw) return
      const cached = JSON.parse(raw)
      if (cached && cached.version) {
        this.version = cached.version
        this.state = cached.state || {}
      }
    } catch { /* corrupted cache */ }
  }
}
```

**Step 2: Verify importmap picks up the new controller**

The existing `pin_all_from 'app/javascript/controllers', under: 'controllers'` in `config/importmap.rb` auto-discovers new controllers. No change needed.

**Step 3: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add menu Stimulus controller for recipe selection sync (#110)"
```

---

### Task 6: Simplify Groceries page view and controllers

**Files:**
- Modify: `app/views/groceries/show.html.erb` — remove recipe selector, update header/subtitle, restructure custom items
- Delete: `app/views/groceries/_recipe_selector.html.erb` (already moved in Task 4)
- Modify: `app/views/groceries/_custom_items.html.erb` — remove header, simplify for inline placement
- Modify: `app/javascript/controllers/grocery_ui_controller.js` — remove `syncCheckboxes`, `bindRecipeCheckboxes`; move custom items rendering to bottom of shopping list
- Modify: `app/javascript/controllers/grocery_sync_controller.js` — remove select URL, update localStorage keys

**Step 1: Update groceries/show.html.erb**

Replace the file with a simplified version. Key changes:
- Remove the recipe selector render
- Remove the `data-select-url` and `data-clear-url` data attributes
- Change the Turbo Stream channel to listen only for relevant updates
- Move custom items inside the shopping list area
- Update header text
- Remove the quick bites editor dialog
- Keep the aisle order editor dialog

```erb
<% content_for(:title) { "#{current_kitchen.name}: Groceries" } %>

<% content_for(:head) do %>
  <%= stylesheet_link_tag 'groceries', "data-turbo-track": "reload" %>
<% end %>

<% if current_kitchen.member?(current_user) %>
<% content_for(:extra_nav) do %>
  <div>
    <button type="button" id="edit-aisle-order-button" class="btn">Edit Aisle Order</button>
  </div>
<% end %>
<% end %>

<header id="groceries-header">
  <h1>Groceries</h1>
  <p class="subtitle">Your shopping list, built from the <%= link_to 'menu', menu_path %>.</p>
</header>

<noscript>
  <p><em>This page requires JavaScript to build your shopping list.</em></p>
</noscript>

<div id="groceries-app" class="hidden-until-js"
     data-controller="wake-lock grocery-sync grocery-ui"
     data-kitchen-slug="<%= current_kitchen.slug %>"
     data-state-url="<%= groceries_state_path %>"
     data-check-url="<%= groceries_check_path %>"
     data-custom-items-url="<%= groceries_custom_items_path %>">

  <div id="shopping-list"></div>

  <%= render 'groceries/custom_items' %>

</div>

<% if current_kitchen.member?(current_user) %>
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Aisle Order',
              dialog_data: { editor_open: '#edit-aisle-order-button',
                             editor_url: groceries_aisle_order_path,
                             editor_method: 'PATCH',
                             editor_on_success: 'close',
                             editor_body_key: 'aisle_order',
                             editor_load_url: groceries_aisle_order_content_path,
                             editor_load_key: 'aisle_order' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" spellcheck="false" placeholder="Loading..."></textarea>
<% end %>
<% end %>
```

**Step 2: Simplify _custom_items.html.erb**

Remove the "Additional Items" heading since it'll be at the bottom of the shopping list:

```erb
<%# locals: () %>
<div id="custom-items-section">
  <div id="custom-input-row">
    <label for="custom-input" class="sr-only">Add an item</label>
    <input type="text" id="custom-input" placeholder="Add an item...">
    <button id="custom-add" type="button" aria-label="Add item"><svg viewBox="0 0 24 24" width="18" height="18"><line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
  </div>
  <ul id="custom-items-list"></ul>
</div>
```

**Step 3: Update grocery_sync_controller.js**

Remove `select` and `clear` URLs since those are now on the menu page:

- Remove `select: this.element.dataset.selectUrl` and `clear: this.element.dataset.clearUrl` from `this.urls`
- The controller now only has `state`, `check`, and `customItems` URLs

**Step 4: Update grocery_ui_controller.js**

- Remove `syncCheckboxes` method entirely
- Remove `bindRecipeCheckboxes` method entirely
- Remove `syncCheckboxes(state)` call from `applyState`
- In `renderShoppingList`, change the empty message from "Select recipes above to build your shopping list." to "No items yet."
- Custom items are already rendered separately in the DOM below the shopping list; keep the existing approach but verify it works with the new layout

**Step 5: Update groceries.css**

- Remove the `#instructions` styles (no longer used)
- Remove the `#recipe-selector` print styles from the groceries CSS (they move to `menu.css`)
- Remove the recipe selector grid desktop layout from `@media (min-width: 700px)` section
- Update `#custom-items-section` styles — remove the top border and extra padding since it's now below the shopping list
- Update print styles to remove recipe-selector print layout (page 1 is gone from groceries)

**Step 6: Update GroceriesController tests**

Update the remaining tests to reflect the simplified page:
- Remove `assert_select '#recipe-selector'` assertions
- Remove `assert_select 'turbo-cable-stream-source'` assertion (no Turbo Stream on groceries page now)
- Remove the "editor dialogs use close mode" test that asserts `count: 2` (now only 1 dialog — aisle order)
- Update `data-controller` assertion to not expect the select/clear URLs

**Step 7: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 8: Commit**

```bash
git add -A && git commit -m "feat: simplify Groceries page to shopping-list only (#110)"
```

---

### Task 7: Update navbar

**Files:**
- Modify: `app/views/shared/_nav.html.erb` — add Menu link between Ingredients and Groceries

**Step 1: Update nav partial**

In `app/views/shared/_nav.html.erb`, add the Menu link:

```erb
<nav>
  <div>
    <% if current_kitchen %>
      <%= link_to 'Home', home_path, class: 'home', title: 'Home (Table of Contents)' %>
      <% if logged_in? %>
        <%= link_to 'Ingredients', ingredients_path, class: 'ingredients', title: 'Ingredients' %>
        <%= link_to 'Menu', menu_path, class: 'menu', title: 'Plan your meals' %>
        <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Shopping list' %>
      <% end %>
    <% else %>
      <%= link_to 'Home', root_path, class: 'home', title: 'Home' %>
    <% end %>
  </div>
  <%= yield :extra_nav if content_for?(:extra_nav) %>
</nav>
```

**Step 2: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: add Menu link to navbar between Ingredients and Groceries (#110)"
```

---

### Task 8: Update service worker and PWA manifest

**Files:**
- Modify: `public/service-worker.js` — update `API_PATTERN` to include menu routes
- Modify: PWA manifest (if it exists as a controller-rendered view, add menu shortcut)

**Step 1: Update API_PATTERN in service-worker.js**

Change line 3 of `public/service-worker.js` from:

```javascript
var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(state|select|check|custom_items|clear|quick_bites|aisle_order|aisle_order_content)|nutrition\/)/;
```

to:

```javascript
var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(state|check|custom_items|aisle_order|aisle_order_content)|menu\/(select|clear|quick_bites)|nutrition\/)/;
```

Note: `select`, `clear`, and `quick_bites` move from the `groceries/` prefix to the `menu/` prefix.

**Step 2: Bump the cache version**

Change `CACHE_NAME` from `'familyrecipes-v3'` to `'familyrecipes-v4'` to invalidate old cached pages.

**Step 3: Run tests**

Run: `rake`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add -A && git commit -m "chore: update service worker API pattern for menu routes (#110)"
```

---

### Task 9: Update CLAUDE.md and clean up

**Files:**
- Modify: `CLAUDE.md` — update routes section, architecture section, Hotwire section

**Step 1: Update CLAUDE.md**

Key updates:
- **Routes section**: Document the new menu routes alongside the slimmed groceries routes. Note that `MealPlan` is the backing model.
- **Architecture section**: Update "Shared Groceries" references to mention the Menu/Groceries split. Update `MealPlanChannel` name.
- **Hotwire section**: Update `grocery_sync_controller` and `grocery_ui_controller` descriptions. Add `menu_controller` to the Stimulus controller catalog.
- **PWA section**: Update the SW skip-list description for menu routes.

**Step 2: Verify no stale references**

Run: `grep -r "GroceryList\|grocery_list" app/ test/ config/ --include="*.rb" --include="*.js" --include="*.erb"`

Expected: No results (all renamed to MealPlan/meal_plan). Schema.rb will auto-update.

Run: `grep -r "GroceryListChannel" app/ test/ --include="*.rb" --include="*.js"`

Expected: No results.

**Step 3: Run full test suite**

Run: `rake`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add -A && git commit -m "docs: update CLAUDE.md for Menu/Groceries split (#110)"
```

---

### Task 10: Manual testing and visual polish

**Step 1: Start dev server**

Run: `pkill -f puma; rm -f tmp/pids/server.pid && bin/dev`

**Step 2: Test Menu page**

- Navigate to `/menu`
- Verify recipe checkboxes render and toggle correctly
- Verify Quick Bites section renders
- Verify "Edit Quick Bites" and "Edit Aisle Order" dialogs work
- Verify "Clear All" button resets selections but preserves custom items and checked-off state
- Verify cross-device sync (open two tabs, select a recipe in one, verify checkbox updates in other)

**Step 3: Test Groceries page**

- Navigate to `/groceries`
- Verify shopping list renders from menu selections
- Verify custom items input at bottom of page works (add, remove)
- Verify check-off works
- Verify aisle collapsing/expanding works
- Verify the subtitle links to the Menu page
- Verify cross-device sync (select recipe on menu tab, verify groceries tab updates)

**Step 4: Test print layouts**

- Print Menu page — verify selected recipes appear in 2-column layout, checkboxes hidden
- Print Groceries page — verify shopping list appears in 4-column layout, empty check squares

**Step 5: Test navbar**

- Verify [Ingredients] [Menu] [Groceries] order
- Verify links only appear when logged in with kitchen context

**Step 6: Commit any visual fixes**

```bash
git add -A && git commit -m "fix: visual polish for Menu/Groceries split (#110)"
```

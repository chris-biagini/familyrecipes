# Turbo Stream Morph Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the JSON+JS rendering pipeline on groceries and menu pages with Turbo Stream morphing, making server-rendered ERB the single source of truth.

**Architecture:** Controllers return `turbo_stream.action(:morph)` responses instead of JSON. Cross-device sync uses `turbo_stream_from` ActionCable subscriptions instead of custom `MealPlanChannel`. ~500 lines of JS deleted, `MealPlanSync` and `MealPlanChannel` removed entirely.

**Tech Stack:** Rails 8, Turbo 8 (morph stream action), Stimulus, Solid Cable

**Design doc:** `docs/plans/2026-03-03-turbo-stream-morph-design.md`

---

## Milestone 1: Broadcasting Foundation

### Task 1: Create MealPlanBroadcasting concern

Build the shared broadcasting infrastructure. Both controllers and `RecipeBroadcaster` will use this to send morph updates.

**Files:**
- Create: `app/controllers/concerns/meal_plan_broadcasting.rb`
- Test: `test/controllers/concerns/meal_plan_broadcasting_test.rb`

**Step 1: Write the test**

```ruby
# test/controllers/concerns/meal_plan_broadcasting_test.rb
require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MealPlanBroadcastingTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
    log_in
  end

  test 'broadcast_grocery_morph broadcasts to groceries stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      patch groceries_check_path(kitchen_slug: kitchen_slug),
            params: { item: 'flour', checked: true },
            as: :turbo_stream
    end
  end

  test 'broadcast_menu_morph broadcasts to menu stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :turbo_stream
    end
  end
end
```

Note: these tests will pass after Tasks 1-3 and 1-9 are complete. Create the file now; they'll initially fail.

**Step 2: Implement the concern**

The concern provides three methods:
- `broadcast_grocery_morph` — morphs `#shopping-list` and `#custom-items-list`
- `broadcast_menu_morph` — morphs `#recipe-selector` with availability data
- `broadcast_all_meal_plan_morphs` — calls both

```ruby
# app/controllers/concerns/meal_plan_broadcasting.rb
module MealPlanBroadcasting
  extend ActiveSupport::Concern

  private

  def broadcast_grocery_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    checked_off = plan.state.fetch('checked_off', []).to_set
    custom_items = plan.state.fetch('custom_items', [])

    Turbo::StreamsChannel.broadcast_action_to(
      current_kitchen, 'groceries',
      action: :morph, target: 'shopping-list',
      partial: 'groceries/shopping_list',
      locals: { shopping_list:, checked_off: }
    )
    Turbo::StreamsChannel.broadcast_action_to(
      current_kitchen, 'groceries',
      action: :morph, target: 'custom-items-list',
      partial: 'groceries/custom_items_list_items',
      locals: { custom_items: }
    )
  end

  def broadcast_menu_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    categories = current_kitchen.categories.ordered.includes(:recipes)
    quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
    selected_recipes = plan.state.fetch('selected_recipes', []).to_set
    selected_quick_bites = plan.state.fetch('selected_quick_bites', []).to_set
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call

    Turbo::StreamsChannel.broadcast_action_to(
      current_kitchen, 'menu',
      action: :morph, target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: { categories:, quick_bites_by_subsection:, selected_recipes:,
                selected_quick_bites:, availability: }
    )
  end

  def broadcast_all_meal_plan_morphs
    broadcast_grocery_morph
    broadcast_menu_morph
  end
end
```

Note: The `custom_items_list_items` partial doesn't exist yet — it will be extracted in Task 4. For now, create the concern and we'll circle back.

**Step 3: Commit**

```bash
git add app/controllers/concerns/meal_plan_broadcasting.rb \
        test/controllers/concerns/meal_plan_broadcasting_test.rb
git commit -m "feat: add MealPlanBroadcasting concern for Turbo Stream morphs"
```

---

### Task 2: Refactor MealPlanActions concern

Split `mutate_and_respond` into `mutate_plan` (mutation + optimistic retry, returns plan) and let each controller choose its own response format.

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb`
- Test: existing tests in `test/controllers/groceries_controller_test.rb` and `test/controllers/menu_controller_test.rb` — they still pass since the old methods delegate to the new one during transition.

**Step 1: Add `mutate_plan` alongside existing `mutate_and_respond`**

Keep `mutate_and_respond` working so existing code doesn't break yet. Add `mutate_plan` as the new primitive:

```ruby
# app/controllers/concerns/meal_plan_actions.rb
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def mutate_plan
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end

  def apply_plan(action_type, **action_params)
    mutate_plan do |plan|
      plan.apply_action(action_type, **action_params)
      prune_if_deselect(action_type, action_params)
    end
  end

  # DEPRECATED: used during transition. Remove when all controllers use Turbo Streams.
  def apply_and_respond(action_type, **action_params)
    plan = apply_plan(action_type, **action_params)
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def mutate_and_respond
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { yield plan }
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def prune_if_deselect(action_type, action_params)
    return unless action_type == 'select'
    return if MealPlan.truthy?(action_params[:selected])

    MealPlan.prune_stale_items(kitchen: current_kitchen)
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end
```

**Step 2: Run tests**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb
ruby -Itest test/controllers/menu_controller_test.rb
```

Expected: all pass (no behavior changed).

**Step 3: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb
git commit -m "refactor: add mutate_plan/apply_plan to MealPlanActions for Turbo Stream transition"
```

---

## Milestone 2: Groceries Page Conversion

### Task 3: Convert GroceriesController to Turbo Stream morphs

Change `check`, `update_custom_items`, and `update_aisle_order` to return Turbo Stream morph responses and broadcast. Keep `show` as-is (it already server-renders).

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Update tests first**

The tests currently assert JSON responses and `MealPlanChannel` broadcasts. Change them to assert Turbo Stream responses and `[kitchen, 'groceries']` broadcasts.

Key changes to test file:
- Add `include Turbo::Broadcastable::TestHelper`
- Change `as: :json` to `as: :turbo_stream` for mutation requests
- Change `assert_broadcasts(MealPlanChannel.broadcasting_for(...))` to `assert_turbo_stream_broadcasts [kitchen, 'groceries']`
- Change `assert_response :success` + JSON parsing to `assert_response :success` (Turbo Stream 200)
- Keep JSON for `aisle_order_content` (editor dialog endpoint, unchanged)
- Keep JSON error responses for validation failures (custom item too long, aisle order too many) — these stay JSON since the editor dialog JS expects it

**Step 2: Update controller**

```ruby
class GroceriesController < ApplicationController
  include MealPlanActions
  include MealPlanBroadcasting

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    @checked_off = plan.state.fetch('checked_off', []).to_set
    @custom_items = plan.state.fetch('custom_items', [])
  end

  def check
    apply_plan('check', item: params[:item], checked: params[:checked])
    broadcast_grocery_morph
    broadcast_menu_morph  # availability dots change
    render_grocery_morph
  end

  def update_custom_items
    item = params[:item].to_s
    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    apply_plan('custom_items', item:, action: params[:action_type])
    broadcast_grocery_morph
    render_grocery_morph
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_aisle_order
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    current_kitchen.save!
    broadcast_grocery_morph
    render_grocery_morph
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def render_grocery_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    checked_off = plan.state.fetch('checked_off', []).to_set

    render turbo_stream: turbo_stream.action(
      :morph, 'shopping-list',
      partial: 'groceries/shopping_list',
      locals: { shopping_list:, checked_off: }
    )
  end

  # validate_aisle_order and build_aisle_order_text stay the same
end
```

**Step 3: Run tests**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb
```

**Step 4: Commit**

```bash
git add app/controllers/groceries_controller.rb test/controllers/groceries_controller_test.rb
git commit -m "feat: convert GroceriesController to Turbo Stream morph responses"
```

---

### Task 4: Update groceries views for Turbo Stream subscriptions

Add `turbo_stream_from`, remove `data-state-url`, extract `custom_items_list_items` partial.

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/groceries/_custom_items.html.erb`
- Create: `app/views/groceries/_custom_items_list_items.html.erb`
- Modify: `test/controllers/groceries_controller_test.rb` (update data attribute assertions)

**Step 1: Update show.html.erb**

```erb
<%# Add turbo_stream_from before the groceries-app div %>
<%= turbo_stream_from current_kitchen, "groceries" %>

<%# Remove data-state-url from div, remove grocery-sync controller %>
<div id="groceries-app"
     data-controller="wake-lock grocery-ui"
     data-kitchen-slug="<%= current_kitchen.slug %>"
     data-check-url="<%= groceries_check_path %>"
     data-custom-items-url="<%= groceries_custom_items_path %>">
```

**Step 2: Extract custom items list partial**

The broadcast needs to morph just the `<ul>` contents. Extract the `<li>` elements from `_custom_items.html.erb` into `_custom_items_list_items.html.erb`:

```erb
<%# app/views/groceries/_custom_items_list_items.html.erb %>
<%# locals: (custom_items:) %>
<% custom_items.each do |item| %>
  <li>
    <span><%= item %></span>
    <button class="custom-item-remove" type="button" aria-label="Remove <%= item %>" data-item="<%= item %>">&times;</button>
  </li>
<% end %>
```

Update `_custom_items.html.erb` to render this partial:

```erb
<%# app/views/groceries/_custom_items.html.erb %>
<%# locals: (custom_items:) %>
<div id="custom-items-section">
  <h3>Custom Items</h3>
  <div class="custom-input-row">
    <input type="text" id="custom-input" placeholder="Add item..." maxlength="100">
    <button type="button" id="custom-add" class="btn">Add</button>
  </div>
  <ul id="custom-items-list">
    <%= render 'groceries/custom_items_list_items', custom_items: custom_items %>
  </ul>
</div>
```

**Step 3: Update test assertions**

Remove `assert_select '#groceries-app[data-state-url]'`. Remove `assert_select '[data-controller~="grocery-sync"]'`.

**Step 4: Run tests**

```bash
ruby -Itest test/controllers/groceries_controller_test.rb
```

**Step 5: Commit**

```bash
git add app/views/groceries/
git commit -m "feat: add turbo_stream_from to groceries, extract custom items partial"
```

---

### Task 5: Rewrite grocery_ui_controller.js

Delete all rendering code. Keep: optimistic checkbox toggle, aisle collapse persistence, custom item input binding, offline queue.

**Files:**
- Rewrite: `app/javascript/controllers/grocery_ui_controller.js`

**Step 1: Write the slim controller**

The new controller is ~80-100 lines. Key behaviors:

1. **Optimistic checkbox toggle**: On checkbox change, immediately toggle `checked`, update aisle count span, then send action to server. If fetch fails, queue in localStorage.
2. **Aisle collapse**: Save/restore `<details>` open state. Listen to `turbo:before-stream-render` to preserve collapse state across morphs (morph should handle this, but belt-and-suspenders).
3. **Custom item input**: Bind Enter key and Add button, send action to server.
4. **Offline queue**: On fetch failure, push `{ url, params }` to localStorage. On `online` event, flush queue.

```javascript
import { Controller } from "@hotwired/stimulus"
import ListenerManager from "utilities/listener_manager"
import { getCsrfToken } from "utilities/editor_utils"

export default class extends Controller {
  connect() {
    this.aisleCollapseKey = `grocery-aisles-${this.element.dataset.kitchenSlug}`
    this.pendingKey = `grocery-pending-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()

    this.bindShoppingListEvents()
    this.bindCustomItemInput()
    this.restoreAisleCollapse()

    this.listeners.add(window, "online", () => this.flushPending())
    this.listeners.add(document, "turbo:before-stream-render", (e) => this.preserveAisleState(e))

    this.flushPending()
  }

  disconnect() {
    this.listeners.teardown()
  }

  // --- Shopping list check-off ---

  bindShoppingListEvents() {
    const shoppingList = document.getElementById("shopping-list")

    this.listeners.add(shoppingList, "change", (e) => {
      const cb = e.target
      if (!cb.matches('.check-off input[type="checkbox"]')) return

      const name = cb.dataset.item
      if (!name) return

      // Optimistic: update aisle count immediately
      this.updateAisleCount(cb.closest("details.aisle"))

      this.sendAction(this.element.dataset.checkUrl, {
        item: name,
        checked: cb.checked
      })
    })

    this.listeners.add(shoppingList, "toggle", (e) => {
      if (e.target.matches("details.aisle")) this.saveAisleCollapse()
    }, true)
  }

  updateAisleCount(details) {
    if (!details) return
    let total = 0, checked = 0
    details.querySelectorAll("li[data-item]").forEach(li => {
      total++
      const cb = li.querySelector('input[type="checkbox"]')
      if (cb && cb.checked) checked++
    })
    const countSpan = details.querySelector(".aisle-count")
    if (!countSpan) return
    const remaining = total - checked
    if (remaining === 0 && total > 0) {
      countSpan.textContent = "\u2713"
      countSpan.classList.add("aisle-done")
    } else {
      countSpan.textContent = `(${remaining})`
      countSpan.classList.remove("aisle-done")
    }
  }

  // --- Custom items ---

  bindCustomItemInput() { /* same as current — unchanged */ }

  // --- Offline queue ---

  sendAction(url, params) {
    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": getCsrfToken() || ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) throw new Error("action failed")
        return response.text()
      })
      .then(html => {
        // Turbo processes the stream response automatically when using
        // requestSubmission, but since we use raw fetch, process manually
        Turbo.renderStreamMessage(html)
      })
      .catch(err => {
        if (!err.message.includes("action failed")) {
          this.queuePending(url, params)
        }
      })
  }

  queuePending(url, params) { /* push to localStorage */ }
  flushPending() { /* read from localStorage, send each */ }

  // --- Aisle collapse ---

  saveAisleCollapse() { /* same as current */ }
  restoreAisleCollapse() { /* read from localStorage, set details.open */ }
  preserveAisleState(event) {
    // Before morph: save current state, after morph: restore
    const collapsed = this.readAisleCollapse()
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      this.applyAisleCollapse(collapsed)
    }
  }
}
```

Note on `Turbo.renderStreamMessage(html)`: When using raw `fetch` instead of Turbo form submission, the response stream isn't auto-processed. We call `Turbo.renderStreamMessage()` to apply the morph. This is a documented Turbo API.

**Step 2: Run the full test suite (Playwright tests if any, otherwise just Minitest)**

```bash
rake test
```

**Step 3: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: rewrite grocery_ui_controller — delete rendering, keep behavior"
```

---

### Task 6: Delete grocery_sync_controller.js

Now that `grocery_ui_controller.js` handles its own fetch and `turbo_stream_from` handles ActionCable subscriptions, `grocery_sync_controller` is dead code.

**Files:**
- Delete: `app/javascript/controllers/grocery_sync_controller.js`
- Verify: `show.html.erb` no longer references `grocery-sync` (done in Task 4)

**Step 1: Delete the file**

```bash
rm app/javascript/controllers/grocery_sync_controller.js
```

**Step 2: Run tests**

```bash
rake test
```

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: delete grocery_sync_controller — replaced by turbo_stream_from"
```

---

### Task 7: Remove GroceriesController#state and route

The JSON polling endpoint is no longer used.

**Files:**
- Modify: `app/controllers/groceries_controller.rb` (remove `state` method)
- Modify: `config/routes.rb` (remove `groceries/state` route)
- Modify: `test/controllers/groceries_controller_test.rb` (remove state tests)
- Modify: `app/views/pwa/service_worker.js.erb` (remove `state` from API_PATTERN)

**Step 1: Remove from routes**

Delete the line: `get 'groceries/state', to: 'groceries#state', as: :groceries_state`

**Step 2: Remove from controller**

Delete the `state` method entirely.

**Step 3: Remove from tests**

Delete tests: 'state returns version and empty state for new list', 'state includes shopping_list when recipes selected', 'state includes selected_recipes in response', 'state includes all state keys', and 'state requires membership'. Also remove any test that calls `groceries_state_path`.

Note: the `custom_items removes item` test currently verifies removal by calling `groceries_state_path`. Rewrite it to check MealPlan state directly:

```ruby
test 'custom_items removes item' do
  log_in
  patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
        params: { item: 'birthday candles', action_type: 'add' },
        as: :turbo_stream

  patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
        params: { item: 'birthday candles', action_type: 'remove' },
        as: :turbo_stream

  plan = MealPlan.for_kitchen(@kitchen)
  assert_not_includes plan.state.fetch('custom_items', []), 'birthday candles'
end
```

**Step 4: Update service worker**

In `app/views/pwa/service_worker.js.erb`, remove `state|` from the groceries part of `API_PATTERN`.

**Step 5: Run tests**

```bash
rake test
```

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove GroceriesController#state — replaced by Turbo Stream morphs"
```

---

## Milestone 3: Menu Page Conversion

### Task 8: Add availability dots to server-rendered menu partial

Currently availability dots are rendered by JS from JSON. Move to ERB.

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb`
- Modify: `app/controllers/menu_controller.rb` (pass availability to partial in `show`)
- Modify: `test/controllers/menu_controller_test.rb` (test dot rendering)

**Step 1: Write test for availability dots**

```ruby
test 'show renders availability dots for recipes' do
  log_in
  create_focaccia_recipe
  setup_ingredient_catalog  # helper to create Flour + Salt catalog entries

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Flour', checked: true)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select '.availability-dot[data-slug="focaccia"]'
end
```

**Step 2: Update MenuController#show**

```ruby
def show
  @categories = recipe_selector_categories
  @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
  plan = MealPlan.for_kitchen(current_kitchen)
  @selected_recipes = plan.state.fetch('selected_recipes', []).to_set
  @selected_quick_bites = plan.state.fetch('selected_quick_bites', []).to_set
  checked_off = plan.state.fetch('checked_off', [])
  @availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call
end
```

**Step 3: Update _recipe_selector.html.erb**

Add `availability: {}` to locals declaration. After each checkbox+label, render a dot if availability data exists:

```erb
<%# locals: (categories:, quick_bites_by_subsection:, selected_recipes: Set.new, selected_quick_bites: Set.new, availability: {}) %>
```

For each recipe `<li>`:

```erb
<li>
  <input type="checkbox" ...>
  <% if (info = availability[recipe.slug]) %>
    <span class="availability-dot"
          data-slug="<%= recipe.slug %>"
          data-missing="<%= info[:missing] > 2 ? '3+' : info[:missing] %>"
          aria-label="<%= info[:missing].zero? ? 'All ingredients on hand' : "Missing #{info[:missing]}: #{info[:missing_names].join(', ')}" %>">
    </span>
  <% end %>
  <label ...>
</li>
```

Similar for quick bites, with the `3+`/`0` simplified logic.

**Step 4: Run tests**

```bash
ruby -Itest test/controllers/menu_controller_test.rb
```

**Step 5: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb app/controllers/menu_controller.rb \
        test/controllers/menu_controller_test.rb
git commit -m "feat: server-render availability dots in menu partial"
```

---

### Task 9: Convert MenuController to Turbo Stream morphs

Same pattern as Task 3 for groceries.

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `test/controllers/menu_controller_test.rb`

**Step 1: Update tests**

- Change mutation requests from `as: :json` to `as: :turbo_stream`
- Change `MealPlanChannel` broadcast assertions to `assert_turbo_stream_broadcasts [@kitchen, 'menu']`
- Remove version JSON assertions (no longer returns JSON)
- Keep `update_quick_bites` broadcast assertions (it already uses Turbo Streams for `menu_content`)

**Step 2: Update controller**

```ruby
class MenuController < ApplicationController
  include MealPlanActions
  include MealPlanBroadcasting

  def select
    apply_plan('select', type: params[:type], slug: params[:slug], selected: params[:selected])
    broadcast_all_meal_plan_morphs
    render_menu_morph
  end

  def select_all
    mutate_plan { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
    broadcast_all_meal_plan_morphs
    render_menu_morph
  end

  def clear
    mutate_plan(&:clear_selections!)
    broadcast_all_meal_plan_morphs
    render_menu_morph
  end

  def update_quick_bites
    # This already broadcasts to menu_content and notifies groceries
    # Update to use new broadcasting
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)
    MealPlan.prune_stale_items(kitchen: current_kitchen)
    RecipeBroadcaster.broadcast_recipe_selector(kitchen: current_kitchen, stream: 'menu_content')
    broadcast_grocery_morph
    render json: { status: 'ok' }
  end

  private

  def render_menu_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    categories = recipe_selector_categories
    quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
    selected_recipes = plan.state.fetch('selected_recipes', []).to_set
    selected_quick_bites = plan.state.fetch('selected_quick_bites', []).to_set
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call

    render turbo_stream: turbo_stream.action(
      :morph, 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: { categories:, quick_bites_by_subsection:, selected_recipes:,
                selected_quick_bites:, availability: }
    )
  end
end
```

**Step 3: Run tests**

```bash
ruby -Itest test/controllers/menu_controller_test.rb
```

**Step 4: Commit**

```bash
git add app/controllers/menu_controller.rb test/controllers/menu_controller_test.rb
git commit -m "feat: convert MenuController to Turbo Stream morph responses"
```

---

### Task 10: Update menu views and JS

Add `turbo_stream_from` for menu state. Slim down `menu_controller.js`.

**Files:**
- Modify: `app/views/menu/show.html.erb`
- Rewrite: `app/javascript/controllers/menu_controller.js`

**Step 1: Update show.html.erb**

Add state sync stream, remove `data-state-url`:

```erb
<%= turbo_stream_from current_kitchen, "menu_content" %>
<%= turbo_stream_from current_kitchen, "recipes" %>
<%= turbo_stream_from current_kitchen, "menu" %>

<div id="menu-app"
     data-controller="menu"
     data-kitchen-slug="<%= current_kitchen.slug %>"
     data-select-url="<%= menu_select_path %>"
     data-select-all-url="<%= menu_select_all_path %>"
     data-clear-url="<%= menu_clear_path %>">
```

**Step 2: Rewrite menu_controller.js**

Delete: `syncCheckboxes`, `syncAvailability`, all `MealPlanSync` imports and wiring.

Keep: optimistic checkbox toggle, popover behavior, select-all/clear button handlers, `sendAction` with offline queue (same pattern as grocery_ui_controller).

The controller sends actions via `fetch` with `Accept: text/vnd.turbo-stream.html` and calls `Turbo.renderStreamMessage()` to apply the morph response.

**Step 3: Run tests**

```bash
rake test
```

**Step 4: Commit**

```bash
git add app/views/menu/show.html.erb app/javascript/controllers/menu_controller.js
git commit -m "feat: update menu views and JS for Turbo Stream morphs"
```

---

### Task 11: Remove MenuController#state and route

**Files:**
- Modify: `app/controllers/menu_controller.rb` (remove `state` method)
- Modify: `config/routes.rb` (remove `menu/state` route)
- Modify: `test/controllers/menu_controller_test.rb` (remove state tests)
- Modify: `app/views/pwa/service_worker.js.erb` (remove `state` from menu API_PATTERN)

**Step 1: Remove route, controller method, and tests**

Same pattern as Task 7 for groceries.

**Step 2: Run tests**

```bash
rake test
```

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove MenuController#state — replaced by Turbo Stream morphs"
```

---

## Milestone 4: Cleanup

### Task 12: Update RecipeBroadcaster

Replace `MealPlanChannel.broadcast_content_changed` with direct grocery morph broadcasting.

**Files:**
- Modify: `app/services/recipe_broadcaster.rb`
- Modify: `test/services/recipe_broadcaster_test.rb`

**Step 1: Replace the MealPlanChannel call**

In `RecipeBroadcaster#broadcast`, change:

```ruby
# Before
MealPlanChannel.broadcast_content_changed(kitchen)

# After — broadcast grocery morph directly
broadcast_grocery_morph_for(kitchen)
```

Add a private method that mirrors `MealPlanBroadcasting#broadcast_grocery_morph` but takes `kitchen` as a parameter (since RecipeBroadcaster isn't a controller and doesn't have `current_kitchen`):

```ruby
def broadcast_grocery_morph_for(kitchen)
  plan = ActsAsTenant.with_tenant(kitchen) { MealPlan.for_kitchen(kitchen) }
  shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
  checked_off = plan.state.fetch('checked_off', []).to_set

  Turbo::StreamsChannel.broadcast_action_to(
    kitchen, 'groceries',
    action: :morph, target: 'shopping-list',
    partial: 'groceries/shopping_list',
    locals: { shopping_list:, checked_off: }
  )
end
```

Similarly for `MenuController#update_quick_bites` — it currently calls both `RecipeBroadcaster.broadcast_recipe_selector` and `MealPlanChannel.broadcast_content_changed`. Replace the latter with `broadcast_grocery_morph`.

**Step 2: Update tests**

Remove assertions on `MealPlanChannel` broadcasts. Add assertions on `[kitchen, 'groceries']` Turbo Stream broadcasts.

**Step 3: Run tests**

```bash
ruby -Itest test/services/recipe_broadcaster_test.rb
rake test
```

**Step 4: Commit**

```bash
git add app/services/recipe_broadcaster.rb test/services/recipe_broadcaster_test.rb
git commit -m "feat: RecipeBroadcaster sends grocery morph instead of MealPlanChannel"
```

---

### Task 13: Delete MealPlanChannel and MealPlanSync

All references to both should now be gone.

**Files:**
- Delete: `app/channels/meal_plan_channel.rb`
- Delete: `test/channels/meal_plan_channel_test.rb`
- Delete: `app/javascript/utilities/meal_plan_sync.js`
- Modify: `app/controllers/concerns/meal_plan_actions.rb` (remove deprecated methods and MealPlanChannel references)
- Modify: `config/importmap.rb` (if meal_plan_sync was pinned — verify)

**Step 1: Delete files**

```bash
rm app/channels/meal_plan_channel.rb
rm test/channels/meal_plan_channel_test.rb
rm app/javascript/utilities/meal_plan_sync.js
```

**Step 2: Clean up MealPlanActions**

Remove `apply_and_respond` and `mutate_and_respond` (the deprecated JSON methods). Remove `MealPlanChannel` references. The concern should now only contain: `mutate_plan`, `apply_plan`, `prune_if_deselect`, `handle_stale_record`.

**Step 3: Grep for any remaining references**

```bash
grep -r "MealPlanChannel" app/ test/ config/
grep -r "MealPlanSync\|meal_plan_sync" app/ test/ config/
grep -r "broadcast_version\|broadcast_content_changed" app/ test/
```

Fix any stragglers.

**Step 4: Run tests**

```bash
rake test
```

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete MealPlanChannel and MealPlanSync — fully replaced by Turbo Streams"
```

---

### Task 14: Extract shared offline queue utility

Both `grocery_ui_controller` and `menu_controller` need the same offline queue pattern. Extract to a shared utility.

**Files:**
- Create: `app/javascript/utilities/offline_queue.js`
- Modify: `app/javascript/controllers/grocery_ui_controller.js` (import utility)
- Modify: `app/javascript/controllers/menu_controller.js` (import utility)
- Modify: `config/importmap.rb` (pin new utility if needed — verify auto-pin)

**Step 1: Create the utility**

```javascript
// app/javascript/utilities/offline_queue.js
import { getCsrfToken } from "utilities/editor_utils"

export default class OfflineQueue {
  constructor(storageKey) {
    this.storageKey = storageKey
  }

  sendAction(url, params, method = "PATCH") {
    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": getCsrfToken() || ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) {
          const err = new Error("action failed")
          err.status = response.status
          throw err
        }
        return response.text()
      })
      .then(html => {
        if (html.includes("<turbo-stream")) Turbo.renderStreamMessage(html)
      })
      .catch(err => {
        if (!err.status) this.queue(url, params, method)
      })
  }

  queue(url, params, method) {
    try {
      const pending = this.load()
      pending.push({ url, params, method })
      localStorage.setItem(this.storageKey, JSON.stringify(pending))
    } catch { /* localStorage full */ }
  }

  flush() {
    const pending = this.load()
    if (pending.length === 0) return

    this.clear()
    pending.forEach(entry => this.sendAction(entry.url, entry.params, entry.method))
  }

  load() {
    try {
      const raw = localStorage.getItem(this.storageKey)
      return raw ? JSON.parse(raw) : []
    } catch { return [] }
  }

  clear() {
    try { localStorage.removeItem(this.storageKey) } catch { /* */ }
  }
}
```

**Step 2: Import in both controllers**

```javascript
import OfflineQueue from "utilities/offline_queue"

// In connect():
this.queue = new OfflineQueue(`grocery-pending-${slug}`)
this.listeners.add(window, "online", () => this.queue.flush())
this.queue.flush()

// Replace inline sendAction with:
this.queue.sendAction(url, params)
```

**Step 3: Run tests**

```bash
rake test
```

**Step 4: Commit**

```bash
git add app/javascript/utilities/offline_queue.js \
        app/javascript/controllers/grocery_ui_controller.js \
        app/javascript/controllers/menu_controller.js
git commit -m "feat: extract shared OfflineQueue utility for grocery and menu controllers"
```

---

### Task 15: Delete GroceriesHelper#aisle_count_tag

The helper we added at the start of this session is now unnecessary — the partial is the only rendering path and it already handles this via `aisle_count_tag`. Wait — actually, `aisle_count_tag` IS used by the partial. The duplication was the JS `updateAisleCounts`. Now that JS rendering is gone, the Ruby helper is the single source of truth.

**Keep `aisle_count_tag`** — it's correct and used. No action needed.

But DO delete `formatAmounts` and `formatNumber` from the JS (already done in Task 5 as part of the rewrite).

---

### Task 16: Final sweep

**Files:**
- All files — RuboCop, tests, manual verification

**Step 1: Run full test suite**

```bash
rake test
```

**Step 2: Run RuboCop**

```bash
bundle exec rubocop
```

**Step 3: Run html_safe lint**

```bash
rake lint:html_safe
```

If line numbers shifted in modified views, update `config/html_safe_allowlist.yml`.

**Step 4: Verify no stale references**

```bash
grep -r "grocery.sync\|grocery_sync" app/ test/
grep -r "meal_plan_sync\|MealPlanSync" app/ test/ config/
grep -r "MealPlanChannel" app/ test/ config/
grep -r "data-state-url" app/
grep -r "groceries_state\|menu_state" app/ config/ test/
```

All should return nothing (except possibly comments in design docs).

**Step 5: Verify service worker API_PATTERN**

Confirm `state` is removed from both groceries and menu sections.

**Step 6: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final cleanup — lint, stale references, service worker"
```

---

## Cross-Broadcast Matrix

For reference during implementation — which mutations broadcast to which streams:

| Action | Groceries stream | Menu stream |
|--------|:---:|:---:|
| `groceries#check` | yes | yes (availability) |
| `groceries#update_custom_items` | yes | no |
| `groceries#update_aisle_order` | yes | no |
| `menu#select` | yes | yes |
| `menu#select_all` | yes | yes |
| `menu#clear` | yes | yes |
| `menu#update_quick_bites` | yes (via broadcast) | yes (existing RecipeBroadcaster) |
| Recipe CRUD | yes (via RecipeBroadcaster) | yes (existing RecipeBroadcaster) |

## Files Deleted (total)

- `app/javascript/utilities/meal_plan_sync.js` (221 lines)
- `app/javascript/controllers/grocery_sync_controller.js` (46 lines)
- `app/channels/meal_plan_channel.rb` (36 lines)
- `test/channels/meal_plan_channel_test.rb`

## Files Created

- `app/controllers/concerns/meal_plan_broadcasting.rb`
- `test/controllers/concerns/meal_plan_broadcasting_test.rb`
- `app/javascript/utilities/offline_queue.js` (~50 lines)
- `app/views/groceries/_custom_items_list_items.html.erb`

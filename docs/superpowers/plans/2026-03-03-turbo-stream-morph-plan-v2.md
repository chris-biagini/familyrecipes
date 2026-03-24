# Turbo Stream Morph Refactor — Implementation Plan (v2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the JSON+JS rendering pipeline on groceries and menu pages with Turbo Stream morphing, making server-rendered ERB the single source of truth.

**Architecture:** Controllers return inline `turbo_stream.action(:morph)` responses for the acting client and broadcast morphs to all other clients via `MealPlanBroadcaster`. `MealPlanChannel`, `MealPlanSync`, and all client-side rendering code are deleted. A shared `turbo_fetch.js` utility handles fetch-with-retry for cellular resilience.

**Tech Stack:** Rails 8, Turbo 8 (morph stream action), Stimulus, Solid Cable

**Design doc:** `docs/plans/2026-03-03-turbo-stream-morph-design-v2.md`

---

## Milestone 1: Server-Side Foundation

### Task 1: Create MealPlanBroadcaster service

Build the standalone broadcasting service. Controllers and `RecipeBroadcaster` both call this to send morph updates.

**Files:**
- Create: `app/services/meal_plan_broadcaster.rb`
- Create: `test/services/meal_plan_broadcaster_test.rb`

**Step 1: Write the test**

```ruby
# test/services/meal_plan_broadcaster_test.rb
require 'test_helper'
require 'turbo/broadcastable/test_helper'

class MealPlanBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
  end

  test 'broadcast_grocery_morph broadcasts to groceries stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      MealPlanBroadcaster.broadcast_grocery_morph(@kitchen)
    end
  end

  test 'broadcast_menu_morph broadcasts to menu stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      MealPlanBroadcaster.broadcast_menu_morph(@kitchen)
    end
  end

  test 'broadcast_all broadcasts to both streams' do
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
        MealPlanBroadcaster.broadcast_all(@kitchen)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/meal_plan_broadcaster_test.rb`
Expected: FAIL — `NameError: uninitialized constant MealPlanBroadcaster`

**Step 3: Implement the service**

```ruby
# app/services/meal_plan_broadcaster.rb

# Broadcasts Turbo Stream morphs for meal plan state changes. Standalone service
# with class methods so both controllers and RecipeBroadcaster can call it.
# Builds full partial locals (shopping list, availability, selections) and
# broadcasts action: :morph to the groceries and menu streams.
#
# - GroceriesController / MenuController: call after mutations
# - RecipeBroadcaster: calls when recipe/quick-bite content changes
# - Turbo::StreamsChannel: transport layer
class MealPlanBroadcaster
  def self.broadcast_grocery_morph(kitchen)
    new(kitchen).broadcast_grocery_morph
  end

  def self.broadcast_menu_morph(kitchen)
    new(kitchen).broadcast_menu_morph
  end

  def self.broadcast_all(kitchen)
    broadcaster = new(kitchen)
    broadcaster.broadcast_grocery_morph
    broadcaster.broadcast_menu_morph
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def broadcast_grocery_morph
    plan = load_plan
    shopping_list = ShoppingListBuilder.new(kitchen:, meal_plan: plan).build
    checked_off = plan.checked_off_set

    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'groceries',
      action: :morph, target: 'shopping-list',
      partial: 'groceries/shopping_list',
      locals: { shopping_list:, checked_off: }
    )
    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'groceries',
      action: :morph, target: 'custom-items-section',
      partial: 'groceries/custom_items',
      locals: { custom_items: plan.custom_items_list }
    )
  end

  def broadcast_menu_morph
    plan = load_plan
    categories = kitchen.categories.ordered.includes(:recipes)
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen:, checked_off:).call

    Turbo::StreamsChannel.broadcast_action_to(
      kitchen, 'menu',
      action: :morph, target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: {
        categories:,
        quick_bites_by_subsection: kitchen.quick_bites_by_subsection,
        selected_recipes: plan.selected_recipes_set,
        selected_quick_bites: plan.selected_quick_bites_set,
        availability:
      }
    )
  end

  private

  attr_reader :kitchen

  def load_plan
    ActsAsTenant.with_tenant(kitchen) { MealPlan.for_kitchen(kitchen) }
  end
end
```

Note: This references helper methods on `MealPlan` (`checked_off_set`, `custom_items_list`, `selected_recipes_set`, `selected_quick_bites_set`) that don't exist yet. Add them:

```ruby
# In app/models/meal_plan.rb — add these convenience readers:

def checked_off_set
  state.fetch('checked_off', []).to_set
end

def custom_items_list
  state.fetch('custom_items', [])
end

def selected_recipes_set
  state.fetch('selected_recipes', []).to_set
end

def selected_quick_bites_set
  state.fetch('selected_quick_bites', []).to_set
end
```

Read `app/models/meal_plan.rb` first to find the right location for these methods. Place them in the public section, before the `apply_action` method.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/meal_plan_broadcaster_test.rb`
Expected: PASS (3 tests, 3 assertions)

**Step 5: Run full test suite**

Run: `rake test`
Expected: all pass — new methods are additive, nothing uses them yet.

**Step 6: Commit**

```bash
git add app/services/meal_plan_broadcaster.rb \
        test/services/meal_plan_broadcaster_test.rb \
        app/models/meal_plan.rb
git commit -m "feat: add MealPlanBroadcaster service for Turbo Stream morphs"
```

---

### Task 2: Rewrite MealPlanActions concern

Clean cut-over: replace `apply_and_respond` / `mutate_and_respond` with `mutate_plan` / `apply_plan`. Both controllers switch at the same time.

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb`

**Step 1: Rewrite the concern**

Read the current file at `app/controllers/concerns/meal_plan_actions.rb` first.

```ruby
# app/controllers/concerns/meal_plan_actions.rb

# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry and a common StaleObjectError handler.
# Used by MenuController and GroceriesController.
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

**Step 2: Update GroceriesController**

Read `app/controllers/groceries_controller.rb`. Replace all `apply_and_respond` and `mutate_and_respond` calls, and add `MealPlanBroadcaster` calls + Turbo Stream responses. Remove the `state` action. Add a private `render_grocery_morph` method.

```ruby
# app/controllers/groceries_controller.rb

# Shopping list page — member-only. Server-renders the full shopping list on
# page load via ShoppingListBuilder. Mutations return inline Turbo Stream morph
# responses for the acting client and broadcast morphs to all other connected
# clients via MealPlanBroadcaster.
class GroceriesController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    @checked_off = plan.checked_off_set
    @custom_items = plan.custom_items_list
  end

  def check
    apply_plan('check', item: params[:item], checked: params[:checked])
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_grocery_morph
  end

  def update_custom_items
    item = params[:item].to_s
    max = MealPlan::MAX_CUSTOM_ITEM_LENGTH
    if item.size > max
      return render json: { errors: ["Custom item name is too long (max #{max} characters)"] },
                    status: :unprocessable_content
    end

    apply_plan('custom_items', item: item, action: params[:action_type])
    MealPlanBroadcaster.broadcast_grocery_morph(current_kitchen)
    render_grocery_morph
  end

  def update_aisle_order
    current_kitchen.aisle_order = params[:aisle_order].to_s
    current_kitchen.normalize_aisle_order!

    errors = validate_aisle_order
    return render json: { errors: }, status: :unprocessable_content if errors.any?

    current_kitchen.save!
    MealPlanBroadcaster.broadcast_grocery_morph(current_kitchen)
    render_grocery_morph
  end

  def aisle_order_content
    render json: { aisle_order: build_aisle_order_text }
  end

  private

  def render_grocery_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
    checked_off = plan.checked_off_set

    render turbo_stream: [
      turbo_stream.action(:morph, 'shopping-list',
                          partial: 'groceries/shopping_list',
                          locals: { shopping_list:, checked_off: }),
      turbo_stream.action(:morph, 'custom-items-section',
                          partial: 'groceries/custom_items',
                          locals: { custom_items: plan.custom_items_list })
    ]
  end

  def validate_aisle_order
    lines = current_kitchen.parsed_aisle_order
    too_many = lines.size > Kitchen::MAX_AISLES ? ["Too many aisles (max #{Kitchen::MAX_AISLES})"] : []

    max = Kitchen::MAX_AISLE_NAME_LENGTH
    too_long = lines.filter_map do |line|
      "Aisle name '#{line.truncate(20)}' is too long (max #{max} characters)" if line.size > max
    end

    too_many + too_long
  end

  def build_aisle_order_text
    current_kitchen.all_aisles.join("\n")
  end
end
```

**Step 3: Update MenuController**

Read `app/controllers/menu_controller.rb`. Replace all `apply_and_respond` and `mutate_and_respond` calls. Remove the `state` action. Add availability computation to `show`. Add a private `render_menu_morph` method.

```ruby
# app/controllers/menu_controller.rb

# Meal planning page — member-only. Displays a recipe selector with checkboxes.
# Manages MealPlan state (select/select_all/clear) and broadcasts Turbo Stream
# morphs to all connected clients via MealPlanBroadcaster. Availability dots
# are server-rendered in the recipe selector partial.
class MenuController < ApplicationController
  include MealPlanActions

  before_action :require_membership
  before_action :prevent_html_caching, only: :show

  def show
    plan = MealPlan.for_kitchen(current_kitchen)
    @categories = recipe_selector_categories
    @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
    @selected_recipes = plan.selected_recipes_set
    @selected_quick_bites = plan.selected_quick_bites_set
    checked_off = plan.state.fetch('checked_off', [])
    @availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call
  end

  def select
    apply_plan('select', type: params[:type], slug: params[:slug], selected: params[:selected])
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def select_all
    mutate_plan { |plan| plan.select_all!(all_recipe_slugs, all_quick_bite_slugs) }
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def clear
    mutate_plan(&:clear_selections!)
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render_menu_morph
  end

  def quick_bites_content
    render json: { content: current_kitchen.quick_bites_content || '' }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_content if content.blank?

    current_kitchen.update!(quick_bites_content: content)
    MealPlan.prune_stale_items(kitchen: current_kitchen)
    MealPlanBroadcaster.broadcast_all(current_kitchen)
    render json: { status: 'ok' }
  end

  private

  def render_menu_morph
    plan = MealPlan.for_kitchen(current_kitchen)
    checked_off = plan.state.fetch('checked_off', [])
    availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off:).call

    render turbo_stream: turbo_stream.action(
      :morph, 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: {
        categories: recipe_selector_categories,
        quick_bites_by_subsection: current_kitchen.quick_bites_by_subsection,
        selected_recipes: plan.selected_recipes_set,
        selected_quick_bites: plan.selected_quick_bites_set,
        availability:
      }
    )
  end

  def recipe_selector_categories
    current_kitchen.categories.ordered.includes(:recipes)
  end

  def all_recipe_slugs
    current_kitchen.recipes.pluck(:slug)
  end

  def all_quick_bite_slugs
    current_kitchen.parsed_quick_bites.map(&:id)
  end
end
```

**Step 4: Do NOT run tests yet** — tests still assert JSON responses and MealPlanChannel broadcasts. Those are updated in Task 3.

**Step 5: Commit (WIP)**

```bash
git add app/controllers/concerns/meal_plan_actions.rb \
        app/controllers/groceries_controller.rb \
        app/controllers/menu_controller.rb
git commit -m "feat: convert controllers to Turbo Stream morph responses

WIP — tests updated in next commit."
```

---

### Task 3: Update controller tests

Both test files need to change: `as: :json` → `as: :turbo_stream`, `MealPlanChannel` broadcast assertions → `Turbo::StreamsChannel` broadcast assertions, JSON response assertions → Turbo Stream or model-state assertions. Remove all `state` endpoint tests. Remove `state` routes.

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `test/controllers/menu_controller_test.rb`
- Modify: `config/routes.rb`

**Step 1: Update groceries test**

Read `test/controllers/groceries_controller_test.rb`.

Key changes:
- Add `include Turbo::Broadcastable::TestHelper` and `require 'turbo/broadcastable/test_helper'`
- DELETE tests: `state returns version and empty state for new list`, `state includes shopping_list when recipes selected`, `state includes selected_recipes in response`, `state includes all state keys`, `state requires membership`
- `check requires membership`: keep `as: :json` (unauthenticated requests don't need turbo stream format)
- `custom_items requires membership`: keep `as: :json`
- `check marks item as checked`: change `as: :json` → `as: :turbo_stream`
- `custom_items adds item`: change `as: :json` → `as: :turbo_stream`
- `custom_items removes item`: change to use `as: :turbo_stream`, verify via model state instead of `groceries_state_path`:
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
    assert_not_includes plan.custom_items_list, 'birthday candles'
  end
  ```
- `custom_items rejects item over 100 characters`: keep `as: :json` (error responses stay JSON)
- `custom_items accepts item at exactly 100 characters`: change `as: :turbo_stream`
- `update_aisle_order saves valid order`: keep `as: :json` (aisle order returns JSON for the editor dialog — wait, actually `update_aisle_order` now returns a Turbo Stream morph. But the editor dialog JS sends JSON. We need to check: does the editor dialog's `saveRequest` use `Accept: application/json`?)

Check `app/javascript/utilities/editor_utils.js` — the `saveRequest` function sends `Content-Type: application/json` and `Accept: application/json`. The `update_aisle_order` action now renders `render_grocery_morph` (Turbo Stream). This is a format mismatch.

**Resolution:** `update_aisle_order` is called by the editor dialog (which expects JSON). Keep it rendering JSON for success. Broadcast the morph but don't render one inline — the editor dialog closes on success anyway, and the broadcast will update the shopping list.

Revise `update_aisle_order` in the controller (from Task 2):

```ruby
def update_aisle_order
  current_kitchen.aisle_order = params[:aisle_order].to_s
  current_kitchen.normalize_aisle_order!

  errors = validate_aisle_order
  return render json: { errors: }, status: :unprocessable_content if errors.any?

  current_kitchen.save!
  MealPlanBroadcaster.broadcast_grocery_morph(current_kitchen)
  render json: { status: 'ok' }
end
```

So `update_aisle_order` tests keep `as: :json`. The broadcast updates the shopping list on all connected clients.

Similarly, `update_quick_bites` is called by the editor dialog and already renders JSON — keep it as-is. Already correct in Task 2.

Broadcast assertions — replace `MealPlanChannel.broadcasting_for(@kitchen)` with `assert_turbo_stream_broadcasts`:

```ruby
test 'check broadcasts to groceries stream' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :turbo_stream
  end
end

test 'update_custom_items broadcasts to groceries stream' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :turbo_stream
  end
end

test 'update_aisle_order broadcasts to groceries stream' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Produce\nBaking" },
          as: :json
  end
end
```

Remove `data-state-url` assertion from `renders shopping list container with data attributes`:

```ruby
test 'renders shopping list container with data attributes' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '#shopping-list'
  assert_select '#groceries-app[data-kitchen-slug]'
  assert_select '#groceries-app[data-check-url]'
  assert_select '#groceries-app[data-custom-items-url]'
end
```

Remove `grocery-sync` assertion from `includes groceries CSS and Stimulus controllers`:

```ruby
test 'includes groceries CSS and Stimulus controllers' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'link[href*="groceries"]'
  assert_select '[data-controller~="grocery-ui"]'
end
```

**Step 2: Update menu test**

Read `test/controllers/menu_controller_test.rb`.

Key changes:
- DELETE tests: `state requires membership`, `state returns version and selections`, `state includes availability map`, `state availability reflects checked_off items`
- `select requires membership`: keep `as: :json`
- `select adds recipe and returns version`: rewrite — no longer returns JSON version. Assert turbo stream response and verify model state:
  ```ruby
  test 'select adds recipe' do
    log_in
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :turbo_stream

    assert_response :success

    plan = MealPlan.for_kitchen(@kitchen)
    assert_includes plan.state['selected_recipes'], 'focaccia'
  end
  ```
- `select broadcasts version via MealPlanChannel`: rewrite:
  ```ruby
  test 'select broadcasts to menu stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      patch menu_select_path(kitchen_slug: kitchen_slug),
            params: { type: 'recipe', slug: 'focaccia', selected: true },
            as: :turbo_stream
    end
  end
  ```
- `select deselects recipe`: change `as: :json` → `as: :turbo_stream`
- `select returns 409`: change `as: :json` → `as: :turbo_stream`. Keep JSON error response assertion (the `handle_stale_record` still renders JSON).
  Wait — actually `handle_stale_record` renders JSON. But the request is `as: :turbo_stream`. Rails will still render JSON because the rescue handler explicitly calls `render json:`. This works regardless of request format.
- `select_all requires membership`: keep `as: :json`
- `select_all selects all recipes and quick bites`: change `as: :json` → `as: :turbo_stream`
- `select_all preserves custom items and checked off`: change `as: :json` → `as: :turbo_stream`
- `select_all broadcasts version`: rewrite:
  ```ruby
  test 'select_all broadcasts to menu stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :turbo_stream
    end
  end
  ```
- `clear resets selections and checked off`: change `as: :json` → `as: :turbo_stream`. Remove `json = response.parsed_body` and `assert json.key?('version')`.
- `clear broadcasts version`: rewrite:
  ```ruby
  test 'clear broadcasts to menu stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
      delete menu_clear_path(kitchen_slug: kitchen_slug), as: :turbo_stream
    end
  end
  ```
- `clear returns 409`: change `as: :json` → `as: :turbo_stream`
- `update_quick_bites broadcasts Turbo Stream to menu_content`: also assert groceries broadcast:
  ```ruby
  test 'update_quick_bites broadcasts to groceries stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
      patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
            params: { content: "## Snacks\n  - Goldfish" },
            as: :json
    end
  end
  ```

**Step 3: Remove state routes**

In `config/routes.rb`, delete:
- Line 31: `get 'menu/state', to: 'menu#state', as: :menu_state`
- Line 33: `get 'groceries/state', to: 'groceries#state', as: :groceries_state`

**Step 4: Run tests**

Run: `rake test`
Expected: all pass.

**Step 5: Commit**

```bash
git add test/controllers/groceries_controller_test.rb \
        test/controllers/menu_controller_test.rb \
        config/routes.rb
git commit -m "test: update controller tests for Turbo Stream morph responses

Remove state endpoint tests and routes. Switch mutation tests from
as: :json to as: :turbo_stream. Replace MealPlanChannel broadcast
assertions with Turbo Stream broadcast assertions."
```

---

## Milestone 2: View & Partial Updates

### Task 4: Update views for Turbo Stream subscriptions

Add `turbo_stream_from` subscriptions, remove stale data attributes, add availability dots to menu partial.

**Files:**
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/menu/show.html.erb`
- Modify: `app/views/menu/_recipe_selector.html.erb`

**Step 1: Update groceries/show.html.erb**

Read the file first.

Changes:
- Add `<%= turbo_stream_from current_kitchen, "groceries" %>` before `<header id="groceries-header">`
- Remove `grocery-sync` from `data-controller` (becomes `wake-lock grocery-ui`)
- Remove `data-state-url="<%= groceries_state_path %>"` attribute

**Step 2: Update menu/show.html.erb**

Read the file first.

Changes:
- Add `<%= turbo_stream_from current_kitchen, "menu" %>` after the existing `turbo_stream_from` lines
- Remove `data-state-url="<%= menu_state_path %>"` from `#menu-app`
- Delete the entire `#ingredient-popover` div (lines 38-41)

**Step 3: Update menu/_recipe_selector.html.erb**

Read the file first.

Changes:
- Update locals declaration to include `availability: {}`:
  ```erb
  <%# locals: (categories:, quick_bites_by_subsection:, selected_recipes: Set.new, selected_quick_bites: Set.new, availability: {}) %>
  ```
- After each recipe checkbox+label, add availability dot:
  ```erb
  <li>
    <input type="checkbox" id="<%= recipe.slug %>-checkbox" data-slug="<%= recipe.slug %>" data-title="<%= h recipe.title %>" <%= 'checked' if selected_recipes.include?(recipe.slug) %>>
    <label for="<%= recipe.slug %>-checkbox"><%= recipe.title %></label>
    <% if (info = availability[recipe.slug]) %>
      <span class="availability-dot" data-slug="<%= recipe.slug %>" data-missing="<%= info[:missing] > 2 ? '3+' : info[:missing] %>" aria-label="<%= info[:missing].zero? ? 'All ingredients on hand' : "Missing #{info[:missing]}: #{info[:missing_names].join(', ')}" %>"></span>
    <% end %>
    <%= link_to "\u2192", recipe_path(recipe.slug), class: 'recipe-link', title: "Open #{recipe.title} in new tab", target: '_blank' %>
  </li>
  ```
- After each quick bite checkbox+label, add availability dot (binary: 0 or 3+):
  ```erb
  <li>
    <input type="checkbox" id="<%= item.id %>-checkbox" data-slug="<%= item.id %>" data-title="<%= h item.title %>" <%= 'checked' if selected_quick_bites.include?(item.id) %>>
    <label for="<%= item.id %>-checkbox"><%= item.title %></label>
    <% if (info = availability[item.id]) %>
      <span class="availability-dot" data-slug="<%= item.id %>" data-missing="<%= info[:missing].zero? ? '0' : '3+' %>" aria-label="<%= info[:missing].zero? ? 'All ingredients on hand' : "Missing #{info[:missing]}: #{info[:missing_names].join(', ')}" %>"></span>
    <% end %>
  </li>
  ```

**Step 4: Update `RecipeBroadcaster#broadcast_recipe_selector`**

Read `app/services/recipe_broadcaster.rb`. The `broadcast_recipe_selector` method does a `broadcast_replace_to` on `#recipe-selector`. Now the partial requires `availability:` and selection state. This method needs to pass the full locals, and switch from `replace` to `morph`.

Rather than duplicating all the local-building logic, have `RecipeBroadcaster` delegate to `MealPlanBroadcaster`:

```ruby
# In RecipeBroadcaster#broadcast_recipe_selector — replace the method body:
def broadcast_recipe_selector(categories: nil, stream: 'recipes')
  # Delegate to MealPlanBroadcaster which builds full locals (selections, availability)
  MealPlanBroadcaster.broadcast_menu_morph(kitchen)
end
```

Wait — `broadcast_recipe_selector` takes a `stream:` param and broadcasts to different streams (`'recipes'` vs `'menu_content'`). But `MealPlanBroadcaster.broadcast_menu_morph` always broadcasts to `'menu'`. The menu page subscribes to the `'menu'` stream. The homepage subscribes to `'recipes'`. We need to keep broadcasting to `'recipes'` too for the homepage recipe selector.

Actually, let's check: does the homepage have a `#recipe-selector`? Read the homepage views. If the homepage doesn't show a recipe selector, we don't need to broadcast to `'recipes'` for that target. The `'recipes'` stream is used for recipe listings and ingredients — not the selector.

The `broadcast_recipe_selector` is called from two places:
1. `RecipeBroadcaster#broadcast` (called on recipe CRUD) — uses default `stream: 'recipes'`
2. `MenuController#update_quick_bites` — uses `stream: 'menu_content'`

For case 1: recipe CRUD should update the menu page's selector. `MealPlanBroadcaster.broadcast_menu_morph` does this via the `'menu'` stream. The homepage doesn't show a recipe selector, so the old `'recipes'` stream broadcast for the selector was unnecessary (the homepage has `#recipe-listings`, not `#recipe-selector`).

For case 2: `update_quick_bites` already calls `MealPlanBroadcaster.broadcast_all` in the new code (Task 2). So `broadcast_recipe_selector` is no longer needed from `update_quick_bites`.

**Decision:** Remove the standalone `broadcast_recipe_selector` calls from `RecipeBroadcaster#broadcast` and from `MenuController#update_quick_bites`. `MealPlanBroadcaster.broadcast_menu_morph` replaces both.

In `RecipeBroadcaster#broadcast`, replace:
```ruby
broadcast_recipe_selector(categories:)
MealPlanChannel.broadcast_content_changed(kitchen)
```
with:
```ruby
MealPlanBroadcaster.broadcast_all(kitchen)
```

Keep the `broadcast_recipe_selector` class method for now (in case it's called elsewhere), but have it delegate to `MealPlanBroadcaster`. We'll verify in the cleanup task.

**Step 5: Run tests**

Run: `rake test`
Expected: some test failures related to the `broadcast_recipe_selector` changes. Fix as needed.

**Step 6: Commit**

```bash
git add app/views/groceries/show.html.erb \
        app/views/menu/show.html.erb \
        app/views/menu/_recipe_selector.html.erb \
        app/services/recipe_broadcaster.rb
git commit -m "feat: add turbo_stream_from subscriptions, server-render availability dots"
```

---

### Task 5: Update RecipeBroadcaster and its tests

Fully replace `MealPlanChannel` calls with `MealPlanBroadcaster` calls. Update `broadcast_recipe_selector` to delegate. Update tests.

**Files:**
- Modify: `app/services/recipe_broadcaster.rb`
- Modify: `test/services/recipe_broadcaster_test.rb`

**Step 1: Update RecipeBroadcaster**

Read `app/services/recipe_broadcaster.rb`.

In `broadcast` method, replace the last two lines:
```ruby
# Before:
broadcast_recipe_selector(categories:)
MealPlanChannel.broadcast_content_changed(kitchen)

# After:
MealPlanBroadcaster.broadcast_all(kitchen)
```

Update `broadcast_recipe_selector` to delegate:
```ruby
def broadcast_recipe_selector(categories: nil, stream: 'recipes')
  MealPlanBroadcaster.broadcast_menu_morph(kitchen)
end
```

Remove `categories:` parameter from the call in `broadcast` since it's no longer used:
```ruby
def broadcast(action:, recipe_title:, recipe: nil)
  categories = preload_categories

  broadcast_recipe_listings(categories)
  broadcast_ingredients(categories.flat_map(&:recipes))
  broadcast_recipe_page(recipe, action:, recipe_title:)
  broadcast_toast(action:, recipe_title:)
  MealPlanBroadcaster.broadcast_all(kitchen)
end
```

Wait — `broadcast_recipe_selector` is still a public class method called by `MenuController#update_quick_bites`. But in the new `MenuController` (Task 2), `update_quick_bites` calls `MealPlanBroadcaster.broadcast_all` directly. So `RecipeBroadcaster.broadcast_recipe_selector` is no longer called from outside. Verify:

```bash
grep -r 'broadcast_recipe_selector' app/ test/
```

If only called from `RecipeBroadcaster#broadcast` internally, remove the public class method and make it a private instance method that just calls `MealPlanBroadcaster`.

Actually, the simplest change: since `broadcast` already calls `MealPlanBroadcaster.broadcast_all`, and that handles the menu morph, just delete the `broadcast_recipe_selector` call from `broadcast` entirely. And keep the class method as a thin delegate for any remaining callers.

**Step 2: Update tests**

Read `test/services/recipe_broadcaster_test.rb`.

Replace `broadcasts content_changed via MealPlanChannel` test:
```ruby
test 'broadcasts grocery morph via MealPlanBroadcaster' do
  assert_turbo_stream_broadcasts [@kitchen, 'groceries'] do
    RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
  end
end
```

Update `broadcast_recipe_selector` tests — they currently assert `broadcast_replace_to`. Now it delegates to `MealPlanBroadcaster.broadcast_menu_morph`, which broadcasts to `[kitchen, 'menu']`:

```ruby
test 'broadcast_recipe_selector broadcasts to menu stream' do
  assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
    RecipeBroadcaster.broadcast_recipe_selector(kitchen: @kitchen, stream: 'menu_content')
  end
end

test 'broadcast_recipe_selector defaults to menu stream' do
  assert_turbo_stream_broadcasts [@kitchen, 'menu'] do
    RecipeBroadcaster.broadcast_recipe_selector(kitchen: @kitchen)
  end
end
```

Note: the `stream:` parameter is now ignored (delegates to `MealPlanBroadcaster` which always uses `'menu'`). Both tests assert the same thing. Consider collapsing into one test.

**Step 3: Run tests**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Then: `rake test`
Expected: all pass.

**Step 4: Commit**

```bash
git add app/services/recipe_broadcaster.rb \
        test/services/recipe_broadcaster_test.rb
git commit -m "feat: RecipeBroadcaster delegates to MealPlanBroadcaster, drops MealPlanChannel"
```

---

## Milestone 3: JavaScript Rewrite

### Task 6: Create turbo_fetch.js utility

Shared fetch-with-retry utility for Stimulus controllers.

**Files:**
- Create: `app/javascript/utilities/turbo_fetch.js`

**Step 1: Write the utility**

```javascript
// app/javascript/utilities/turbo_fetch.js

/**
 * Shared fetch-with-retry for Turbo Stream mutations. Sends a request with the
 * Turbo Stream accept header, processes the morph response via
 * Turbo.renderStreamMessage, and retries on network failure with exponential
 * backoff (1s, 2s, 4s). Used by grocery_ui_controller and menu_controller.
 */
import { getCsrfToken } from "utilities/editor_utils"

export function sendAction(url, params, { method = "PATCH", retries = 3 } = {}) {
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
      if (!response.ok) throw new Error("server error")
      return response.text()
    })
    .then(html => {
      if (html.includes("<turbo-stream")) Turbo.renderStreamMessage(html)
    })
    .catch(error => {
      if (error.message === "server error" || retries <= 0) return
      const delay = 1000 * Math.pow(2, 3 - retries)
      setTimeout(() => sendAction(url, params, { method, retries: retries - 1 }), delay)
    })
}
```

**Step 2: Verify importmap auto-pins**

`config/importmap.rb` has `pin_all_from "app/javascript/utilities"` — new files are auto-pinned. No config change needed.

**Step 3: Commit**

```bash
git add app/javascript/utilities/turbo_fetch.js
git commit -m "feat: add turbo_fetch.js utility with fetch-retry for cellular resilience"
```

---

### Task 7: Rewrite grocery_ui_controller.js

Delete all rendering code. Keep: optimistic checkbox toggle with inline aisle count update, custom item input, aisle collapse persistence + morph preservation.

**Files:**
- Rewrite: `app/javascript/controllers/grocery_ui_controller.js`

**Step 1: Write the new controller**

Read the current file first (`app/javascript/controllers/grocery_ui_controller.js`).

```javascript
// app/javascript/controllers/grocery_ui_controller.js

import { Controller } from "@hotwired/stimulus"
import { sendAction } from "utilities/turbo_fetch"
import ListenerManager from "utilities/listener_manager"

/**
 * Groceries page interaction — optimistic checkbox toggle, custom item input,
 * aisle collapse persistence. All rendering is server-side via Turbo Stream
 * morphs; this controller only handles user interactions and preserves local
 * state (aisle collapse) across morphs.
 */
export default class extends Controller {
  connect() {
    this.aisleCollapseKey = `grocery-aisles-${this.element.dataset.kitchenSlug}`
    this.listeners = new ListenerManager()

    this.bindShoppingListEvents()
    this.bindCustomItemInput()
    this.restoreAisleCollapse()

    this.listeners.add(document, "turbo:before-stream-render", (e) => this.preserveAisleState(e))
  }

  disconnect() {
    this.listeners.teardown()
  }

  // --- Shopping list ---

  bindShoppingListEvents() {
    const shoppingList = document.getElementById("shopping-list")

    this.listeners.add(shoppingList, "change", (e) => {
      const cb = e.target
      if (!cb.matches('.check-off input[type="checkbox"]')) return

      const name = cb.dataset.item
      if (!name) return

      this.updateAisleCount(cb.closest("details.aisle"))
      this.updateItemCount()

      sendAction(this.element.dataset.checkUrl, { item: name, checked: cb.checked })
    })

    this.listeners.add(shoppingList, "toggle", (e) => {
      if (e.target.matches("details.aisle")) this.saveAisleCollapse()
    }, true)
  }

  updateAisleCount(details) {
    if (!details) return
    const checkboxes = details.querySelectorAll('li[data-item] input[type="checkbox"]')
    const total = checkboxes.length
    const checked = Array.from(checkboxes).filter(cb => cb.checked).length
    const remaining = total - checked

    const countSpan = details.querySelector(".aisle-count")
    if (!countSpan) return

    if (remaining === 0 && total > 0) {
      countSpan.textContent = "\u2713"
      countSpan.classList.add("aisle-done")
    } else {
      countSpan.textContent = `(${remaining})`
      countSpan.classList.remove("aisle-done")
    }
  }

  updateItemCount() {
    const countEl = document.getElementById("item-count")
    if (!countEl) return

    const items = document.querySelectorAll("#shopping-list li[data-item]")
    const total = items.length
    const checked = Array.from(items).filter(li => {
      const cb = li.querySelector('input[type="checkbox"]')
      return cb && cb.checked
    }).length
    const remaining = total - checked

    if (total === 0) {
      countEl.textContent = ""
    } else if (remaining === 0) {
      countEl.textContent = "\u2713 All done!"
    } else if (checked > 0) {
      countEl.textContent = `${remaining} of ${total} items needed`
    } else {
      countEl.textContent = `${total} ${total === 1 ? "item" : "items"}`
    }
  }

  // --- Custom items ---

  bindCustomItemInput() {
    const input = document.getElementById("custom-input")
    const addBtn = document.getElementById("custom-add")
    const customList = document.getElementById("custom-items-list")
    const url = this.element.dataset.customItemsUrl

    const addItem = () => {
      const text = input.value.trim()
      if (!text) return

      sendAction(url, { item: text, action_type: "add" })
      input.value = ""
      input.focus()
    }

    this.listeners.add(addBtn, "click", addItem)
    this.listeners.add(input, "keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        addItem()
      }
    })

    this.listeners.add(customList, "click", (e) => {
      const btn = e.target.closest(".custom-item-remove")
      if (!btn) return
      sendAction(url, { item: btn.dataset.item, action_type: "remove" })
    })
  }

  // --- Aisle collapse ---

  saveAisleCollapse() {
    const collapsed = Array.from(document.querySelectorAll("#shopping-list details.aisle"))
      .filter(d => !d.open)
      .map(d => d.dataset.aisle)

    try {
      localStorage.setItem(this.aisleCollapseKey, JSON.stringify(collapsed))
    } catch { /* localStorage full */ }
  }

  restoreAisleCollapse() {
    const collapsed = this.loadCollapsedAisles()
    collapsed.forEach(aisle => {
      const details = document.querySelector(`#shopping-list details.aisle[data-aisle="${CSS.escape(aisle)}"]`)
      if (details) details.open = false
    })
  }

  loadCollapsedAisles() {
    try {
      const raw = localStorage.getItem(this.aisleCollapseKey)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  }

  preserveAisleState(event) {
    const collapsed = this.loadCollapsedAisles()
    const originalRender = event.detail.render

    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      this.restoreAisleCollapse()
    }
  }
}
```

**Step 2: Run tests**

Run: `rake test`
Expected: all pass (JS changes don't affect Minitest).

**Step 3: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: rewrite grocery_ui_controller — server morphs replace client rendering"
```

---

### Task 8: Rewrite menu_controller.js

Delete sync, availability rendering, and popover code. Keep: optimistic checkbox toggle, select-all/clear.

**Files:**
- Rewrite: `app/javascript/controllers/menu_controller.js`

**Step 1: Write the new controller**

Read the current file first (`app/javascript/controllers/menu_controller.js`).

```javascript
// app/javascript/controllers/menu_controller.js

import { Controller } from "@hotwired/stimulus"
import { sendAction } from "utilities/turbo_fetch"

/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle,
 * select-all, and clear-all actions. All rendering (checkboxes, availability
 * dots) is server-side via Turbo Stream morphs.
 */
export default class extends Controller {
  connect() {
    this.element.addEventListener("change", (e) => {
      const cb = e.target.closest('#recipe-selector input[type="checkbox"]')
      if (!cb) return

      const slug = cb.dataset.slug
      const typeEl = cb.closest("[data-type]")
      const type = typeEl ? typeEl.dataset.type : "recipe"

      sendAction(this.element.dataset.selectUrl, { type, slug, selected: cb.checked })
    })
  }

  selectAll() {
    sendAction(this.element.dataset.selectAllUrl, {})
  }

  clear() {
    sendAction(this.element.dataset.clearUrl, {}, { method: "DELETE" })
  }
}
```

**Step 2: Run tests**

Run: `rake test`
Expected: all pass.

**Step 3: Commit**

```bash
git add app/javascript/controllers/menu_controller.js
git commit -m "feat: rewrite menu_controller — server morphs replace client sync"
```

---

## Milestone 4: Cleanup

### Task 9: Delete MealPlanChannel, MealPlanSync, grocery_sync_controller

All references should now be gone.

**Files:**
- Delete: `app/channels/meal_plan_channel.rb`
- Delete: `test/channels/meal_plan_channel_test.rb`
- Delete: `app/javascript/utilities/meal_plan_sync.js`
- Delete: `app/javascript/controllers/grocery_sync_controller.js`

**Step 1: Verify no remaining references**

```bash
grep -r "MealPlanChannel" app/ test/ config/
grep -r "MealPlanSync\|meal_plan_sync" app/ test/ config/
grep -r "grocery.sync\|grocery_sync" app/ test/
grep -r "broadcast_version\|broadcast_content_changed" app/ test/
```

All should return nothing (except possibly design docs in `docs/`).

**Step 2: Delete files**

```bash
rm app/channels/meal_plan_channel.rb
rm test/channels/meal_plan_channel_test.rb
rm app/javascript/utilities/meal_plan_sync.js
rm app/javascript/controllers/grocery_sync_controller.js
```

**Step 3: Run tests**

Run: `rake test`
Expected: all pass.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete MealPlanChannel, MealPlanSync, grocery_sync_controller

Fully replaced by Turbo Stream morphs via MealPlanBroadcaster and
turbo_stream_from subscriptions."
```

---

### Task 10: Remove popover CSS and update service worker

Clean up remaining dead code.

**Files:**
- Modify: `app/assets/stylesheets/menu.css` (remove popover and ingredient-popover styles)
- Modify: `app/views/pwa/service_worker.js.erb` (remove `state` from API_PATTERN)
- Modify: `config/html_safe_allowlist.yml` (update line numbers if shifted)

**Step 1: Remove popover CSS from menu.css**

Read `app/assets/stylesheets/menu.css`. Delete the `#ingredient-popover`, `.popover-ingredients`, `.popover-missing` rule blocks, and their responsive counterpart in the `@media` section at the bottom. Keep the `.availability-dot` styles — those are still used.

**Step 2: Update service worker API_PATTERN**

Read `app/views/pwa/service_worker.js.erb`. In the `API_PATTERN` regex, remove `state|` from both the groceries and menu sections:

Before:
```javascript
var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(state|check|custom_items|aisle_order|aisle_order_content)|menu\/(state|select|select_all|clear|quick_bites|quick_bites_content)|nutrition\/)/;
```

After:
```javascript
var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(check|custom_items|aisle_order|aisle_order_content)|menu\/(select|select_all|clear|quick_bites|quick_bites_content)|nutrition\/)/;
```

**Step 3: Run html_safe lint**

Run: `rake lint:html_safe`

If line numbers shifted in modified views, update `config/html_safe_allowlist.yml`.

**Step 4: Run full suite**

Run: `rake test`
Then: `bundle exec rubocop`
Expected: all pass, 0 offenses.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove popover CSS, update service worker API_PATTERN"
```

---

### Task 11: Final verification sweep

Verify no stale references, run full suite, RuboCop.

**Files:**
- All files — verification only

**Step 1: Grep for stale references**

```bash
grep -r "grocery.sync\|grocery_sync" app/ test/
grep -r "meal_plan_sync\|MealPlanSync" app/ test/ config/
grep -r "MealPlanChannel" app/ test/ config/
grep -r "data-state-url" app/
grep -r "groceries_state\|menu_state" app/ config/ test/
grep -r "broadcast_version\|broadcast_content_changed" app/ test/
grep -r "formatAmounts\|formatNumber\|renderShoppingList\|renderCustomItems" app/
grep -r "syncCheckboxes\|syncAvailability\|showIngredientPopover" app/
```

All should return nothing except design docs.

**Step 2: Run full test suite**

Run: `rake test`
Expected: all pass.

**Step 3: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses.

**Step 4: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: clean.

**Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final sweep — stale references, lint, tests"
```

---

## Cross-Reference: Files Changed

### Deleted
- `app/channels/meal_plan_channel.rb` (36 lines)
- `test/channels/meal_plan_channel_test.rb` (50 lines)
- `app/javascript/utilities/meal_plan_sync.js` (221 lines)
- `app/javascript/controllers/grocery_sync_controller.js` (46 lines)

### Created
- `app/services/meal_plan_broadcaster.rb`
- `test/services/meal_plan_broadcaster_test.rb`
- `app/javascript/utilities/turbo_fetch.js` (~25 lines)

### Rewritten
- `app/javascript/controllers/grocery_ui_controller.js` (302 → ~90 lines)
- `app/javascript/controllers/menu_controller.js` (197 → ~25 lines)

### Modified
- `app/controllers/groceries_controller.rb`
- `app/controllers/menu_controller.rb`
- `app/controllers/concerns/meal_plan_actions.rb`
- `app/models/meal_plan.rb` (add convenience readers)
- `app/services/recipe_broadcaster.rb`
- `app/views/groceries/show.html.erb`
- `app/views/menu/show.html.erb`
- `app/views/menu/_recipe_selector.html.erb`
- `app/assets/stylesheets/menu.css`
- `app/views/pwa/service_worker.js.erb`
- `config/routes.rb`
- `test/controllers/groceries_controller_test.rb`
- `test/controllers/menu_controller_test.rb`
- `test/services/recipe_broadcaster_test.rb`

# Recipe Change Propagation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Auto-update all pages when recipes are created, updated, or deleted — with toast notifications.

**Architecture:** Turbo Stream broadcasts replace HTML targets on the homepage, menu, ingredients, and recipe pages. The groceries page auto-fetches JSON state via ActionCable. A `RecipeBroadcaster` service orchestrates all broadcasts. Only kitchen members receive updates.

**Tech Stack:** Turbo Streams, ActionCable (Solid Cable), Stimulus

---

### Task 1: Toast Infrastructure

**Files:**
- Create: `app/javascript/controllers/toast_controller.js`
- Create: `app/views/shared/_toast.html.erb`
- Modify: `app/views/layouts/application.html.erb:17-21`

**Step 1: Create toast Stimulus controller**

```javascript
// app/javascript/controllers/toast_controller.js
import { Controller } from "@hotwired/stimulus"
import { show as notifyShow } from "utilities/notify"

export default class extends Controller {
  static values = { message: String }

  connect() {
    notifyShow(this.messageValue)
    this.element.remove()
  }
}
```

No importmap pin needed — `pin_all_from "app/javascript/controllers"` auto-discovers it.

**Step 2: Create toast partial**

```erb
<%# app/views/shared/_toast.html.erb %>
<%# locals: (message:) %>
<div data-controller="toast" data-toast-message-value="<%= message %>"></div>
```

**Step 3: Add notifications container to layout**

In `app/views/layouts/application.html.erb`, add `<div id="notifications"></div>` just before `</body>`:

```erb
  <main>
    <%= yield %>
  </main>
  <div id="notifications"></div>
</body>
```

**Step 4: Run tests to verify nothing broke**

Run: `rake test`
Expected: All tests pass (layout change is inert — empty div).

**Step 5: Commit**

```bash
git add app/javascript/controllers/toast_controller.js app/views/shared/_toast.html.erb app/views/layouts/application.html.erb
git commit -m "feat: toast infrastructure for real-time notifications (#114)"
```

---

### Task 2: Extract Homepage Recipe Listings Partial

**Files:**
- Create: `app/views/homepage/_recipe_listings.html.erb`
- Modify: `app/views/homepage/show.html.erb:17-34`

**Step 1: Create the partial**

Extract the TOC nav + category sections into a partial wrapped in an identifiable container:

```erb
<%# app/views/homepage/_recipe_listings.html.erb %>
<%# locals: (categories:) %>
<div id="recipe-listings">
  <div class="toc_nav">
    <ul>
      <%- categories.each do |category| -%>
      <li><%= link_to category.name, "##{category.slug}" %></li>
      <%- end -%>
    </ul>
  </div>

  <%- categories.each do |category| -%>
  <section id="<%= category.slug %>">
    <h2><%= category.name %></h2>
    <ul>
      <%- category.recipes.sort_by(&:title).each do |recipe| -%>
      <li><%= link_to recipe.title, recipe_path(recipe.slug), title: recipe.description %></li>
      <%- end -%>
    </ul>
  </section>
  <%- end -%>
</div>
```

**Step 2: Update the homepage view**

Replace lines 17-34 of `app/views/homepage/show.html.erb` with:

```erb
  <%= render 'homepage/recipe_listings', categories: @categories %>
```

**Step 3: Run homepage tests**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: All tests pass — same HTML output, just extracted into a partial.

**Step 4: Commit**

```bash
git add app/views/homepage/_recipe_listings.html.erb app/views/homepage/show.html.erb
git commit -m "refactor: extract homepage recipe listings into partial (#114)"
```

---

### Task 3: Prepare Ingredients Page for Turbo Stream

**Files:**
- Create: `app/views/ingredients/_table.html.erb`
- Modify: `app/views/ingredients/index.html.erb:20-44`

**Step 1: Extract the table into a partial**

Create `app/views/ingredients/_table.html.erb` containing the full `<table>` element (thead + rows) with an `id` attribute:

```erb
<%# app/views/ingredients/_table.html.erb %>
<%# locals: (ingredient_rows:) %>
<table id="ingredients-table" class="ingredients-table" data-ingredient-table-target="table">
  <thead>
    <tr>
      <th class="col-name sortable" data-sort-key="name" data-action="click->ingredient-table#sort"
          role="columnheader" aria-sort="ascending">
        Ingredient<span class="sort-arrow" aria-hidden="true"> &#9650;</span>
      </th>
      <th class="col-nutrition sortable" data-sort-key="nutrition" data-action="click->ingredient-table#sort"
          role="columnheader">
        Nutrition<span class="sort-arrow" aria-hidden="true"></span>
      </th>
      <th class="col-density sortable" data-sort-key="density" data-action="click->ingredient-table#sort"
          role="columnheader">
        Density<span class="sort-arrow" aria-hidden="true"></span>
      </th>
      <th class="col-aisle sortable" data-sort-key="aisle" data-action="click->ingredient-table#sort"
          role="columnheader">
        Aisle<span class="sort-arrow" aria-hidden="true"></span>
      </th>
    </tr>
  </thead>
  <% ingredient_rows.each do |row| %>
    <%= render 'ingredients/table_row', row: row %>
  <% end %>
</table>
```

**Step 2: Update the ingredients index view**

Replace lines 20-44 of `app/views/ingredients/index.html.erb` with:

```erb
  <%= render 'ingredients/table', ingredient_rows: @ingredient_rows %>
```

**Step 3: Run ingredients tests**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add app/views/ingredients/_table.html.erb app/views/ingredients/index.html.erb
git commit -m "refactor: extract ingredients table into partial (#114)"
```

---

### Task 4: Prepare Recipe Page for Turbo Stream

**Files:**
- Modify: `app/views/recipes/show.html.erb:16-44`
- Create: `app/views/recipes/_recipe_content.html.erb`
- Create: `app/views/recipes/_deleted.html.erb`

**Step 1: Extract recipe content into a partial**

Create `app/views/recipes/_recipe_content.html.erb` wrapping the `<article>` in an identifiable div:

```erb
<%# app/views/recipes/_recipe_content.html.erb %>
<%# locals: (recipe:, nutrition:) %>
<div id="recipe-content">
  <article class="recipe" data-controller="wake-lock recipe-state">
    <header>
      <h1><%= recipe.title %></h1>
      <%- if recipe.description.present? -%>
      <p><%= recipe.description %></p>
      <%- end -%>
      <p class="recipe-meta">
        <%= link_to recipe.category.name, home_path(anchor: recipe.category.slug) %><%- if recipe.makes -%>
        <%- if nutrition&.dig('makes_unit_singular') -%>
        &middot; Makes <%= format_yield_with_unit(recipe.makes, nutrition['makes_unit_singular'], nutrition['makes_unit_plural']) %><%- else -%>
        &middot; Makes <%= format_yield_line(recipe.makes) %><%- end -%><%- end -%><%- if recipe.serves -%>
        &middot; Serves <%= format_yield_line(recipe.serves.to_s) %><%- end -%>
      </p>
    </header>

    <% recipe.steps.each do |step| %>
      <%= render 'step', step: step %>
    <% end %>

    <%- if recipe.footer.present? -%>
    <footer>
      <%= render_markdown(recipe.footer) %>
    </footer>
    <%- end -%>

    <%- if nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
      <%= render 'nutrition_table', nutrition: nutrition %>
    <%- end -%>
  </article>
</div>
```

**Step 2: Update the recipe show view**

Replace lines 16-44 of `app/views/recipes/show.html.erb` with:

```erb
<%= render 'recipes/recipe_content', recipe: @recipe, nutrition: @nutrition %>
```

**Step 3: Create the deleted partial**

```erb
<%# app/views/recipes/_deleted.html.erb %>
<%# locals: (recipe_title:, redirect_path: nil, redirect_title: nil) %>
<div id="recipe-content">
  <article class="recipe">
    <header>
      <h1><%= recipe_title %></h1>
    </header>
    <p>This recipe has been deleted.<%- if redirect_path -%>
      <%= link_to redirect_title || 'Return to recipes', redirect_path %><%- end -%>
    </p>
  </article>
</div>
```

**Step 4: Run recipe tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb app/views/recipes/_deleted.html.erb app/views/recipes/show.html.erb
git commit -m "refactor: extract recipe content into partial (#114)"
```

---

### Task 5: Add Turbo Stream Subscriptions to Views

**Files:**
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/views/menu/show.html.erb:15`
- Modify: `app/views/ingredients/index.html.erb`
- Modify: `app/views/recipes/show.html.erb`

All subscriptions are gated on `current_user && current_kitchen.member?(current_user)`.

**Step 1: Homepage subscription**

Add after the `content_for(:extra_nav)` block (before `<article>`) in `homepage/show.html.erb`:

```erb
<% if current_user && current_kitchen.member?(current_user) %>
  <%= turbo_stream_from current_kitchen, "recipes" %>
<% end %>
```

**Step 2: Menu subscription**

The menu page already has `<%= turbo_stream_from current_kitchen, "menu_content" %>` on line 15. Add a second subscription below it:

```erb
<%= turbo_stream_from current_kitchen, "menu_content" %>
<%= turbo_stream_from current_kitchen, "recipes" %>
```

The menu page already requires membership, so no auth gate needed (but keep the existing pattern for consistency if desired).

**Step 3: Ingredients subscription**

Add at the top of `ingredients/index.html.erb`, after the `content_for(:title)`:

```erb
<%= turbo_stream_from current_kitchen, "recipes" %>
```

The ingredients page already requires membership, so all visitors are authenticated.

**Step 4: Recipe page subscription**

Add in `recipes/show.html.erb`, after the `content_for(:extra_nav)` block:

```erb
<% if current_user && current_kitchen.member?(current_user) %>
  <%= turbo_stream_from @recipe, "content" %>
<% end %>
```

**Step 5: Write tests for auth gate**

Add to `test/controllers/homepage_controller_test.rb`:

```ruby
test 'homepage includes turbo stream subscription for members' do
  log_in
  get home_path(kitchen_slug: kitchen_slug)
  assert_select 'turbo-cable-stream-source'
end

test 'homepage excludes turbo stream subscription for non-members' do
  get home_path(kitchen_slug: kitchen_slug)
  assert_select 'turbo-cable-stream-source', count: 0
end
```

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'recipe page includes turbo stream subscription for members' do
  log_in
  get recipe_path('focaccia', kitchen_slug: kitchen_slug)
  assert_select 'turbo-cable-stream-source'
end

test 'recipe page excludes turbo stream subscription for non-members' do
  get recipe_path('focaccia', kitchen_slug: kitchen_slug)
  assert_select 'turbo-cable-stream-source', count: 0
end
```

**Step 6: Run tests**

Run: `rake test`
Expected: All tests pass, including the new subscription tests.

**Step 7: Commit**

```bash
git add app/views/homepage/show.html.erb app/views/menu/show.html.erb app/views/ingredients/index.html.erb app/views/recipes/show.html.erb test/controllers/homepage_controller_test.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: add Turbo Stream subscriptions for recipe updates (#114)"
```

---

### Task 6: RecipeBroadcaster Service

**Files:**
- Create: `app/services/recipe_broadcaster.rb`
- Create: `test/services/recipe_broadcaster_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/recipe_broadcaster_test.rb
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class RecipeBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    @user = User.find_or_create_by!(email: 'test@example.com') { |u| u.name = 'Test' }
    Membership.find_or_create_by!(kitchen: @kitchen, user: @user)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      A simple bread.

      Category: Bread

      ## Dough

      - Flour, 3 cups
      - Water, 1 cup

      Mix and knead.
    MD
  end

  test 'broadcasts Turbo Streams to kitchen recipes stream' do
    assert_turbo_stream_broadcasts [@kitchen, 'recipes'] do
      RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
    end
  end

  test 'broadcasts content_changed via MealPlanChannel' do
    stream = MealPlanChannel.broadcasting_for(@kitchen)

    assert_broadcasts(stream, 1) do
      RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
    end
  end

  test 'broadcasts to recipe-specific stream when recipe provided' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.broadcast(
        kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia', recipe: recipe
      )
    end
  end

  test 'broadcasts deleted partial for recipe-specific stream on delete' do
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')

    assert_turbo_stream_broadcasts [recipe, 'content'] do
      RecipeBroadcaster.broadcast(
        kitchen: @kitchen, action: :deleted, recipe_title: 'Focaccia', recipe: recipe
      )
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: FAIL — `RecipeBroadcaster` not defined.

**Step 3: Implement RecipeBroadcaster**

```ruby
# app/services/recipe_broadcaster.rb
# frozen_string_literal: true

class RecipeBroadcaster
  include IngredientRows

  def self.broadcast(kitchen:, action:, recipe_title:, recipe: nil)
    new(kitchen).broadcast(action:, recipe_title:, recipe:)
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def broadcast(action:, recipe_title:, recipe: nil)
    broadcast_recipe_listings
    broadcast_recipe_selector
    broadcast_ingredients
    broadcast_recipe_page(recipe, action:, recipe_title:)
    broadcast_toast(action:, recipe_title:)
    MealPlanChannel.broadcast_content_changed(@kitchen)
  end

  private

  attr_reader :kitchen

  def current_kitchen = kitchen

  def broadcast_recipe_listings
    categories = kitchen.categories.ordered.includes(:recipes).reject { |c| c.recipes.empty? }
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-listings',
      partial: 'homepage/recipe_listings',
      locals: { categories: }
    )
  end

  def broadcast_recipe_selector
    categories = kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    quick_bites = parse_quick_bites
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'recipe-selector',
      partial: 'menu/recipe_selector',
      locals: { categories:, quick_bites_by_subsection: quick_bites }
    )
  end

  def broadcast_ingredients
    lookup = IngredientCatalog.lookup_for(kitchen)
    rows = build_ingredient_rows(lookup)
    summary = build_summary(rows)

    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'ingredients-summary',
      partial: 'ingredients/summary_bar',
      locals: { summary: }
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      kitchen, 'recipes',
      target: 'ingredients-table',
      partial: 'ingredients/table',
      locals: { ingredient_rows: rows }
    )
  end

  def broadcast_recipe_page(recipe, action:, recipe_title:)
    return unless recipe

    if action == :deleted
      broadcast_recipe_deleted(recipe, recipe_title:)
    else
      broadcast_recipe_updated(recipe)
    end
    broadcast_recipe_toast(recipe, action:, recipe_title:)
  end

  def broadcast_recipe_updated(recipe)
    fresh = kitchen.recipes
                   .includes(steps: [:ingredients, { cross_references: :target_recipe }])
                   .find_by(slug: recipe.slug)
    return unless fresh

    Turbo::StreamsChannel.broadcast_replace_to(
      fresh, 'content',
      target: 'recipe-content',
      partial: 'recipes/recipe_content',
      locals: { recipe: fresh, nutrition: fresh.nutrition_data }
    )
  end

  def broadcast_recipe_deleted(recipe, recipe_title:)
    Turbo::StreamsChannel.broadcast_replace_to(
      recipe, 'content',
      target: 'recipe-content',
      partial: 'recipes/deleted',
      locals: { recipe_title: }
    )
  end

  def broadcast_toast(action:, recipe_title:)
    Turbo::StreamsChannel.broadcast_append_to(
      kitchen, 'recipes',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was #{action}" }
    )
  end

  def broadcast_recipe_toast(recipe, action:, recipe_title:)
    Turbo::StreamsChannel.broadcast_append_to(
      recipe, 'content',
      target: 'notifications',
      partial: 'shared/toast',
      locals: { message: "#{recipe_title} was #{action}" }
    )
  end

  def parse_quick_bites
    content = kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: All 4 tests pass.

**Step 5: Commit**

```bash
git add app/services/recipe_broadcaster.rb test/services/recipe_broadcaster_test.rb
git commit -m "feat: RecipeBroadcaster service for real-time updates (#114)"
```

---

### Task 7: Wire RecipeBroadcaster into RecipesController

**Files:**
- Modify: `app/controllers/recipes_controller.rb:13-66`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write failing tests for broadcasts**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
require 'turbo/broadcastable/test_helper'

# Inside the test class:
include Turbo::Broadcastable::TestHelper

test 'create broadcasts Turbo Streams to recipes stream' do
  log_in
  markdown = "# New Bread\n\nCategory: Bread\n\n## Step\n\n- Flour, 1 cup\n\nMix.\n"

  assert_turbo_stream_broadcasts [@kitchen, 'recipes'] do
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: markdown },
         as: :json
  end
end

test 'update broadcasts Turbo Streams to recipes stream' do
  log_in

  assert_turbo_stream_broadcasts [@kitchen, 'recipes'] do
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: @focaccia.markdown_source },
          as: :json
  end
end

test 'destroy broadcasts Turbo Streams to recipes stream' do
  log_in

  assert_turbo_stream_broadcasts [@kitchen, 'recipes'] do
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /broadcasts_Turbo/`
Expected: FAIL — no Turbo Stream broadcasts yet.

**Step 3: Update RecipesController**

Replace `MealPlanChannel.broadcast_content_changed(current_kitchen)` on lines 20, 47, and 62 with `RecipeBroadcaster.broadcast` calls:

In `create` (line 20):
```ruby
RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :created, recipe_title: recipe.title, recipe: recipe)
```

In `update` (line 47), also handle rename. Replace the `MealPlanChannel` line with:
```ruby
RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :updated, recipe_title: recipe.title, recipe: recipe)
```

For the rename case, add a pre-broadcast BEFORE `@recipe.destroy!` (around line 43):
```ruby
if recipe.slug != @recipe.slug
  RecipeBroadcaster.broadcast_rename(@recipe, new_title: recipe.title, new_slug: recipe.slug)
  @recipe.destroy!
end
```

Add `broadcast_rename` class method to `RecipeBroadcaster`:
```ruby
def self.broadcast_rename(old_recipe, new_title:, new_slug:)
  Turbo::StreamsChannel.broadcast_replace_to(
    old_recipe, 'content',
    target: 'recipe-content',
    partial: 'recipes/deleted',
    locals: { recipe_title: old_recipe.title,
              redirect_path: "/recipes/#{new_slug}",
              redirect_title: new_title }
  )
end
```

In `destroy` (line 62), broadcast to the recipe BEFORE destroying:
```ruby
updated_references = CrossReferenceUpdater.strip_references(@recipe)
RecipeBroadcaster.broadcast(kitchen: current_kitchen, action: :deleted, recipe_title: @recipe.title, recipe: @recipe)
@recipe.destroy!
Category.cleanup_orphans(current_kitchen)

response_json = { redirect_url: home_path }
response_json[:updated_references] = updated_references if updated_references.any?
render json: response_json
```

Note: move the broadcast BEFORE `@recipe.destroy!` so the recipe-specific stream still exists.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: All tests pass, including the new broadcast tests.

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb app/services/recipe_broadcaster.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: wire RecipeBroadcaster into recipe CRUD actions (#114)"
```

---

### Task 8: Groceries Auto-Fetch on Content Changed

**Files:**
- Modify: `app/javascript/controllers/grocery_sync_controller.js:157-172`
- Modify: `app/javascript/controllers/menu_controller.js:289-301`

**Step 1: Update grocery_sync_controller**

In `grocery_sync_controller.js`, update the `received` callback (around line 162) to handle `content_changed`:

```javascript
received: (data) => {
  if (data.type === 'content_changed') {
    this.fetchState()
    return
  }
  if (data.version && data.version > this.version && !this.awaitingOwnAction) {
    this.fetchState()
  }
}
```

The `fetchState()` method already shows a toast ("Shopping list updated.") for remote updates via the `isRemoteUpdate` check. However, `content_changed` doesn't bump the version, so the `isRemoteUpdate` flag won't trigger. To show the toast on content changes, modify `fetchState()` to accept an optional flag:

Actually, simpler: add a method that fetches and always shows a toast:

```javascript
received: (data) => {
  if (data.type === 'content_changed') {
    this.fetchStateWithNotification()
    return
  }
  if (data.version && data.version > this.version && !this.awaitingOwnAction) {
    this.fetchState()
  }
}
```

Add the new method:

```javascript
fetchStateWithNotification() {
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
      this.version = data.version
      this.state = data
      this.saveCache()
      this.applyStateToUI(data)
      notifyShow("Shopping list updated.")
    })
    .catch(() => {})
}
```

**Step 2: Update menu_controller**

In `menu_controller.js`, update the `received` callback (around line 294) to handle `content_changed`:

```javascript
received: (data) => {
  if (data.type === 'content_changed') {
    this.fetchState()
    return
  }
  if (data.version && data.version > this.version && !this.awaitingOwnAction) {
    this.fetchState()
  }
}
```

The menu page also gets Turbo Stream replacements for `#recipe-selector`, so the `content_changed` fetch is about refreshing availability data (which recipes are missing ingredients). The `fetchState()` already handles the toast on remote updates.

**Step 3: Test manually**

Start the dev server (`bin/dev`), open the groceries page in one tab and the menu page in another. Edit a recipe in a third tab. Verify:
- Groceries page auto-updates and shows "Shopping list updated." toast
- Menu page auto-updates checkbox list and availability dots

**Step 4: Commit**

```bash
git add app/javascript/controllers/grocery_sync_controller.js app/javascript/controllers/menu_controller.js
git commit -m "feat: auto-fetch groceries/menu state on recipe changes (#114)"
```

---

### Task 9: Run Full Test Suite and Verify

**Step 1: Run lint**

Run: `rake lint`
Expected: No new offenses. If RuboCop flags the RecipeBroadcaster, address inline.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: No new violations. The toast partial uses `<%= message %>` which auto-escapes.

**Step 4: Manual smoke test**

Start `bin/dev` and open multiple tabs:
1. Homepage in tab 1
2. Menu page in tab 2
3. Groceries page in tab 3 (select a recipe first)
4. A recipe page in tab 4
5. Ingredients page in tab 5

From the recipe page (tab 4), edit the recipe and save. Verify:
- Tab 1 (homepage): recipe listing updates, toast appears
- Tab 2 (menu): recipe selector updates, toast appears
- Tab 3 (groceries): shopping list re-fetches, toast appears
- Tab 4 (recipe): content updates (after redirect back)
- Tab 5 (ingredients): table updates, toast appears

Create a new recipe. Verify it appears on all tabs.
Delete a recipe. Verify it disappears and any open recipe page shows "deleted" message.

**Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: address issues from recipe propagation smoke test (#114)"
```

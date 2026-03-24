# Broadcast Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace MealPlanBroadcaster's targeted Turbo Stream morphs with page-refresh broadcasts, eliminating ~170 lines (production + test) and 16-20 queries per broadcast.

**Architecture:** Controllers call `broadcast_meal_plan_refresh` (a one-liner in `MealPlanActions` concern) which sends `Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)`. Views subscribe via `turbo_stream_from current_kitchen, :meal_plan_updates`. Turbo Drive re-fetches the current page and morphs the result.

**Tech Stack:** Rails 8, Turbo Rails 2.0, Stimulus, Solid Cable

---

### Task 1: Add broadcast helper to MealPlanActions concern

**Files:**
- Modify: `app/controllers/concerns/meal_plan_actions.rb`
- Test: `test/controllers/groceries_controller_test.rb` (existing broadcast tests serve as integration check)

**Step 1: Add the `broadcast_meal_plan_refresh` helper**

Add a private method to the `MealPlanActions` concern:

```ruby
def broadcast_meal_plan_refresh
  Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
end
```

In `app/controllers/concerns/meal_plan_actions.rb`, add after `handle_stale_record`:

```ruby
def broadcast_meal_plan_refresh
  Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
end
```

**Step 2: Run tests to verify nothing breaks**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass (helper not called yet)

**Step 3: Commit**

```bash
git add app/controllers/concerns/meal_plan_actions.rb
git commit -m "feat: add broadcast_meal_plan_refresh helper to MealPlanActions"
```

---

### Task 2: Switch GroceriesController to refresh broadcasts

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `app/views/groceries/show.html.erb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Update the view's stream subscription**

In `app/views/groceries/show.html.erb`, change line 15:

```erb
<%# OLD: %>
<%= turbo_stream_from current_kitchen, "groceries" %>
<%# NEW: %>
<%= turbo_stream_from current_kitchen, :meal_plan_updates %>
```

**Step 2: Replace broadcaster calls in controller**

In `app/controllers/groceries_controller.rb`:

- Line 22: `MealPlanBroadcaster.broadcast_all(current_kitchen)` → `broadcast_meal_plan_refresh`
- Line 35: `MealPlanBroadcaster.broadcast_grocery_morph(current_kitchen)` → `broadcast_meal_plan_refresh`
- Line 47: `MealPlanBroadcaster.broadcast_grocery_morph(current_kitchen)` → `broadcast_meal_plan_refresh`

**Step 3: Update the header comment**

Replace the header comment (lines 1-6) with:

```ruby
# Shopping list page -- member-only. Server-renders the full shopping list on
# page load via ShoppingListBuilder. Mutations return 204 No Content and
# broadcast a page-refresh signal for cross-device sync. Manages check-off
# state, custom items, and aisle ordering.
```

**Step 4: Update broadcast assertions in tests**

In `test/controllers/groceries_controller_test.rb`, update three tests.

Change `'check broadcasts to groceries stream'` (lines 359-365):

```ruby
test 'check broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch groceries_check_path(kitchen_slug: kitchen_slug),
          params: { item: 'flour', checked: true },
          as: :turbo_stream
  end
end
```

Change `'update_custom_items broadcasts to groceries stream'` (lines 368-374):

```ruby
test 'update_custom_items broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
          params: { item: 'birthday candles', action_type: 'add' },
          as: :turbo_stream
  end
end
```

Change `'update_aisle_order broadcasts to groceries stream'` (lines 377-384):

```ruby
test 'update_aisle_order broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch groceries_aisle_order_path(kitchen_slug: kitchen_slug),
          params: { aisle_order: "Produce\nBaking" },
          as: :json
  end
end
```

**Step 5: Run tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/controllers/groceries_controller.rb app/views/groceries/show.html.erb test/controllers/groceries_controller_test.rb
git commit -m "feat: GroceriesController uses page-refresh broadcasts"
```

---

### Task 3: Switch MenuController to refresh broadcasts

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `app/views/menu/show.html.erb`
- Modify: `test/controllers/menu_controller_test.rb`

**Step 1: Update the view's stream subscriptions**

In `app/views/menu/show.html.erb`, change lines 15-16:

```erb
<%# OLD: %>
<%= turbo_stream_from current_kitchen, "recipes" %>
<%= turbo_stream_from current_kitchen, "menu" %>
<%# NEW: %>
<%= turbo_stream_from current_kitchen, "recipes" %>
<%= turbo_stream_from current_kitchen, :meal_plan_updates %>
```

Keep `"recipes"` — RecipeBroadcaster still uses that stream for targeted recipe listing updates.

**Step 2: Replace broadcaster calls in controller**

In `app/controllers/menu_controller.rb`:

- Line 25: `MealPlanBroadcaster.broadcast_all(current_kitchen)` → `broadcast_meal_plan_refresh`
- Line 31: `MealPlanBroadcaster.broadcast_all(current_kitchen)` → `broadcast_meal_plan_refresh`
- Line 37: `MealPlanBroadcaster.broadcast_all(current_kitchen)` → `broadcast_meal_plan_refresh`
- Line 51: `MealPlanBroadcaster.broadcast_all(current_kitchen)` → `broadcast_meal_plan_refresh`

**Step 3: Update the header comment**

Replace the header comment (lines 1-6) with:

```ruby
# Meal planning page -- member-only. Displays a recipe selector (recipes + quick
# bites) with checkboxes. Mutations return 204 No Content and broadcast a
# page-refresh signal for cross-device sync. Quick bites content is web-editable;
# changes broadcast to all connected clients.
```

**Step 4: Update broadcast assertions in tests**

In `test/controllers/menu_controller_test.rb`, update four tests.

Change `'select broadcasts to menu stream'` (lines 96-103):

```ruby
test 'select broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch menu_select_path(kitchen_slug: kitchen_slug),
          params: { type: 'recipe', slug: 'focaccia', selected: true },
          as: :turbo_stream
  end
end
```

Change `'select_all broadcasts to menu stream'` (lines 173-178):

```ruby
test 'select_all broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch menu_select_all_path(kitchen_slug: kitchen_slug), as: :turbo_stream
  end
end
```

Change `'clear broadcasts to menu stream'` (lines 201-206):

```ruby
test 'clear broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    delete menu_clear_path(kitchen_slug: kitchen_slug), as: :turbo_stream
  end
end
```

Change `'update_quick_bites broadcasts to groceries and menu streams'` (lines 264-273):

```ruby
test 'update_quick_bites broadcasts meal plan refresh' do
  log_in
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    patch menu_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: "## Snacks\n  - Goldfish" },
          as: :json
  end
end
```

**Step 5: Run tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/controllers/menu_controller.rb app/views/menu/show.html.erb test/controllers/menu_controller_test.rb
git commit -m "feat: MenuController uses page-refresh broadcasts"
```

---

### Task 4: Switch NutritionEntriesController and RecipeBroadcaster

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Modify: `app/services/recipe_broadcaster.rb`
- Modify: `test/services/recipe_broadcaster_test.rb`
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Update NutritionEntriesController**

`NutritionEntriesController` does not include `MealPlanActions`, so it can't use the concern helper. Add a direct call instead.

In `app/controllers/nutrition_entries_controller.rb`:

Change `broadcast_aisle_change` (line 115-117):

```ruby
def broadcast_aisle_change
  Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
end
```

Change `destroy` method (line 28):

```ruby
MealPlanBroadcaster.broadcast_all(current_kitchen)
```
→
```ruby
Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
```

Update the header comment (lines 1-8):

```ruby
# JSON/Turbo Stream API for creating, updating, and deleting kitchen-scoped
# IngredientCatalog entries from the web nutrition editor. On save, syncs new
# aisles to the kitchen's aisle_order, broadcasts a page-refresh signal for
# cross-device sync, and recalculates nutrition for all affected recipes.
# Responds with Turbo Stream updates to refresh the ingredients table in-place.
```

**Step 2: Update RecipeBroadcaster**

In `app/services/recipe_broadcaster.rb`, change line 66:

```ruby
MealPlanBroadcaster.broadcast_all(kitchen, catalog_lookup:)
```
→
```ruby
Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
```

Update the header comment (lines 1-9) — remove MealPlanBroadcaster from collaborators:

```ruby
# Owns all recipe-related Turbo Stream broadcasting: listings, ingredient tables,
# recipe pages, and cascading updates to cross-referencing parents. Wraps queries
# in ActsAsTenant.with_tenant since callers may lack controller tenant context.
# Also triggers a meal-plan page-refresh so groceries/menu pages stay in sync.
#
# - RecipeWriteService: sole caller for CRUD broadcasts
# - Turbo::StreamsChannel: transport layer for all stream pushes
```

**Step 3: Update RecipeBroadcaster test**

In `test/services/recipe_broadcaster_test.rb`, change `'broadcasts grocery morph via MealPlanBroadcaster'` (lines 34-38):

```ruby
test 'broadcasts meal plan refresh after recipe CRUD' do
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    RecipeBroadcaster.broadcast(kitchen: @kitchen, action: :updated, recipe_title: 'Focaccia')
  end
end
```

**Step 4: Update NutritionEntriesController test**

In `test/controllers/nutrition_entries_controller_test.rb`, find and update the two broadcast tests.

Change `'upsert broadcasts turbo stream morph when aisle is saved'`:

```ruby
test 'upsert broadcasts meal plan refresh when aisle is saved' do
  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
         params: { nutrients: { basis_grams: nil }, density: nil, portions: {}, aisle: 'Deli' },
```

(Keep the rest of the test body, just change the stream from `[@kitchen, 'groceries']` to `[@kitchen, :meal_plan_updates]` and the test name.)

Change `'destroy broadcasts turbo stream morph'`:

```ruby
test 'destroy broadcasts meal plan refresh' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour', basis_grams: 30, calories: 110)

  assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
    delete nutrition_entry_destroy_path('flour', kitchen_slug: kitchen_slug), as: :json
  end
```

**Step 5: Run tests**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb test/controllers/nutrition_entries_controller_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb app/services/recipe_broadcaster.rb test/services/recipe_broadcaster_test.rb test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: NutritionEntriesController and RecipeBroadcaster use page-refresh"
```

---

### Task 5: Delete MealPlanBroadcaster

**Files:**
- Delete: `app/services/meal_plan_broadcaster.rb`
- Delete: `test/services/meal_plan_broadcaster_test.rb`

**Step 1: Delete files**

```bash
rm app/services/meal_plan_broadcaster.rb test/services/meal_plan_broadcaster_test.rb
```

**Step 2: Verify no remaining references**

```bash
grep -r "MealPlanBroadcaster" app/ test/ lib/ --include="*.rb" --include="*.erb"
```

Expected: No matches. If any remain, update them.

**Step 3: Run full test suite**

Run: `rake test`
Expected: All tests pass with no `NameError: uninitialized constant MealPlanBroadcaster`

**Step 4: Commit**

```bash
git add -u
git commit -m "chore: delete MealPlanBroadcaster (replaced by page-refresh broadcasts)"
```

---

### Task 6: Preserve aisle collapse state during page-level morph

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

**Step 1: Add `turbo:before-render` listener for page-level morphs**

The current `turbo:before-stream-render` listener handles targeted stream morphs. Page-refresh broadcasts trigger a full Turbo Drive navigation, which fires `turbo:before-render` instead. Add a second listener.

In `app/javascript/controllers/grocery_ui_controller.js`, in the `connect()` method, after line 20:

```javascript
this.listeners.add(document, "turbo:before-render", (e) => this.preserveAisleStateOnRefresh(e))
```

Add the new method after `preserveAisleState`:

```javascript
preserveAisleStateOnRefresh(event) {
  if (!event.detail.render) return
  this.saveAisleCollapse()
  const originalRender = event.detail.render
  event.detail.render = async (...args) => {
    await originalRender(...args)
    this.restoreAisleCollapse()
  }
}
```

**Step 2: Update header comment**

Replace the header comment (lines 5-9):

```javascript
/**
 * Groceries page interaction — optimistic checkbox toggle, custom item input,
 * aisle collapse persistence. All rendering is server-side via Turbo page-refresh
 * morphs; this controller only handles user interactions and preserves local
 * state (aisle collapse) across morphs.
 */
```

**Step 3: Remove stale `turbo:before-stream-render` listener**

The groceries page no longer receives targeted stream broadcasts (it uses page-refresh now). Remove line 20:

```javascript
this.listeners.add(document, "turbo:before-stream-render", (e) => this.preserveAisleState(e))
```

And remove the `preserveAisleState` method (lines 155-163).

**Step 4: Run lint**

Run: `rake lint`
Expected: No offenses

**Step 5: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: preserve aisle collapse state during page-refresh morphs"
```

---

### Task 7: Update docs and run full suite

**Files:**
- Modify: `CLAUDE.md`
- Modify: `app/models/meal_plan.rb` (header comment references MealPlanBroadcaster)
- Modify: `app/services/shopping_list_builder.rb` (header comment references MealPlanBroadcaster)
- Modify: `app/services/recipe_availability_calculator.rb` (header comment references MealPlanBroadcaster)
- Modify: `app/channels/application_cable/channel.rb` (header comment references MealPlanBroadcaster)

**Step 1: Update CLAUDE.md**

In `CLAUDE.md`, replace the ActionCable paragraph (line 123):

```
**ActionCable.** Turbo Streams over Solid Cable, using `turbo_stream_from` tags in views. `MealPlanBroadcaster` pushes morph updates to groceries/menu pages; `RecipeBroadcaster` handles recipe CRUD streams. Broadcaster service objects wrap queries in `ActsAsTenant.with_tenant(kitchen)` since they lack controller tenant context.
```

with:

```
**ActionCable.** Turbo Streams over Solid Cable, using `turbo_stream_from` tags in views. Meal plan changes broadcast a page-refresh signal (`broadcast_refresh_to`) — each client re-fetches its own page and Turbo morphs the result. `RecipeBroadcaster` handles recipe CRUD streams with targeted broadcasts, plus triggers a meal-plan refresh. `RecipeBroadcaster` wraps queries in `ActsAsTenant.with_tenant(kitchen)` since it lacks controller tenant context.
```

**Step 2: Update header comments that reference MealPlanBroadcaster**

Search for all `MealPlanBroadcaster` references in header comments and update them:

In `app/models/meal_plan.rb`, update the header comment to reference page-refresh broadcasts instead of `MealPlanBroadcaster`.

In `app/services/shopping_list_builder.rb`, update the header comment to reference controllers/page-refresh instead of `MealPlanBroadcaster`.

In `app/services/recipe_availability_calculator.rb`, update the header comment to reference `MenuController` instead of `MealPlanBroadcaster`.

In `app/channels/application_cable/channel.rb`, update the header comment to reference page-refresh broadcasts instead of `MealPlanBroadcaster`.

**Step 3: Run full suite**

Run: `rake`
Expected: All tests pass, no lint offenses

**Step 4: Commit**

```bash
git add CLAUDE.md app/models/meal_plan.rb app/services/shopping_list_builder.rb app/services/recipe_availability_calculator.rb app/channels/application_cable/channel.rb
git commit -m "docs: update references from MealPlanBroadcaster to page-refresh broadcasts (gh-171)"
```

**Step 5: Verify no stale references remain**

```bash
grep -r "MealPlanBroadcaster" . --include="*.rb" --include="*.erb" --include="*.js" --include="*.md" | grep -v "docs/plans/" | grep -v "vendor/"
```

Expected: No matches (design docs excluded).

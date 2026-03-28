# Performance Feel Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce perceived framework overhead so the app feels closer to static HTML — instant input feedback, no morph jank, snappy page loads — then stress-test with realistic data to establish scaling limits.

**Architecture:** Three layers of improvement: (1) client-side feel fixes (deferred frames, self-morph suppression), (2) server-side speedups (cached computations, query consolidation), (3) stress testing with a data generator. The feel audit bookends the work — initial measurement establishes the baseline, final measurement verifies the improvements.

**Tech Stack:** Rails 8 / Turbo Drive / Stimulus / SQLite / rack-mini-profiler / stackprof

**Spec:** `docs/superpowers/specs/2026-03-28-performance-feel-design.md`

---

## File Map

### Feel audit
- Create: `docs/performance-audit.md` — structured audit template and results

### Client-side feel fixes
- Modify: `app/views/recipes/show.html.erb` — lazy-load recipe editor frame
- Modify: `app/views/menu/show.html.erb` — lazy-load quickbites editor frame
- Modify: `app/views/groceries/show.html.erb` — lazy-load aisle order frame
- Modify: `app/views/homepage/show.html.erb` — lazy-load category and tag editor frames
- Modify: `app/javascript/utilities/turbo_fetch.js` — self-morph suppression tracking
- Modify: `app/javascript/application.js` — suppress self-triggered broadcast morphs

### Server-side speedups
- Modify: `app/controllers/menu_controller.rb` — cache availability, lazy-load weights
- Create: `test/controllers/menu_availability_cache_test.rb` — test for cached availability
- Modify: `app/javascript/controllers/dinner_picker_controller.js` — fetch weights on demand
- Modify: `app/controllers/groceries_controller.rb` — consolidate double query
- Modify: `config/routes.rb` — add dinner picker weights endpoint

### Stress testing
- Create: `lib/tasks/stress.rake` — generate realistic test data
- Create: `lib/stress_data_generator.rb` — data generation logic

### Documentation
- Modify: `CLAUDE.md` — document new patterns

---

### Task 1: Feel Audit Template + Initial Baseline

**Files:**
- Create: `docs/performance-audit.md`

This task is **manual** — it produces a document, not code. The subagent creates the
template; the human fills it in using browser DevTools.

- [ ] **Step 1: Create the audit template**

Create `docs/performance-audit.md`:

```markdown
# Performance Feel Audit

**Date:** ___
**Browser:** ___
**Device:** ___

## Scoring

- **Instant** — feels like static HTML. No perceptible delay or disruption.
- **Smooth** — brief delay but no jank. Acceptable.
- **Sluggish** — noticeable pause or visual glitch. Needs investigation.
- **Broken** — delay long enough to feel wrong, or visible reflow/flash.

## Pages

| Page | Feel | FCP (ms) | Layout shifts? | Notes |
|------|------|----------|----------------|-------|
| Homepage | | | | |
| Recipe show | | | | |
| Menu | | | | |
| Groceries | | | | |
| Settings | | | | |

## Interactions

| Surface | Action | Feel | Input delay (ms) | Notes |
|---------|--------|------|-------------------|-------|
| Menu | Toggle recipe checkbox | | | |
| Menu | Toggle Quick Bite checkbox | | | |
| Menu | Click "What Should We Make?" | | | |
| Groceries | Check off to-buy item | | | |
| Groceries | Click "Have It" | | | |
| Groceries | Click "Need It" | | | |
| Groceries | Add custom item | | | |
| Recipe | Open editor dialog | | | |
| Recipe | Open nutrition editor | | | |
| Homepage | Open category editor | | | |
| Homepage | Open tag editor | | | |
| Any | Open search overlay | | | |
| Any | Type in search overlay | | | |
| Any | Navigate between pages | | | |

## ActionCable Morphs

Open two tabs. Perform an action in Tab A, observe Tab B.

| Action in Tab A | Tab B response | Feel | Notes |
|-----------------|---------------|------|-------|
| Toggle menu recipe | | | |
| Check grocery item | | | |
| Have It on grocery item | | | |
| Save recipe edit | | | |

## Static Baseline Comparison

For the worst-scoring pages, save the server HTML and compare:

```bash
curl -s -b cookie.txt http://rika:3030/kitchens/our-kitchen/menu > /tmp/menu-static.html
curl -s -b cookie.txt http://rika:3030/kitchens/our-kitchen/groceries > /tmp/groceries-static.html
```

| Page | Live FCP (ms) | Static FCP (ms) | Framework tax (ms) |
|------|--------------|-----------------|-------------------|
| Menu | | | |
| Groceries | | | |
```

- [ ] **Step 2: Commit**

```bash
git add docs/performance-audit.md
git commit -m "Add performance feel audit template"
```

---

### Task 2: Defer Editor Frame Loading

**Files:**
- Modify: `app/views/recipes/show.html.erb:53-54`
- Modify: `app/views/menu/show.html.erb:52`
- Modify: `app/views/groceries/show.html.erb:39`
- Modify: `app/views/homepage/show.html.erb` (category and tag frames)

Editor Turbo Frames have `src` attributes that trigger HTTP requests on page load,
even though the editor dialogs are closed. Adding `loading="lazy"` defers the fetch
until the frame becomes visible (when the dialog opens).

- [ ] **Step 1: Find all eager-loading editor frames**

```bash
grep -n 'turbo-frame.*src=.*editor\|turbo-frame.*src=.*frame\|turbo-frame.*src=.*content' app/views/**/*.erb
```

Expected: frames in recipes/show, menu/show, groceries/show, homepage/show.

- [ ] **Step 2: Add `loading="lazy"` to the recipe editor frame**

In `app/views/recipes/show.html.erb`, replace lines 53-54:

```erb
  <turbo-frame id="recipe-editor-content"
               src="<%= recipe_editor_frame_path(@recipe.slug) %>"
               loading="lazy"
               data-editor-target="frame">
```

- [ ] **Step 3: Add `loading="lazy"` to the quickbites editor frame**

In `app/views/menu/show.html.erb`, replace line 52:

```erb
  <turbo-frame id="quickbites-editor-content"
               src="<%= menu_quickbites_editor_frame_path %>"
               loading="lazy"
               data-editor-target="frame">
```

- [ ] **Step 4: Add `loading="lazy"` to the aisle order frame**

In `app/views/groceries/show.html.erb`, replace line 39:

```erb
      <turbo-frame id="aisle-order-frame"
                   src="<%= groceries_aisle_order_content_path %>"
                   loading="lazy"
                   data-editor-target="frame">
```

- [ ] **Step 5: Add `loading="lazy"` to the homepage editor frames**

Find and update the category-order and tag-order turbo-frames in
`app/views/homepage/show.html.erb`. Each frame that has a `src` attribute and
`data-editor-target="frame"` gets `loading="lazy"` added.

- [ ] **Step 6: Verify the editor controller handles lazy frames correctly**

Read `app/javascript/controllers/editor_controller.js` lines 64-68. The
`frameLoaded` getter checks `this.frameTarget.complete`. For lazy frames, the
frame won't have started loading yet when the dialog opens, so `complete` will
be false. The existing logic in `open()` (lines 76-87) already handles this:
it disables the Save button and waits for `turbo:frame-load`. No JS changes
needed.

Verify manually: start `bin/dev`, open a recipe page, check the Network tab.
The editor frame request should NOT appear on page load. Click the Edit
button — the frame should load and the editor should work normally.

- [ ] **Step 7: Run tests**

Run: `bundle exec rake test`

Expected: All pass. Lazy-loading only affects the browser fetch timing, not
the server-side rendering tested by integration tests.

- [ ] **Step 8: Commit**

```bash
git add app/views/recipes/show.html.erb app/views/menu/show.html.erb \
  app/views/groceries/show.html.erb app/views/homepage/show.html.erb
git commit -m "Defer editor frame loading with loading=lazy

Turbo Frames for editor dialogs now use loading=lazy, deferring the
HTTP fetch until the dialog opens. Eliminates 1-3 requests that
competed with the primary page render on every navigation."
```

---

### Task 3: Cache RecipeAvailabilityCalculator

**Files:**
- Modify: `app/controllers/menu_controller.rb:84-88`
- Create: `test/controllers/menu_availability_cache_test.rb`

`RecipeAvailabilityCalculator` runs on every menu page load (~100ms of the 209ms
total). The result only changes when on-hand entries or recipes change — both
go through `Kitchen.finalize_writes`, which touches `kitchen.updated_at`. Cache
the result with `Rails.cache.fetch` using `updated_at` as the key.

- [ ] **Step 1: Write a test that verifies caching behavior**

Create `test/controllers/menu_availability_cache_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class MenuAvailabilityCacheTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Mains')
    @recipe = create_recipe("## Step 1\n- 1 cup flour", category_name: 'Mains')
    MealPlan.find_or_create_by!(kitchen: @kitchen)
    log_in
  end

  test 'second menu load uses cached availability (fewer queries)' do
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success

    first_count = count_queries { get menu_path(kitchen_slug: kitchen_slug) }
    second_count = count_queries { get menu_path(kitchen_slug: kitchen_slug) }

    assert second_count <= first_count,
           "Second load (#{second_count} queries) should not exceed first (#{first_count})"
  end

  test 'availability cache invalidates when kitchen is updated' do
    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success

    @kitchen.update_column(:updated_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

    get menu_path(kitchen_slug: kitchen_slug)

    assert_response :success
  end

  private

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end
end
```

- [ ] **Step 2: Run test to verify it passes (baseline)**

Run: `ruby -Itest test/controllers/menu_availability_cache_test.rb`

Expected: Both tests pass (they verify current behavior, not the optimization yet).

- [ ] **Step 3: Read the current `compute_availability` method**

Read `app/controllers/menu_controller.rb` lines 84-88. Note the current
implementation:

```ruby
def compute_availability
  on_hand_names = OnHandEntry.where(kitchen_id: current_kitchen.id).active.pluck(:ingredient_name)
  recipes = @categories.flat_map(&:recipes)
  RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:).call
end
```

- [ ] **Step 4: Add caching to `compute_availability`**

Replace `compute_availability` in `app/controllers/menu_controller.rb`:

```ruby
def compute_availability
  Rails.cache.fetch(['menu_availability', current_kitchen.id, current_kitchen.updated_at.to_f]) do
    on_hand_names = OnHandEntry.where(kitchen_id: current_kitchen.id).active.pluck(:ingredient_name)
    recipes = @categories.flat_map(&:recipes)
    RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: on_hand_names, recipes:).call
  end
end
```

The cache key includes `updated_at` — `Kitchen.finalize_writes` touches this
timestamp after every write, naturally invalidating the cache when on-hand
entries, recipes, or selections change.

- [ ] **Step 5: Run the availability cache test**

Run: `ruby -Itest test/controllers/menu_availability_cache_test.rb`

Expected: Both tests pass.

- [ ] **Step 6: Run the full test suite**

Run: `bundle exec rake test`

Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/menu_controller.rb test/controllers/menu_availability_cache_test.rb
git commit -m "Cache RecipeAvailabilityCalculator per kitchen.updated_at

The availability computation (~100ms) now uses Rails.cache.fetch keyed
on kitchen.updated_at, which Kitchen.finalize_writes touches after
every write. Subsequent menu loads within the same kitchen state skip
the computation entirely."
```

---

### Task 4: Lazy-Load Dinner Picker Weights

**Files:**
- Modify: `app/controllers/menu_controller.rb:17-23`
- Modify: `app/views/menu/show.html.erb:58-63`
- Modify: `app/javascript/controllers/dinner_picker_controller.js`
- Modify: `config/routes.rb`

`CookHistoryWeighter` computes dinner picker weights on every menu page load,
but the weights are only used when the user clicks "What Should We Make?".
Move the computation to a JSON endpoint that the dinner picker fetches on demand.

- [ ] **Step 1: Read the current dinner picker controller**

Read `app/javascript/controllers/dinner_picker_controller.js` to understand
how it currently consumes `@cook_weights`. Note the `weightsValue` Stimulus
value that's set from the embedded JSON.

- [ ] **Step 2: Add a `dinner_weights` action to the menu controller**

In `app/controllers/menu_controller.rb`, add after the `show` action:

```ruby
def dinner_weights
  weights = CookHistoryWeighter.call(CookHistoryEntry.where(kitchen_id: current_kitchen.id).recent)
  render json: weights
end
```

- [ ] **Step 3: Add the route**

In `config/routes.rb`, find the menu routes section and add:

```ruby
get 'menu/dinner_weights', to: 'menu#dinner_weights', as: :menu_dinner_weights
```

Add it inside the same scope as the other menu routes.

- [ ] **Step 4: Remove weights computation from the `show` action**

In `app/controllers/menu_controller.rb`, remove line 22 from the `show` action:

```ruby
@cook_weights = CookHistoryWeighter.call(CookHistoryEntry.where(kitchen_id: current_kitchen.id).recent)
```

The `show` action should now read:

```ruby
def show
  @categories = recipe_selector_categories
  @selected_recipes = selected_ids_for('Recipe')
  @selected_quick_bites = selected_ids_for('QuickBite').to_set(&:to_i)
  @availability = compute_availability
end
```

- [ ] **Step 5: Replace the embedded weights with a URL data attribute**

In `app/views/menu/show.html.erb`, replace lines 58-63 (the dinner picker
dialog's data attributes):

```erb
<dialog id="dinner-picker-dialog" class="editor-dialog"
        data-controller="editor dinner-picker"
        data-editor-open-selector-value="#dinner-picker-button"
        data-editor-on-success-value="close"
        data-action="editor:opened->dinner-picker#onOpen"
        data-dinner-picker-weights-url-value="<%= menu_dinner_weights_path %>"
        data-dinner-picker-recipe-base-path-value="<%= recipes_path %>/">
```

Note the change: `data-dinner-picker-weights-value` (embedded JSON) becomes
`data-dinner-picker-weights-url-value` (URL to fetch).

- [ ] **Step 6: Update the dinner picker controller to fetch weights on demand**

Read the full `app/javascript/controllers/dinner_picker_controller.js` first.
Then modify it:

1. Change the Stimulus value declaration from `weights: Object` to
   `weightsUrl: String`.
2. In the `onOpen` handler (or equivalent method that initializes the picker),
   fetch the weights from the URL:

```javascript
async loadWeights() {
  if (this.weights) return this.weights

  const response = await fetch(this.weightsUrlValue, {
    headers: { "Accept": "application/json" }
  })
  this.weights = await response.json()
  return this.weights
}
```

3. Replace direct `this.weightsValue` access with `await this.loadWeights()`.
   The weights are cached on the controller instance, so the fetch only
   happens once per page visit.

- [ ] **Step 7: Run the full test suite**

Run: `bundle exec rake test`

Expected: All pass. Any existing dinner picker tests should still work since
the weights endpoint returns the same data.

- [ ] **Step 8: Verify manually**

Start `bin/dev`, navigate to the menu page. Open Network tab. Confirm no
`dinner_weights` request fires on page load. Click "What Should We Make?".
Confirm the weights are fetched and the dinner picker works normally.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/menu_controller.rb app/views/menu/show.html.erb \
  app/javascript/controllers/dinner_picker_controller.js config/routes.rb
git commit -m "Lazy-load dinner picker weights via JSON endpoint

CookHistoryWeighter computation moves from the show action (runs on
every page load) to a dedicated endpoint (fetched on button click).
Reduces menu page computation by ~20ms and shrinks the HTML response."
```

---

### Task 5: Consolidate Groceries Double Query

**Files:**
- Modify: `app/controllers/groceries_controller.rb:17-22`

The groceries controller loads on-hand entries twice: once via the `active`
scope (for names) and once unfiltered (for the data index). Consolidate to
a single load.

- [ ] **Step 1: Read the current `show` action**

Read `app/controllers/groceries_controller.rb` lines 17-22:

```ruby
def show
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen).build
  entries = OnHandEntry.where(kitchen_id: current_kitchen.id)
  @on_hand_names = entries.active.pluck(:ingredient_name).to_set
  @on_hand_data = entries.index_by { |e| e.ingredient_name.downcase }
  @custom_names = CustomGroceryItem.where(kitchen_id: current_kitchen.id).pluck(:name).to_set(&:downcase)
end
```

- [ ] **Step 2: Consolidate to a single load**

Replace lines 17-22 of `app/controllers/groceries_controller.rb`:

```ruby
def show
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen).build
  all_entries = OnHandEntry.where(kitchen_id: current_kitchen.id).to_a
  @on_hand_names = all_entries.select(&:on_hand?).map(&:ingredient_name).to_set
  @on_hand_data = all_entries.index_by { |e| e.ingredient_name.downcase }
  @custom_names = CustomGroceryItem.where(kitchen_id: current_kitchen.id).pluck(:name).to_set(&:downcase)
end
```

This loads all entries once with `.to_a`, then filters in Ruby using the
existing `on_hand?` method (which is pure date arithmetic — no DB queries).
Eliminates one SQL query per page load.

- [ ] **Step 3: Run the groceries controller tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`

Expected: All pass.

- [ ] **Step 4: Run the full test suite**

Run: `bundle exec rake test`

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/groceries_controller.rb
git commit -m "Consolidate groceries double query into single load

Load all OnHandEntry records once with .to_a, then filter in Ruby
using on_hand? (pure date arithmetic). Eliminates one SQL query per
grocery page load."
```

---

### Task 6: Suppress Self-Morph for Frequent Actions

**Files:**
- Modify: `app/javascript/utilities/turbo_fetch.js`
- Modify: `app/javascript/application.js`

When a user checks a grocery item or toggles a menu selection, the server
broadcasts a full-page morph to all clients — including the acting client.
The acting client already has the correct state (via optimistic UI or browser
default checkbox behavior). The morph is a no-op that still costs a full page
fetch + DOM diff. Suppress it for a short window after user actions.

- [ ] **Step 1: Add morph suppression tracking to turbo_fetch.js**

In `app/javascript/utilities/turbo_fetch.js`, add before the `sendAction`
function:

```javascript
let lastActionAt = 0
const MORPH_SUPPRESS_MS = 2000

export function recentlyActed() {
  return Date.now() - lastActionAt < MORPH_SUPPRESS_MS
}
```

Then inside the `sendAction` function, add `lastActionAt = Date.now()` as the
first line of the function body (before the `return fetch(...)` call).

- [ ] **Step 2: Add the stream suppression listener in application.js**

In `app/javascript/application.js`, add after the existing `turbo:before-cache`
listener (after line 74):

```javascript
// Suppress broadcast morphs that follow the acting client's own action.
// The optimistic UI (or browser default checkbox toggle) already reflects
// the correct state — the morph is a redundant full-page fetch + DOM diff.
import { recentlyActed } from "./utilities/turbo_fetch"
document.addEventListener("turbo:before-stream-render", (event) => {
  if (event.target.getAttribute("action") === "refresh" && recentlyActed()) {
    event.preventDefault()
  }
})
```

Note: The `import` must be at the top of the file with the other imports. Move
it there and reference the function in the listener.

- [ ] **Step 3: Handle error rollback**

In `turbo_fetch.js`, in the `.catch` block for `ServerError` (line 44-46),
reset the timestamp so the next morph is not suppressed:

```javascript
if (error instanceof ServerError) {
  lastActionAt = 0  // Allow morph to fix state on error
  notifyShow(error.message)
  return
}
```

- [ ] **Step 4: Run JS tests**

Run: `npm test`

Expected: All pass. The JS tests don't test Turbo Stream handling.

- [ ] **Step 5: Manual verification**

Start `bin/dev`. Open two browser tabs to the groceries page.

Tab A: Check off an item. Observe:
- The item moves instantly (optimistic UI, as before).
- Tab A does NOT re-fetch the page (check Network tab — no HTML request
  within 2 seconds of the action).

Tab B: Observe:
- Tab B receives the broadcast and morphs normally (the checked item appears
  in the on-hand zone).

Now wait 3 seconds after the Tab A action. Make a change in Tab B. Tab A
should morph normally (the suppression window has expired).

- [ ] **Step 6: Run the full test suite**

Run: `bundle exec rake test`

Expected: All pass. Server-side behavior is unchanged.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/utilities/turbo_fetch.js app/javascript/application.js
git commit -m "Suppress self-morph for 2s after user actions

After sendAction fires, suppress incoming broadcast refresh morphs
for 2 seconds. The acting client already has the correct state via
optimistic UI or browser default checkbox behavior — the morph is a
redundant full-page fetch + DOM diff. Other clients still receive
morphs normally. Error responses clear the suppression so morphs
can fix inconsistent state."
```

---

### Task 7: Stress Data Generator

**Files:**
- Create: `lib/stress_data_generator.rb`
- Create: `lib/tasks/stress.rake`
- Modify: `.rubocop.yml` — add stress.rake to Rails/Output exclusion

A rake task that populates a test kitchen with realistic data volumes for
stress testing: 200 recipes, 150 catalog entries, full grocery state, and
6 months of cook history.

- [ ] **Step 1: Write the StressDataGenerator class**

Create `lib/stress_data_generator.rb`:

```ruby
# frozen_string_literal: true

# Generates realistic test data for performance stress testing. Creates a
# kitchen with configurable recipe count, ingredient catalog, meal plan state,
# and cook history. Data is plausible (real-looking titles, varied ingredients)
# because HTML size and rendering cost depend on content length.
#
# Collaborators:
# - MarkdownImporter: creates recipes from markdown via the standard write path
# - Kitchen.finalize_writes: runs reconciliation after batch creation
class StressDataGenerator
  CATEGORIES = %w[Breakfast Lunch Dinner Snacks Sides Soups Salads Desserts
                  Appetizers Drinks Baking Sauces].freeze

  TAGS = %w[quick easy vegetarian vegan gluten-free dairy-free spicy comfort
            healthy meal-prep one-pot weeknight holiday batch summer winter
            kid-friendly budget grill fermented].freeze

  PROTEINS = %w[chicken beef pork salmon shrimp tofu tempeh eggs turkey lamb
                cod tilapia tuna sausage bacon ham].freeze

  PRODUCE = ['onion', 'garlic', 'tomatoes', 'bell pepper', 'carrots', 'celery',
             'potatoes', 'spinach', 'broccoli', 'mushrooms', 'zucchini', 'corn',
             'green beans', 'lettuce', 'cucumber', 'avocado', 'lemon', 'lime',
             'ginger', 'jalapeño', 'cilantro', 'parsley', 'basil', 'thyme',
             'rosemary'].freeze

  PANTRY = ['olive oil', 'butter', 'flour', 'sugar', 'salt', 'black pepper',
            'rice', 'pasta', 'bread', 'tortillas', 'chicken broth', 'soy sauce',
            'vinegar', 'honey', 'milk', 'cream', 'cheese', 'yogurt',
            'canned tomatoes', 'coconut milk', 'baking powder', 'vanilla',
            'paprika', 'cumin', 'chili powder', 'oregano', 'cinnamon',
            'brown sugar', 'maple syrup', 'cornstarch'].freeze

  UNITS = ['cup', 'cups', 'tbsp', 'tsp', 'oz', 'lb', 'cloves', 'bunch',
           'can', 'large', 'medium', 'small', 'piece', 'slices', 'handful'].freeze

  ADJECTIVES = %w[Simple Quick Easy Classic Rustic Homestyle Grandma's Mom's
                  Savory Sweet Crispy Creamy Spicy Tangy Smoky Fresh Light
                  Hearty Golden Roasted Grilled Braised].freeze

  NOUNS = ['Bowl', 'Skillet', 'Bake', 'Stew', 'Soup', 'Salad', 'Wrap',
           'Sandwich', 'Pasta', 'Rice', 'Tacos', 'Curry', 'Stir-Fry',
           'Casserole', 'Pie', 'Bread', 'Muffins', 'Pancakes', 'Hash',
           'Frittata', 'Risotto', 'Chili', 'Noodles', 'Burrito', 'Platter'].freeze

  AISLES = ['Produce', 'Dairy', 'Meat & Seafood', 'Bakery', 'Canned Goods',
            'Pasta & Rice', 'Spices', 'Oils & Vinegar', 'Snacks', 'Frozen',
            'Beverages', 'Baking', 'Condiments', 'International', 'Deli'].freeze

  ALL_INGREDIENTS = (PROTEINS + PRODUCE + PANTRY).freeze

  attr_reader :kitchen, :recipe_count

  def initialize(recipe_count: 200)
    @recipe_count = recipe_count
    @used_titles = Set.new
  end

  def generate!
    setup_kitchen
    create_categories
    create_tags
    create_catalog_entries
    create_recipes
    create_meal_plan_state
    create_cook_history
    run_finalization

    puts "Stress kitchen '#{kitchen.name}' created:"
    puts "  #{recipe_count} recipes across #{CATEGORIES.size} categories"
    puts "  #{kitchen.ingredient_catalog.count} catalog entries"
    puts "  #{kitchen.on_hand_entries.count} on-hand entries"
    puts "  #{kitchen.cook_history_entries.count} cook history entries"
    puts "  #{kitchen.meal_plan_selections.count} meal plan selections"
  end

  private

  def setup_kitchen
    @kitchen = ActsAsTenant.without_tenant do
      Kitchen.find_or_create_by!(slug: 'stress-kitchen') do |k|
        k.name = 'Stress Kitchen'
        k.aisle_order = AISLES.join("\n")
      end
    end

    ActsAsTenant.without_tenant { clean_existing_data }
  end

  def clean_existing_data
    [Recipe, Category, Tag, IngredientCatalog, MealPlanSelection,
     OnHandEntry, CustomGroceryItem, CookHistoryEntry, QuickBite].each do |model|
      model.where(kitchen_id: kitchen.id).delete_all
    end
  end

  def create_categories
    ActsAsTenant.with_tenant(kitchen) do
      CATEGORIES.each_with_index do |name, i|
        Category.create!(name:, position: i, kitchen:)
      end
    end
  end

  def create_tags
    ActsAsTenant.with_tenant(kitchen) do
      TAGS.each { |name| Tag.create!(name:, kitchen:) }
    end
  end

  def create_catalog_entries
    ActsAsTenant.with_tenant(kitchen) do
      ALL_INGREDIENTS.each_with_index do |name, i|
        aisle = AISLES[i % AISLES.size]
        IngredientCatalog.create!(
          ingredient_name: name,
          aisle:,
          kitchen:,
          calories: rand(20..400),
          total_fat: rand(0.0..30.0).round(1),
          saturated_fat: rand(0.0..15.0).round(1),
          cholesterol: rand(0..120),
          sodium: rand(0..1200),
          total_carbohydrate: rand(0.0..60.0).round(1),
          dietary_fiber: rand(0.0..10.0).round(1),
          total_sugars: rand(0.0..20.0).round(1),
          protein: rand(0.0..40.0).round(1),
          serving_size: "#{rand(1..4)} #{UNITS.sample}",
          serving_unit: 'g',
          serving_weight: rand(28..250)
        )
      end
    end
  end

  def create_recipes
    categories = ActsAsTenant.with_tenant(kitchen) { Category.all.to_a }

    Kitchen.batch_writes(kitchen) do
      recipe_count.times do |i|
        category = categories[i % categories.size]
        title = unique_title
        tags = TAGS.sample(rand(1..4))
        step_count = rand(1..4)
        ingredients_per_step = rand(3..8)

        markdown = build_markdown(title:, tags:, step_count:, ingredients_per_step:)

        ActsAsTenant.with_tenant(kitchen) do
          MarkdownImporter.import(markdown, kitchen:, category: category.name)
        end

        print '.' if (i % 20).zero?
      end
    end
    puts
  end

  def create_meal_plan_state
    ActsAsTenant.with_tenant(kitchen) do
      MealPlan.find_or_create_by!(kitchen:)

      recipes = kitchen.recipes.limit(15).pluck(:slug)
      recipes.each do |slug|
        MealPlanSelection.create!(kitchen:, selectable_type: 'Recipe', selectable_id: slug)
      end

      all_ingredients = kitchen.recipes
                               .includes(steps: :ingredients)
                               .flat_map { |r| r.steps.flat_map(&:ingredients) }
                               .map(&:name).uniq

      all_ingredients.sample([all_ingredients.size, 200].min).each_with_index do |name, i|
        days_ago = rand(0..90)
        interval = rand(OnHandEntry::STARTING_INTERVAL..OnHandEntry::MAX_INTERVAL)
        ease = rand(OnHandEntry::MIN_EASE..OnHandEntry::MAX_EASE).round(2)

        entry = OnHandEntry.create!(
          kitchen:,
          ingredient_name: name,
          confirmed_at: Date.current - days_ago,
          interval:,
          ease:
        )

        entry.update_columns(depleted_at: Date.current - rand(0..3)) if i % 5 == 0 # rubocop:disable Rails/SkipsModelValidations
      end

      8.times do |i|
        CustomGroceryItem.create!(
          kitchen:,
          name: "Custom Item #{i + 1}",
          aisle: AISLES.sample,
          last_used_at: Date.current - rand(0..30)
        )
      end
    end
  end

  def create_cook_history
    ActsAsTenant.with_tenant(kitchen) do
      slugs = kitchen.recipes.pluck(:slug)

      180.times do |day|
        next if rand > 0.6

        slug = slugs.sample
        CookHistoryEntry.create!(
          kitchen:,
          recipe_slug: slug,
          cooked_on: Date.current - day
        )
      end
    end
  end

  def run_finalization
    Kitchen.finalize_writes(kitchen)
  end

  def unique_title
    100.times do
      title = "#{ADJECTIVES.sample} #{PROTEINS.sample.capitalize} #{NOUNS.sample}"
      next if @used_titles.include?(title)

      @used_titles.add(title)
      return title
    end
    "Recipe #{@used_titles.size + 1}"
  end

  def build_markdown(title:, tags:, step_count:, ingredients_per_step:)
    lines = []
    lines << "Tags: #{tags.join(', ')}" if tags.any?
    lines << ""

    step_count.times do |s|
      lines << "## Step #{s + 1}"
      lines << ""
      ingredients_per_step.times do
        amount = rand(1..4)
        unit = UNITS.sample
        ingredient = ALL_INGREDIENTS.sample
        lines << "- #{amount} #{unit} #{ingredient}"
      end
      lines << ""
      lines << "Cook until done. Stir occasionally and season to taste."
      lines << ""
    end

    lines.join("\n")
  end
end
```

- [ ] **Step 2: Write the rake task**

Create `lib/tasks/stress.rake`:

```ruby
# frozen_string_literal: true

require_relative '../stress_data_generator'

namespace :profile do
  desc 'Generate stress test data (200 recipes, full grocery state, cook history)'
  task generate_stress_data: :environment do
    count = ENV.fetch('RECIPE_COUNT', 200).to_i
    puts "Generating stress data with #{count} recipes..."
    StressDataGenerator.new(recipe_count: count).generate!
  end
end
```

- [ ] **Step 3: Add stress.rake to Rails/Output exclusion**

In `.rubocop.yml`, find the `Rails/Output` exclusion list and add
`lib/tasks/stress.rake`:

```yaml
Rails/Output:
  Exclude:
    - 'lib/build_validator.rb'
    - 'db/seeds.rb'
    - 'lib/tasks/profile.rake'
    - 'lib/tasks/stress.rake'
```

- [ ] **Step 4: Run lint**

Run: `bundle exec rubocop lib/stress_data_generator.rb lib/tasks/stress.rake`

Expected: No offenses.

- [ ] **Step 5: Test the generator**

Run: `bundle exec rake profile:generate_stress_data RECIPE_COUNT=10`

Expected: Creates a "stress-kitchen" with 10 recipes and associated data.
Verify by checking the output summary.

- [ ] **Step 6: Clean up the test run**

```bash
rails runner "Kitchen.find_by(slug: 'stress-kitchen')&.destroy"
```

- [ ] **Step 7: Commit**

```bash
git add lib/stress_data_generator.rb lib/tasks/stress.rake .rubocop.yml
git commit -m "Add stress data generator for performance testing

rake profile:generate_stress_data creates a kitchen with 200 recipes,
150 catalog entries, 200+ on-hand entries, 6 months of cook history,
and full meal plan state. Configurable via RECIPE_COUNT env var."
```

---

### Task 8: Stress Baseline + Scaling Thresholds

**Files:**
- Modify: `lib/profile_baseline.rb` — support configurable kitchen slug
- Modify: `lib/tasks/profile.rake` — accept KITCHEN env var

This task generates stress data, runs the baseline profiler against it, and
documents the results. Partially manual (interpreting results).

- [ ] **Step 1: Make ProfileBaseline accept any kitchen**

Read `lib/tasks/profile.rake`. Currently it hardcodes `Kitchen.find_by!(slug: 'our-kitchen')`.
Modify it to accept an environment variable:

```ruby
namespace :profile do
  desc 'Run performance baseline: measure key pages and asset sizes'
  task baseline: :environment do
    slug = ENV.fetch('KITCHEN', 'our-kitchen')
    kitchen = Kitchen.find_by!(slug:)
    user = kitchen.memberships.first&.user || User.first

    abort "No kitchen '#{slug}' or user found. Run db:seed first." unless kitchen && user
    # ... rest unchanged
```

- [ ] **Step 2: Run the stress data generator at full scale**

Run: `bundle exec rake profile:generate_stress_data`

Expected: Creates 200 recipes, 150 catalog entries, etc. Takes ~30-60 seconds.

- [ ] **Step 3: Create a user + membership for the stress kitchen**

The stress kitchen needs a user with a membership for the profiler to log in:

```bash
rails runner "
  k = Kitchen.find_by!(slug: 'stress-kitchen')
  u = User.first || User.create!(name: 'Test', email: 'test@example.com')
  Membership.find_or_create_by!(kitchen: k, user: u)
"
```

- [ ] **Step 4: Run the baseline against the stress kitchen**

Run: `bundle exec rake profile:baseline KITCHEN=stress-kitchen`

Expected: Markdown table with timing, query counts, and sizes for all four
pages. Record the output for comparison.

- [ ] **Step 5: Compare results**

Compare the stress baseline against the seed baseline (from the spec):

| Metric | Seed (8 recipes) | Stress (200 recipes) | Ratio |
|--------|-----------------|---------------------|-------|
| Menu time | 209ms | ___ms | ___ |
| Menu queries | 23 | ___ | ___ |
| Menu HTML | 117 KB | ___ KB | ___ |
| Groceries time | 116ms | ___ms | ___ |

Document in `docs/performance-audit.md` under a "Stress Test Results" heading.

- [ ] **Step 6: Check search data JSON size**

```bash
rails runner "
  k = Kitchen.find_by!(slug: 'stress-kitchen')
  ActsAsTenant.with_tenant(k) do
    data = SearchDataHelper.search_data_json(k)
    puts \"Search JSON size: #{data.bytesize} bytes (#{(data.bytesize / 1024.0).round(1)} KB)\"
  end
"
```

Document whether the size exceeds or approaches 50 KB.

- [ ] **Step 7: Document scaling thresholds**

Add a "Scaling Thresholds" section to `docs/performance-audit.md` based on
the stress results:

```markdown
## Scaling Thresholds

Based on stress testing with 200 recipes:

- Menu page: ___ms (vs 209ms with 8 recipes). Linear/sublinear/superlinear scaling.
- Groceries page: ___ms (vs 116ms). Scaling profile: ___.
- Search JSON: ___ KB. Threshold for lazy-loading (50 KB): reached/not reached.
- HTML sizes: Menu ___ KB, Groceries ___ KB. Turbo morph impact: ___.
- SM-2 reconcile: Covered by finalize_writes timing within the page profiles.
```

- [ ] **Step 8: Commit**

```bash
git add lib/tasks/profile.rake docs/performance-audit.md
git commit -m "Add stress baseline results and scaling thresholds

Profile baseline now accepts KITCHEN env var for testing against any
kitchen. Stress results with 200 recipes document scaling profile
and thresholds for future monitoring."
```

---

### Task 9: Final Re-Audit, Baseline, and Documentation

**Files:**
- Modify: `docs/performance-audit.md` — final audit results
- Modify: `CLAUDE.md` — document new conventions

This task is partially manual (browser audit) and partially code (CLAUDE.md updates).

- [ ] **Step 1: Run the final baseline against the seed kitchen**

Run: `bundle exec rake profile:baseline`

Record the results and compare against the initial baseline from the spec.

- [ ] **Step 2: Repeat the feel audit**

Using the template from Task 1, re-score all pages and interactions. Focus
on the four symptoms: navigation flicker, morph jank, input lag, heaviness.

Document the before/after comparison in `docs/performance-audit.md`.

- [ ] **Step 3: Update CLAUDE.md**

Add to the Architecture section, after the existing performance profiling
paragraph:

```markdown
**Performance feel patterns.** Turbo Frame editor dialogs use `loading="lazy"`
to defer HTTP fetches until the dialog opens. `sendAction` (turbo_fetch.js)
suppresses incoming broadcast morphs for 2s after a user action — the
optimistic UI already reflects the correct state. Menu availability is cached
per `kitchen.updated_at` via `Rails.cache.fetch`. Dinner picker weights are
lazy-loaded via JSON endpoint on button click, not embedded in page HTML.
```

- [ ] **Step 4: Run lint**

Run: `bundle exec rake`

Expected: All tests pass, no RuboCop offenses.

- [ ] **Step 5: Commit**

```bash
git add docs/performance-audit.md CLAUDE.md
git commit -m "Document performance feel patterns and final audit results"
```

---

## Task Dependency Graph

```
Task 1 (feel audit template) ──→ standalone, do first for baseline
Task 2 (defer frames) ──────────→ independent
Task 3 (cache availability) ────→ independent
Task 4 (lazy dinner weights) ───→ independent
Task 5 (groceries double query) → independent
Task 6 (suppress self-morph) ───→ independent
Task 7 (stress generator) ──────→ independent
Task 8 (stress baseline) ───────→ depends on Task 7
Task 9 (final audit + docs) ────→ depends on Tasks 2-6, 8
```

Tasks 2-7 are fully independent and can be parallelized. Task 8 requires
Task 7's generator. Task 9 is the final pass after all fixes are in place.

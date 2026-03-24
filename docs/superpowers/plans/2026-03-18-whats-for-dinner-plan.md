# What's for Dinner? Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a weighted random recipe picker dialog to the menu page, with cook history tracking and per-session tag preferences.

**Architecture:** Hybrid client/server approach — server computes recency weights from cook history (stored in MealPlan JSON), client applies session-local tag and decline adjustments for instant re-rolls. Select-all/clear-all stubs are removed as cleanup.

**Tech Stack:** Rails 8, Stimulus, MealPlan JSON state, existing SearchDataHelper for recipe data.

---

## File Map

**New files:**
- `app/services/cook_history_weighter.rb` — pure-function service: cook history array → `{ slug => weight }` hash
- `test/services/cook_history_weighter_test.rb` — unit tests for weight formula
- `app/javascript/controllers/dinner_picker_controller.js` — Stimulus controller for the dialog
- `test/javascript/dinner_picker_test.mjs` — JS unit tests for weighted selection and weight computation

**Modified files:**
- `app/models/meal_plan.rb` — add `COOK_HISTORY_WINDOW`, `record_cook_event`, `cook_history` accessor; remove `clear!`, `clear_selections!`, `select_all!`
- `app/services/meal_plan_write_service.rb` — remove `select_all` and `clear` methods; update header comment
- `app/controllers/menu_controller.rb` — remove `select_all` and `clear` actions; add `@cook_weights` to `show`; update header comment
- `config/routes.rb` — remove `select_all` and `clear` routes
- `app/views/menu/show.html.erb` — add dinner picker button + dialog; remove select-all/clear-all UI
- `app/javascript/controllers/menu_controller.js` — remove `selectAll` and `clear` methods and URL attributes; update header comment
- `app/javascript/application.js` — register `dinner-picker` controller
- `app/assets/stylesheets/menu.css` — dinner picker dialog and slot machine styles
- `test/models/meal_plan_test.rb` — add cook history tests; remove clear!/select_all! tests
- `test/services/meal_plan_write_service_test.rb` — remove select_all/clear tests; add cook history via deselect test
- `test/controllers/menu_controller_test.rb` — remove select_all/clear tests; add cook weights embed test
- `CLAUDE.md` — update MealPlanWriteService description; add dinner_picker_controller note

---

## Task 1: Remove Select-All / Clear-All Stubs

**Files:**
- Modify: `config/routes.rb:32-33`
- Modify: `app/controllers/menu_controller.rb:36-48`
- Modify: `app/services/meal_plan_write_service.rb:18-24,39-49`
- Modify: `app/models/meal_plan.rb:63-81`
- Modify: `app/views/menu/show.html.erb:26-27,31-34`
- Modify: `app/javascript/controllers/menu_controller.js:54-60`
- Modify: `test/controllers/menu_controller_test.rb` (select_all/clear test groups)
- Modify: `test/services/meal_plan_write_service_test.rb` (select_all/clear test groups)
- Modify: `test/models/meal_plan_test.rb` (clear!/select_all! tests)

- [ ] **Step 1: Remove routes**

In `config/routes.rb`, delete lines 32-33:
```ruby
    patch 'menu/select_all', to: 'menu#select_all', as: :menu_select_all
    delete 'menu/clear', to: 'menu#clear', as: :menu_clear
```

- [ ] **Step 2: Remove controller actions**

In `app/controllers/menu_controller.rb`, delete the `select_all` and `clear` methods (lines 36-48). Also delete private helpers `all_recipe_slugs` and `all_quick_bite_slugs` (lines 94-100). Update the header comment to remove "select-all, clear" from the MealPlanWriteService collaborator note.

- [ ] **Step 3: Remove write service methods**

In `app/services/meal_plan_write_service.rb`, delete:
- Class method `select_all` (lines 18-20)
- Class method `clear` (lines 22-24)
- Instance method `select_all` (lines 39-43)
- Instance method `clear` (lines 45-49)

Update the header comment to remove "select-all, and clear" from the description.

- [ ] **Step 4: Remove model methods**

In `app/models/meal_plan.rb`, delete:
- `clear!` (lines 63-66)
- `select_all!` (lines 68-73)
- `clear_selections!` (lines 75-81)

- [ ] **Step 5: Remove view elements**

In `app/views/menu/show.html.erb`:
- Remove `data-select-all-url` and `data-clear-url` attributes from the `menu-app` div (lines 26-27)
- Remove the `#menu-actions` div entirely (lines 31-34)

- [ ] **Step 6: Remove JS methods**

In `app/javascript/controllers/menu_controller.js`, delete:
- `selectAll()` method (lines 54-56)
- `clear()` method (lines 58-60)

Update the header comment to remove "select-all, and clear-all actions".

- [ ] **Step 7: Remove tests**

In `test/controllers/menu_controller_test.rb`, remove the entire "Select All" and "Clear" test groups (search for `# -- Select All --` and `# -- Clear --` section comments and delete all tests in those groups).

In `test/services/meal_plan_write_service_test.rb`, remove the "select_all" and "clear" test groups.

In `test/models/meal_plan_test.rb`, remove tests for `clear!`, `clear_selections!`, and `select_all!`.

- [ ] **Step 8: Run tests to verify nothing broke**

Run: `rake test`
Expected: All tests pass (fewer tests than before, but no failures).

- [ ] **Step 9: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "Remove select-all and clear-all menu stubs

These were testing stubs that complicated MealPlan logic. Removing them
simplifies the model and clears the path for cook history tracking."
```

---

## Task 2: Add Cook History to MealPlan

**Files:**
- Modify: `app/models/meal_plan.rb`
- Test: `test/models/meal_plan_test.rb`

- [ ] **Step 1: Write failing tests for cook history recording**

In `test/models/meal_plan_test.rb`, add a new test group:

```ruby
# -- Cook History --

test "recipe deselect appends cook history entry" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

  history = plan.state.fetch('cook_history', [])

  assert_equal 1, history.size
  assert_equal 'focaccia', history.first['slug']
  assert history.first['at'].present?
end

test "quick bite deselect does not append cook history" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'quick_bite', slug: 'snacks', selected: true)
  plan.apply_action('select', type: 'quick_bite', slug: 'snacks', selected: false)

  history = plan.state.fetch('cook_history', [])

  assert_empty history
end

test "cook history accumulates multiple entries for same recipe" do
  plan = MealPlan.for_kitchen(@kitchen)
  2.times do
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)
  end

  history = plan.state.fetch('cook_history', [])

  assert_equal 2, history.size
  assert(history.all? { |e| e['slug'] == 'focaccia' })
end

test "cook history prunes entries older than 90 days" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['cook_history'] = [
    { 'slug' => 'old-recipe', 'at' => 91.days.ago.iso8601 },
    { 'slug' => 'recent-recipe', 'at' => 10.days.ago.iso8601 }
  ]
  plan.save!

  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

  history = plan.state['cook_history']
  slugs = history.map { |e| e['slug'] }

  assert_includes slugs, 'recent-recipe'
  assert_includes slugs, 'focaccia'
  assert_not_includes slugs, 'old-recipe'
end

test "cook history is preserved across other state changes" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: false)

  plan.apply_action('check', item: 'flour', checked: true)

  history = plan.state.fetch('cook_history', [])

  assert_equal 1, history.size
  assert_equal 'focaccia', history.first['slug']
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /cook_history/`
Expected: FAIL — cook history is never populated.

- [ ] **Step 3: Implement cook history in MealPlan**

In `app/models/meal_plan.rb`:

Add constant after `MAX_CUSTOM_ITEM_LENGTH`:
```ruby
  COOK_HISTORY_WINDOW = 90
```

Add public accessor after `selected_quick_bites_set`:
```ruby
  def cook_history
    state.fetch('cook_history', [])
  end
```

Modify `apply_select` to record history before toggling:
```ruby
  def apply_select(type:, slug:, selected:, **)
    record_cook_event(slug) if !selected && type == 'recipe'
    key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
    toggle_array(key, slug, selected)
  end
```

Add private method `record_cook_event`:
```ruby
  def record_cook_event(slug)
    history = state['cook_history'] ||= []
    history << { 'slug' => slug, 'at' => Time.current.iso8601 }
    cutoff = COOK_HISTORY_WINDOW.days.ago
    history.reject! { |e| Time.parse(e['at']) < cutoff }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/meal_plan_test.rb -n /cook_history/`
Expected: All 5 new tests pass.

- [ ] **Step 5: Run full test suite and lint**

Run: `rake`
Expected: All tests pass, no RuboCop offenses.

- [ ] **Step 6: Commit**

```bash
git add app/models/meal_plan.rb test/models/meal_plan_test.rb
git commit -m "Track cook history on recipe deselect in MealPlan

Appends { slug, at } to cook_history JSON array when a recipe is unchecked
from the menu. Prunes entries older than 90 days on each write. Quick bite
deselections are excluded."
```

---

## Task 3: Add CookHistoryWeighter Service

**Files:**
- Create: `app/services/cook_history_weighter.rb`
- Create: `test/services/cook_history_weighter_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/services/cook_history_weighter_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class CookHistoryWeighterTest < ActiveSupport::TestCase
  test "empty history returns empty hash" do
    result = CookHistoryWeighter.call([])

    assert_equal({}, result)
  end

  test "single recent cook produces reduced weight" do
    history = [{ 'slug' => 'tacos', 'at' => 1.day.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :<, 1.0
    assert_operator result['tacos'], :>, 0.0
  end

  test "cook from today produces maximum penalty" do
    history = [{ 'slug' => 'tacos', 'at' => Time.current.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_in_delta 0.5, result['tacos'], 0.05
  end

  test "multiple cooks for same recipe compound penalty" do
    single = [{ 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 }]
    double = [
      { 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 },
      { 'slug' => 'tacos', 'at' => 10.days.ago.iso8601 }
    ]

    single_weight = CookHistoryWeighter.call(single)['tacos']
    double_weight = CookHistoryWeighter.call(double)['tacos']

    assert_operator double_weight, :<, single_weight
  end

  test "cook at 89 days contributes near-zero penalty" do
    history = [{ 'slug' => 'tacos', 'at' => 89.days.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :>, 0.99
  end

  test "mixed recipes produce independent weights" do
    history = [
      { 'slug' => 'tacos', 'at' => 1.day.ago.iso8601 },
      { 'slug' => 'tacos', 'at' => 5.days.ago.iso8601 },
      { 'slug' => 'bagels', 'at' => 60.days.ago.iso8601 }
    ]
    result = CookHistoryWeighter.call(history)

    assert_operator result['tacos'], :<, result['bagels']
  end

  test "uses quadratic decay curve" do
    # At 45 days, (90-45)/90 = 0.5, squared = 0.25
    # weight = 1/(1+0.25) = 0.8
    history = [{ 'slug' => 'tacos', 'at' => 45.days.ago.iso8601 }]
    result = CookHistoryWeighter.call(history)

    assert_in_delta 0.8, result['tacos'], 0.02
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/cook_history_weighter_test.rb`
Expected: Error — `CookHistoryWeighter` not defined.

- [ ] **Step 3: Implement CookHistoryWeighter**

Create `app/services/cook_history_weighter.rb`:

```ruby
# frozen_string_literal: true

# Pure-function service that converts cook history events into per-recipe
# recency weights for the dinner picker. Uses a quadratic decay curve over
# the MealPlan cook history window so recently/frequently cooked recipes
# are less likely to be suggested.
#
# Formula: weight = 1 / (1 + Σ ((window - days_ago) / window)²)
#
# - MealPlan: provides cook_history array and COOK_HISTORY_WINDOW constant
# - dinner_picker_controller.js: consumes the weights as a JSON data attribute
class CookHistoryWeighter
  def self.call(cook_history)
    new(cook_history).call
  end

  def initialize(cook_history)
    @cook_history = cook_history
  end

  def call
    penalty_sums = compute_penalty_sums
    penalty_sums.transform_values { |sum| 1.0 / (1.0 + sum) }
  end

  private

  attr_reader :cook_history

  def compute_penalty_sums
    window = MealPlan::COOK_HISTORY_WINDOW.to_f

    cook_history.each_with_object(Hash.new(0.0)) do |entry, sums|
      days_ago = (Time.current.to_date - Date.parse(entry['at'])).to_f
      next if days_ago >= window

      contribution = ((window - days_ago) / window)**2
      sums[entry['slug']] += contribution
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/cook_history_weighter_test.rb`
Expected: All 7 tests pass.

- [ ] **Step 5: Run lint**

Run: `bundle exec rubocop app/services/cook_history_weighter.rb test/services/cook_history_weighter_test.rb`
Expected: No offenses.

- [ ] **Step 6: Commit**

```bash
git add app/services/cook_history_weighter.rb test/services/cook_history_weighter_test.rb
git commit -m "Add CookHistoryWeighter service for dinner picker

Pure-function service converts cook history into per-recipe recency weights
using quadratic decay: weight = 1/(1 + Σ((90-d)/90)²). Recently and
frequently cooked recipes get lower weights."
```

---

## Task 4: Wire Cook Weights into Menu Page

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `app/views/menu/show.html.erb`
- Modify: `test/controllers/menu_controller_test.rb`
- Modify: `test/services/meal_plan_write_service_test.rb`

- [ ] **Step 1: Write failing test for cook weights in menu**

In `test/controllers/menu_controller_test.rb`, add to the show test group:

```ruby
test "show embeds cook history weights" do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.state['cook_history'] = [
    { 'slug' => 'focaccia', 'at' => 1.day.ago.iso8601 }
  ]
  plan.save!

  get menu_path(kitchen_slug:)

  assert_response :ok
  assert_select '[data-controller*="dinner-picker"]' do
    assert_select '[data-dinner-picker-weights-value]'
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n test_show_embeds_cook_history_weights`
Expected: FAIL — no dinner-picker controller element yet.

- [ ] **Step 3: Add cook weights computation to menu controller**

In `app/controllers/menu_controller.rb`, at the end of the `show` method, add:

```ruby
    @cook_weights = CookHistoryWeighter.call(plan.cook_history)
```

- [ ] **Step 4: Add dinner picker container to menu view**

In `app/views/menu/show.html.erb`, after the `recipe-actions` div (after the Edit QuickBites button block), add the "What's for Dinner?" button and dialog container inside the `current_member?` guard. Add the dinner picker controller wrapper around the existing `menu-app` div area.

Replace the `recipe-actions` div content (inside the `current_member?` guard) with:

```erb
  <div class="recipe-actions">
    <% if current_kitchen.recipes.any? %>
    <button type="button" id="dinner-picker-button" class="dinner-picker-trigger">
      🎰 What's for Dinner?
    </button>
    <% end %>
    <button type="button" id="edit-quick-bites-button" class="edit-toggle">
      <svg width="12" height="12" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 4l6 6-16 16H6v-6z"/><line x1="18" y1="8" x2="24" y2="14"/></svg>
      Edit QuickBites
    </button>
  </div>
```

After the QuickBites editor dialog (before the final `<% end %>`), add the dinner picker dialog:

```erb
<div data-controller="dinner-picker"
     data-dinner-picker-weights-value="<%= @cook_weights.to_json %>"
     data-dinner-picker-recipe-base-path-value="<%= recipes_path %>/">
  <dialog id="dinner-picker-dialog" data-dinner-picker-target="dialog">
    <div class="dinner-picker-content">
      <div data-dinner-picker-target="tagState" class="dinner-picker-tags"></div>
      <div data-dinner-picker-target="slotDisplay" class="dinner-picker-slot" hidden></div>
      <div data-dinner-picker-target="resultArea" class="dinner-picker-result" hidden></div>
    </div>
  </dialog>
</div>
```

- [ ] **Step 5: Update write service test for cook history via deselect**

In `test/services/meal_plan_write_service_test.rb`, add to the `apply_action` test group:

```ruby
test "deselecting a recipe records cook history" do
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'select',
    type: 'recipe', slug: 'focaccia', selected: true
  )
  MealPlanWriteService.apply_action(
    kitchen: @kitchen, action_type: 'select',
    type: 'recipe', slug: 'focaccia', selected: false
  )

  plan = MealPlan.for_kitchen(@kitchen)
  history = plan.cook_history

  assert_equal 1, history.size
  assert_equal 'focaccia', history.first['slug']
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 7: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/menu_controller.rb app/views/menu/show.html.erb \
  test/controllers/menu_controller_test.rb test/services/meal_plan_write_service_test.rb
git commit -m "Wire cook history weights into menu page

MenuController computes recency weights via CookHistoryWeighter and embeds
them as a data attribute on the dinner picker container. Adds the What's
for Dinner button and empty dialog scaffold to the menu view."
```

---

## Task 5: Implement Dinner Picker Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/dinner_picker_controller.js`
- Modify: `app/javascript/application.js`
- Create: `test/javascript/dinner_picker_test.mjs`

- [ ] **Step 1: Write JS unit tests**

Create `test/javascript/dinner_picker_test.mjs`:

```javascript
import assert from "node:assert/strict"
import { test } from "node:test"

// We'll test the exported pure functions from the controller's module.
// Import the utility functions once they're extracted.
import {
  computeFinalWeights,
  weightedRandomPick
} from "../../app/javascript/utilities/dinner_picker_logic.js"

function assertCloseTo(actual, expected, delta) {
  assert.ok(Math.abs(actual - expected) <= delta,
    `Expected ${actual} to be within ${delta} of ${expected}`)
}

test("computeFinalWeights with no adjustments returns recency weights", () => {
  const recipes = [
    { slug: "tacos", tags: ["mexican"] },
    { slug: "bagels", tags: ["baking"] }
  ]
  const recencyWeights = { tacos: 0.5 }
  const tagPrefs = {}
  const declines = {}

  const result = computeFinalWeights(recipes, recencyWeights, tagPrefs, declines)

  assert.equal(result.tacos, 0.5)
  assert.equal(result.bagels, 1.0) // not in recencyWeights → default 1.0
})

test("computeFinalWeights applies tag up multiplier", () => {
  const recipes = [
    { slug: "tacos", tags: ["quick"] },
    { slug: "stew", tags: ["slow"] }
  ]
  const tagPrefs = { quick: 2 }

  const result = computeFinalWeights(recipes, {}, tagPrefs, {})

  assert.equal(result.tacos, 2.0)
  assert.equal(result.stew, 1.0)
})

test("computeFinalWeights applies tag down multiplier", () => {
  const recipes = [{ slug: "fish", tags: ["seafood"] }]
  const tagPrefs = { seafood: 0.25 }

  const result = computeFinalWeights(recipes, {}, tagPrefs, {})

  assert.equal(result.fish, 0.25)
})

test("computeFinalWeights compounds multiple tag multipliers", () => {
  const recipes = [{ slug: "tacos", tags: ["quick", "mexican"] }]
  const tagPrefs = { quick: 2, mexican: 2 }

  const result = computeFinalWeights(recipes, {}, tagPrefs, {})

  assert.equal(result.tacos, 4.0)
})

test("computeFinalWeights applies decline penalty", () => {
  const recipes = [{ slug: "tacos", tags: [] }]
  const declines = { tacos: 1 }

  const result = computeFinalWeights(recipes, {}, {}, declines)

  assertCloseTo(result.tacos, 0.3, 0.001)
})

test("computeFinalWeights compounds all factors", () => {
  const recipes = [{ slug: "tacos", tags: ["quick"] }]
  const recencyWeights = { tacos: 0.5 }
  const tagPrefs = { quick: 2 }
  const declines = { tacos: 1 }

  const result = computeFinalWeights(recipes, recencyWeights, tagPrefs, declines)

  // 0.5 * 2 * 0.3 = 0.3
  assertCloseTo(result.tacos, 0.3, 0.001)
})

test("weightedRandomPick selects from weighted pool", () => {
  const weights = { tacos: 1.0, bagels: 0.0001 }
  // With tacos having ~10000x weight, it should almost always be picked
  // Use a deterministic mock of Math.random
  const originalRandom = Math.random
  Math.random = () => 0.5 // will land in tacos range
  try {
    const result = weightedRandomPick(weights)
    assert.equal(result, "tacos")
  } finally {
    Math.random = originalRandom
  }
})

test("weightedRandomPick returns null for empty pool", () => {
  const result = weightedRandomPick({})
  assert.equal(result, null)
})
```

- [ ] **Step 2: Create dinner picker logic utility**

Create `app/javascript/utilities/dinner_picker_logic.js`:

```javascript
/**
 * Pure computation functions for the dinner picker: weight composition and
 * weighted random selection. Extracted from the controller for testability.
 *
 * - dinner_picker_controller.js: consumes these functions
 * - test/javascript/dinner_picker_test.mjs: unit tests
 */

const DECLINE_FACTOR = 0.3

export function computeFinalWeights(recipes, recencyWeights, tagPrefs, declines) {
  const weights = {}
  for (const recipe of recipes) {
    const base = recencyWeights[recipe.slug] ?? 1.0
    let tagFactor = 1.0
    for (const tag of recipe.tags) {
      tagFactor *= (tagPrefs[tag] ?? 1.0)
    }
    const declineCount = declines[recipe.slug] ?? 0
    weights[recipe.slug] = base * tagFactor * (DECLINE_FACTOR ** declineCount)
  }
  return weights
}

export function weightedRandomPick(weights) {
  const entries = Object.entries(weights)
  if (entries.length === 0) return null

  const total = entries.reduce((sum, [, w]) => sum + w, 0)
  if (total === 0) return entries[0][0]

  let roll = Math.random() * total
  for (const [slug, w] of entries) {
    roll -= w
    if (roll <= 0) return slug
  }
  return entries[entries.length - 1][0]
}
```

- [ ] **Step 3: Run JS tests to verify they pass**

Run: `npm test`
Expected: All new tests pass alongside existing tests.

- [ ] **Step 4: Create dinner picker Stimulus controller**

Create `app/javascript/controllers/dinner_picker_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { computeFinalWeights, weightedRandomPick } from "../utilities/dinner_picker_logic"
import ListenerManager from "../utilities/listener_manager"

/**
 * Dinner picker dialog: weighted random recipe suggestion with tag preferences,
 * slot machine animation, and re-roll with decline penalties. Opens from the
 * menu page, reads recipe data from SearchDataHelper JSON and recency weights
 * from a data attribute. Accept dispatches a checkbox change to menu_controller.
 *
 * - dinner_picker_logic.js: weight computation and random selection
 * - search_overlay_controller.js: provides searchData JSON (shared data source)
 * - menu_controller.js: handles checkbox change events for recipe selection
 * - ListenerManager: clean event listener teardown
 */

const QUIPS = [
  "I'm feeling lucky",
  "Baby needs new shoes",
  "Let it ride",
  "Fortune favors the bold",
  "Big money, no whammies",
  "Today's my lucky day",
  "This one's got my name on it",
  "Third time's the charm",
  "This is the one"
]

export default class extends Controller {
  static targets = ["dialog", "tagState", "slotDisplay", "resultArea"]
  static values = { weights: Object, recipeBasePath: String }

  connect() {
    this.listeners = new ListenerManager()
    this.tagPreferences = {}
    this.declinePenalties = {}

    this.recipes = this.loadRecipes()
    this.allTags = this.loadTags()

    const btn = document.getElementById("dinner-picker-button")
    if (btn) {
      this.listeners.add(btn, "click", () => this.open())
    }

    this.listeners.add(this.dialogTarget, "close", () => this.reset())
  }

  disconnect() {
    this.listeners.teardown()
  }

  open() {
    this.tagPreferences = {}
    this.declinePenalties = {}
    this.showTagState()
    this.dialogTarget.showModal()
  }

  reset() {
    this.tagPreferences = {}
    this.declinePenalties = {}
  }

  showTagState() {
    this.tagStateTarget.hidden = false
    this.slotDisplayTarget.hidden = true
    this.resultAreaTarget.hidden = true
    this.renderTagUI()
  }

  renderTagUI() {
    const container = this.tagStateTarget
    container.textContent = ""

    const heading = document.createElement("h2")
    heading.textContent = "What are you in the mood for?"
    container.appendChild(heading)

    const subtitle = document.createElement("p")
    subtitle.className = "dinner-picker-subtitle"
    subtitle.textContent = "Tap tags to steer the pick, or just spin."
    container.appendChild(subtitle)

    const pills = document.createElement("div")
    pills.className = "dinner-picker-tag-pills"
    this.buildTagPills(pills)
    container.appendChild(pills)

    const btn = document.createElement("button")
    btn.className = "dinner-picker-spin-btn"
    btn.textContent = this.randomQuip()
    btn.addEventListener("click", () => this.spin())
    container.appendChild(btn)
  }

  buildTagPills(container) {
    const smartTags = this.loadSmartTagData()

    for (const tag of this.allTags) {
      const pill = document.createElement("button")
      pill.className = "dinner-picker-tag"
      pill.dataset.tag = tag
      this.applyTagState(pill, tag, smartTags)
      pill.addEventListener("click", () => this.cycleTag(pill, tag, smartTags))
      container.appendChild(pill)
    }
  }

  cycleTag(pill, tag, smartTags) {
    const current = this.tagPreferences[tag] ?? 1
    if (current === 1) this.tagPreferences[tag] = 2
    else if (current === 2) this.tagPreferences[tag] = 0.25
    else delete this.tagPreferences[tag]
    this.applyTagState(pill, tag, smartTags)
  }

  applyTagState(pill, tag, smartTags) {
    const pref = this.tagPreferences[tag] ?? 1
    pill.textContent = ""

    const prefixMap = { 2: "\u{1F44D} ", 0.25: "\u{1F44E} " }
    const prefix = prefixMap[pref] || ""

    const smart = smartTags[tag]
    const emoji = smart?.emoji ? smart.emoji + " " : ""
    pill.textContent = prefix + emoji + tag

    pill.classList.remove("tag-up", "tag-down", "tag-neutral")
    if (pref === 2) pill.classList.add("tag-up")
    else if (pref === 0.25) pill.classList.add("tag-down")
    else pill.classList.add("tag-neutral")
  }

  spin() {
    const weights = computeFinalWeights(
      this.recipes, this.weightsValue, this.tagPreferences, this.declinePenalties
    )
    const pick = weightedRandomPick(weights)
    if (!pick) return

    const recipe = this.recipes.find(r => r.slug === pick)
    this.animateSlotMachine(recipe, Object.keys(this.declinePenalties).length > 0)
  }

  animateSlotMachine(winner, isReroll) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.showResult(winner)
      return
    }

    this.tagStateTarget.hidden = true
    this.slotDisplayTarget.hidden = false
    this.resultAreaTarget.hidden = true

    const display = this.slotDisplayTarget
    display.textContent = ""

    const emoji = document.createElement("div")
    emoji.className = "slot-emoji"
    emoji.textContent = "\u{1F3B0}"
    display.appendChild(emoji)

    const window_ = document.createElement("div")
    window_.className = "slot-window"
    display.appendChild(window_)

    const nameEl = document.createElement("div")
    nameEl.className = "slot-name"
    window_.appendChild(nameEl)

    const cycles = isReroll ? 8 : 15
    let i = 0
    const animate = () => {
      if (i < cycles) {
        const weights = computeFinalWeights(
          this.recipes, this.weightsValue, this.tagPreferences, this.declinePenalties
        )
        const randomRecipe = i < cycles - 1
          ? this.recipes[Math.floor(Math.random() * this.recipes.length)]
          : winner
        nameEl.textContent = randomRecipe.title
        i++
        setTimeout(animate, 80 + i * (isReroll ? 20 : 15))
      } else {
        nameEl.textContent = winner.title
        nameEl.classList.add("slot-landed")
        emoji.textContent = "\u{1F389}"
        setTimeout(() => this.showResult(winner), 400)
      }
    }
    animate()
  }

  showResult(recipe) {
    this.tagStateTarget.hidden = true
    this.slotDisplayTarget.hidden = true
    this.resultAreaTarget.hidden = false

    const container = this.resultAreaTarget
    container.textContent = ""

    const label = document.createElement("div")
    label.className = "result-label"
    label.textContent = "Tonight's Pick"
    container.appendChild(label)

    const title = document.createElement("h2")
    title.className = "result-title"
    title.textContent = recipe.title
    container.appendChild(title)

    if (recipe.description) {
      const desc = document.createElement("p")
      desc.className = "result-description"
      desc.textContent = recipe.description
      container.appendChild(desc)
    }

    if (recipe.tags.length > 0) {
      const tags = document.createElement("div")
      tags.className = "result-tags"
      for (const tag of recipe.tags) {
        const pill = document.createElement("span")
        pill.className = "result-tag-pill"
        pill.textContent = tag
        tags.appendChild(pill)
      }
      container.appendChild(tags)
    }

    const actions = document.createElement("div")
    actions.className = "result-actions"

    const acceptBtn = document.createElement("button")
    acceptBtn.className = "result-accept-btn"
    acceptBtn.textContent = "\u2713 Add to Menu"
    acceptBtn.addEventListener("click", () => this.accept(recipe))
    actions.appendChild(acceptBtn)

    const retryBtn = document.createElement("button")
    retryBtn.className = "result-retry-btn"
    retryBtn.textContent = "Try again"
    retryBtn.addEventListener("click", () => this.retry(recipe))
    actions.appendChild(retryBtn)

    container.appendChild(actions)

    const viewLink = document.createElement("a")
    viewLink.className = "result-view-link"
    viewLink.href = this.recipeBasePathValue + recipe.slug
    viewLink.textContent = "View Recipe"
    container.appendChild(viewLink)
  }

  accept(recipe) {
    const checkbox = document.querySelector(
      `#recipe-selector input[type="checkbox"][data-slug="${CSS.escape(recipe.slug)}"]`
    )
    if (checkbox && !checkbox.checked) {
      checkbox.checked = true
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.dialogTarget.close()
  }

  retry(recipe) {
    this.declinePenalties[recipe.slug] = (this.declinePenalties[recipe.slug] || 0) + 1
    this.showTagState()
  }

  randomQuip() {
    return "\u{1F3B0} " + QUIPS[Math.floor(Math.random() * QUIPS.length)]
  }

  loadRecipes() {
    const el = document.querySelector("[data-search-data]")
    if (!el) return []
    try {
      const data = JSON.parse(el.dataset.searchData)
      return data.recipes || []
    } catch { return [] }
  }

  loadTags() {
    const el = document.querySelector("[data-search-data]")
    if (!el) return []
    try {
      const data = JSON.parse(el.dataset.searchData)
      return data.all_tags || []
    } catch { return [] }
  }

  loadSmartTagData() {
    const el = document.querySelector("[data-smart-tags]")
    if (!el) return {}
    try { return JSON.parse(el.dataset.smartTags) } catch { return {} }
  }
}
```

- [ ] **Step 5: Register controller in application.js**

In `app/javascript/application.js`, add the import (alphabetical order, after `DualModeEditorController`):

```javascript
import DinnerPickerController from "./controllers/dinner_picker_controller"
```

And register it (alphabetical, after `dual-mode-editor`):

```javascript
application.register("dinner-picker", DinnerPickerController)
```

- [ ] **Step 6: Run JS tests**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/dinner_picker_controller.js \
  app/javascript/utilities/dinner_picker_logic.js \
  app/javascript/application.js \
  test/javascript/dinner_picker_test.mjs
git commit -m "Add dinner picker Stimulus controller with slot machine animation

Three dialog states: tag preferences → slot machine → result card.
Weighted random selection using recency weights, tag multipliers, and
decline penalties. Random gambling quips on the spin button."
```

---

## Task 6: Dinner Picker CSS

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

- [ ] **Step 1: Add dinner picker styles**

Append to `app/assets/stylesheets/menu.css` (before the `@media print` section — find the print media query and insert before it):

```css
/* -- Dinner Picker -- */

.dinner-picker-trigger {
  background: var(--link);
  color: white;
  border: none;
  padding: 0.4rem 0.8rem;
  border-radius: 4px;
  font-size: 0.85rem;
  cursor: pointer;
}

.dinner-picker-trigger:hover {
  opacity: 0.85;
}

#dinner-picker-dialog {
  max-width: 28rem;
  width: 90vw;
  border: 1px solid var(--rule-faint);
  border-radius: 8px;
  padding: 1.5rem;
  background: var(--bg);
  color: var(--fg);
}

#dinner-picker-dialog::backdrop {
  background: rgba(0, 0, 0, 0.5);
}

.dinner-picker-subtitle {
  color: var(--fg-muted);
  font-size: 0.85rem;
  margin: 0.3rem 0 1rem;
}

.dinner-picker-tag-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  justify-content: center;
  margin-bottom: 1.2rem;
}

.dinner-picker-tag {
  padding: 0.3rem 0.6rem;
  border-radius: 12px;
  font-size: 0.8rem;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background 0.15s, color 0.15s;
}

.dinner-picker-tag.tag-neutral {
  background: var(--bg-offset);
  color: var(--fg-muted);
}

.dinner-picker-tag.tag-up {
  background: var(--tag-green-bg, #065f46);
  color: var(--tag-green-fg, #6ee7b7);
}

.dinner-picker-tag.tag-down {
  background: var(--tag-red-bg, #7f1d1d);
  color: var(--tag-red-fg, #fca5a5);
}

.dinner-picker-spin-btn {
  display: block;
  margin: 0 auto;
  background: var(--link);
  color: white;
  border: none;
  padding: 0.6rem 1.8rem;
  border-radius: 6px;
  font-size: 0.95rem;
  cursor: pointer;
  min-width: 200px;
}

.dinner-picker-spin-btn:hover {
  opacity: 0.85;
}

/* Slot machine */

.dinner-picker-slot {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 14rem;
  text-align: center;
}

.slot-emoji {
  font-size: 2rem;
  margin-bottom: 0.8rem;
}

.slot-window {
  background: var(--bg-offset);
  border-radius: 8px;
  padding: 0.8rem 2rem;
  width: 85%;
  overflow: hidden;
}

.slot-name {
  font-size: 1.2rem;
  font-weight: 600;
  color: var(--link);
  transition: transform 0.2s ease;
}

.slot-name.slot-landed {
  transform: scale(1.15);
}

/* Result card */

.result-label {
  text-align: center;
  font-size: 0.75rem;
  color: var(--fg-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.result-title {
  text-align: center;
  margin: 0.3rem 0;
}

.result-description {
  text-align: center;
  color: var(--fg-muted);
  font-size: 0.85rem;
  margin: 0.4rem 0 0.8rem;
}

.result-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
  justify-content: center;
  margin-bottom: 1rem;
}

.result-tag-pill {
  background: var(--bg-offset);
  color: var(--fg-muted);
  padding: 0.2rem 0.5rem;
  border-radius: 10px;
  font-size: 0.75rem;
}

.result-actions {
  display: flex;
  gap: 0.5rem;
  justify-content: center;
  margin-bottom: 0.6rem;
}

.result-accept-btn {
  background: var(--tag-green-bg, #065f46);
  color: var(--tag-green-fg, #6ee7b7);
  border: none;
  padding: 0.5rem 1.2rem;
  border-radius: 6px;
  font-size: 0.85rem;
  cursor: pointer;
}

.result-accept-btn:hover {
  opacity: 0.85;
}

.result-retry-btn {
  background: transparent;
  border: 1px solid var(--rule-faint);
  color: var(--fg-muted);
  padding: 0.5rem 1rem;
  border-radius: 6px;
  font-size: 0.85rem;
  cursor: pointer;
}

.result-retry-btn:hover {
  border-color: var(--fg-muted);
}

.result-view-link {
  display: block;
  text-align: center;
  color: var(--fg-muted);
  font-size: 0.8rem;
}

/* Reduced motion: skip slot machine animation */
@media (prefers-reduced-motion: reduce) {
  .slot-name {
    transition: none;
  }
}
```

- [ ] **Step 2: Hide dinner picker dialog in print**

In the existing `@media print` section of `menu.css`, add:

```css
  #dinner-picker-dialog,
  .dinner-picker-trigger {
    display: none;
  }
```

- [ ] **Step 3: Verify styles load correctly**

Run: `npm run build`
Expected: esbuild succeeds. Start `bin/dev` and verify the menu page loads without CSP errors.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Add dinner picker dialog styles

Slot machine animation, tag pill states (neutral/up/down), result card
layout. Respects prefers-reduced-motion. Hidden in print."
```

---

## Task 7: Update CLAUDE.md and Final Verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In `CLAUDE.md`, update the `MealPlanWriteService` line (currently reads "select/deselect, select-all, clear, reconciliation"):
```
- `MealPlanWriteService` — select/deselect, reconciliation.
```

Add a note about cook history in the MealPlan description or write path section:
```
- `MealPlan#apply_select` records cook history (slug + timestamp) on recipe
  deselect. `CookHistoryWeighter` converts history to recency weights.
```

Add `dinner_picker_controller` to the architecture notes, perhaps near the search overlay section:
```
**Dinner picker.** `dinner_picker_controller` provides a weighted random
recipe suggestion dialog on the menu page. Reads recipes from
`SearchDataHelper` JSON and recency weights from `CookHistoryWeighter`
(data attribute). Per-session tag preferences and decline penalties are
ephemeral. `dinner_picker_logic.js` holds the pure weight computation
and selection functions.
```

- [ ] **Step 2: Run full test suite**

Run: `rake`
Expected: All tests pass, no RuboCop offenses.

- [ ] **Step 3: Run JS tests**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 4: Update html_safe_allowlist.yml if needed**

Run: `rake lint:html_safe`
Expected: No new violations (dinner picker uses `to_json` which is safe, and data attributes don't need `.html_safe`).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md with dinner picker architecture

Document CookHistoryWeighter, dinner_picker_controller, and removal
of select-all/clear-all from MealPlanWriteService."
```

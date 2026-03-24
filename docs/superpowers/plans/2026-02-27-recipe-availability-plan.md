# Recipe Availability & Ingredient Provenance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Show recipe availability indicators on the Menu page based on checked-off grocery items, and ingredient provenance tooltips on the Groceries page.

**Architecture:** New `RecipeAvailabilityCalculator` service computes per-recipe ingredient availability. `ShoppingListBuilder` extended to track ingredient provenance. Menu gets its own `/menu/state` endpoint; Groceries state adds `sources` to shopping list items. Menu page JS renders colored dots with click-to-open popovers.

**Tech Stack:** Ruby service objects, Rails controller endpoints, Stimulus JS, CSS custom properties

---

### Task 0: RecipeAvailabilityCalculator Service — Tests

**Files:**
- Create: `test/services/recipe_availability_calculator_test.rb`
- Create: `app/services/recipe_availability_calculator.rb` (empty placeholder)

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipeAvailabilityCalculatorTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp
      - Water, 1 cup

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Bagels

      Category: Bread

      ## Mix (combine)

      - Flour, 4 cups
      - Salt, 1 tsp
      - Yeast, 1 tsp

      Mix well.
    MD

    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Water') do |p|
      p.basis_grams = 240
      p.aisle = 'omit'
    end
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Yeast') do |p|
      p.basis_grams = 3
      p.aisle = 'Baking'
    end
  end

  test 'returns availability for all recipes' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert result.key?('focaccia')
    assert result.key?('bagels')
  end

  test 'all missing when nothing checked off' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_equal 2, result['focaccia'][:missing]
    assert_includes result['focaccia'][:missing_names], 'Flour'
    assert_includes result['focaccia'][:missing_names], 'Salt'
    assert_not_includes result['focaccia'][:missing_names], 'Water'
  end

  test 'excludes omitted ingredients from count' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_not_includes result['focaccia'][:ingredients], 'Water'
  end

  test 'zero missing when all non-omit ingredients checked off' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Flour Salt]
    ).call

    assert_equal 0, result['focaccia'][:missing]
    assert_empty result['focaccia'][:missing_names]
  end

  test 'partial check-off shows correct missing count' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Flour]
    ).call

    assert_equal 1, result['focaccia'][:missing]
    assert_equal ['Salt'], result['focaccia'][:missing_names]

    assert_equal 2, result['bagels'][:missing]
    assert_includes result['bagels'][:missing_names], 'Salt'
    assert_includes result['bagels'][:missing_names], 'Yeast'
  end

  test 'includes ingredient names list per recipe' do
    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: []).call

    assert_includes result['focaccia'][:ingredients], 'Flour'
    assert_includes result['focaccia'][:ingredients], 'Salt'
  end

  test 'includes quick bites when present' do
    @kitchen.update!(quick_bites_content: <<~MD)
      ## Snacks
        - Nachos: Tortilla chips, Cheese
    MD

    result = RecipeAvailabilityCalculator.new(kitchen: @kitchen, checked_off: ['Cheese']).call

    assert result.key?('nachos')
    assert_equal 1, result['nachos'][:missing]
    assert_equal ['Tortilla chips'], result['nachos'][:missing_names]
  end

  test 'handles cross-referenced recipe ingredients' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Poolish

      Category: Bread

      ## Mix (combine)

      - Flour, 1 cup
      - Water, 1 cup

      Mix.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza

      Category: Bread

      ## Dough (assemble)

      - Salt, 1 tsp
      - @[Poolish]

      Make dough.
    MD

    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[Salt]
    ).call

    assert_equal 1, result['pizza'][:missing]
    assert_includes result['pizza'][:missing_names], 'Flour'
    assert_not_includes result['pizza'][:missing_names], 'Water'
  end
end
```

**Step 2: Create empty service file**

```ruby
# frozen_string_literal: true

class RecipeAvailabilityCalculator
end
```

**Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_availability_calculator_test.rb`
Expected: FAIL (no `call` method, etc.)

**Step 4: Commit**

```bash
git add test/services/recipe_availability_calculator_test.rb app/services/recipe_availability_calculator.rb
git commit -m "test: add RecipeAvailabilityCalculator test suite"
```

---

### Task 1: RecipeAvailabilityCalculator Service — Implementation

**Files:**
- Modify: `app/services/recipe_availability_calculator.rb`

**Step 1: Implement the service**

```ruby
# frozen_string_literal: true

class RecipeAvailabilityCalculator
  def initialize(kitchen:, checked_off:)
    @kitchen = kitchen
    @checked_off = Set.new(checked_off)
    @omitted = load_omitted_names
  end

  def call
    availability = {}
    compute_recipe_availability(availability)
    compute_quick_bite_availability(availability)
    availability
  end

  private

  def compute_recipe_availability(availability)
    recipes.each do |recipe|
      ingredients = non_omitted_names(recipe.all_ingredients_with_quantities.map(&:first))
      missing = ingredients - @checked_off.to_a
      availability[recipe.slug] = { missing: missing.size, missing_names: missing, ingredients: ingredients }
    end
  end

  def compute_quick_bite_availability(availability)
    quick_bites.each do |qb|
      ingredients = non_omitted_names(qb.all_ingredient_names)
      missing = ingredients - @checked_off.to_a
      availability[qb.id] = { missing: missing.size, missing_names: missing, ingredients: ingredients }
    end
  end

  def recipes
    @kitchen.recipes.includes(:category, steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
  end

  def quick_bites
    content = @kitchen.quick_bites_content
    return [] unless content

    FamilyRecipes.parse_quick_bites_content(content)
  end

  def non_omitted_names(names)
    names.reject { |name| @omitted.include?(name) }.uniq
  end

  def load_omitted_names
    profiles = IngredientCatalog.lookup_for(@kitchen)
    Set.new(profiles.select { |_name, entry| entry.aisle == 'omit' }.keys)
  end
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_availability_calculator_test.rb`
Expected: All PASS

**Step 3: Run lint**

Run: `bundle exec rubocop app/services/recipe_availability_calculator.rb`

**Step 4: Commit**

```bash
git add app/services/recipe_availability_calculator.rb
git commit -m "feat: implement RecipeAvailabilityCalculator service"
```

---

### Task 2: ShoppingListBuilder Provenance — Tests & Implementation

**Files:**
- Modify: `app/services/shopping_list_builder.rb`
- Modify: `test/services/shopping_list_builder_test.rb`

**Step 1: Add provenance tests to existing test file**

Append these tests to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'items include sources listing recipe titles' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  flour = result['Baking'].find { |i| i[:name] == 'Flour' }

  assert_includes flour[:sources], 'Focaccia'
end

test 'shared ingredients list all contributing recipe titles' do
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Sourdough

    Category: Bread

    ## Mix (combine)

    - Flour, 2 cups
    - Salt, 0.5 tsp

    Mix well.
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  list.apply_action('select', type: 'recipe', slug: 'sourdough', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  flour = result['Baking'].find { |i| i[:name] == 'Flour' }

  assert_includes flour[:sources], 'Focaccia'
  assert_includes flour[:sources], 'Sourdough'
end

test 'quick bite ingredients include quick bite title as source' do
  @kitchen.update!(quick_bites_content: <<~MD)
    ## Snacks
      - Hummus with Pretzels: Hummus, Pretzels
  MD

  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'quick_bite', slug: 'hummus-with-pretzels', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  all_items = result.values.flatten

  hummus = all_items.find { |i| i[:name] == 'Hummus' }

  assert_includes hummus[:sources], 'Hummus with Pretzels'
end

test 'custom items have empty sources' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('custom_items', item: 'birthday candles', action: 'add')

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

  assert_empty custom[:sources]
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: FAIL (no `:sources` key in items)

**Step 3: Modify ShoppingListBuilder to track provenance**

In `app/services/shopping_list_builder.rb`, the approach: track which recipe/quick-bite titles contribute each ingredient name during aggregation, then include that in the organized output.

Replace the `merge_all_ingredients` method and related methods. Key changes:

1. `aggregate_recipe_ingredients` returns `{ name => { amounts:, sources: } }` instead of `{ name => amounts }`
2. `aggregate_quick_bite_ingredients` same pattern
3. `merge_all_ingredients` merges both amounts and sources
4. `organize_by_aisle` passes sources through to items

The modified `shopping_list_builder.rb`:

```ruby
# frozen_string_literal: true

class ShoppingListBuilder
  def initialize(kitchen:, meal_plan:)
    @kitchen = kitchen
    @meal_plan = meal_plan
    @profiles = IngredientCatalog.lookup_for(kitchen)
  end

  def build
    ingredients = merge_all_ingredients
    organized = organize_by_aisle(ingredients)
    add_custom_items(organized)
    organized
  end

  private

  def merge_all_ingredients
    recipe_ingredients = aggregate_recipe_ingredients
    quick_bite_ingredients = aggregate_quick_bite_ingredients

    recipe_ingredients.merge(quick_bite_ingredients) do |_name, existing, incoming|
      {
        amounts: IngredientAggregator.merge_amounts(existing[:amounts], incoming[:amounts]),
        sources: existing[:sources] + incoming[:sources]
      }
    end
  end

  def selected_recipes
    slugs = @meal_plan.state.fetch('selected_recipes', [])
    xref_includes = { cross_references: { target_recipe: { steps: :ingredients } } }
    @kitchen.recipes
            .includes(:category, steps: [:ingredients, xref_includes])
            .where(slug: slugs)
  end

  def selected_quick_bites
    slugs = @meal_plan.state.fetch('selected_quick_bites', [])
    return [] if slugs.empty?

    content = @kitchen.quick_bites_content
    return [] unless content

    all_bites = FamilyRecipes.parse_quick_bites_content(content)
    all_bites.select { |qb| slugs.include?(qb.id) }
  end

  def aggregate_recipe_ingredients
    selected_recipes.each_with_object({}) do |recipe, merged|
      recipe.all_ingredients_with_quantities.each do |name, amounts|
        if merged.key?(name)
          merged[name][:amounts] = IngredientAggregator.merge_amounts(merged[name][:amounts], amounts)
          merged[name][:sources] << recipe.title unless merged[name][:sources].include?(recipe.title)
        else
          merged[name] = { amounts: amounts, sources: [recipe.title] }
        end
      end
    end
  end

  def aggregate_quick_bite_ingredients
    selected_quick_bites.each_with_object({}) do |qb, merged|
      qb.ingredients_with_quantities.each do |name, amounts|
        if merged.key?(name)
          merged[name][:amounts] = IngredientAggregator.merge_amounts(merged[name][:amounts], amounts)
          merged[name][:sources] << qb.title unless merged[name][:sources].include?(qb.title)
        else
          merged[name] = { amounts: amounts, sources: [qb.title] }
        end
      end
    end
  end

  def organize_by_aisle(ingredients)
    visible = ingredients.reject { |name, _| @profiles[name]&.aisle == 'omit' }
    grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, data), result|
      target_aisle = @profiles[name]&.aisle || 'Miscellaneous'
      result[target_aisle] << { name: name, amounts: serialize_amounts(data[:amounts]), sources: data[:sources] }
    end

    sort_aisles(grouped)
  end

  def sort_aisles(aisles_hash)
    order = @kitchen.parsed_aisle_order
    return aisles_hash.sort_by { |aisle, _| aisle == 'Miscellaneous' ? 'zzz' : aisle }.to_h if order.empty?

    aisles_hash.sort_by { |aisle, _| aisle_sort_key(aisle, order) }.to_h
  end

  def aisle_sort_key(aisle, order)
    position = order.index(aisle)
    return [0, position] if position

    # Miscellaneous defaults to last unless explicitly ordered
    return [2, 0] if aisle == 'Miscellaneous'

    # Unordered aisles sort alphabetically after ordered ones
    [1, aisle]
  end

  def add_custom_items(organized)
    custom = @meal_plan.state.fetch('custom_items', [])
    return if custom.empty?

    organized['Miscellaneous'] ||= []
    organized['Miscellaneous'].concat(custom.map { |item| { name: item, amounts: [], sources: [] } })
  end

  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value.to_f, q.unit] }
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All PASS

**Step 5: Run full test suite to check for regressions**

Run: `rake test`
Expected: All pass. Some existing tests may need minor adjustment if they assert on item hash structure (they now have `:sources` key too).

**Step 6: Run lint**

Run: `bundle exec rubocop app/services/shopping_list_builder.rb`

**Step 7: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "feat: add ingredient provenance tracking to ShoppingListBuilder"
```

---

### Task 3: MenuController#state Endpoint — Route, Tests & Implementation

**Files:**
- Modify: `config/routes.rb` (add `menu/state` route)
- Modify: `app/controllers/menu_controller.rb` (add `state` action)
- Modify: `test/controllers/menu_controller_test.rb` (add state tests)
- Modify: `app/views/menu/show.html.erb` (switch `data-state-url` to `menu_state_path`)
- Modify: `public/service-worker.js` (add `state` to menu API pattern)

**Step 1: Add route**

In `config/routes.rb`, after line 20 (the `menu/quick_bites_content` route), add:

```ruby
get 'menu/state', to: 'menu#state', as: :menu_state
```

**Step 2: Add controller tests**

Append to `test/controllers/menu_controller_test.rb`:

```ruby
# --- State endpoint ---

test 'state requires membership' do
  get menu_state_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :forbidden
end

test 'state returns version and selections' do
  log_in
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  get menu_state_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
  json = response.parsed_body

  assert json.key?('version')
  assert_includes json['selected_recipes'], 'focaccia'
  assert json.key?('selected_quick_bites')
end

test 'state includes availability map' do
  log_in
  get menu_state_path(kitchen_slug: kitchen_slug), as: :json

  json = response.parsed_body

  assert json.key?('availability')
end

test 'state availability reflects checked_off items' do
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix well.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end
  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
    p.basis_grams = 6
    p.aisle = 'Spices'
  end

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Flour', checked: true)

  log_in
  get menu_state_path(kitchen_slug: kitchen_slug), as: :json

  json = response.parsed_body
  focaccia = json['availability']['focaccia']

  assert_equal 1, focaccia['missing']
  assert_includes focaccia['missing_names'], 'Salt'
  assert_includes focaccia['ingredients'], 'Flour'
  assert_includes focaccia['ingredients'], 'Salt'
end
```

**Step 3: Add controller action**

In `app/controllers/menu_controller.rb`, add the `state` action:

```ruby
def state
  plan = MealPlan.for_kitchen(current_kitchen)
  checked_off = plan.state.fetch('checked_off', [])
  availability = RecipeAvailabilityCalculator.new(kitchen: current_kitchen, checked_off: checked_off).call

  render json: {
    version: plan.lock_version,
    **plan.state.slice('selected_recipes', 'selected_quick_bites'),
    availability: availability
  }
end
```

**Step 4: Update view to use new state endpoint**

In `app/views/menu/show.html.erb`, change line 32:

```erb
data-state-url="<%= menu_state_path %>">
```

(Replace `groceries_state_path` with `menu_state_path`)

**Step 5: Update service worker API pattern**

In `public/service-worker.js`, update the `API_PATTERN` regex to include `state` in the menu section:

```javascript
var API_PATTERN = /^(\/kitchens\/[^/]+)?\/(groceries\/(state|check|custom_items|aisle_order|aisle_order_content)|menu\/(state|select|select_all|clear|quick_bites|quick_bites_content)|nutrition\/)/;
```

**Step 6: Run tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All PASS

**Step 7: Run full suite**

Run: `rake test`

**Step 8: Commit**

```bash
git add config/routes.rb app/controllers/menu_controller.rb test/controllers/menu_controller_test.rb app/views/menu/show.html.erb public/service-worker.js
git commit -m "feat: add MenuController#state endpoint with availability data"
```

---

### Task 4: Menu Page JS — Availability Indicators

**Files:**
- Modify: `app/javascript/controllers/menu_controller.js`

**Step 1: Update `syncCheckboxes` to also render indicators**

After the existing checkbox sync logic, add indicator rendering. The `state.availability` map is keyed by slug.

Add a new method `syncAvailability(state)` called from both `syncCheckboxes` and `fetchState`:

```javascript
syncAvailability(state) {
  const availability = state.availability || {}

  this.element.querySelectorAll('#recipe-selector input[type="checkbox"]').forEach(cb => {
    const slug = cb.dataset.slug
    if (!slug) return

    const li = cb.closest('li')
    if (!li) return

    let dot = li.querySelector('.availability-dot')
    const info = availability[slug]

    if (!info) {
      if (dot) dot.remove()
      return
    }

    if (!dot) {
      dot = document.createElement('span')
      dot.className = 'availability-dot'
      dot.dataset.slug = slug
      li.appendChild(dot)
    }

    const missing = info.missing
    dot.dataset.missing = missing > 2 ? '3+' : String(missing)

    const label = missing === 0
      ? 'All ingredients on hand'
      : `Missing ${missing}: ${info.missing_names.join(', ')}`
    dot.setAttribute('aria-label', label)
    dot.setAttribute('title', '')
  })
}
```

Call `this.syncAvailability(data)` in `fetchState` after `this.syncCheckboxes(data)`, and `this.syncAvailability(this.state)` from the cache-load path in `connect`.

Also call it after Turbo Stream renders in `handleStreamRender`.

**Step 2: Run the dev server and verify indicators appear**

Run: `bin/dev`
Navigate to Menu page. Indicators should appear as unstyled spans. Verify in dev tools that `data-missing` attributes are set.

**Step 3: Commit**

```bash
git add app/javascript/controllers/menu_controller.js
git commit -m "feat: render availability indicator dots on Menu page"
```

---

### Task 5: Menu Page CSS — Indicator Styling

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

**Step 1: Add CSS custom properties and indicator styles**

Add to `menu.css` (after the existing checkbox styles around line 42):

```css
/* Availability indicators */
.availability-dot {
  width: 0.6rem;
  height: 0.6rem;
  border-radius: 50%;
  flex-shrink: 0;
  margin-left: 0.4rem;
  cursor: pointer;
  background: var(--border-muted);
  transition: background-color 0.2s ease;
}

.availability-dot[data-missing="0"] {
  background: #4caf50;
}

.availability-dot[data-missing="1"] {
  background: #ffc107;
}

.availability-dot[data-missing="2"] {
  background: #ff9800;
}

@media print {
  .availability-dot {
    display: none;
  }
}
```

Colors: green (#4caf50), yellow (#ffc107), orange (#ff9800), gray (var(--border-muted)) for 3+. These are intentionally hardcoded values rather than CSS variables since they're semantic (traffic-light convention) and unlikely to need theme customization.

**Step 2: Verify in browser**

Check that dots appear with correct colors. Check all 4 states: green (0 missing), yellow (1), orange (2), gray (3+).

**Step 3: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "feat: style availability indicator dots with color coding"
```

---

### Task 6: Menu Page JS — Ingredient Popover

**Files:**
- Modify: `app/javascript/controllers/menu_controller.js`
- Modify: `app/assets/stylesheets/menu.css`

**Step 1: Add popover management to menu_controller.js**

Add methods for popover lifecycle. A single shared `<div id="ingredient-popover">` is created on first use, repositioned and repopulated on each click.

```javascript
showPopover(dot) {
  const slug = dot.dataset.slug
  const info = (this.state.availability || {})[slug]
  if (!info) return

  let popover = document.getElementById('ingredient-popover')
  if (!popover) {
    popover = document.createElement('div')
    popover.id = 'ingredient-popover'
    popover.setAttribute('role', 'tooltip')
    document.body.appendChild(popover)
  }

  if (this.activePopoverDot === dot) {
    this.hidePopover()
    return
  }

  popover.textContent = ''

  const ingredientsList = document.createElement('p')
  ingredientsList.className = 'popover-ingredients'
  ingredientsList.textContent = info.ingredients.join(', ')
  popover.appendChild(ingredientsList)

  if (info.missing_names.length > 0) {
    const missingEl = document.createElement('p')
    missingEl.className = 'popover-missing'
    missingEl.textContent = 'Missing: ' + info.missing_names.join(', ')
    popover.appendChild(missingEl)
  }

  popover.classList.add('visible')

  const rect = dot.getBoundingClientRect()
  const popoverRect = popover.getBoundingClientRect()

  let top = rect.bottom + 6
  let left = rect.left

  if (top + popoverRect.height > window.innerHeight) {
    top = rect.top - popoverRect.height - 6
  }
  if (left + popoverRect.width > window.innerWidth) {
    left = window.innerWidth - popoverRect.width - 8
  }

  popover.style.top = (top + window.scrollY) + 'px'
  popover.style.left = (left + window.scrollX) + 'px'

  this.activePopoverDot = dot
  dot.setAttribute('aria-expanded', 'true')
  popover.id = 'ingredient-popover'
  dot.setAttribute('aria-describedby', 'ingredient-popover')

  setTimeout(() => {
    this.boundHideOnClickOutside = (e) => {
      if (!popover.contains(e.target) && e.target !== dot) {
        this.hidePopover()
      }
    }
    this.boundHideOnEscape = (e) => {
      if (e.key === 'Escape') {
        this.hidePopover()
        dot.focus()
      }
    }
    document.addEventListener('click', this.boundHideOnClickOutside)
    document.addEventListener('keydown', this.boundHideOnEscape)
  }, 0)
}

hidePopover() {
  const popover = document.getElementById('ingredient-popover')
  if (popover) popover.classList.remove('visible')

  if (this.activePopoverDot) {
    this.activePopoverDot.setAttribute('aria-expanded', 'false')
    this.activePopoverDot.removeAttribute('aria-describedby')
    this.activePopoverDot = null
  }

  if (this.boundHideOnClickOutside) {
    document.removeEventListener('click', this.boundHideOnClickOutside)
    this.boundHideOnClickOutside = null
  }
  if (this.boundHideOnEscape) {
    document.removeEventListener('keydown', this.boundHideOnEscape)
    this.boundHideOnEscape = null
  }
}
```

Add click delegation in `connect()` (or a new bind method):

```javascript
this.element.addEventListener('click', (e) => {
  const dot = e.target.closest('.availability-dot')
  if (dot) {
    e.preventDefault()
    e.stopPropagation()
    this.showPopover(dot)
  }
})
```

Clean up in `disconnect()`:

```javascript
this.hidePopover()
```

**Step 2: Add popover CSS**

Append to `menu.css`:

```css
/* Ingredient popover */
#ingredient-popover {
  position: absolute;
  z-index: 100;
  background: var(--surface-color, #fff);
  border: 1px solid var(--border-light);
  border-radius: 6px;
  padding: 0.6rem 0.8rem;
  font-size: 0.85rem;
  max-width: 300px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
  display: none;
}

#ingredient-popover.visible {
  display: block;
}

.popover-ingredients {
  margin: 0;
  line-height: 1.4;
}

.popover-missing {
  margin: 0.4rem 0 0;
  color: var(--danger-color);
  font-weight: 600;
  font-size: 0.8rem;
}
```

**Step 3: Verify in browser**

Click a dot — popover appears with ingredient list. Click outside — dismisses. Press Escape — dismisses and returns focus. Click same dot — toggles off. Check mobile viewport.

**Step 4: Commit**

```bash
git add app/javascript/controllers/menu_controller.js app/assets/stylesheets/menu.css
git commit -m "feat: add ingredient popover on availability dot click"
```

---

### Task 7: Groceries Page — Provenance Tooltips

**Files:**
- Modify: `app/javascript/controllers/grocery_ui_controller.js`

**Step 1: Update `renderShoppingList` to set title attributes**

In `grocery_ui_controller.js`, in the `renderShoppingList` method, after the `li` element is fully built (around line 137, before `ul.appendChild(li)`), add:

```javascript
if (item.sources && item.sources.length > 0) {
  li.title = 'Needed for: ' + item.sources.join(', ')
}
```

**Step 2: Run the dev server and verify**

Navigate to Groceries page. Hover over an ingredient — should see "Needed for: Focaccia, Bagels" tooltip. Custom items should have no tooltip.

**Step 3: Run full test suite**

Run: `rake test`
Expected: All pass

**Step 4: Commit**

```bash
git add app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: add provenance tooltips to grocery shopping list items"
```

---

### Task 8: Final Verification & Cleanup

**Files:**
- All modified files

**Step 1: Run full test suite**

Run: `rake test`
Expected: All pass

**Step 2: Run lint**

Run: `rake lint`
Expected: Clean

**Step 3: Manual smoke test checklist**

1. Menu page: indicators appear on all recipes and quick bites
2. Menu page: check off items on Groceries, return to Menu — indicators update
3. Menu page: green dot when all ingredients checked, yellow for 1 missing, orange for 2, gray for 3+
4. Menu page: click dot — popover shows ingredients + missing
5. Menu page: popover dismisses on click-outside and Escape
6. Menu page: print view hides indicators
7. Groceries page: hover ingredient — tooltip shows "Needed for: ..."
8. Groceries page: custom items have no tooltip
9. Both pages: real-time sync across tabs (check off on Groceries, indicators update on Menu)

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "chore: final cleanup for recipe availability feature"
```

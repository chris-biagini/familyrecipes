# Server-Render Performance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate layout shift on Menu and Groceries pages by server-rendering initial state so content is visible on first paint.

**Architecture:** Load MealPlan state in controllers and pass it to views. Menu pre-checks checkboxes; Groceries server-renders the full shopping list HTML. JS still takes over on connect — its first rebuild is invisible because server HTML matches. Remove `hidden-until-js` pattern entirely.

**Tech Stack:** Rails ERB views, Stimulus controllers (JS), CSS cleanup.

**Design doc:** `docs/plans/2026-03-03-server-render-performance-design.md`

---

### Task 1: Menu — Server-Render Pre-Checked Checkboxes

**Files:**
- Modify: `app/controllers/menu_controller.rb:14-17` (show action)
- Modify: `app/views/menu/_recipe_selector.html.erb:1` (locals declaration, checkbox lines)
- Test: `test/controllers/menu_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/menu_controller_test.rb` after the existing show tests:

```ruby
test 'show pre-checks selected recipes' do
  log_in
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select '#recipe-selector input[data-slug="focaccia"][checked]'
end

test 'show does not check unselected recipes' do
  log_in
  get menu_path(kitchen_slug: kitchen_slug)

  assert_select '#recipe-selector input[checked]', count: 0
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /pre-checks|does_not_check/`
Expected: FAIL — checkboxes don't have `checked` attribute yet.

**Step 3: Implement the controller and partial changes**

In `app/controllers/menu_controller.rb`, update `show`:

```ruby
def show
  @categories = recipe_selector_categories
  @quick_bites_by_subsection = current_kitchen.quick_bites_by_subsection
  plan = MealPlan.for_kitchen(current_kitchen)
  @selected_recipes = plan.state.fetch('selected_recipes', []).to_set
  @selected_quick_bites = plan.state.fetch('selected_quick_bites', []).to_set
end
```

In `app/views/menu/show.html.erb`, update the render call (line 35) to pass the new locals:

```erb
<%= render 'menu/recipe_selector', categories: @categories, quick_bites_by_subsection: @quick_bites_by_subsection, selected_recipes: @selected_recipes, selected_quick_bites: @selected_quick_bites %>
```

In `app/views/menu/_recipe_selector.html.erb`:

- Update locals declaration (line 1): `<%# locals: (categories:, quick_bites_by_subsection:, selected_recipes: Set.new, selected_quick_bites: Set.new) %>`
- Recipe checkbox (line 10): Add `<%= 'checked' if selected_recipes.include?(recipe.slug) %>` before the closing `>` of the input tag.
- Quick bite checkbox (line 28): Add `<%= 'checked' if selected_quick_bites.include?(item.id) %>` before the closing `>` of the input tag.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass, including the new ones.

**Step 5: Commit**

```bash
git add app/controllers/menu_controller.rb app/views/menu/_recipe_selector.html.erb app/views/menu/show.html.erb test/controllers/menu_controller_test.rb
git commit -m "feat: pre-check menu checkboxes server-side (gh-158)"
```

---

### Task 2: Menu — Remove hidden-until-js

**Files:**
- Modify: `app/views/menu/show.html.erb:23-25,27` (remove noscript, remove class)
- Modify: `app/assets/stylesheets/menu.css:1-3` (remove CSS rule)
- Modify: `app/javascript/controllers/menu_controller.js:61` (remove classList line)
- Test: `test/controllers/menu_controller_test.rb`

**Step 1: Remove the `hidden-until-js` class from the view**

In `app/views/menu/show.html.erb`:
- Delete the `<noscript>` block (lines 23-25).
- Remove `class="hidden-until-js"` from the `#menu-app` div (line 27). The div should just be `<div id="menu-app"` with its data attributes.

**Step 2: Remove the CSS rule**

In `app/assets/stylesheets/menu.css`, delete lines 1-3 (the `.hidden-until-js` block).

**Step 3: Remove the JS classList call**

In `app/javascript/controllers/menu_controller.js`, delete line 61: `this.element.classList.remove("hidden-until-js")`

**Step 4: Update the test that asserts noscript**

Check if there's a test asserting `noscript` on the menu page. There isn't one in the existing test file, so no test change needed.

**Step 5: Run all menu tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All pass.

**Step 6: Commit**

```bash
git add app/views/menu/show.html.erb app/assets/stylesheets/menu.css app/javascript/controllers/menu_controller.js
git commit -m "feat: remove hidden-until-js from menu page (gh-158)"
```

---

### Task 3: Groceries — Add Formatting Helper

**Files:**
- Create: `app/helpers/groceries_helper.rb`
- Test: `test/helpers/groceries_helper_test.rb`

The JS `formatAmounts` function formats `[[3.0, "cups"], [1.0, "tsp"]]` as `(3 cups + 1 tsp)`. We need an equivalent Ruby helper for the ERB partial.

**Step 1: Write the failing test**

Create `test/helpers/groceries_helper_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class GroceriesHelperTest < ActionView::TestCase
  test 'format_amounts with single amount and unit' do
    assert_equal '(3\u00a0cups)', format_amounts([[3.0, 'cups']])
  end

  test 'format_amounts with multiple amounts' do
    assert_equal '(3\u00a0cups + 1\u00a0tsp)', format_amounts([[3.0, 'cups'], [1.0, 'tsp']])
  end

  test 'format_amounts with unitless amount' do
    assert_equal '(2)', format_amounts([[2.0, nil]])
  end

  test 'format_amounts strips trailing zeros' do
    assert_equal '(3\u00a0cups)', format_amounts([[3.0, 'cups']])
  end

  test 'format_amounts preserves decimals when needed' do
    assert_equal '(1.5\u00a0cups)', format_amounts([[1.5, 'cups']])
  end

  test 'format_amounts returns empty string for empty array' do
    assert_equal '', format_amounts([])
  end

  test 'format_amounts returns empty string for nil' do
    assert_equal '', format_amounts(nil)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: FAIL — `GroceriesHelper` not defined.

**Step 3: Implement the helper**

Create `app/helpers/groceries_helper.rb`:

```ruby
# frozen_string_literal: true

# Formatting helpers for the groceries page. Mirrors the JS formatAmounts
# function in grocery_ui_controller.js so server-rendered shopping list
# HTML matches what JS rebuilds on state updates.
module GroceriesHelper
  def format_amounts(amounts)
    return '' if amounts.nil? || amounts.empty?

    parts = amounts.map { |value, unit| format_amount_part(value, unit) }
    "(#{parts.join(' + ')})"
  end

  private

  def format_amount_part(value, unit)
    formatted = format_number(value)
    unit ? "#{formatted}\u00a0#{unit}" : formatted
  end

  def format_number(value)
    num = value.is_a?(String) ? Float(value) : value
    num.round(2).to_s.sub(/\.0\z/, '')
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/helpers/groceries_helper_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/helpers/groceries_helper.rb test/helpers/groceries_helper_test.rb
git commit -m "feat: add format_amounts helper for groceries (gh-158)"
```

---

### Task 4: Groceries — Server-Render Shopping List

**Files:**
- Modify: `app/controllers/groceries_controller.rb:13` (show action)
- Create: `app/views/groceries/_shopping_list.html.erb`
- Modify: `app/views/groceries/show.html.erb:20-22,24,31` (remove noscript, class, embed partial)
- Modify: `app/views/groceries/_custom_items.html.erb` (accept and render items)
- Test: `test/controllers/groceries_controller_test.rb`

**Step 1: Write failing tests**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
test 'show renders shopping list header' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '.shopping-list-header h2', 'Shopping List'
end

test 'show renders empty message when no recipes selected' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '#grocery-preview-empty', 'No items yet.'
end

test 'show renders aisle sections when recipes selected' do
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'details.aisle[data-aisle="Baking"]'
  assert_select 'li[data-item="Flour"]'
  assert_select 'input[type="checkbox"][data-item="Flour"]'
end

test 'show pre-checks checked-off items' do
  Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end

  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)
  plan.apply_action('check', item: 'Flour', checked: true)

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'input[type="checkbox"][data-item="Flour"][checked]'
end

test 'show renders custom items' do
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('custom_items', item: 'Birthday candles', action: 'add')

  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select '#custom-items-list li span', 'Birthday candles'
  assert_select '#custom-items-list button.custom-item-remove[data-item="Birthday candles"]'
end
```

Also, update the existing noscript test (`renders noscript fallback` at line 78-83) to expect noscript is gone:

```ruby
test 'does not render noscript fallback' do
  log_in
  get groceries_path(kitchen_slug: kitchen_slug)

  assert_select 'noscript', count: 0
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb -n /shopping_list_header|empty_message|aisle_sections|pre-checks|custom_items|noscript/`
Expected: FAIL — shopping list isn't server-rendered yet.

**Step 3: Implement controller changes**

Update `app/controllers/groceries_controller.rb` `show` action:

```ruby
def show
  plan = MealPlan.for_kitchen(current_kitchen)
  @shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: plan).build
  @checked_off = plan.state.fetch('checked_off', []).to_set
  @custom_items = plan.state.fetch('custom_items', [])
end
```

**Step 4: Create the shopping list partial**

Create `app/views/groceries/_shopping_list.html.erb`:

```erb
<%# locals: (shopping_list:, checked_off:) %>
<div class="shopping-list-header">
  <h2>Shopping List</h2>
  <span id="item-count"><%= shopping_list_count_text(shopping_list, checked_off) %></span>
</div>

<% if shopping_list.empty? %>
  <p id="grocery-preview-empty">No items yet.</p>
<% else %>
  <% shopping_list.each do |aisle, items| %>
    <details class="aisle" data-aisle="<%= aisle %>" open>
      <summary><%= aisle %> <span class="aisle-count">(<%= items.size %>)</span></summary>
      <ul>
        <% items.each do |item| %>
          <li data-item="<%= item[:name] %>"<%= " title=\"Needed for: #{h item[:sources].join(', ')}\"" if item[:sources].present? %>>
            <label class="check-off">
              <input type="checkbox" data-item="<%= item[:name] %>"<%= ' checked' if checked_off.include?(item[:name]) %>>
              <span class="item-text"><%= item[:name] %><% amount_str = format_amounts(item[:amounts]) %><% if amount_str.present? %> <span class="item-amount"><%= amount_str %></span><% end %></span>
            </label>
          </li>
        <% end %>
      </ul>
    </details>
  <% end %>
<% end %>
```

Add the `shopping_list_count_text` helper to `app/helpers/groceries_helper.rb`:

```ruby
def shopping_list_count_text(shopping_list, checked_off)
  total = shopping_list.each_value.sum(&:size)
  return '' if total.zero?

  checked = shopping_list.each_value.sum { |items| items.count { |i| checked_off.include?(i[:name]) } }
  remaining = total - checked

  return "\u2713 All done!" if remaining.zero?

  checked.positive? ? "#{remaining} of #{total} items needed" : "#{total} #{'item'.pluralize(total)}"
end
```

**Step 5: Update the view**

In `app/views/groceries/show.html.erb`:
- Remove the `<noscript>` block (lines 20-22).
- Remove `class="hidden-until-js"` from the `#groceries-app` div (line 24).
- Replace `<div id="shopping-list"></div>` (line 31) with:

```erb
<div id="shopping-list">
  <%= render 'groceries/shopping_list', shopping_list: @shopping_list, checked_off: @checked_off %>
</div>
```

- Update the custom items render (line 33) to pass items:

```erb
<%= render 'groceries/custom_items', custom_items: @custom_items %>
```

**Step 6: Update the custom items partial**

Update `app/views/groceries/_custom_items.html.erb` to accept and render items:

```erb
<%# locals: (custom_items: []) %>
<div id="custom-items-section">
  <div id="custom-input-row">
    <label for="custom-input" class="sr-only">Add a custom item</label>
    <input type="text" id="custom-input" placeholder="Add an item...">
    <button id="custom-add" type="button" aria-label="Add item"><svg viewBox="0 0 24 24" width="18" height="18"><line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
  </div>
  <ul id="custom-items-list">
    <% custom_items.each do |name| %>
      <li>
        <span><%= name %></span>
        <button class="custom-item-remove" type="button" aria-label="Remove <%= name %>" data-item="<%= name %>">&times;</button>
      </li>
    <% end %>
  </ul>
</div>
```

**Step 7: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass.

**Step 8: Commit**

```bash
git add app/controllers/groceries_controller.rb app/views/groceries/show.html.erb app/views/groceries/_shopping_list.html.erb app/views/groceries/_custom_items.html.erb app/helpers/groceries_helper.rb
git commit -m "feat: server-render groceries shopping list (gh-158)"
```

---

### Task 5: Groceries — Remove hidden-until-js CSS and JS

**Files:**
- Modify: `app/assets/stylesheets/groceries.css:1-3` (remove CSS rule)
- Modify: `app/javascript/controllers/grocery_ui_controller.js:28` (remove classList line)

**Step 1: Remove the CSS rule**

In `app/assets/stylesheets/groceries.css`, delete lines 1-3 (the `.hidden-until-js` block).

**Step 2: Remove the JS classList call**

In `app/javascript/controllers/grocery_ui_controller.js`, delete line 28: `this.element.classList.remove("hidden-until-js")`

**Step 3: Run the full test suite**

Run: `rake test`
Expected: All pass.

**Step 4: Commit**

```bash
git add app/assets/stylesheets/groceries.css app/javascript/controllers/grocery_ui_controller.js
git commit -m "feat: remove hidden-until-js from groceries page (gh-158)"
```

---

### Task 6: Run Full Suite and Update Header Comments

**Files:**
- Modify: `app/controllers/groceries_controller.rb` (header comment)
- Modify: `app/javascript/controllers/grocery_ui_controller.js` (header comment)

**Step 1: Run lint and full test suite**

Run: `bundle exec rake`
Expected: 0 offenses, all tests pass.

**Step 2: Update architectural header comments**

`app/controllers/groceries_controller.rb` header comment should now mention that `show` builds the shopping list for server-side rendering.

`app/javascript/controllers/grocery_ui_controller.js` header comment should note that the page arrives pre-rendered and JS hydrates on connect.

**Step 3: Run lint again**

Run: `bundle exec rubocop`
Expected: 0 offenses.

**Step 4: Commit**

```bash
git add app/controllers/groceries_controller.rb app/javascript/controllers/grocery_ui_controller.js
git commit -m "docs: update header comments for server-rendered groceries (gh-158)"
```

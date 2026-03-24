# Availability Indicator Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace colored availability dots with text-based "need N" badges using native `<details>/<summary>` for inline ingredient expansion (GH #163).

**Architecture:** Pure view/CSS swap. The `RecipeAvailabilityCalculator` service and its data shape (`{ missing:, missing_names:, ingredients: }`) are unchanged. Replace the dot `<span>` with `<details>/<summary>` for missing-ingredient recipes and a `<span>` checkmark for ready recipes. Delete all dot CSS, add badge/expansion CSS.

**Tech Stack:** ERB templates, CSS, Minitest (controller integration tests)

---

### Task 1: Add controller tests for availability badge rendering

The menu controller tests currently don't assert on availability rendering at all. Add tests for the new markup before changing anything.

**Files:**
- Modify: `test/controllers/menu_controller_test.rb`

**Step 1: Write failing tests**

Add these tests after the existing "show does not check unselected recipes" test (line 79):

```ruby
test 'show renders need-N badge for recipe with missing ingredients' do
  log_in
  create_focaccia_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-detail summary', text: /need\s+1/
end

test 'show renders ready checkmark when all ingredients checked off' do
  log_in
  create_focaccia_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  plan = MealPlan.for_kitchen(@kitchen)
  plan.apply_action('check', item: 'Flour', checked: true)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'span.availability-ready', text: "\u2713"
  assert_select 'details.availability-detail', count: 0
end

test 'show renders missing ingredient names in expanded detail' do
  log_in
  create_focaccia_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-detail .availability-missing', text: 'Flour'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /availability|ready|missing/`
Expected: FAIL — no `details.availability-detail` or `span.availability-ready` elements exist yet.

---

### Task 2: Replace dot markup with details/summary in the recipe selector partial

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb`

**Step 1: Replace recipe availability dot (lines 12-14)**

Replace:
```erb
<% if (info = availability[recipe.slug]) %>
  <span class="availability-dot" data-slug="<%= recipe.slug %>" data-missing="<%= info[:missing] > 2 ? '3+' : info[:missing] %>" aria-label="<%= info[:missing].zero? ? 'All ingredients on hand' : "Missing #{info[:missing]}: #{info[:missing_names].join(', ')}" %>"></span>
<% end %>
```

With:
```erb
<% if (info = availability[recipe.slug]) %>
  <% if info[:missing].zero? %>
    <span class="availability-ready" aria-label="All ingredients on hand">&#10003;</span>
  <% else %>
    <details class="availability-detail">
      <summary aria-label="Missing <%= info[:missing] %>: <%= info[:missing_names].join(', ') %>">need&nbsp;<%= info[:missing] %></summary>
      <span class="availability-missing"><%= info[:missing_names].join(', ') %></span>
    </details>
  <% end %>
<% end %>
```

**Step 2: Replace quick bite availability dot (lines 33-35)**

Replace:
```erb
<% if (info = availability[item.id]) %>
  <span class="availability-dot" data-slug="<%= item.id %>" data-missing="<%= info[:missing].zero? ? '0' : '3+' %>" aria-label="<%= info[:missing].zero? ? 'All ingredients on hand' : "Missing #{info[:missing]}: #{info[:missing_names].join(', ')}" %>"></span>
<% end %>
```

With the same pattern (identical markup, just using `item.id` context — copy from recipe block above).

**Step 3: Run the Task 1 tests to verify they pass**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n /availability|ready|missing/`
Expected: PASS

---

### Task 3: Replace dot CSS with badge/expansion styles

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

**Step 1: Delete dot styles (lines 100-121)**

Remove the entire `.availability-dot` block and its `[data-missing]` variants.

**Step 2: Add badge and expansion styles**

Insert in the same location:

```css
/* Availability badges */
.availability-ready {
  flex-shrink: 0;
  margin-left: auto;
  padding: 0 0.4rem;
  font-size: 0.85rem;
  color: var(--checked-color);
}

.availability-detail {
  flex-shrink: 0;
  margin-left: auto;
}

.availability-detail summary {
  list-style: none;
  font-size: 0.8rem;
  color: var(--muted-text);
  cursor: pointer;
  padding: 0 0.4rem;
  white-space: nowrap;
}

.availability-detail summary::-webkit-details-marker {
  display: none;
}

.availability-detail summary:hover {
  text-decoration: underline;
}

.availability-missing {
  display: block;
  font-size: 0.75rem;
  color: var(--muted-text);
  padding: 0.15rem 0 0.15rem 0;
  font-style: italic;
}
```

**Step 3: Handle expanded content layout**

The `<li>` is `display: flex` which won't let the expanded content wrap to a new line. Add `flex-wrap: wrap` to the recipe and quick bite `<li>` selectors, and make `.availability-missing` take full width:

```css
#recipe-selector .category li,
#recipe-selector .quick-bites .subsection li {
  flex-wrap: wrap;
}

.availability-missing {
  flex-basis: 100%;
  padding-left: 1.6rem; /* align with label (checkbox width + margin) */
}
```

**Step 4: Update print styles**

Replace `.availability-dot { display: none; }` in the `@media print` block with:

```css
.availability-detail,
.availability-ready {
  display: none;
}
```

**Step 5: Verify visually**

Run: `bin/dev`
Navigate to the menu page. Verify:
- Recipes with missing ingredients show "need N" text
- Clicking "need N" expands to show missing ingredient names
- Recipes with all ingredients checked off show ✓
- Quick bites render identically
- Mobile viewport works (resize browser narrow)

---

### Task 4: Update header comments

**Files:**
- Modify: `app/services/recipe_availability_calculator.rb` (lines 1-11)
- Modify: `app/javascript/controllers/menu_controller.js` (lines 5-8)

**Step 1: Update calculator header comment**

Replace "availability dots" with "availability badges" and "dot rendering" with "badge rendering":

```ruby
# Computes per-recipe and per-quick-bite ingredient availability for the menu
# page's availability badges. For each recipe/quick bite, reports how many
# ingredients are still needed (not yet checked off on the grocery list). Used
# by MenuController for badge rendering.
```

**Step 2: Update menu controller JS header comment**

Replace:
```js
/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle,
 * select-all, and clear-all actions. All rendering (checkboxes, availability
 * dots) is server-side via Turbo Stream morphs.
 */
```

With:
```js
/**
 * Menu page recipe/quick-bite selection. Handles optimistic checkbox toggle,
 * select-all, and clear-all actions. All rendering (checkboxes, availability
 * badges) is server-side via Turbo Stream morphs.
 */
```

---

### Task 5: Run full test suite and lint

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass

**Step 3: Check html_safe audit**

Run: `rake lint:html_safe`
Expected: Pass (no new `.html_safe` or `raw()` calls)

**Step 4: Verify morph preservation**

Start the dev server (`bin/dev`), navigate to menu page:
1. Select some recipes with checked-off groceries so badges render
2. Click a "need N" badge to expand it
3. Toggle a checkbox (triggers Turbo morph)
4. Verify the expanded `<details>` stays open after morph

If it doesn't survive morphs, note it as a follow-up — a small Stimulus behavior can be added later (same pattern as grocery aisle collapse).

---

### Task 6: Commit

**Step 1: Stage and commit**

```bash
git add app/views/menu/_recipe_selector.html.erb \
       app/assets/stylesheets/menu.css \
       app/services/recipe_availability_calculator.rb \
       app/javascript/controllers/menu_controller.js \
       test/controllers/menu_controller_test.rb
git commit -m "feat: replace availability dots with text badges (#163)

Replace colored dots with 'need N' / ✓ text badges using native
<details>/<summary> for inline missing-ingredient expansion.
CVD-safe, mobile-friendly, zero JS."
```

# Menu Indicator Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make menu availability indicators visible without hover and replace cryptic circle icons with uniform "have/total" pills.

**Architecture:** Two changes in the partial (`_recipe_selector.html.erb`): clamp opacity floor and replace circle rendering with pills. CSS cleanup removes dead `.availability-single` styles and adds a `.availability-pill` class for static single-ingredient pills. Two existing tests need updating.

**Tech Stack:** ERB, CSS, Minitest

---

### Task 1: Update tests for new single-ingredient rendering

The two existing tests assert `span.availability-single` with SVG circles.
Rewrite them to expect the new static pill `<span>` with "have/total" text.

**Files:**
- Modify: `test/controllers/menu_controller_test.rb:144-164`

- [ ] **Step 1: Rewrite the "not on hand" single-ingredient test**

Replace lines 144-152:

```ruby
  test 'show renders 0/1 pill for single-ingredient recipe when not on hand' do
    log_in
    create_focaccia_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'span.availability-pill', text: '0/1'
  end
```

- [ ] **Step 2: Rewrite the "on hand" single-ingredient test**

Replace lines 154-164:

```ruby
  test 'show renders 1/1 pill for single-ingredient recipe when on hand' do
    log_in
    create_focaccia_recipe
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'span.availability-pill', text: '1/1'
  end
```

- [ ] **Step 3: Run the two tests to confirm they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n "/single-ingredient/"`

Expected: both FAIL — the partial still renders `.availability-single` SVG circles.

- [ ] **Step 4: Add a test for the opacity floor**

Add after the single-ingredient tests. This test creates a recipe with
availability below 50% and asserts the opacity class is clamped to 3.

```ruby
  test 'show clamps availability opacity to floor of 3' do
    log_in
    recipe = create_multi_ingredient_recipe(count: 6)
    create_catalog_entries_for(recipe)
    # 1 of 6 on hand = 16.7% → old formula yields 0, new formula clamps to 3
    OnHandEntry.create!(kitchen: @kitchen,
                        ingredient_name: recipe.ingredients.first.name,
                        confirmed_at: Date.current, interval: 7, ease: 1.5)

    get menu_path(kitchen_slug: kitchen_slug)

    assert_select 'details.collapse-header.opacity-3'
  end
```

Note: this test depends on `create_multi_ingredient_recipe` and
`create_catalog_entries_for` helpers. If these don't exist, check
`test/controllers/menu_controller_test.rb` for existing helper patterns and
adapt — the test may need to use `create_two_ingredient_recipe` or set up
recipes manually matching whatever helpers are available. The key assertion is
that a low-availability recipe gets `opacity-3` instead of `opacity-0`.

- [ ] **Step 5: Run the opacity floor test to confirm it fails**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n "/clamps/"`

Expected: FAIL — the partial still produces `opacity-0`.

- [ ] **Step 6: Commit the failing tests**

```bash
git add test/controllers/menu_controller_test.rb
git commit -m "Red: update menu indicator tests for pill rendering and opacity floor (GH #347)"
```

---

### Task 2: Update the partial — opacity floor and uniform pills

Replace the circle rendering with static pills and clamp the opacity formula.
Both the recipe block (lines 17-24) and the quick bite block (lines 64-72)
need identical changes.

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb:17-24` (recipe indicators)
- Modify: `app/views/menu/_recipe_selector.html.erb:64-72` (quick bite indicators)

- [ ] **Step 1: Update the opacity formula — recipe block**

On line 17, change:

```erb
<% opacity_step = (fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round %>
```

to:

```erb
<% opacity_step = [(fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round, 3].max %>
```

- [ ] **Step 2: Replace the circle with a static pill — recipe block**

Replace lines 18-24 (the `if total == 1` / `else` / `end` block) with:

```erb
<% if total == 1 %>
  <span class="availability-pill opacity-<%= opacity_step %>"><%= have_count %>/<%= total %></span>
<% else %>
  <details class="collapse-header<%= ' all-on-hand' if info[:missing].zero? %> opacity-<%= opacity_step %>">
    <summary aria-label="Have <%= have_count %> of <%= total %><%= info[:missing_names].any? ? '; missing: ' + info[:missing_names].join(', ') : '' %>"><%= have_count %>/<%= total %></summary>
  </details>
<% end %>
```

- [ ] **Step 3: Update the opacity formula — quick bite block**

On line 65, apply the same clamp:

```erb
<% opacity_step = [(fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round, 3].max %>
```

- [ ] **Step 4: Replace the circle with a static pill — quick bite block**

Replace the quick bite `if total == 1` / `else` / `end` block (lines 66-72)
with the same pill markup as step 2 (identical code).

- [ ] **Step 5: Run the failing tests from Task 1**

Run: `ruby -Itest test/controllers/menu_controller_test.rb -n "/single-ingredient|clamps/"`

Expected: all three PASS.

- [ ] **Step 6: Run the full menu test file**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`

Expected: all tests PASS. Existing tests for multi-ingredient indicators
should be unaffected.

- [ ] **Step 7: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb
git commit -m "Replace circle indicators with uniform pills, add opacity floor (GH #347)"
```

---

### Task 3: CSS cleanup

Remove the dead `.availability-single` styles, add `.availability-pill` styles,
and update selectors that referenced the old class.

**Files:**
- Modify: `app/assets/stylesheets/menu.css:69-84` (remove `.availability-single`)
- Modify: `app/assets/stylesheets/menu.css:122-128` (update hover rule)
- Modify: `app/assets/stylesheets/menu.css:466` (update print rule)

- [ ] **Step 1: Replace `.availability-single` with `.availability-pill`**

Replace the `.availability-single` block (lines 69-84) with:

```css
/* Static pill for single-ingredient items (no disclosure triangle) */
.availability-pill {
  flex-shrink: 0;
  margin-left: auto;
  font-family: var(--font-body);
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--red);
  padding: 0.15rem 0.5rem;
  white-space: nowrap;
  background: var(--surface-alt);
  border: 1px solid var(--red);
  border-radius: 6px;
  transition: opacity var(--duration-fast) ease;
}
```

This matches the existing `.collapse-header summary` styles so pills look
identical whether static or expandable.

- [ ] **Step 2: Update the hover-reveal selector**

Replace lines 122-128:

```css
/* Snap availability pill opacity to full on row hover */
@media (hover: hover) {
  #recipe-selector li:hover .availability-pill,
  #recipe-selector li:hover .collapse-header {
    opacity: 1 !important;
  }
}
```

- [ ] **Step 3: Update the print media rule**

In the `@media print` block, replace line 466:

```css
  .availability-pill,
```

(replacing `.availability-single,` — the rest of the rule stays the same)

- [ ] **Step 4: Run the full menu tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`

Expected: all PASS.

- [ ] **Step 5: Run full test suite**

Run: `rake test`

Expected: all PASS. No other files reference `.availability-single`.

- [ ] **Step 6: Run lint**

Run: `bundle exec rubocop`

Expected: 0 offenses.

- [ ] **Step 7: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Replace .availability-single CSS with .availability-pill (GH #347)"
```

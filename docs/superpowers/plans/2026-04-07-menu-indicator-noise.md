# Menu Availability Indicator Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the noisy X/Y fraction + 10-step opacity availability indicators with a three-tier system (Ready ✓ / Close "Need N" / Far "Need N" muted) that is CVD-safe, mobile-discoverable, and visually calm.

**Architecture:** The partial computes a `missing` count from the existing availability hash and assigns one of three CSS tier classes. `<details>`/`<summary>` is retained for all items (including single-ingredient), with the disclosure marker hidden via CSS and the summary styled as the pill. The 10-step opacity scale is replaced by three tier classes plus an opacity rule for "far" items.

**Tech Stack:** Rails ERB partial, CSS, Stimulus controller (minor selector update), Minitest

**Spec:** `docs/superpowers/specs/2026-04-07-menu-indicator-noise-design.md`

---

### Task 1: Update tests for new tier rendering

**Files:**
- Modify: `test/controllers/menu_controller_test.rb:131-219`

- [ ] **Step 1: Replace the "M/N badge when partially available" test**

The current test at line 131 asserts `details.collapse-header summary` text matches `%r{1/2}`. Replace it with a test that asserts the "Need N" text and `availability-close` class (1 of 2 on hand = 1 missing = "close" tier):

```ruby
test 'show renders Need N pill for close-tier recipe' do
  log_in
  create_two_ingredient_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                      confirmed_at: Date.current, interval: 7, ease: 1.5)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-close summary', text: 'Need 1'
end
```

- [ ] **Step 2: Replace the "0/1 pill single-ingredient not on hand" test**

The current test at line 144 asserts `span.availability-pill` text `'0/1'`. Single-ingredient items now use `<details>` too. 0 of 1 on hand = 1 missing = "close" tier:

```ruby
test 'show renders Need 1 pill for single-ingredient recipe when not on hand' do
  log_in
  create_focaccia_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-close summary', text: 'Need 1'
end
```

- [ ] **Step 3: Replace the "1/1 pill single-ingredient on hand" test**

The current test at line 154 asserts `span.availability-pill` text `'1/1'`. Now it should be a ✓ with `availability-ready` class:

```ruby
test 'show renders checkmark pill for single-ingredient recipe when on hand' do
  log_in
  create_focaccia_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                      confirmed_at: Date.current, interval: 7, ease: 1.5)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-ready summary', text: '✓'
end
```

- [ ] **Step 4: Replace the "clamps opacity to floor of 3" test**

The current test at line 166 asserts `details.collapse-header.opacity-3`. The new system uses `availability-far` class instead (1 of 3 on hand = 2 missing... wait, that's "close" tier). We need 3+ missing for "far". Update the test to check for the `availability-far` class with a scenario where 3+ are missing:

```ruby
test 'show renders far-tier pill for recipe missing 3 or more' do
  log_in
  create_three_ingredient_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
  create_catalog_entry('Olive Oil', basis_grams: 14, aisle: 'Oils')

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-far summary', text: 'Need 3'
end
```

- [ ] **Step 5: Replace the "checkmark-only pill when all on hand" test**

The current test at line 181 asserts `details.collapse-header.all-on-hand summary` text `2/2`. Replace with `availability-ready` and ✓:

```ruby
test 'show renders checkmark pill when multi-ingredient recipe all on hand' do
  log_in
  create_two_ingredient_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                      confirmed_at: Date.current, interval: 7, ease: 1.5)
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                      confirmed_at: Date.current, interval: 7, ease: 1.5)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-ready summary', text: '✓'
end
```

- [ ] **Step 6: Add a test for close-tier with 2 missing**

Verify the boundary: 2 missing is still "close":

```ruby
test 'show renders close-tier pill when missing exactly 2' do
  log_in
  create_three_ingredient_recipe
  create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
  create_catalog_entry('Salt', basis_grams: 5, aisle: 'Baking')
  create_catalog_entry('Olive Oil', basis_grams: 14, aisle: 'Oils')
  OnHandEntry.create!(kitchen: @kitchen, ingredient_name: 'Salt',
                      confirmed_at: Date.current, interval: 7, ease: 1.5)

  get menu_path(kitchen_slug: kitchen_slug)

  assert_select 'details.availability-close summary', text: 'Need 2'
end
```

- [ ] **Step 7: Keep the have/missing detail test unchanged**

The test at line 208 (`assert_select '.availability-have'` / `.availability-need'`) should pass as-is since the collapse body markup isn't changing. No action needed — just verify it still passes after implementation.

- [ ] **Step 8: Run the tests to confirm they fail**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: The 5 replaced tests and 1 new test FAIL (old markup doesn't match new assertions). The have/missing detail test should still PASS.

- [ ] **Step 9: Commit**

```bash
git add test/controllers/menu_controller_test.rb
git commit -m "Red: update menu indicator tests for three-tier pill system (GH #351)"
```

---

### Task 2: Update the partial to render three-tier pills

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb`

The partial has two nearly identical blocks of availability rendering — one for recipes (lines 12–35) and one for quick bites (lines 60–83). Both need the same changes.

- [ ] **Step 1: Replace the recipe availability block (lines 12–25)**

Replace the current rendering logic with tier-based rendering. The key changes:
- Remove the `fraction` / `opacity_step` calculation
- Compute `missing = info[:missing]` directly
- Assign tier class: `availability-ready` (0 missing), `availability-close` (1–2), `availability-far` (3+)
- Pill text: `"✓"` for ready, `"Need #{missing}"` for close/far
- All items use `<details>`/`<summary>` uniformly (no more `<span>` for single-ingredient)
- Remove the `all-on-hand` class
- Add `aria-label` to `<details>` for accessibility and morph preservation

Replace lines 12–25 of the partial (the `<% if info %>` block inside the recipe loop) with:

```erb
<% info = availability[recipe.slug] %>
<% if info %>
  <% missing = info[:missing] %>
  <% tier = missing.zero? ? 'ready' : missing <= 2 ? 'close' : 'far' %>
  <% pill_text = missing.zero? ? '✓' : "Need #{missing}" %>
  <details class="availability-<%= tier %>"
           aria-label="<%= missing.zero? ? 'All on hand' : "Need #{missing}; missing: #{info[:missing_names].join(', ')}" %>">
    <summary><%= pill_text %></summary>
  </details>
<% end %>
```

- [ ] **Step 2: Replace the quick bite availability block (lines 60–72)**

Apply the same change to the quick bite block. Replace the `<% if info %>` block inside the quick bite loop with:

```erb
<% info = availability[item.id] %>
<% if info %>
  <% missing = info[:missing] %>
  <% tier = missing.zero? ? 'ready' : missing <= 2 ? 'close' : 'far' %>
  <% pill_text = missing.zero? ? '✓' : "Need #{missing}" %>
  <details class="availability-<%= tier %>"
           aria-label="<%= missing.zero? ? 'All on hand' : "Need #{missing}; missing: #{info[:missing_names].join(', ')}" %>">
    <summary><%= pill_text %></summary>
  </details>
<% end %>
```

- [ ] **Step 3: Update the collapse body conditional for recipes**

The current collapse body (lines 27–35) only renders for multi-ingredient items (`if info && info[:ingredients].size > 1`). Now all items use `<details>`, so the body should render for all items with availability info. For ready-tier items, show only the "Have" list. The collapse body selector also needs to be inside the `<details>` tag for the `[open]` sibling selector to work — but looking at the current markup, the collapse body is a *sibling* of the `<details>`, not a child. This works because of the CSS rule `details.collapse-header[open] ~ .collapse-body > .collapse-inner`.

Keep the collapse body as a sibling of `<details>`, but change the conditional from `info[:ingredients].size > 1` to just `info`:

```erb
<% if info %>
  <div class="collapse-body">
    <div class="collapse-inner">
      <% have = info[:ingredients] - info[:missing_names] %>
      <% if have.any? %><div class="availability-have"><strong>Have</strong><span><%= have.join(', ') %></span></div><% end %>
      <% if info[:missing_names].any? %><div class="availability-need"><strong>Missing</strong><span><%= info[:missing_names].join(', ') %></span></div><% end %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: Apply the same collapse body change for quick bites**

Same change: replace `if info && info[:ingredients].size > 1` with `if info`.

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: The new tier tests should now PASS. The have/missing detail test should still PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb
git commit -m "Render three-tier availability pills in menu partial (GH #351)"
```

---

### Task 3: Update CSS for three-tier styling

**Files:**
- Modify: `app/assets/stylesheets/menu.css`

- [ ] **Step 1: Replace `.availability-pill` and `.collapse-header` pill styles (lines 69–106) with tier classes**

Remove the old `.availability-pill`, `.collapse-header`, `.collapse-header summary`, and `.collapse-header summary::before` rules. Replace with shared base styles and three tier classes:

```css
/* Shared availability pill base (applied to all three tier classes) */
.availability-ready,
.availability-close,
.availability-far {
  flex-shrink: 0;
  margin-left: auto;
  transition: opacity var(--duration-fast) ease;
}

.availability-ready summary,
.availability-close summary,
.availability-far summary {
  font-family: var(--font-body);
  font-size: 0.75rem;
  font-weight: 500;
  padding: 0.15rem 0.5rem;
  white-space: nowrap;
  border-radius: 6px;
  cursor: pointer;
  list-style: none;
}

.availability-ready summary::marker,
.availability-close summary::marker,
.availability-far summary::marker {
  display: none;
}

.availability-ready summary::-webkit-details-marker,
.availability-close summary::-webkit-details-marker,
.availability-far summary::-webkit-details-marker {
  display: none;
}

/* Ready tier — green */
.availability-ready summary {
  color: #4a8c3f;
  background: rgba(74, 140, 63, 0.08);
  border: 1px solid rgba(74, 140, 63, 0.25);
}

/* Close tier — amber */
.availability-close summary {
  color: #946b1a;
  background: rgba(200, 160, 32, 0.08);
  border: 1px solid rgba(200, 160, 32, 0.25);
}

/* Far tier — amber at reduced opacity */
.availability-far {
  opacity: 0.45;
}

.availability-far summary {
  color: #946b1a;
  background: rgba(200, 160, 32, 0.08);
  border: 1px solid rgba(200, 160, 32, 0.25);
}
```

- [ ] **Step 2: Remove the opacity scale classes (lines 108–119)**

Delete the `.opacity-0` through `.opacity-10` rules entirely.

- [ ] **Step 3: Update the hover-reveal rule (lines 121–127)**

Replace the old selectors with the new tier class selectors:

```css
@media (hover: hover) {
  #recipe-selector li:hover .availability-ready,
  #recipe-selector li:hover .availability-close,
  #recipe-selector li:hover .availability-far {
    opacity: 1 !important;
  }
}
```

- [ ] **Step 4: Update the collapse body `[open]` sibling selector (line 143)**

The current rule is `.recipe-selector-item .collapse-header[open] ~ .collapse-body > .collapse-inner`. Update the selector to match any tier class:

```css
.recipe-selector-item details[open] ~ .collapse-body > .collapse-inner {
  padding-top: 0.4rem;
  padding-bottom: 0.4rem;
}
```

- [ ] **Step 5: Update the print styles (lines 465–469)**

Replace the old selectors in the print block:

```css
.availability-ready,
.availability-close,
.availability-far,
.recipe-selector-item .collapse-body {
  display: none;
}
```

- [ ] **Step 6: Run the tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add app/assets/stylesheets/menu.css
git commit -m "Replace opacity scale with three-tier availability pill CSS (GH #351)"
```

---

### Task 4: Update menu_controller.js morph preservation

**Files:**
- Modify: `app/javascript/controllers/menu_controller.js`

- [ ] **Step 1: Update the `preserveOpenDetails` selector**

The current selector on line 38 queries for `details.collapse-header[open] summary`. Update it to match any of the three tier classes:

```javascript
const openSummaries = Array.from(this.element.querySelectorAll(
  "details.availability-ready[open] summary, details.availability-close[open] summary, details.availability-far[open] summary"
)).map(s => s.closest("details").getAttribute("aria-label"))
```

Note: the `aria-label` is now on the `<details>` element, not the `<summary>`, so we read it from the parent.

- [ ] **Step 2: Update the restoration selector**

The current selector on line 47 queries for `details.collapse-header summary[aria-label="..."]`. Update to match via the `<details>` element's `aria-label`:

```javascript
openSummaries.forEach(label => {
  const details = this.element.querySelector(`details[aria-label="${CSS.escape(label)}"]`)
  if (details) details.open = true
})
```

- [ ] **Step 3: Build JS**

Run: `npm run build`
Expected: Build succeeds without errors.

- [ ] **Step 4: Run all tests**

Run: `ruby -Itest test/controllers/menu_controller_test.rb`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/menu_controller.js
git commit -m "Update morph preservation selectors for tier-based pills (GH #351)"
```

---

### Task 5: Full test suite and lint

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `rake test`
Expected: All tests PASS. No Bullet N+1 warnings.

- [ ] **Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. If the partial changes trigger any offenses, fix them.

- [ ] **Step 3: Run JS build**

Run: `npm run build`
Expected: Clean build.

- [ ] **Step 4: Update `html_safe_allowlist.yml` if needed**

If line numbers shifted in files that use `.html_safe`, update the allowlist. Check with:

Run: `rake lint:html_safe`
Expected: PASS.

- [ ] **Step 5: Commit any fixes**

Only if previous steps revealed issues to fix.

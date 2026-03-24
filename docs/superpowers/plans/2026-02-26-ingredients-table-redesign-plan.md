# Ingredients Table Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the ingredients page with filter-count buttons, sortable table headers, click-to-edit rows, and a cleaner layout.

**Architecture:** Pure client-side changes for sorting/filtering (Stimulus controller), server-side view changes for layout, and editor dialog additions for recipe links and reset button. No new routes needed — the existing `edit` action gets enhanced. The `show` action and detail panel are removed.

**Tech Stack:** Rails views (ERB), Stimulus JS, CSS, Minitest

---

### Task 0: Remove detail panel and show action

**Files:**
- Delete: `app/views/ingredients/_detail_panel.html.erb`
- Modify: `app/controllers/ingredients_controller.rb` — remove `show` action and `load_ingredient_or_not_found`, `recipes_for_ingredient` methods
- Modify: `config/routes.rb:14` — remove `ingredient_detail` route
- Modify: `test/controllers/ingredients_controller_test.rb` — remove show tests (lines 128-149, 297-331)
- Modify: `test/integration/end_to_end_test.rb` — remove or rewrite the detail panel test (line 232)

**Step 1: Remove show action from controller**

In `app/controllers/ingredients_controller.rb`, delete:
- The `show` method (lines 16-22)
- The `load_ingredient_or_not_found` method (lines 59-71)
- The `recipes_for_ingredient` method (lines 73-77)

**Step 2: Remove route**

In `config/routes.rb`, delete line 14:
```ruby
get 'ingredients/:ingredient_name', to: 'ingredients#show', as: :ingredient_detail
```

**Step 3: Delete detail panel partial**

Delete `app/views/ingredients/_detail_panel.html.erb`.

**Step 4: Update tests**

In `test/controllers/ingredients_controller_test.rb`:
- Remove "detail panel includes recipe links" test (line 128)
- Remove the three show action tests (lines 297-331)

In `test/integration/end_to_end_test.rb`:
- Remove or rewrite "ingredients detail panel links back to recipe pages" test (line 232). Since recipe links now appear in the editor form, rewrite to test the edit action instead:
```ruby
test 'ingredients edit form shows recipe links' do
  log_in
  get ingredient_edit_path('Mozzarella', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'a[href=?]', recipe_path('white-pizza', kitchen_slug: kitchen_slug)
end
```

**Step 5: Run tests, commit**

```bash
bundle exec rake test
git add -A && git commit -m "refactor: remove ingredient detail panel and show action"
```

---

### Task 1: Add recipe links to editor form

**Files:**
- Modify: `app/controllers/ingredients_controller.rb` — pass recipes to editor form
- Modify: `app/views/ingredients/_editor_form.html.erb` — add "Used in" section at bottom
- Modify: `test/controllers/ingredients_controller_test.rb` — add test for recipe links in editor

**Step 1: Pass recipes from edit action**

In `app/controllers/ingredients_controller.rb`, update `edit`:
```ruby
def edit
  ingredient_name, entry = load_ingredient_data
  aisles = current_kitchen.all_aisles
  recipes = recipes_for_ingredient(ingredient_name)

  render partial: 'ingredients/editor_form',
         locals: { ingredient_name:, entry:, available_aisles: aisles,
                   next_name: next_needing_attention(ingredient_name),
                   recipes: recipes }
end
```

Add a `recipes_for_ingredient` private method:
```ruby
def recipes_for_ingredient(name)
  lookup = IngredientCatalog.lookup_for(current_kitchen)
  current_kitchen.recipes.includes(steps: :ingredients).select do |recipe|
    recipe.ingredients.any? { |i| (lookup[i.name]&.ingredient_name || i.name) == name }
  end
end
```

**Step 2: Add "Used in" section to editor form**

At the bottom of `app/views/ingredients/_editor_form.html.erb`, before the closing `</div>` of `.editor-form`, add a locals declaration update and a new section:

Update locals line to accept `recipes: []`:
```erb
<%# locals: (ingredient_name:, entry:, available_aisles:, next_name: nil, recipes: []) %>
```

Add after the aisle fieldset:
```erb
<% if recipes.any? %>
  <div class="editor-recipes">
    <span class="editor-recipes-label">Used in</span>
    <% recipes.each_with_index do |recipe, i| %>
      <% unless i.zero? %>, <% end %>
      <%= link_to recipe.title, recipe_path(recipe.slug), target: "_blank" %>
    <% end %>
  </div>
<% end %>
```

**Step 3: Add CSS for the recipe links section**

In `app/assets/stylesheets/style.css`, in the editor section:
```css
.editor-recipes {
  font-size: 0.85rem;
  color: var(--muted-text);
  padding-top: 0.75rem;
  border-top: 1px solid var(--border-color, #e5e7eb);
}
.editor-recipes-label {
  font-weight: 600;
  margin-right: 0.25em;
}
.editor-recipes a { white-space: nowrap; }
```

**Step 4: Add test**

In `test/controllers/ingredients_controller_test.rb`, add:
```ruby
test 'edit includes recipe links for ingredient' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'a', text: 'Focaccia'
end
```

**Step 5: Run tests, commit**

```bash
bundle exec rake test
git add -A && git commit -m "feat: show recipe links in ingredient editor form"
```

---

### Task 2: Move reset-to-built-in button into editor

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb` — add reset button
- Modify: `app/assets/stylesheets/style.css` — style the reset button in editor context

**Step 1: Add reset button to editor form**

In `_editor_form.html.erb`, after the "Used in" section (or after the aisle section if no recipes), add:
```erb
<% if entry&.custom? %>
  <div class="editor-reset">
    <button type="button" class="btn btn-small btn-secondary"
            data-reset-ingredient
            data-ingredient-name="<%= ingredient_name %>">Reset to built-in</button>
  </div>
<% end %>
```

**Step 2: Add CSS**

```css
.editor-reset {
  padding-top: 0.75rem;
  border-top: 1px solid var(--border-color, #e5e7eb);
}
```

If a "Used in" section precedes it, only one of them needs the border-top. Use `.editor-recipes + .editor-reset { border-top: none; }`.

**Step 3: Run tests, commit**

```bash
bundle exec rake test
git add -A && git commit -m "feat: move reset-to-built-in button into editor dialog"
```

---

### Task 3: Rewrite table row partial — remove expansion, add badge, simplify icons

**Files:**
- Modify: `app/views/ingredients/_table_row.html.erb` — single `<tr>`, no expand row, add badge, add `data-open-editor`
- Modify: `app/helpers/ingredients_helper.rb` — remove tristate density helpers
- Modify: `test/controllers/ingredients_controller_test.rb` — update assertions that check col-recipes

**Step 1: Rewrite `_table_row.html.erb`**

Replace the entire file with a single `<tbody>` containing one `<tr>`:

```erb
<%# locals: (row:) %>
<tbody id="ingredient-<%= row[:name].parameterize %>">
<tr class="ingredient-row"
    data-ingredient-table-target="row"
    data-ingredient-name="<%= row[:name] %>"
    data-status="<%= row[:status] %>"
    data-has-nutrition="<%= row[:has_nutrition] %>"
    data-has-density="<%= row[:has_density] %>"
    data-aisle="<%= row[:aisle] || '' %>"
    data-open-editor
    tabindex="0"
    role="button"
    data-action="click->ingredient-table#openEditor keydown->ingredient-table#rowKeydown">
  <td class="col-name">
    <%= row[:name] %>
    <span class="source-badge source-<%= row[:source] %>"><%= row[:source] %></span>
  </td>
  <td class="col-nutrition" aria-label="<%= row[:has_nutrition] ? 'Has nutrition' : 'Missing nutrition' %>">
    <span class="status-icon <%= row[:has_nutrition] ? 'status-yes' : 'status-no' %>">
      <%= row[:has_nutrition] ? "\u2713" : "\u2717" %>
    </span>
  </td>
  <td class="col-density" aria-label="<%= row[:has_density] ? 'Has density' : 'Missing density' %>">
    <span class="status-icon <%= row[:has_density] ? 'status-yes' : 'status-no' %>">
      <%= row[:has_density] ? "\u2713" : "\u2717" %>
    </span>
  </td>
  <td class="col-aisle"><%= display_aisle(row[:aisle]) %></td>
</tr>
</tbody>
```

Key changes:
- No expansion row
- `data-open-editor` on the `<tr>` itself (nutrition_editor_controller picks this up)
- Binary ✓/✗ for both nutrition and density
- Source badge inline in the name cell
- No recipes column
- New `data-aisle` attribute for client-side sorting

**Step 2: Simplify helper**

In `app/helpers/ingredients_helper.rb`, remove `density_icon_class`, `density_icon_text`, `density_aria_label` methods (no longer needed).

**Step 3: Update controller tests**

Remove or rewrite any tests that assert on `td.col-recipes`. Update the two tests in `ingredients_controller_test.rb`:
- "groups multiple recipes under the same ingredient" — remove the `col-recipes` assertion, just check the row exists
- "does not duplicate a recipe under the same ingredient" — same

**Step 4: Run tests, commit**

```bash
bundle exec rake test && bundle exec rake lint
git add -A && git commit -m "refactor: simplify table rows — remove expansion, binary status icons, inline badges"
```

---

### Task 4: Rewrite filter buttons with integrated counts

**Files:**
- Modify: `app/views/ingredients/index.html.erb` — replace summary bar + pills with count buttons
- Modify/Delete: `app/views/ingredients/_summary_bar.html.erb` — no longer a separate partial (counts live in filter buttons)
- Modify: `app/javascript/controllers/ingredient_table_controller.js` — update filter logic for new filter values
- Modify: `app/views/nutrition_entries/upsert.turbo_stream.erb` — update Turbo Stream to replace new filter bar
- Modify: `app/assets/stylesheets/style.css` — update filter pill styles, remove old summary styles

**Step 1: Replace the index.html.erb toolbar section**

Remove the `_summary_bar` render and the old filter pills. Replace with:

```erb
<div class="ingredients-toolbar">
  <input type="search" class="ingredients-search"
         placeholder="Search ingredients…"
         aria-label="Search ingredients"
         data-ingredient-table-target="searchInput"
         data-action="input->ingredient-table#search"
         autocomplete="off">
  <div id="ingredients-summary" class="filter-pills" role="group" aria-label="Filter ingredients">
    <button type="button" class="filter-pill active"
            data-ingredient-table-target="filterButton"
            data-filter="all"
            data-action="click->ingredient-table#filter"
            aria-pressed="true">All (<%= @summary[:total] %>)</button>
    <button type="button" class="filter-pill"
            data-ingredient-table-target="filterButton"
            data-filter="complete"
            data-action="click->ingredient-table#filter"
            aria-pressed="false">Complete (<%= @summary[:complete] %>)</button>
    <button type="button" class="filter-pill"
            data-ingredient-table-target="filterButton"
            data-filter="missing_nutrition"
            data-action="click->ingredient-table#filter"
            aria-pressed="false">Missing Nutrition (<%= @summary[:missing_nutrition] %>)</button>
    <button type="button" class="filter-pill"
            data-ingredient-table-target="filterButton"
            data-filter="missing_density"
            data-action="click->ingredient-table#filter"
            aria-pressed="false">Missing Density (<%= @summary[:missing_density] %>)</button>
  </div>
</div>
```

Note: the `id="ingredients-summary"` moves onto the filter pills `<div>` so the Turbo Stream from upsert can still replace it.

Remove the old "Showing X of Y" `<p>` at the bottom. Remove the `countLabel` target reference.

**Step 2: Rewrite `_summary_bar.html.erb` to render filter buttons**

Replace the summary bar partial content so it can be rendered both from `index.html.erb` and from the Turbo Stream:

```erb
<%# locals: (summary:, active_filter: 'all') %>
<button type="button" class="filter-pill <%= 'active' if active_filter == 'all' %>"
        data-ingredient-table-target="filterButton"
        data-filter="all"
        data-action="click->ingredient-table#filter"
        aria-pressed="<%= active_filter == 'all' %>">All (<%= summary[:total] %>)</button>
<button type="button" class="filter-pill <%= 'active' if active_filter == 'complete' %>"
        data-ingredient-table-target="filterButton"
        data-filter="complete"
        data-action="click->ingredient-table#filter"
        aria-pressed="<%= active_filter == 'complete' %>">Complete (<%= summary[:complete] %>)</button>
<button type="button" class="filter-pill <%= 'active' if active_filter == 'missing_nutrition' %>"
        data-ingredient-table-target="filterButton"
        data-filter="missing_nutrition"
        data-action="click->ingredient-table#filter"
        aria-pressed="<%= active_filter == 'missing_nutrition' %>">Missing Nutrition (<%= summary[:missing_nutrition] %>)</button>
<button type="button" class="filter-pill <%= 'active' if active_filter == 'missing_density' %>"
        data-ingredient-table-target="filterButton"
        data-filter="missing_density"
        data-action="click->ingredient-table#filter"
        aria-pressed="<%= active_filter == 'missing_density' %>">Missing Density (<%= summary[:missing_density] %>)</button>
```

Then `index.html.erb` renders this partial inside the `#ingredients-summary` div, and the Turbo Stream replaces it the same way.

**Step 3: Update Stimulus controller filter logic**

In `ingredient_table_controller.js`, update `matchesStatus`:
```javascript
matchesStatus(status, hasNutrition, hasDensity) {
  if (this.currentFilter === "all") return true
  if (this.currentFilter === "complete") return status === "complete"
  if (this.currentFilter === "missing_nutrition") return hasNutrition === "false"
  if (this.currentFilter === "missing_density") return hasNutrition === "true" && hasDensity === "false"
  return true
}
```

Update `applyFilters` to pass the row's data attributes:
```javascript
const matchesFilter = this.matchesStatus(
  row.dataset.status,
  row.dataset.hasNutrition,
  row.dataset.hasDensity
)
```

Remove the `countLabel` target and related code from `applyFilters`. Remove `countLabelTarget` from `static targets`.

**Step 4: Update CSS**

Remove `.ingredients-summary`, `.summary-count`, `.summary-sep`, `.summary-attention` rules. Remove `.ingredients-count`. Keep filter pill styles.

**Step 5: Update test assertions**

In `test/controllers/ingredients_controller_test.rb`, the test "shows missing ingredients banner when nutrition data is absent" (line 276) currently asserts `assert_select '.ingredients-summary'`. Update to assert the filter buttons wrapper exists:
```ruby
assert_select '#ingredients-summary'
```

**Step 6: Run tests, commit**

```bash
bundle exec rake test && bundle exec rake lint
git add -A && git commit -m "feat: merge filter buttons with summary counts"
```

---

### Task 5: Update table headers and add sort functionality

**Files:**
- Modify: `app/views/ingredients/index.html.erb` — full-word headers with sort attributes
- Modify: `app/javascript/controllers/ingredient_table_controller.js` — add sorting
- Modify: `app/assets/stylesheets/style.css` — Futura headers, sort indicator styles

**Step 1: Update table headers in `index.html.erb`**

```erb
<table class="ingredients-table" data-ingredient-table-target="table">
  <thead>
    <tr>
      <th class="col-name sortable" data-sort-key="name" data-action="click->ingredient-table#sort"
          role="columnheader" aria-sort="ascending">
        Ingredient<span class="sort-arrow" aria-hidden="true"></span>
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
  <% @ingredient_rows.each do |row| %>
    <%= render 'ingredients/table_row', row: row %>
  <% end %>
</table>
```

**Step 2: Add sorting to Stimulus controller**

Add `table` to static targets. Add state:

```javascript
connect() {
  this.currentFilter = "all"
  this.sortKey = "name"
  this.sortAsc = true
}
```

Add sort method:
```javascript
sort(event) {
  const key = event.currentTarget.dataset.sortKey
  if (this.sortKey === key) {
    this.sortAsc = !this.sortAsc
  } else {
    this.sortKey = key
    this.sortAsc = true
  }

  this.updateSortIndicators()
  this.sortRows()
}

updateSortIndicators() {
  this.element.querySelectorAll("th.sortable").forEach(th => {
    const arrow = th.querySelector(".sort-arrow")
    if (th.dataset.sortKey === this.sortKey) {
      th.setAttribute("aria-sort", this.sortAsc ? "ascending" : "descending")
      arrow.textContent = this.sortAsc ? " \u25B2" : " \u25BC"
    } else {
      th.removeAttribute("aria-sort")
      arrow.textContent = ""
    }
  })
}

sortRows() {
  const table = this.tableTarget
  const tbody = Array.from(table.querySelectorAll("tbody"))

  tbody.sort((a, b) => {
    const rowA = a.querySelector("tr")
    const rowB = b.querySelector("tr")
    const valA = this.sortValue(rowA)
    const valB = this.sortValue(rowB)

    let cmp = 0
    if (typeof valA === "string") {
      cmp = valA.localeCompare(valB)
    } else {
      cmp = valA - valB
    }
    return this.sortAsc ? cmp : -cmp
  })

  tbody.forEach(tb => table.appendChild(tb))
}

sortValue(row) {
  switch (this.sortKey) {
    case "name":
      return (row.dataset.ingredientName || "").toLowerCase()
    case "nutrition":
      return row.dataset.hasNutrition === "true" ? 0 : 1
    case "density":
      return row.dataset.hasDensity === "true" ? 0 : 1
    case "aisle": {
      const aisle = (row.dataset.aisle || "").toLowerCase()
      return aisle || "\uffff"  // empty sorts last
    }
    default:
      return ""
  }
}
```

**Step 3: Add CSS for headers**

```css
.ingredients-table thead th {
  text-align: left;
  font-family: 'Futura', 'Trebuchet MS', Arial, sans-serif;
  font-size: 0.8rem;
  font-weight: 600;
  letter-spacing: 0.03em;
  color: var(--muted-text);
  padding: 0.4rem 0.5rem;
  border-bottom: 2px solid var(--border-color, #e5e7eb);
}

.sortable { cursor: pointer; user-select: none; white-space: nowrap; }
.sortable:hover { color: var(--text-color, #1f2937); }
.sort-arrow { font-size: 0.65rem; margin-left: 0.15em; }
```

Remove old uppercase text-transform from headers — use Futura's natural casing instead.

**Step 4: Run tests, commit**

```bash
bundle exec rake test && bundle exec rake lint
git add -A && git commit -m "feat: sortable table headers in Futura with sort indicators"
```

---

### Task 6: Wire row click to open editor, remove expansion code

**Files:**
- Modify: `app/javascript/controllers/ingredient_table_controller.js` — remove `toggleRow`, `collapseRow`, `collapseCurrentRow`, `hideExpandRowWhenFiltered`, add `openEditor`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js` — no changes needed (already listens for `[data-open-editor]` clicks)

**Step 1: Add `openEditor` method to ingredient_table_controller**

```javascript
openEditor(event) {
  // Don't intercept if they clicked a link inside the row
  if (event.target.closest("a")) return
  // The [data-open-editor] attribute on the row lets nutrition_editor_controller handle it
}

rowKeydown(event) {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault()
    event.currentTarget.click()
  }
}
```

Actually, since the `<tr>` has `data-open-editor` and `data-ingredient-name`, the `nutrition_editor_controller`'s document click listener already handles it. The `ingredient_table_controller` just needs to NOT interfere. The `openEditor` action on the row is effectively a no-op — the nutrition_editor_controller's delegated listener fires on the same click.

Wait — there's a subtlety. The nutrition_editor_controller listens for `event.target.closest("[data-open-editor]")`. Since `data-open-editor` is on the `<tr>`, and the user clicks a `<td>` inside it, `.closest("[data-open-editor]")` will find the `<tr>`. That works.

So the ingredient_table_controller's `openEditor` method can simply be empty (the event bubbles to the nutrition_editor_controller's document listener). But we should keep `rowKeydown` to translate Enter/Space into a click.

**Step 2: Remove expansion code**

Remove from `ingredient_table_controller.js`:
- `toggleRow` method
- `collapseRow` method
- `collapseCurrentRow` method
- `hideExpandRowWhenFiltered` method
- `expandIdFor` method
- `this.expandedRowId` state

**Step 3: Run tests, commit**

```bash
bundle exec rake test && bundle exec rake lint
git add -A && git commit -m "feat: row click opens editor, remove expansion code"
```

---

### Task 7: CSS cleanup — remove expansion styles, update mobile responsive

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Remove dead CSS**

Remove:
- `.ingredient-expand td` block
- `.ingredient-detail p` block
- `.detail-missing` rule
- `.detail-recipes a` rule
- `.detail-actions` block
- `.btn-small` block (unless used elsewhere — search first)
- `.loading-placeholder` block (unless used elsewhere)
- `.col-recipes` rule
- `.status-na` rule
- `.ingredients-count` rule
- `.ingredients-summary`, `.summary-count`, `.summary-sep`, `.summary-attention` (if not already removed in Task 4)

**Step 2: Update mobile responsive**

Update the `@media (max-width: 640px)` block:
- Remove `.col-recipes` hide rule
- Remove `.ingredient-expand td` rule
- Remove `.detail-actions` rules
- Keep `.col-aisle` hide rule

**Step 3: Verify `btn-small` and `loading-placeholder` usage**

Search the codebase for other uses before removing. `loading-placeholder` may be used in the editor frame. `btn-small` may be used in groceries.

**Step 4: Run lint, tests, commit**

```bash
bundle exec rake lint && bundle exec rake test
git add -A && git commit -m "style: clean up dead CSS from ingredients page redesign"
```

---

### Task 8: Final integration test and polish

**Files:**
- Modify: `test/controllers/ingredients_controller_test.rb` — verify final state of all assertions
- Run: full test suite + lint

**Step 1: Review all ingredient controller test assertions**

Ensure no tests reference:
- `.col-recipes`
- `ingredient_detail_path`
- `.ingredients-summary` (class) — should use `#ingredients-summary` (id)
- `data-expand-id`

**Step 2: Run full suite**

```bash
bundle exec rake
```

**Step 3: Browser test**

Manual verification:
1. Ingredients page loads with filter-count buttons
2. Clicking a filter highlights it and filters the table
3. Search + filter work together
4. Clicking a header sorts the table; clicking again reverses
5. Sort indicator shows on active column
6. Clicking a row opens the editor dialog
7. Editor shows "Used in" recipe links at bottom
8. Editor shows "Reset to built-in" button for custom entries
9. Save updates the row in the table via Turbo Stream
10. Save & Next advances to next incomplete ingredient

**Step 4: Commit**

```bash
git add -A && git commit -m "test: update integration tests for ingredients table redesign"
```

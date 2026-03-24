# Ingredient Display Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Data column and CUSTOM badge with inline icons next to ingredient names, add a Custom filter pill.

**Architecture:** Move SVG icons (apple, scale) from the Data column into the name cell, replace the text CUSTOM badge with a pencil SVG, add `data-source` attribute for client-side filtering. Pure view/CSS/JS change plus one line in IngredientRowBuilder.

**Tech Stack:** ERB views, CSS, Stimulus JS, Minitest

---

### Task 1: Add `custom` count to IngredientRowBuilder summary

**Files:**
- Modify: `app/services/ingredient_row_builder.rb:76` (build_summary method)
- Test: `test/services/ingredient_row_builder_test.rb`

**Step 1: Write the failing test**

In `test/services/ingredient_row_builder_test.rb`, add after the existing summary test (line ~182):

```ruby
test 'summary counts custom entries' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)

  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  summary = builder.summary

  assert_equal 1, summary[:custom]
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n test_summary_counts_custom_entries`
Expected: FAIL — `summary[:custom]` is nil

**Step 3: Write minimal implementation**

In `app/services/ingredient_row_builder.rb`, update `build_summary`:

```ruby
def build_summary
  { total: rows.size,
    complete: rows.count { |r| r[:status] == 'complete' },
    custom: rows.count { |r| r[:source] == 'custom' },
    missing_aisle: rows.count { |r| r[:aisle].blank? },
    missing_nutrition: rows.count { |r| !r[:has_nutrition] },
    missing_density: rows.count { |r| !r[:has_density] } }
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n test_summary_counts_custom_entries`
Expected: PASS

**Step 5: Run full test suite**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: All pass

**Step 6: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "feat: add custom count to IngredientRowBuilder summary (#213)"
```

---

### Task 2: Update row markup — inline icons, add data-source, remove Data column

**Files:**
- Modify: `app/views/ingredients/_table_row.html.erb`
- Modify: `app/views/ingredients/_table.html.erb`
- Modify: `app/views/ingredients/_summary_bar.html.erb`
- Test: `test/controllers/ingredients_controller_test.rb`

**Step 1: Write failing tests**

Add to `test/controllers/ingredients_controller_test.rb`:

```ruby
test 'rows have data-source attribute' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'tr.ingredient-row[data-source="custom"]'
end

test 'renders custom filter pill' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'button.filter-pill[data-filter="custom"]'
end

test 'renders inline ingredient icons for custom entry with nutrition' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour', basis_grams: 30, calories: 110)
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'td.col-name .ingredient-icons svg.ingredient-icon', minimum: 1
end

test 'does not render Data column header' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'th.col-data', count: 0
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: 4 new tests fail (no `data-source`, no `custom` filter pill, no `.ingredient-icons`, Data column still present)

**Step 3: Update `_table_row.html.erb`**

Replace the entire file with:

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
    data-recipe-count="<%= row[:recipe_count] %>"
    data-resolvable="<%= row[:resolvable] %>"
    data-source="<%= row[:source] %>"
    data-open-editor
    tabindex="0"
    role="button"
    data-action="click->ingredient-table#openEditor keydown->ingredient-table#rowKeydown">
  <td class="col-name">
    <%= row[:name] %>
    <span class="ingredient-icons">
      <% if row[:source] == 'custom' %>
        <svg class="ingredient-icon" width="14" height="14" viewBox="0 0 32 32" aria-label="Custom entry" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 4l6 6-16 16H6v-6z"/><line x1="18" y1="8" x2="24" y2="14"/></svg>
      <% end %>
      <% if row[:has_nutrition] %>
        <svg class="ingredient-icon" width="14" height="14" viewBox="0 0 32 32" aria-label="Has nutrition" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="16" y1="9" x2="16" y2="4"/><path d="M16 7c-2-2-5-2-6 0"/><path d="M16 9C13 7 7 8 5 12c-2 5 0 10 3 14 2 2 4 3 6 3 1 0 1.5-1 2-1s1 1 2 1c2 0 4-1 6-3 3-4 5-9 3-14-2-4-8-5-11-3z"/></svg>
      <% end %>
      <% if row[:has_density] %>
        <svg class="ingredient-icon" width="14" height="14" viewBox="0 0 32 32" aria-label="Has density" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="16" y1="3" x2="16" y2="26"/><line x1="4" y1="9" x2="28" y2="9"/><path d="M6 9L3 19h10L10 9"/><path d="M22 9l-3 10h10l-3-10"/><line x1="10" y1="26" x2="22" y2="26"/></svg>
      <% end %>
    </span>
  </td>
  <td class="col-aisle"><%= display_aisle(row[:aisle]) %></td>
  <td class="col-recipes"><%= row[:recipe_count] %></td>
</tr>
</tbody>
```

**Step 4: Update `_table.html.erb`**

Remove the Data column `<th>`. The table header becomes:

```erb
<%# locals: (ingredient_rows:) %>
<table id="ingredients-table" class="ingredients-table" data-ingredient-table-target="table">
  <thead>
    <tr>
      <th class="col-name sortable" data-sort-key="name" data-action="click->ingredient-table#sort"
          role="columnheader" aria-sort="ascending">
        Name<span class="sort-arrow" aria-hidden="true"> &#9650;</span>
      </th>
      <th class="col-aisle sortable" data-sort-key="aisle" data-action="click->ingredient-table#sort"
          role="columnheader">
        Aisle<span class="sort-arrow" aria-hidden="true"></span>
      </th>
      <th class="col-recipes sortable" data-sort-key="recipes" data-action="click->ingredient-table#sort"
          role="columnheader">
        Recipes<span class="sort-arrow" aria-hidden="true"></span>
      </th>
    </tr>
  </thead>
  <% ingredient_rows.each do |row| %>
    <%= render 'ingredients/table_row', row: row %>
  <% end %>
</table>
```

**Step 5: Update `_summary_bar.html.erb`**

Add the Custom pill after the Complete pill:

```erb
<%# locals: (summary:, coverage:) %>
<button type="button" class="filter-pill active"
        data-ingredient-table-target="filterButton"
        data-filter="all"
        data-action="click->ingredient-table#filter"
        aria-pressed="true">All (<%= summary[:total] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="complete"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Complete (<%= summary[:complete] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="custom"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Custom (<%= summary[:custom] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="no_aisle"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">No Aisle (<%= summary[:missing_aisle] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="no_nutrition"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">No Nutrition (<%= summary[:missing_nutrition] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="no_density"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">No Density (<%= summary[:missing_density] %>)</button>
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="not_resolvable"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Not Resolvable (<%= coverage[:unresolvable].size %>)</button>
```

**Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All pass (including existing tests — the `shows custom badge` test at
line 161 asserts on `data-has-nutrition`, not the old badge markup, so it still
passes)

**Step 7: Commit**

```bash
git add app/views/ingredients/_table_row.html.erb app/views/ingredients/_table.html.erb app/views/ingredients/_summary_bar.html.erb test/controllers/ingredients_controller_test.rb
git commit -m "feat: inline ingredient icons, add Custom filter, remove Data column (#213)"
```

---

### Task 3: Update Stimulus controller — add custom filter, remove data sort

**Files:**
- Modify: `app/javascript/controllers/ingredient_table_controller.js`

**Step 1: Add `"custom"` case to `matchesStatus()`**

In `matchesStatus()` (line ~101), add between `"complete"` and `"no_aisle"`:

```javascript
case "custom": return row.dataset.source === "custom"
```

**Step 2: Remove `"data"` sort key handling**

In `sortValue()` (line ~154), remove the `case "data"` branch and the
`dataScore()` method (lines 148-152). The Data column no longer exists.

**Step 3: Manual test**

Start dev server (`bin/dev`), navigate to ingredients page. Verify:
- Custom filter pill toggles correctly
- Sort by Name, Aisle, Recipes still works
- No JS console errors

**Step 4: Commit**

```bash
git add app/javascript/controllers/ingredient_table_controller.js
git commit -m "feat: add custom filter, remove data sort from ingredient table (#213)"
```

---

### Task 4: Update CSS — remove old styles, add new icon styles

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Remove old styles**

Delete these CSS rules:
- `.col-data { width: 3.5rem; }` (line 760)
- `.data-icons { ... }` (line 763)
- `.data-icon { ... }` (line 764)
- `.data-icon.empty { ... }` (line 765)
- `.source-badge { ... }` (lines 767-774)
- `.source-custom { ... }` (line 775)

In the mobile responsive section (~line 878), the `.col-data` reference is
implicitly gone since `.col-data` no longer exists, but remove it from any
media queries if present.

**Step 2: Add new icon styles**

After `.col-name` (line 758), add:

```css
.ingredient-icons {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  margin-left: 0.4rem;
  vertical-align: middle;
}
.ingredient-icon { color: var(--muted-text); flex-shrink: 0; }
```

**Step 3: Verify no unused CSS variable references**

The `--source-badge-bg` and `--source-badge-text` variables are defined in
`:root` and dark mode. They can be removed too since nothing references them
anymore.

**Step 4: Run lint**

Run: `bundle exec rubocop` (CSS isn't linted by RuboCop, but verify no Ruby
regressions)

**Step 5: Run full test suite**

Run: `rake test`
Expected: All pass

**Step 6: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: replace Data column and badge CSS with inline icon styles (#213)"
```

---

### Task 5: Update html_safe allowlist if needed

**Files:**
- Check: `config/html_safe_allowlist.yml`

**Step 1: Check if the allowlist references ingredient view files**

If any entries reference `_table_row.html.erb` line numbers that shifted,
update them.

**Step 2: Run allowlist audit**

Run: `rake lint:html_safe`
Expected: PASS (no `.html_safe` / `raw()` calls in ingredient views)

**Step 3: Run full suite**

Run: `rake`
Expected: All lint + tests pass

**Step 4: Commit (if any changes)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers (#213)"
```

# Ingredient Filter Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify ingredient page filters by dropping the "No Density" pill, making QB-only ingredients context-aware, removing noise icons, and hiding irrelevant editor sections for QB-only ingredients.

**Architecture:** Add a `qb_only` flag computed at row-build time in `IngredientRowBuilder`. This flag drives context-aware status, adjusted summary/coverage counts, simplified editor rendering, and JS filter behavior. No schema changes.

**Tech Stack:** Rails 8, Stimulus JS, Minitest

**Spec:** `docs/superpowers/specs/2026-04-07-ingredient-filter-cleanup-design.md`

---

### Task 1: Add `qb_only` flag and context-aware status to IngredientRowBuilder

**Files:**
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `test/services/ingredient_row_builder_test.rb`

- [ ] **Step 1: Write failing test — QB-only ingredient with aisle is complete**

Add to `test/services/ingredient_row_builder_test.rb`, after the existing Quick Bite tests (around line 300):

```ruby
test 'qb_only ingredient with aisle has status complete' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  create_catalog_entry('butter', aisle: 'Dairy')
  qb = create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen, recipes: Recipe.none)
  row = builder.rows.find { |r| r[:name] == 'butter' }

  assert row[:qb_only]
  assert_equal 'complete', row[:status]
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n 'test_qb_only_ingredient_with_aisle_has_status_complete'`
Expected: FAIL — `qb_only` key doesn't exist

- [ ] **Step 3: Write failing test — QB-only ingredient without aisle is incomplete**

```ruby
test 'qb_only ingredient without aisle has status incomplete' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  create_catalog_entry('butter')
  qb = create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen, recipes: Recipe.none)
  row = builder.rows.find { |r| r[:name] == 'butter' }

  assert row[:qb_only]
  assert_equal 'incomplete', row[:status]
end
```

- [ ] **Step 4: Write failing test — QB-only ingredient omitted from shopping is complete**

```ruby
test 'qb_only ingredient omitted from shopping is complete without aisle' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  create_catalog_entry('butter', omit_from_shopping: true)
  qb = create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen, recipes: Recipe.none)
  row = builder.rows.find { |r| r[:name] == 'butter' }

  assert row[:qb_only]
  assert_equal 'complete', row[:status]
end
```

- [ ] **Step 5: Write failing test — ingredient in both recipe and QB is not QB-only**

```ruby
test 'ingredient in both recipe and quick bite is not qb_only' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Pancakes
    ## Mix (combine)
    - 2 tablespoons butter
  MD
  create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  row = builder.rows.find { |r| r[:name] == 'butter' }

  refute row[:qb_only]
  assert_equal 'missing', row[:status]
end
```

- [ ] **Step 6: Implement `qb_only` flag and context-aware `row_status`**

In `app/services/ingredient_row_builder.rb`, modify `ingredient_row` to compute
`qb_only` and pass it to `row_status`:

```ruby
def ingredient_row(name, recs)
  entry = @resolver.catalog_entry(name)
  units = collect_units_for(name)
  qb_only = recs.all? { |r| r.is_a?(QuickBiteSource) }
  all_resolvable = units.empty? || (entry&.basis_grams.present? && units.all? { |u| unit_resolvable?(u, entry) })
  { name:, entry:, recipe_count: recs.size, recipes: recs,
    has_nutrition: entry&.basis_grams.present?,
    has_density: entry&.density_grams.present?,
    aisle: entry&.aisle,
    omit_from_shopping: entry&.omit_from_shopping || false,
    source: entry_source(entry),
    status: row_status(entry, qb_only:, aisle: entry&.aisle, omit: entry&.omit_from_shopping),
    resolvable: all_resolvable,
    qb_only: }
end
```

Update `row_status` to accept keyword arguments and handle QB-only:

```ruby
def row_status(entry, qb_only: false, aisle: nil, omit: false)
  return qb_only_status(aisle, omit) if qb_only
  return 'missing' if entry&.basis_grams.blank?
  return 'incomplete' if entry.density_grams.blank?

  'complete'
end

def qb_only_status(aisle, omit)
  aisle.present? || omit ? 'complete' : 'incomplete'
end
```

Also update `next_needing_attention` which calls `row_status` directly — it
needs to pass the QB-only context. The simplest fix is to look up the row from
`rows` instead of recomputing status:

```ruby
def next_needing_attention(after:)
  sorted = rows.sort_by { |r| r[:name].downcase }
  idx = sorted.index { |r| r[:name].casecmp(after).zero? }
  return unless idx

  match = sorted[(idx + 1)..].find { |r| r[:status] != 'complete' }
  match&.fetch(:name)
end
```

- [ ] **Step 7: Run the four new tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n '/qb_only/'`
Expected: 4 tests, 4 passes

- [ ] **Step 8: Run all IngredientRowBuilder tests to check for regressions**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "Add qb_only flag and context-aware row_status to IngredientRowBuilder"
```

---

### Task 2: Adjust summary and coverage counts to exclude QB-only

**Files:**
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `test/services/ingredient_row_builder_test.rb`

- [ ] **Step 1: Write failing test — missing_nutrition excludes QB-only**

```ruby
test 'summary missing_nutrition excludes qb_only ingredients' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Pancakes
    ## Mix (combine)
    - 2 cups flour
  MD
  create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen)

  assert_equal 1, builder.summary[:missing_nutrition]
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n 'test_summary_missing_nutrition_excludes_qb_only_ingredients'`
Expected: FAIL — count is 2 (includes QB-only butter)

- [ ] **Step 3: Write failing test — coverage unresolvable list excludes QB-only**

```ruby
test 'coverage unresolvable list excludes qb_only ingredients' do
  IngredientCatalog.where(kitchen_id: nil).delete_all
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Pancakes
    ## Mix (combine)
    - 2 cups flour
  MD
  create_quick_bite('Toast', ingredients: ['butter'])

  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  unresolvable_names = builder.coverage[:unresolvable].map { |u| u[:name] }

  assert_includes unresolvable_names, 'flour'
  refute_includes unresolvable_names, 'butter'
end
```

- [ ] **Step 4: Implement adjusted counts**

In `app/services/ingredient_row_builder.rb`, update `build_summary` to remove
`missing_density` and exclude QB-only from `missing_nutrition`:

```ruby
def build_summary
  { total: rows.size,
    complete: rows.count { |r| r[:status] == 'complete' },
    custom: rows.count { |r| r[:source] == 'custom' },
    missing_aisle: rows.count { |r| r[:aisle].blank? && !r[:omit_from_shopping] },
    missing_nutrition: rows.count { |r| !r[:has_nutrition] && !r[:qb_only] } }
end
```

Update `partition_by_resolvability` to skip QB-only rows:

```ruby
def partition_by_resolvability(units_map)
  countable = rows.reject { |row| row[:qb_only] }
  unresolvable = countable.filter_map do |row|
    unresolvable_units_for(row[:name], row[:entry], units_map[row[:name]])
  end

  [countable.size - unresolvable.size, unresolvable]
end
```

- [ ] **Step 5: Run the two new tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n '/excludes_qb_only/'`
Expected: 2 tests, 2 passes

- [ ] **Step 6: Run all IngredientRowBuilder tests — fix any regressions**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: All pass. Existing summary tests may need updating since
`missing_density` is removed — remove assertions on that key.

- [ ] **Step 7: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "Exclude QB-only ingredients from nutrition and coverage counts"
```

---

### Task 3: Update views — drop No Density pill, remove icons, add data-qb-only

**Files:**
- Modify: `app/views/ingredients/_summary_bar.html.erb`
- Modify: `app/views/ingredients/_table_row.html.erb`
- Modify: `test/controllers/ingredients_controller_test.rb`

- [ ] **Step 1: Write failing test — No Density pill is absent**

Add to `test/controllers/ingredients_controller_test.rb`:

```ruby
test 'index does not render no_density filter pill' do
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_no_match 'No Density', response.body
  assert_select 'button.btn-pill[data-filter="no_density"]', count: 0
end
```

- [ ] **Step 2: Write failing test — apple and scale icons are absent**

```ruby
test 'index does not render apple or scale icons in ingredient rows' do
  create_catalog_entry('flour', basis_grams: 100, calories: 364, density_grams: 120,
                       density_volume: 1, density_unit: 'cup', aisle: 'Baking')
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'svg.ingredient-icon' do |icons|
    icon_labels = icons.map { |i| i['aria-label'] }
    refute_includes icon_labels, 'Has nutrition'
    refute_includes icon_labels, 'Has density'
  end
end
```

- [ ] **Step 3: Write failing test — data-qb-only attribute is rendered**

```ruby
test 'index renders data-qb-only attribute on ingredient rows' do
  create_quick_bite('Toast', ingredients: ['butter'])
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'tr.ingredient-row[data-qb-only="true"]'
end
```

- [ ] **Step 4: Run the three tests to verify they fail**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n '/no_density|apple_or_scale|qb_only/'`
Expected: 3 failures

- [ ] **Step 5: Update `_summary_bar.html.erb` — remove No Density pill**

Remove lines 27-31 (the No Density button). The file should have 6 pills:
All, Complete, Custom, No Aisle, No Nutrition, Not Resolvable.

```erb
<%# locals: (summary:, coverage:) %>
<button type="button" class="btn-pill active"
        data-ingredient-table-target="filterButton"
        data-filter="all"
        data-action="click->ingredient-table#filter"
        aria-pressed="true">All (<%= summary[:total] %>)</button>
<button type="button" class="btn-pill"
        data-ingredient-table-target="filterButton"
        data-filter="complete"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Complete (<%= summary[:complete] %>)</button>
<button type="button" class="btn-pill"
        data-ingredient-table-target="filterButton"
        data-filter="custom"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Custom (<%= summary[:custom] %>)</button>
<button type="button" class="btn-pill"
        data-ingredient-table-target="filterButton"
        data-filter="no_aisle"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">No Aisle (<%= summary[:missing_aisle] %>)</button>
<button type="button" class="btn-pill"
        data-ingredient-table-target="filterButton"
        data-filter="no_nutrition"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">No Nutrition (<%= summary[:missing_nutrition] %>)</button>
<button type="button" class="btn-pill"
        data-ingredient-table-target="filterButton"
        data-filter="not_resolvable"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Not Resolvable (<%= coverage[:unresolvable].size %>)</button>
```

- [ ] **Step 6: Update `_table_row.html.erb` — remove icons, remove data-has-density, add data-qb-only**

```erb
<%# locals: (row:) %>
<tbody id="ingredient-<%= row[:name].parameterize %>">
<tr class="ingredient-row"
    data-ingredient-table-target="row"
    data-ingredient-name="<%= row[:name] %>"
    data-status="<%= row[:status] %>"
    data-has-nutrition="<%= row[:has_nutrition] %>"
    data-aisle="<%= row[:aisle] || '' %>"
    data-recipe-count="<%= row[:recipe_count] %>"
    data-resolvable="<%= row[:resolvable] %>"
    data-omit="<%= row[:omit_from_shopping] %>"
    data-source="<%= row[:source] %>"
    data-qb-only="<%= row[:qb_only] %>"
    data-open-editor
    tabindex="0"
    role="button"
    data-action="click->ingredient-table#openEditor keydown->ingredient-table#rowKeydown">
  <td class="col-name">
    <%= row[:name] %>
    <% if row[:source] == 'custom' %>
      <span class="ingredient-icons">
        <%= icon(:edit, size: 14, class: 'ingredient-icon', 'aria-label': 'Custom entry', 'aria-hidden': nil) %>
      </span>
    <% end %>
  </td>
  <td class="col-aisle"><%= display_aisle(row[:aisle]) %></td>
  <td class="col-recipes"><%= row[:recipe_count] %></td>
</tr>
</tbody>
```

- [ ] **Step 7: Run the three new tests to verify they pass**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n '/no_density|apple_or_scale|qb_only/'`
Expected: 3 passes

- [ ] **Step 8: Update existing controller tests that assert on removed elements**

The test `'renders inline ingredient icons for custom entry with nutrition'`
(around line 507) asserts apple/scale icons. Update it to only assert the
pencil icon:

```ruby
test 'renders inline ingredient icons for custom entry' do
  IngredientCatalog.create!(name: 'flour', kitchen: @kitchen, basis_grams: 100,
                            calories: 364, density_grams: 120, density_volume: 1,
                            density_unit: 'cup')
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_select 'td.col-name .ingredient-icons svg.ingredient-icon' do |icons|
    assert_equal 1, icons.size
    assert_equal 'Custom entry', icons.first['aria-label']
  end
end
```

Any test asserting `data-has-density` should be updated to remove that
assertion. Any test asserting `summary[:missing_density]` should be updated
to remove that key.

- [ ] **Step 9: Run full controller test suite**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All pass

- [ ] **Step 10: Commit**

```bash
git add app/views/ingredients/_summary_bar.html.erb app/views/ingredients/_table_row.html.erb test/controllers/ingredients_controller_test.rb
git commit -m "Drop No Density pill, remove apple/scale icons, add data-qb-only"
```

---

### Task 4: Update JavaScript filter controller

**Files:**
- Modify: `app/javascript/controllers/ingredient_table_controller.js`

- [ ] **Step 1: Update `matchesStatus` — remove no_density, adjust no_nutrition**

```javascript
matchesStatus(row) {
  switch (this.currentFilter) {
    case "all": return true
    case "complete": return row.dataset.status === "complete"
    case "custom": return row.dataset.source === "custom"
    case "no_aisle": return !row.dataset.aisle && row.dataset.omit !== "true"
    case "no_nutrition": return row.dataset.hasNutrition === "false" && row.dataset.qbOnly !== "true"
    case "not_resolvable": return row.dataset.resolvable === "false"
    default: return true
  }
}
```

- [ ] **Step 2: Update the header comment**

```javascript
/**
 * Ingredients page table: client-side search filtering, status filtering
 * (all/complete/custom/no aisle/no nutrition/not resolvable), sortable columns
 * (name, aisle, recipes), and keyboard navigation for row activation.
 * Works entirely on DOM data attributes — no server calls.
 *
 * Persists sort order, active filter pill, and search text to sessionStorage
 * so state survives page reloads, Turbo visits, and broadcast morphs.
 */
```

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `rake test`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/ingredient_table_controller.js
git commit -m "Update JS filter: drop no_density, exclude QB-only from no_nutrition"
```

---

### Task 5: Simplified editor for QB-only ingredients

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `app/views/ingredients/_editor_form.html.erb`
- Modify: `test/controllers/ingredients_controller_test.rb`

- [ ] **Step 1: Write failing test — QB-only editor hides Nutrition section**

```ruby
test 'edit hides nutrition section for qb_only ingredient' do
  create_quick_bite('Toast', ingredients: ['butter'])
  get ingredient_edit_path('butter', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'details[data-section-key="nutrition"]', count: 0
end
```

- [ ] **Step 2: Write failing test — QB-only editor hides Conversions section**

```ruby
test 'edit hides conversions section for qb_only ingredient' do
  create_quick_bite('Toast', ingredients: ['butter'])
  get ingredient_edit_path('butter', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'details[data-section-key="conversions"]', count: 0
end
```

- [ ] **Step 3: Write failing test — non-QB editor still shows both sections**

```ruby
test 'edit shows nutrition and conversions for recipe ingredient' do
  get ingredient_edit_path('flour', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'details[data-section-key="nutrition"]', count: 1
  assert_select 'details[data-section-key="conversions"]', count: 1
end
```

- [ ] **Step 4: Run the three tests to verify they fail**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n '/qb_only_ingredient|recipe_ingredient/'`
Expected: First two fail (sections are present), third may pass already

- [ ] **Step 5: Update `IngredientsController#edit` to pass `qb_only:`**

In `app/controllers/ingredients_controller.rb`, modify the edit action:

```ruby
def edit
  ingredient_name, entry = load_ingredient_data
  aisles = current_kitchen.all_aisles
  sources = row_builder.sources_for(ingredient_name)
  needed_units = row_builder.needed_units(ingredient_name)
  qb_only = sources.present? && sources.all? { |s| s.is_a?(IngredientRowBuilder::QuickBiteSource) }

  render partial: 'ingredients/editor_form',
         locals: { ingredient_name:, entry:, available_aisles: aisles, sources:, needed_units:,
                   has_usda_key: current_kitchen.usda_api_key.present?, qb_only: }
rescue => error # rubocop:disable Style/RescueStandardError
  logger.error "Ingredient edit failed for #{params[:ingredient_name]}: #{error.class} — #{error.message}"
  render partial: 'ingredients/editor_error', locals: { message: error.message }
end
```

- [ ] **Step 6: Update `_editor_form.html.erb` to hide sections for QB-only**

Update the locals declaration at the top:

```erb
<%# locals: (ingredient_name:, entry:, available_aisles:, sources: [], needed_units: [], has_usda_key: false, qb_only: false) %>
```

Wrap the Nutrition section (the `<div class="editor-section">` containing
`data-section-key="nutrition"`) and the Conversions section (the
`<div class="editor-section">` containing `data-section-key="conversions"`)
with `<% unless qb_only %>`:

```erb
    </div>

    <% unless qb_only %>
    <hr class="editor-divider">

    <div class="editor-section">
      <details class="collapse-header" data-section-key="nutrition">
        ...
      </details>
      ...
    </div>

    <div class="editor-section">
      <details class="collapse-header" data-section-key="conversions">
        ...
      </details>
      ...
    </div>
    <% end %>

    <% if sources.any? %>
```

Also remove the `<hr class="editor-divider">` before the Nutrition section
when QB-only — it's inside the `unless` block.

- [ ] **Step 7: Run the three new tests to verify they pass**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n '/qb_only_ingredient|recipe_ingredient/'`
Expected: 3 passes

- [ ] **Step 8: Run full test suite**

Run: `rake test`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add app/controllers/ingredients_controller.rb app/views/ingredients/_editor_form.html.erb test/controllers/ingredients_controller_test.rb
git commit -m "Hide nutrition and conversions editor sections for QB-only ingredients"
```

---

### Task 6: Clean up CSS and update html_safe allowlist

**Files:**
- Modify: `app/assets/stylesheets/ingredients.css` (if needed)
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)

- [ ] **Step 1: Check if ingredient-icons CSS needs cleanup**

The `.ingredient-icons` and `.ingredient-icon` styles in `ingredients.css`
are still used by the pencil icon. No CSS removal needed — just verify.

- [ ] **Step 2: Run `rake lint:html_safe` to check allowlist**

Run: `rake lint:html_safe`

If any line numbers shifted in modified files, update
`config/html_safe_allowlist.yml` accordingly.

- [ ] **Step 3: Run `rake lint` to check RuboCop**

Run: `rake lint`
Expected: 0 offenses

- [ ] **Step 4: Run full test suite one final time**

Run: `rake test`
Expected: All pass

- [ ] **Step 5: Commit any allowlist or lint fixes**

```bash
git add -A
git commit -m "Update html_safe allowlist for shifted line numbers"
```

(Skip this commit if no changes were needed.)

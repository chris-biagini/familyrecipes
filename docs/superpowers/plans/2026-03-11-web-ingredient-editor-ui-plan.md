# Web Ingredient Editor UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add USDA search + import UI, density candidate picker, and coverage filter to the existing ingredient editor.

**Architecture:** Extend existing Stimulus controllers (`nutrition_editor_controller.js`, `ingredient_table_controller.js`) with new methods for USDA search/import and coverage filtering. Add new HTML sections to existing ERB partials. All backend APIs already exist — this is purely frontend work plus passing coverage data from controller to view.

**Tech Stack:** Stimulus, Turbo Frames, ERB partials, CSS, Rails controller changes (data passing only)

**Security:** All dynamic content rendered via `textContent` / `createTextNode` — never `innerHTML`. USDA responses contain only server-controlled data, but we follow the CSP-safe pattern regardless.

---

### Task 1: Pass coverage data to the ingredients index view

The index view needs coverage stats for the "Not Resolvable" filter pill, and each table row needs a `data-resolvable` attribute. Currently `IngredientsController#index` computes `@summary` but not coverage.

**Files:**
- Modify: `app/controllers/ingredients_controller.rb:14-18`
- Modify: `app/services/ingredient_row_builder.rb:127-135`
- Modify: `app/views/ingredients/_summary_bar.html.erb`
- Modify: `app/views/ingredients/_table_row.html.erb:1-10`
- Modify: `app/views/ingredients/index.html.erb:18`
- Modify: `app/javascript/controllers/ingredient_table_controller.js:72-79`
- Test: `test/controllers/ingredients_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/ingredients_controller_test.rb`:

```ruby
test 'index renders not_resolvable filter pill with coverage count' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'button.filter-pill[data-filter="not_resolvable"]'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n test_index_renders_not_resolvable_filter_pill_with_coverage_count`
Expected: FAIL — no filter pill with `data-filter="not_resolvable"`

**Step 3: Add `resolvable` key to each row in IngredientRowBuilder**

In `app/services/ingredient_row_builder.rb`, update `ingredient_row`:

```ruby
def ingredient_row(name, recs)
  entry = @resolver.catalog_entry(name)
  units = collect_units_for(name)
  all_resolvable = entry&.basis_grams.present? && units.all? { |u| unit_resolvable?(u, entry) }
  { name:, entry:, recipe_count: recs.size, recipes: recs,
    has_nutrition: entry&.basis_grams.present?,
    has_density: entry&.density_grams.present?,
    aisle: entry&.aisle,
    source: entry_source(entry),
    status: row_status(entry),
    resolvable: all_resolvable }
end
```

**Step 4: Update controller to pass coverage data**

In `app/controllers/ingredients_controller.rb`, update `index`:

```ruby
def index
  @ingredient_rows = row_builder.rows
  @summary = row_builder.summary
  @coverage = row_builder.coverage
  @available_aisles = current_kitchen.all_aisles
  @next_needing_attention = first_needing_attention
end
```

**Step 5: Add resolvable pill to summary bar**

In `app/views/ingredients/_summary_bar.html.erb`, change locals and add pill:

```erb
<%# locals: (summary:, coverage:) %>
```

Add after the "No Density" pill:

```erb
<button type="button" class="filter-pill"
        data-ingredient-table-target="filterButton"
        data-filter="not_resolvable"
        data-action="click->ingredient-table#filter"
        aria-pressed="false">Not Resolvable (<%= coverage[:unresolvable].size %>)</button>
```

**Step 6: Update index.html.erb to pass coverage**

```erb
<%= render 'ingredients/summary_bar', summary: @summary, coverage: @coverage %>
```

**Step 7: Add data-resolvable attribute to table row**

In `_table_row.html.erb`, add to the `<tr>`:

```erb
data-resolvable="<%= row[:resolvable] %>"
```

**Step 8: Add filter case to ingredient_table_controller.js**

In `matchesStatus`, add:

```javascript
case "not_resolvable": return row.dataset.resolvable === "false"
```

**Step 9: Run test to verify it passes**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n test_index_renders_not_resolvable_filter_pill_with_coverage_count`
Expected: PASS

**Step 10: Run full test suite**

Run: `rake test`
Expected: All pass

**Step 11: Commit**

```bash
git add app/controllers/ingredients_controller.rb app/services/ingredient_row_builder.rb \
  app/views/ingredients/_summary_bar.html.erb app/views/ingredients/_table_row.html.erb \
  app/views/ingredients/index.html.erb app/javascript/controllers/ingredient_table_controller.js \
  test/controllers/ingredients_controller_test.rb
git commit -m "feat: add resolvable filter pill to ingredients page"
```

---

### Task 2: Add USDA search panel HTML to the editor form

Add the `<details>` element with search input and results container to `_editor_form.html.erb`. Wire up search in the same task since the HTML and JS are tightly coupled.

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb:1-6`
- Modify: `app/views/ingredients/index.html.erb:30-33`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`
- Modify: `app/assets/stylesheets/style.css`
- Test: `test/controllers/ingredients_controller_test.rb`

**Step 1: Write the failing test**

```ruby
test 'edit renders USDA search panel' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups
  MD

  log_in
  get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
      headers: { 'Accept' => 'text/html' }

  assert_response :success
  assert_select 'details.usda-search-panel'
  assert_select 'input[data-nutrition-editor-target="usdaQuery"]'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n "test_edit_renders_USDA_search_panel"`
Expected: FAIL

**Step 3: Add USDA search panel HTML to editor form**

In `app/views/ingredients/_editor_form.html.erb`, add before the Nutrition Information fieldset (after line 4, inside the `editor-form` div):

```erb
    <details class="usda-search-panel"
             data-nutrition-editor-target="usdaPanel"
             <%= 'open' unless entry&.basis_grams %>>
      <summary class="editor-section-title usda-summary-title">
        Import from USDA
        <span class="usda-imported-badge" hidden
              data-nutrition-editor-target="usdaBadge">Imported</span>
      </summary>
      <div class="usda-search-row">
        <input type="search" class="usda-search-input"
               placeholder="Search USDA database…"
               value="<%= ingredient_name %>"
               data-nutrition-editor-target="usdaQuery"
               data-action="keydown->nutrition-editor#usdaSearchKeydown"
               aria-label="USDA search query">
        <button type="button" class="btn usda-search-btn"
                data-action="click->nutrition-editor#usdaSearch"
                data-nutrition-editor-target="usdaSearchBtn">Search</button>
      </div>
      <div class="usda-results" hidden data-nutrition-editor-target="usdaResults"></div>
    </details>
```

**Step 4: Pass USDA URLs to the editor dialog**

In `app/views/ingredients/index.html.erb`, add USDA URL values to `extra_data`:

```erb
extra_data: {
  'nutrition-editor-base-url-value' => nutrition_entry_upsert_path(ingredient_name: '__NAME__'),
  'nutrition-editor-edit-url-value' => ingredient_edit_path(ingredient_name: '__NAME__'),
  'nutrition-editor-usda-search-url-value' => usda_search_path,
  'nutrition-editor-usda-show-url-value' => usda_show_path(fdc_id: '__FDC_ID__')
}
```

**Step 5: Update Stimulus controller targets and values**

In `nutrition_editor_controller.js`, update `static targets` and `static values`:

```javascript
static targets = [
  "formContent",
  "basisGrams", "nutrientField",
  "densityVolume", "densityUnit", "densityGrams",
  "portionList", "portionRow", "portionName", "portionGrams",
  "aisleSelect", "aisleInput", "omitCheckbox",
  "aliasList", "aliasInput", "aliasChip",
  "usdaPanel", "usdaQuery", "usdaResults", "usdaBadge", "usdaSearchBtn",
  "densityCandidates", "densityCandidateList"
]

static values = {
  baseUrl: String,
  editUrl: String,
  usdaSearchUrl: String,
  usdaShowUrl: String
}
```

**Step 6: Add USDA search methods to the Stimulus controller**

All dynamic content uses `textContent` / `createTextNode` — never innerHTML.

```javascript
async usdaSearch() {
  const query = this.usdaQueryTarget.value.trim()
  if (!query) return

  this.usdaSearchBtnTarget.disabled = true
  this.usdaSearchBtnTarget.textContent = "Searching…"
  this.usdaResultsTarget.hidden = false
  this.usdaResultsTarget.replaceChildren()
  this.usdaCurrentPage = 0

  try {
    await this.fetchUsdaPage(query, 0)
  } finally {
    this.usdaSearchBtnTarget.disabled = false
    this.usdaSearchBtnTarget.textContent = "Search"
  }
}

usdaSearchKeydown(event) {
  if (event.key === "Enter") {
    event.preventDefault()
    this.usdaSearch()
  }
}

async fetchUsdaPage(query, page) {
  const url = `${this.usdaSearchUrlValue}?q=${encodeURIComponent(query)}&page=${page}`
  const response = await fetch(url, {
    headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
  })

  if (!response.ok) {
    const data = await response.json().catch(() => ({}))
    this.showUsdaError(data.error || "Search failed")
    return
  }

  const data = await response.json()

  if (data.foods.length === 0 && page === 0) {
    const msg = document.createElement("div")
    msg.className = "usda-no-results"
    msg.textContent = "No results found"
    this.usdaResultsTarget.replaceChildren(msg)
    return
  }

  // Remove existing "More results" button before appending
  const moreBtn = this.usdaResultsTarget.querySelector(".usda-more-btn")
  if (moreBtn) moreBtn.remove()

  data.foods.forEach(food => {
    this.usdaResultsTarget.appendChild(this.buildResultItem(food))
  })

  if (data.current_page + 1 < data.total_pages) {
    const btn = document.createElement("button")
    btn.type = "button"
    btn.className = "usda-more-btn"
    btn.textContent = "More results…"
    btn.addEventListener("click", () => {
      btn.disabled = true
      btn.textContent = "Loading…"
      this.fetchUsdaPage(query, page + 1)
    })
    this.usdaResultsTarget.appendChild(btn)
  }
}

buildResultItem(food) {
  const item = document.createElement("div")
  item.className = "usda-result-item"
  item.setAttribute("role", "button")
  item.setAttribute("tabindex", "0")

  const name = document.createElement("div")
  name.className = "usda-result-name"
  name.textContent = food.description

  const nutrients = document.createElement("div")
  nutrients.className = "usda-result-nutrients"
  nutrients.textContent = food.nutrient_summary

  item.appendChild(name)
  item.appendChild(nutrients)

  item.addEventListener("click", () => this.importUsdaResult(food.fdc_id, item))
  item.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault()
      this.importUsdaResult(food.fdc_id, item)
    }
  })

  return item
}

showUsdaError(message) {
  const div = document.createElement("div")
  div.className = message === "no_api_key" ? "usda-error" : "usda-error"
  div.textContent = message === "no_api_key"
    ? "No USDA API key configured. Add one in Settings."
    : message
  this.usdaResultsTarget.replaceChildren(div)
}
```

**Step 7: Add CSS for the USDA search panel**

Append to `app/assets/stylesheets/style.css` (after `.editor-reset-btn`):

```css
/* USDA search panel */
.usda-search-panel {
  margin-bottom: 1rem;
  border: 1px solid var(--border-light);
  border-radius: 6px;
  padding: 0;
}
.usda-search-panel[open] { padding: 0 0.75rem 0.75rem; }
.usda-summary-title {
  cursor: pointer;
  padding: 0.5rem 0.75rem;
  list-style: none;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.usda-summary-title::-webkit-details-marker { display: none; }
.usda-summary-title::before {
  content: '▸';
  font-size: 0.8em;
  transition: transform 0.15s;
}
.usda-search-panel[open] > .usda-summary-title::before { transform: rotate(90deg); }
.usda-imported-badge {
  font-size: 0.7rem;
  padding: 0.1rem 0.4rem;
  border-radius: 999px;
  background: var(--aisle-new-bg);
  border: 1px solid var(--aisle-new-border);
  color: var(--text-color);
  font-variant: normal;
  letter-spacing: 0;
}
.usda-search-row {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}
.usda-search-input { flex: 1; }
.usda-search-btn { white-space: nowrap; }
.usda-results {
  max-height: 250px;
  overflow-y: auto;
  border: 1px solid var(--border-light);
  border-radius: 4px;
}
.usda-result-item {
  padding: 0.5rem 0.75rem;
  cursor: pointer;
  border-bottom: 1px solid var(--separator-color);
}
.usda-result-item:last-child { border-bottom: none; }
.usda-result-item:hover { background: var(--hover-bg); }
.usda-result-item.loading { opacity: 0.5; pointer-events: none; }
.usda-result-name {
  font-weight: 600;
  font-size: 0.9rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.usda-result-nutrients {
  font-size: 0.8rem;
  color: var(--muted-text);
  margin-top: 0.15rem;
}
.usda-more-btn {
  display: block;
  width: 100%;
  padding: 0.4rem;
  text-align: center;
  background: none;
  border: none;
  border-top: 1px solid var(--separator-color);
  cursor: pointer;
  font-size: 0.85rem;
  color: var(--accent-color);
}
.usda-more-btn:hover { background: var(--hover-bg); }
.usda-no-results {
  padding: 0.75rem;
  text-align: center;
  color: var(--muted-text);
  font-size: 0.85rem;
}
.usda-error {
  padding: 0.75rem;
  color: var(--danger-color);
  font-size: 0.85rem;
}
```

**Step 8: Run test to verify it passes**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n "test_edit_renders_USDA_search_panel"`
Expected: PASS

**Step 9: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb app/views/ingredients/index.html.erb \
  app/javascript/controllers/nutrition_editor_controller.js app/assets/stylesheets/style.css \
  test/controllers/ingredients_controller_test.rb
git commit -m "feat: add USDA search panel with search UI to editor form"
```

---

### Task 3: Wire up USDA import (auto-populate form fields)

When a user clicks a USDA result, fetch the full detail and populate all form fields.

**Files:**
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`

**Step 1: Add import and population methods**

```javascript
async importUsdaResult(fdcId, item) {
  item.classList.add("loading")

  try {
    const url = this.usdaShowUrlValue.replace("__FDC_ID__", fdcId)
    const response = await fetch(url, {
      headers: { "Accept": "application/json", "X-CSRF-Token": getCsrfToken() }
    })

    if (!response.ok) {
      item.classList.remove("loading")
      return
    }

    const data = await response.json()
    this.populateFromUsda(data)

    this.usdaPanelTarget.open = false
    this.usdaBadgeTarget.hidden = false
    this.usdaImportData = data
  } catch {
    item.classList.remove("loading")
  }
}

populateFromUsda(data) {
  if (data.nutrients) {
    if (this.hasBasisGramsTarget) {
      this.basisGramsTarget.value = data.nutrients.basis_grams || 100
    }
    this.nutrientFieldTargets.forEach(input => {
      const key = input.dataset.nutrientKey
      const value = data.nutrients[key]
      input.value = value != null ? this.formatValue(value) : ""
    })
  }

  if (data.density) {
    this.densityVolumeTarget.value = data.density.volume || ""
    this.densityUnitTarget.value = data.density.unit || ""
    this.densityGramsTarget.value = data.density.grams != null
      ? this.formatValue(data.density.grams) : ""
  }

  this.portionListTarget.replaceChildren()
  if (data.portions) {
    data.portions.forEach(p => this.addPortionWithValues(p.name, p.grams))
  }

  if (data.density_candidates && data.density_candidates.length > 1) {
    this.showDensityCandidates(data.density_candidates, data.density)
  }
}

formatValue(num) {
  if (num == null) return ""
  return String(Math.round(num * 100) / 100)
}

addPortionWithValues(name, grams) {
  this.addPortion()
  const rows = this.portionListTarget.querySelectorAll(".portion-row")
  const lastRow = rows[rows.length - 1]
  lastRow.querySelector("[data-nutrition-editor-target='portionName']").value = name
  lastRow.querySelector("[data-nutrition-editor-target='portionGrams']").value = this.formatValue(grams)
}
```

**Step 2: Update handleReset to clear USDA state**

Replace the existing `handleReset`:

```javascript
handleReset(event) {
  event.detail.handled = true
  this.currentIngredient = null
  this.originalSnapshot = null
  this.usdaImportData = null
  if (this.hasUsdaBadgeTarget) this.usdaBadgeTarget.hidden = true
  if (this.hasUsdaResultsTarget) {
    this.usdaResultsTarget.hidden = true
    this.usdaResultsTarget.replaceChildren()
  }
  if (this.hasDensityCandidatesTarget) this.densityCandidatesTarget.hidden = true
}
```

**Step 3: Verify manually**

Start `bin/dev`, open ingredient editor, search USDA, click a result. Verify:
- Nutrient fields populate correctly
- Density fields populate
- Portions appear as editable rows
- "Imported" badge shows, panel collapses
- Save works with imported data
- Opening another ingredient clears USDA state

**Step 4: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "feat: auto-populate editor form from USDA import"
```

---

### Task 4: Add density candidate picker

Show alternative density candidates from USDA data after import.

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb:64-65`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js`
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add density candidates container to the form**

In `_editor_form.html.erb`, add after the density `</fieldset>` (after line 65):

```erb
    <details class="density-candidates" hidden data-nutrition-editor-target="densityCandidates">
      <summary class="editor-section-title">Other USDA densities</summary>
      <div data-nutrition-editor-target="densityCandidateList"></div>
    </details>
```

**Step 2: Add showDensityCandidates method**

```javascript
showDensityCandidates(candidates, selectedDensity) {
  if (!this.hasDensityCandidatesTarget) return

  this.densityCandidatesTarget.hidden = false
  const list = this.densityCandidateListTarget
  list.replaceChildren()

  candidates.forEach((candidate, index) => {
    const unit = this.normalizeUnit(candidate.modifier)
    const perUnit = candidate.each
    const isSelected = selectedDensity &&
      Math.abs(perUnit - selectedDensity.grams) < 0.01 &&
      unit === selectedDensity.unit

    const label = document.createElement("label")
    label.className = "density-candidate-row"

    const radio = document.createElement("input")
    radio.type = "radio"
    radio.name = "density-candidate"
    radio.value = index
    radio.checked = isSelected
    radio.addEventListener("change", () => {
      this.densityVolumeTarget.value = 1
      this.densityUnitTarget.value = unit
      this.densityGramsTarget.value = this.formatValue(perUnit)
    })

    label.appendChild(radio)
    label.appendChild(document.createTextNode(
      ` ${this.formatValue(perUnit)}g per 1 ${unit}`
    ))
    list.appendChild(label)
  })
}

normalizeUnit(modifier) {
  const match = modifier.match(/^(cup|tablespoon|tbsp|teaspoon|tsp|fl oz|fluid ounce|ml|liter|litre|quart|pint|gallon)/i)
  return match ? match[1].toLowerCase() : modifier.toLowerCase().split(/[\s(]/)[0]
}
```

**Step 3: Add CSS for density candidates**

```css
/* Density candidates */
.density-candidates {
  margin: -0.5rem 0 1rem;
  padding: 0;
  border: 1px solid var(--border-light);
  border-radius: 4px;
}
.density-candidates[open] { padding: 0 0.75rem 0.75rem; }
.density-candidates > summary {
  cursor: pointer;
  padding: 0.4rem 0.75rem;
  font-size: 0.8rem;
}
.density-candidate-row {
  display: block;
  padding: 0.25rem 0;
  font-size: 0.85rem;
  cursor: pointer;
}
.density-candidate-row:hover { color: var(--accent-color); }
.density-candidate-row input[type="radio"] { margin-right: 0.4rem; }
```

**Step 4: Verify manually**

Import a USDA item with multiple density candidates (e.g. butter, milk). Verify:
- "Other USDA densities" appears below density fields
- Radio buttons with gram weights
- Selecting a candidate updates density form fields
- Hidden when no USDA data or only one candidate

**Step 5: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb \
  app/javascript/controllers/nutrition_editor_controller.js \
  app/assets/stylesheets/style.css
git commit -m "feat: add density candidate picker for USDA imports"
```

---

### Task 5: Dark mode and mobile styles for new elements

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add dark mode styles**

In the `@media (prefers-color-scheme: dark)` block:

```css
.usda-search-panel { border-color: var(--border-color); }
.usda-results { border-color: var(--border-color); }
.usda-result-item { border-bottom-color: var(--border-color); }
.density-candidates { border-color: var(--border-color); }
```

**Step 2: Add mobile styles**

In the `@media (max-width: 720px)` block:

```css
.usda-search-row { flex-wrap: wrap; }
.usda-search-input { min-width: 0; }
.usda-results { max-height: 200px; }
```

**Step 3: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: dark mode and mobile styles for USDA panel"
```

---

### Task 6: Lints and final integration tests

**Files:**
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)
- Modify: `test/controllers/ingredients_controller_test.rb`

**Step 1: Run html_safe lint**

Run: `rake lint:html_safe`
Fix any line-number shifts in allowlist.

**Step 2: Run RuboCop**

Run: `bundle exec rubocop`
Fix any offenses.

**Step 3: Add integration tests**

```ruby
test 'edit form includes USDA panel and density candidates container' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups
  MD

  log_in
  get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
      headers: { 'Accept' => 'text/html' }

  assert_response :success
  assert_select 'details.usda-search-panel[open]'
  assert_select 'details.density-candidates[hidden]'
end

test 'USDA panel is collapsed when ingredient has nutrition data' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups
  MD
  IngredientCatalog.create!(
    ingredient_name: 'Flour', kitchen: @kitchen,
    basis_grams: 100, calories: 364
  )

  log_in
  get ingredient_edit_path(ingredient_name: 'Flour', kitchen_slug: kitchen_slug),
      headers: { 'Accept' => 'text/html' }

  assert_response :success
  assert_select 'details.usda-search-panel:not([open])'
end

test 'not_resolvable filter pill shows count of unresolvable ingredients' do
  @category = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp
  MD

  log_in
  get ingredients_path(kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select 'button[data-filter="not_resolvable"]', /Not Resolvable/
end
```

**Step 4: Run full suite**

Run: `rake`
Expected: All pass, no RuboCop offenses

**Step 5: Commit**

```bash
git add test/controllers/ingredients_controller_test.rb config/html_safe_allowlist.yml
git commit -m "test: integration tests for USDA panel and coverage filter"
```

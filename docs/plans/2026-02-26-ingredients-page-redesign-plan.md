# Ingredients Page Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the flat ingredient list with a filterable table, and the textarea editor with a structured form featuring Turbo Frames, Turbo Streams, and a "Save & Next" batch entry flow.

**Architecture:** Compact table with client-side search/filter (Stimulus), lazy-loaded detail panels (Turbo Frames), structured nutrition editor dialog (Stimulus + server-rendered form), in-place row updates after save (Turbo Streams). The existing `NutritionLabelParser` textarea path is preserved for CLI; the web form posts structured JSON directly.

**Tech Stack:** Rails 8, Stimulus, Turbo Frames, Turbo Streams, importmap-rails, SQLite, Minitest.

---

### Task 0: Create worktree and branch

**Step 1: Create feature worktree**

Run:
```bash
git worktree add .claude/worktrees/ingredients-redesign -b worktree-ingredients-redesign
cd .claude/worktrees/ingredients-redesign
```

**Step 2: Verify clean state**

Run: `rake test && rake lint`
Expected: All green.

---

### Task 1: Add IngredientsHelper with summary data methods

The current controller builds a flat array of `[name, recipes]` pairs. The redesigned table needs richer data per ingredient: status flags, nutrition summary, density summary, recipe count. Extract this into a helper.

**Files:**
- Create: `app/helpers/ingredients_helper.rb`
- Test: `test/helpers/ingredients_helper_test.rb`

**Step 1: Write the failing test**

Create `test/helpers/ingredients_helper_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class IngredientsHelperTest < ActionView::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'nutrition_summary formats key macros from entry' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110, fat: 0.5, carbs: 23, protein: 3,
      saturated_fat: 0, trans_fat: 0, cholesterol: 0, sodium: 5,
      fiber: 1, total_sugars: 0, added_sugars: 0
    )

    assert_equal '110 cal · 0.5g fat · 23g carbs · 3g protein', nutrition_summary(entry)
  end

  test 'nutrition_summary returns nil for nil entry' do
    assert_nil nutrition_summary(nil)
  end

  test 'nutrition_summary returns nil when basis_grams is nil' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: @kitchen,
      basis_grams: nil, aisle: 'Baking'
    )

    assert_nil nutrition_summary(entry)
  end

  test 'density_summary formats volume-to-weight relationship' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110,
      density_grams: 120, density_volume: 1, density_unit: 'cup'
    )

    assert_equal '1 cup = 120g', density_summary(entry)
  end

  test 'density_summary returns nil when no density data' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Salt', kitchen: nil,
      basis_grams: 6, calories: 0
    )

    assert_nil density_summary(entry)
  end

  test 'portions_summary formats portions including each for unitless' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Eggs', kitchen: nil,
      basis_grams: 50, calories: 70,
      portions: { '~unitless' => 50, 'stick' => 113 }
    )

    result = portions_summary(entry)

    assert_includes result, '1 each = 50g'
    assert_includes result, '1 stick = 113g'
  end

  test 'portions_summary returns nil when no portions' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Salt', kitchen: nil,
      basis_grams: 6, calories: 0, portions: {}
    )

    assert_nil portions_summary(entry)
  end

  test 'ingredient_status returns complete when nutrition and density present' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110,
      density_grams: 120, density_volume: 1, density_unit: 'cup'
    )

    assert_equal :complete, ingredient_status(entry)
  end

  test 'ingredient_status returns missing when entry nil' do
    assert_equal :missing, ingredient_status(nil)
  end

  test 'ingredient_status returns needs_nutrition when no basis_grams' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: @kitchen,
      basis_grams: nil, aisle: 'Baking'
    )

    assert_equal :needs_nutrition, ingredient_status(entry)
  end

  test 'ingredient_status returns needs_density when nutrition but no density' do
    entry = IngredientCatalog.create!(
      ingredient_name: 'Flour', kitchen: nil,
      basis_grams: 30, calories: 110
    )

    assert_equal :needs_density, ingredient_status(entry)
  end

  test 'format_nutrient_value omits trailing zeros' do
    assert_equal '110', format_nutrient_value(110.0)
    assert_equal '0.5', format_nutrient_value(0.5)
    assert_equal '0', format_nutrient_value(0.0)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/ingredients_helper_test.rb`
Expected: FAIL — `IngredientsHelper` not found.

**Step 3: Write the helper**

Create `app/helpers/ingredients_helper.rb`:

```ruby
# frozen_string_literal: true

module IngredientsHelper
  def nutrition_summary(entry)
    return unless entry&.basis_grams

    cal = format_nutrient_value(entry.calories)
    fat = format_nutrient_value(entry.fat)
    carbs = format_nutrient_value(entry.carbs)
    protein = format_nutrient_value(entry.protein)
    "#{cal} cal · #{fat}g fat · #{carbs}g carbs · #{protein}g protein"
  end

  def density_summary(entry)
    return unless entry&.density_grams && entry&.density_volume

    vol = format_nutrient_value(entry.density_volume)
    grams = format_nutrient_value(entry.density_grams)
    "#{vol} #{entry.density_unit} = #{grams}g"
  end

  def portions_summary(entry)
    return if entry&.portions.blank?

    entry.portions.map do |name, grams|
      label = name == '~unitless' ? 'each' : name
      "1 #{label} = #{format_nutrient_value(grams)}g"
    end
  end

  def ingredient_status(entry)
    return :missing unless entry&.basis_grams
    return :needs_density unless entry.density_grams

    :complete
  end

  def ingredient_has_nutrition?(entry)
    entry&.basis_grams.present?
  end

  def ingredient_has_density?(entry)
    entry&.density_grams.present?
  end

  def serving_volume_from_density(entry)
    entry&.density_volume
  end

  def format_nutrient_value(value)
    return '0' unless value

    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/helpers/ingredients_helper_test.rb`
Expected: All tests pass.

**Step 5: Run lint**

Run: `bundle exec rubocop app/helpers/ingredients_helper.rb test/helpers/ingredients_helper_test.rb`

**Step 6: Commit**

```bash
git add app/helpers/ingredients_helper.rb test/helpers/ingredients_helper_test.rb
git commit -m "feat: add IngredientsHelper with status and summary methods"
```

---

### Task 2: Refactor IngredientsController — add routes, show/edit actions, richer index data

Replace the flat `@ingredients_with_recipes` with a richer `@ingredient_rows` array and summary counts. Add `show` and `edit` actions. Add routes.

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `config/routes.rb:13` (add show/edit routes)
- Modify: `test/controllers/ingredients_controller_test.rb`

**Step 1: Add routes**

In `config/routes.rb`, inside the `scope '(/kitchens/:kitchen_slug)'` block, replace line 13:

```ruby
get 'ingredients', to: 'ingredients#index', as: :ingredients
```

with:

```ruby
get 'ingredients', to: 'ingredients#index', as: :ingredients
get 'ingredients/:ingredient_name', to: 'ingredients#show', as: :ingredient_detail
get 'ingredients/:ingredient_name/edit', to: 'ingredients#edit', as: :ingredient_edit
```

**Step 2: Write failing tests for the new actions**

Add to `test/controllers/ingredients_controller_test.rb`:

```ruby
# --- show action (Turbo Frame detail panel) ---

test 'show returns detail panel for ingredient with catalog entry' do
  IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  log_in
  get ingredient_detail_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :success
end

test 'show returns 404 for unknown ingredient' do
  log_in
  get ingredient_detail_path('Nonexistent', kitchen_slug: kitchen_slug)

  assert_response :not_found
end

test 'show requires membership' do
  get ingredient_detail_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :forbidden
end

# --- edit action (Turbo Frame editor form) ---

test 'edit returns structured form for ingredient with data' do
  IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110,
    fat: 0.5, saturated_fat: 0, trans_fat: 0, cholesterol: 0, sodium: 5,
    carbs: 23, fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3,
    density_grams: 120, density_volume: 1, density_unit: 'cup')

  log_in
  get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :success
end

test 'edit returns blank form for ingredient without data' do
  log_in
  get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :success
end

test 'edit requires membership' do
  get ingredient_edit_path('Flour', kitchen_slug: kitchen_slug)

  assert_response :forbidden
end
```

**Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb -n /show\|edit/`
Expected: Routing or action errors.

**Step 4: Refactor the controller**

Rewrite `app/controllers/ingredients_controller.rb`. The `index` action now builds `@ingredient_rows` (array of hashes with name, status flags, aisle, recipe_count, entry, source) and `@summary` (counts). The `show` and `edit` actions serve Turbo Frame partials. Private helpers: `build_ingredient_rows`, `build_summary`, `entry_source`, `row_status`, `first_needing_attention`, `next_needing_attention`, `recipes_for_ingredient`, `canonical_match?`, `recipes_by_ingredient`, `canonical_ingredient_name`, `load_ingredient_data`, `load_ingredient_or_not_found`.

The `show` action returns 404 if the ingredient has no catalog entry AND no recipes. The `edit` action always returns a form (blank if no data).

Key changes from current controller:
- `@ingredients_with_recipes` → `@ingredient_rows` (richer data)
- Added `@summary` hash for the summary bar
- Added `@next_needing_attention` for Save & Next
- Added `show` and `edit` actions with `load_ingredient_data` helper
- Kept `recipes_by_ingredient` and `canonical_ingredient_name` private methods

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`

Note: Existing view-assertion tests will likely break because the view template structure changed. These will be updated in Task 3. The new show/edit action tests should pass.

**Step 6: Run lint**

Run: `bundle exec rubocop app/controllers/ingredients_controller.rb config/routes.rb`

**Step 7: Commit**

```bash
git add app/controllers/ingredients_controller.rb config/routes.rb test/controllers/ingredients_controller_test.rb
git commit -m "feat: add ingredients show/edit actions and richer index data"
```

---

### Task 3: Rewrite the index view with table layout

Replace the flat ingredient list with a compact table. Create partials for the table row, summary bar, and detail panel placeholder.

**Files:**
- Rewrite: `app/views/ingredients/index.html.erb`
- Create: `app/views/ingredients/_summary_bar.html.erb`
- Create: `app/views/ingredients/_table_row.html.erb`
- Create: `app/views/ingredients/_detail_panel.html.erb`
- Modify: `test/controllers/ingredients_controller_test.rb` (update view assertions)

**Step 1: Create partials**

`_summary_bar.html.erb` — status counts as clickable filter shortcuts. Uses `data-action` to wire to Stimulus.

`_table_row.html.erb` — one `<tr>` per ingredient with `data-ingredient-name`, `data-status`, `data-has-nutrition`, `data-has-density` attributes. Columns: Name, Nutrition (check/cross icon), Density (check/cross/dash), Aisle, Recipes (count). Below each row, a hidden `<tr>` wrapping a lazy-loaded `<turbo-frame>` for the detail panel.

`_detail_panel.html.erb` — the content inside the Turbo Frame. Shows nutrition summary, density explanation, portions, recipe links, source badge, Edit/Reset buttons.

**Step 2: Rewrite `index.html.erb`**

Structure:
- `<article class="ingredients-page" data-controller="ingredient-table nutrition-editor">`
- Summary bar partial
- Search input + filter pills toolbar
- `<table>` with `<thead>` and `<tbody>` rendering row partials
- Count label ("Showing N of M ingredients")
- Editor `<dialog>` with Turbo Frame for the form and aisle selector in footer

**Step 3: Update existing tests**

All tests that assert on old DOM (`article.index section h2`, `.nutrition-banner`, `.nutrition-badge .nutrition-missing/.global/.custom`) need updating:
- Ingredient presence: assert `tr.ingredient-row[data-ingredient-name="X"]` exists
- Alphabetical order: extract `data-ingredient-name` from rows, assert sorted
- Recipe count: check detail panel or recipe count column
- Status badges: check `data-has-nutrition`, `data-status` attributes
- Missing banner: now `div.ingredients-summary` with count text

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/views/ingredients/ test/controllers/ingredients_controller_test.rb
git commit -m "feat: rewrite ingredients index as filterable table with Turbo Frames"
```

---

### Task 4: CSS for ingredients table and responsive layout

Add all CSS for the ingredients table, filters, detail panel, status icons, and responsive behavior.

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Replace old nutrition/ingredient CSS**

Lines ~428–493 of `style.css` contain `.nutrition-banner`, `.nutrition-badge`, `.nutrition-missing/.global/.custom`, `.btn-link`. Replace this section with new ingredient page styles:

- `.ingredients-summary` — status bar styling
- `.ingredients-toolbar`, `.ingredients-search` — search box (sticky on scroll)
- `.filter-pills`, `.filter-pill`, `.filter-pill.active` — toggle buttons
- `.ingredients-table` — full-width, collapsed borders
- `.ingredient-row` — cursor pointer, hover background, 44px min-height
- `.col-name`, `.col-nutrition`, `.col-density`, `.col-aisle`, `.col-recipes` — column widths
- `.status-icon`, `.status-yes` (green), `.status-no` (red), `.status-na` (muted) — check/cross/dash
- `.ingredient-expand`, `.ingredient-detail` — expand panel
- `.source-badge`, `.source-missing/.builtin/.custom` — colored badges
- `.btn-small` — compact action button
- `.ingredients-count` — "Showing N of M" label
- `@media (max-width: 640px)` — hide Aisle and Recipes columns, collapse layout

**Step 2: Check if `.btn-link` is used elsewhere**

Search for `.btn-link` in views other than ingredients. If used, keep it. If ingredients-only, it can stay since the aisle selector still uses it (the `_aisle_selector.html.erb` partial doesn't reference `.btn-link` — check the "Add portion" link).

**Step 3: Verify visually**

Run: `bin/dev`, navigate to `/ingredients`. Table should render. Filtering won't work yet (Task 5).

**Step 4: Run lint and tests**

Run: `rake`

**Step 5: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: CSS for ingredients table, responsive layout, and detail panels"
```

---

### Task 5: Create ingredient_table_controller.js (search, filter, expand)

Client-side Stimulus controller for the table interactions. No server calls — everything is DOM visibility toggling.

**Files:**
- Create: `app/javascript/controllers/ingredient_table_controller.js`

**Step 1: Write the controller**

Targets: `searchInput`, `row`, `expandPanel`, `filterButton`, `countLabel`, `summary`.

State: `currentFilter` (string: "all"/"incomplete"/"complete"), `expandedRow` (string ID or null).

Methods:
- `search()` — input event handler, calls `applyFilters()`
- `filter(event)` — click handler on filter pills, reads `data-filter`, toggles `.active` and `aria-pressed`, calls `applyFilters()`
- `filterComplete()` / `filterAttention()` — convenience methods called from summary bar clicks
- `toggleRow(event)` — click handler on table rows, toggles expand panel visibility (one at a time)
- `applyFilters()` — iterates `rowTargets`, hides rows that don't match search+filter, updates count label
- `parameterize(str)` — converts name to URL-safe slug (lowercase, hyphens)

The controller is auto-registered by `pin_all_from 'app/javascript/controllers'` in `config/importmap.rb`. The filename `ingredient_table_controller.js` maps to `data-controller="ingredient-table"`.

**Step 2: Test in browser**

Run: `bin/dev`, navigate to `/ingredients`. Test search (type → rows filter), filter pills (click → toggle), row expand/collapse.

**Step 3: Commit**

```bash
git add app/javascript/controllers/ingredient_table_controller.js
git commit -m "feat: ingredient table Stimulus controller with search, filter, and expand"
```

---

### Task 6: Create the structured editor form partial

Replace the textarea with structured numeric inputs for nutrition, density, and portions.

**Files:**
- Create: `app/views/ingredients/_editor_form.html.erb`
- Create: `app/views/ingredients/_portion_row.html.erb`
- Modify: `app/helpers/ingredients_helper.rb` (add `serving_volume_from_density`)
- Modify: `app/assets/stylesheets/style.css` (editor form styles)

**Step 1: Create `_portion_row.html.erb`**

A single portion row: name text input + "=" + grams number input + "g" + delete button. Uses `data-nutrition-editor-target="portionRow"` for Stimulus targeting.

**Step 2: Create `_editor_form.html.erb`**

Wrapped in `<turbo-frame id="nutrition-editor-form">`. Contains:

- **Nutrition Facts fieldset**: Serving size (number + "g"), "measured as" row (optional volume + unit select + "=" + grams), horizontal divider, 11 nutrient rows using `NutritionLabelParser::LABEL_LINES` to iterate. Each nutrient input: `type="number"`, `inputmode="decimal"`, `step="any"`, `min="0"`, `max="10000"`, `font-size: 1rem`. Indentation via CSS class `indent-0/1/2`.

- **Density details** (collapsible, open if data exists): Help text, volume + unit + "=" + grams row, "Derived from serving size" note (hidden by default).

- **Portions details** (collapsible, open if data exists): Help text, portion row partials from `entry.portions`, "+ Add portion" button.

The form reads `entry&.public_send(key)` for pre-population. Nil entry → blank form.

**Step 3: Add editor form CSS**

Append to the ingredients section of `style.css`: `.nutrition-editor-dialog`, `.editor-form`, `.editor-section`, `.form-row`, `.nutrient-row.indent-N`, `.field-narrow`, `.field-unit-select`, `.portion-row`, `.portion-name-input`, `.portion-grams-input`, `.btn-icon`, `.add-portion`. Mobile: dialog fullscreen, sticky footer, narrower inputs.

All `<input>` elements use `font-size: 1rem` to prevent iOS zoom-on-focus.

**Step 4: Test in browser**

Run: `bin/dev`, navigate to `/ingredients`, click Edit. The form should render with correct data.

**Step 5: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb app/views/ingredients/_portion_row.html.erb app/helpers/ingredients_helper.rb app/assets/stylesheets/style.css
git commit -m "feat: structured nutrition editor form with density and portions sections"
```

---

### Task 7: Rewrite nutrition_editor_controller.js for structured form

Complete rewrite of the Stimulus controller to manage the structured form, dialog lifecycle, serving-volume-to-density sync, dynamic portions, validation, and Save & Next.

**Files:**
- Rewrite: `app/javascript/controllers/nutrition_editor_controller.js`

**Step 1: Write the new controller**

Targets: `dialog`, `title`, `errors`, `formFrame`, `saveButton`, `saveNextButton`, `nextLabel`, `nextName`, `basisGrams`, `nutrientField`, `servingVolume`, `servingUnit`, `servingDensityGrams`, `densitySection`, `densityVolume`, `densityUnit`, `densityGrams`, `densityDerivedNote`, `portionList`, `portionRow`, `portionName`, `portionGrams`, `aisleSelect`, `aisleInput`.

Values: `baseUrl` (String).

Key behaviors:
- `openForIngredient(event)` — reads `data-ingredient-name`, sets title, loads form via Turbo Frame `src` change, shows dialog.
- `close()` — dirty-check then close.
- `save()` / `saveAndNext()` — collect form data, client-side validate, POST structured JSON to nutrition endpoint. On success: if Turbo Stream response, call `Turbo.renderStreamMessage(html)` to update the table in place. For Save & Next, read the updated form frame for the next ingredient name.
- `servingVolumeChanged()` — when "measured as" volume/unit/grams change, auto-derive density and set density fields read-only.
- `addPortion()` — create a new portion row DOM element (use safe DOM API: `createElement`, `textContent`, `appendChild` — **not innerHTML**), append to portion list, focus the name input.
- `removePortion(event)` — remove the closest `.portion-row`.
- `resetIngredient(event)` — DELETE to nutrition endpoint, reload on success.
- `collectFormData()` — builds `{ nutrients, density, portions, aisle }` object. Maps "each" → "~unitless".
- `validateForm(data)` — client-side checks: basis_grams > 0, nutrients 0–10000, density grams > 0 if volume set, no duplicate portion names.
- `isModified()` — compares `JSON.stringify(collectFormData())` against captured original.

The controller decouples from `editor_controller` entirely — manages its own dialog lifecycle using `editor_utils.js` shared functions.

**Step 2: Test in browser**

Run: `bin/dev`, navigate to `/ingredients`. Click Edit → form loads. Test serving volume sync, add/remove portions, save (will need Task 8 for server support). Dirty-check on close.

**Step 3: Commit**

```bash
git add app/javascript/controllers/nutrition_editor_controller.js
git commit -m "feat: rewrite nutrition editor controller for structured form"
```

---

### Task 8: Update NutritionEntriesController for structured JSON

Add the structured JSON acceptance path to the upsert action, alongside the existing `label_text` path.

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Write failing tests for structured JSON**

```ruby
test 'upsert accepts structured JSON with nutrients and density' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: {
         nutrients: { basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0,
                      trans_fat: 0, cholesterol: 0, sodium: 5, carbs: 23,
                      fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3 },
         density: { volume: 0.25, unit: 'cup', grams: 30 },
         portions: {},
         aisle: 'Baking'
       },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')
  assert_in_delta 30.0, entry.basis_grams
  assert_in_delta 110.0, entry.calories
  assert_equal 'cup', entry.density_unit
  assert_equal 'Baking', entry.aisle
end

test 'upsert structured JSON maps each to ~unitless in portions' do
  post nutrition_entry_upsert_path('eggs', kitchen_slug: kitchen_slug),
       params: {
         nutrients: { basis_grams: 50, calories: 70, fat: 5, saturated_fat: 1.5,
                      trans_fat: 0, cholesterol: 185, sodium: 70, carbs: 0.5,
                      fiber: 0, total_sugars: 0.5, added_sugars: 0, protein: 6 },
         density: nil,
         portions: { 'each' => 50, 'stick' => 113 },
         aisle: 'Dairy'
       },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'eggs')
  assert_equal 50, entry.portions['~unitless']
  assert_equal 113, entry.portions['stick']
  assert_nil entry.portions['each']
end

test 'upsert structured JSON validates basis_grams > 0' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { nutrients: { basis_grams: 0, calories: 110 }, density: nil, portions: {}, aisle: nil },
       as: :json

  assert_response :unprocessable_entity
end

test 'upsert structured JSON saves aisle-only when nutrients blank' do
  post nutrition_entry_upsert_path('flour', kitchen_slug: kitchen_slug),
       params: { nutrients: { basis_grams: nil }, density: nil, portions: {}, aisle: 'Baking' },
       as: :json

  assert_response :success
  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')
  assert_equal 'Baking', entry.aisle
  assert_nil entry.basis_grams
end

test 'upsert with save_and_next returns next ingredient name' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups
    - Salt, 1 tsp

    Mix well.
  MD

  post nutrition_entry_upsert_path('Flour', kitchen_slug: kitchen_slug),
       params: {
         nutrients: { basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0,
                      trans_fat: 0, cholesterol: 0, sodium: 5, carbs: 23,
                      fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3 },
         density: { volume: 0.25, unit: 'cup', grams: 30 },
         portions: {}, aisle: 'Baking', save_and_next: true
       },
       as: :json

  assert_response :success
  body = response.parsed_body
  assert_equal 'ok', body['status']
  assert_equal 'Salt', body['next_ingredient']
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb -n /structured\|save_and_next/`

**Step 3: Update the controller**

Add `structured_json_request?` detection (checks for `params[:nutrients]`). When true, parse structured JSON directly:
- Extract and validate nutrients from `params[:nutrients]`
- Assign density from `params[:density]` (nil clears density)
- Assign portions from `params[:portions]`, mapping "each" → "~unitless"
- Handle aisle-only save when `basis_grams` is nil/0
- When `params[:save_and_next]`, find next ingredient needing attention and include in response
- All existing `label_text` tests must still pass

**Step 4: Run all tests**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: All pass (both old and new).

**Step 5: Run full suite + lint**

Run: `rake`

**Step 6: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: accept structured JSON for nutrition entry upsert with Save & Next"
```

---

### Task 9: Add Turbo Stream responses to upsert

When the client sends `Accept: text/vnd.turbo-stream.html`, respond with Turbo Streams that update the table row, detail panel, and summary bar in place.

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Create: `app/views/nutrition_entries/upsert.turbo_stream.erb`
- Modify: `test/controllers/nutrition_entries_controller_test.rb`

**Step 1: Write failing test**

```ruby
test 'upsert responds with Turbo Stream when requested' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  post nutrition_entry_upsert_path('Flour', kitchen_slug: kitchen_slug),
       params: {
         nutrients: { basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0,
                      trans_fat: 0, cholesterol: 0, sodium: 5, carbs: 23,
                      fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3 },
         density: { volume: 0.25, unit: 'cup', grams: 30 },
         portions: {}, aisle: 'Baking'
       },
       headers: { 'Accept' => 'text/vnd.turbo-stream.html' },
       as: :json

  assert_response :success
  assert_includes response.media_type, 'turbo-stream'
end
```

**Step 2: Add `respond_to` in the controller**

After successful save in both `handle_structured_json` and `save_full_entry`, use:

```ruby
respond_to do |format|
  format.turbo_stream { render_turbo_stream_update }
  format.json { render json: response_data }
end
```

The `render_turbo_stream_update` private method sets instance variables and renders the Turbo Stream template.

**Step 3: Create Turbo Stream template**

`app/views/nutrition_entries/upsert.turbo_stream.erb` — replaces the table row, detail panel, and summary bar. For Save & Next, also replaces the editor form frame with the next ingredient's form.

Uses `turbo_stream.replace` with partial rendering. The template needs access to helper methods to build row data and summary data — extract shared logic into `IngredientsHelper` or a service object so both `IngredientsController` and the Turbo Stream template can use it.

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`

**Step 5: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb app/views/nutrition_entries/ test/controllers/nutrition_entries_controller_test.rb
git commit -m "feat: Turbo Stream responses for nutrition upsert"
```

---

### Task 10: Update tests for redesigned view structure

Systematically update all existing `IngredientsControllerTest` assertions to match the new table-based DOM structure.

**Files:**
- Modify: `test/controllers/ingredients_controller_test.rb`

**Step 1: Update all view assertions**

For each test, replace old selectors with new ones:

| Old selector | New selector |
|---|---|
| `article.index section h2` | `tr.ingredient-row[data-ingredient-name]` |
| `article.index section` | `tr.ingredient-row` |
| `.nutrition-missing` | `tr[data-has-nutrition="false"]` |
| `.nutrition-global` | `tr[data-has-nutrition="true"]` (with source check) |
| `.nutrition-custom` | `tr[data-has-nutrition="true"]` (with source check) |
| `details.nutrition-banner` | `div.ingredients-summary` |
| `h2` containing text | `td.col-name` containing text |

**Step 2: Run tests**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All pass.

**Step 3: Run full suite**

Run: `rake`

**Step 4: Commit**

```bash
git add test/controllers/ingredients_controller_test.rb
git commit -m "test: update ingredient controller tests for table-based view"
```

---

### Task 11: Polish — accessibility, keyboard navigation, edge cases

Final pass on keyboard nav, ARIA, mobile, and edge cases.

**Files:**
- Modify: various view, CSS, and JS files as needed

**Step 1: Keyboard navigation**

- Add `keydown` listener to `ingredient_table_controller.js`: Enter/Space on a focused row triggers expand.
- Escape closes the editor dialog (already handled by `<dialog>` default + dirty check).
- After Save & Next, focus lands on serving size field.
- Filter pills: Space/Enter toggles (default button behavior).

**Step 2: ARIA attributes (verify)**

- Rows: `role="button"`, `tabindex="0"` (already in template)
- Filter pills: `aria-pressed` toggled by Stimulus (already implemented)
- Search: `aria-label="Search ingredients"` (already in template)
- Status icons: `aria-label` (already in template)
- Expand: add `aria-expanded` attribute, toggled by Stimulus
- Form sections: `<fieldset>` + `<legend>` for nutrition, `<details>` + `<summary>` for density/portions

**Step 3: Edge cases**

- Ingredient with zero recipes → "0" in count, "No recipes" in detail
- Very long ingredient names → CSS `word-break: break-word` on `.col-name`
- Aisle "omit" → display as "Omit" in aisle column (not "—")
- Empty portions → portions section stays collapsed
- Fractional density volume → "0.25 cup = 30g" renders correctly

**Step 4: Service worker check**

New routes `/ingredients/:name` and `/ingredients/:name/edit` serve HTML (Turbo Frames). They're covered by the existing network-first HTML caching strategy. No SW update needed. Verify.

**Step 5: Run full suite + lint**

Run: `rake`

**Step 6: Commit**

```bash
git add -A
git commit -m "fix: accessibility, keyboard nav, and edge case polish"
```

---

### Task 12: Final review and merge

**Step 1: Run full test suite**

Run: `rake`
Expected: All pass, no lint errors.

**Step 2: Visual review in browser**

Test the complete flow:
- Table renders with all ingredients, correct status indicators
- Search filters instantly, filter pills toggle correctly
- Expand/collapse works (one at a time, lazy loads detail)
- Edit dialog opens with correct pre-populated data
- Serving volume → density sync works (locks density section)
- Add/remove portions works
- Save updates the row in place (Turbo Streams, no page reload)
- Save & Next loads next ingredient without closing dialog
- Reset to built-in works
- Mobile layout: table collapses, dialog goes fullscreen, no zoom-on-focus
- All keyboard flows work

**Step 3: Merge to main**

Use the `superpowers-extended-cc:finishing-a-development-branch` skill to decide the merge strategy.

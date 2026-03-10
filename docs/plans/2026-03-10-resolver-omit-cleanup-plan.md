# Resolver Omit Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate scattered omit-set logic by making IngredientResolver the single owner, replace the `aisle: 'omit'` sentinel with a proper `omit_from_shopping` boolean column, and fix N+1 catalog lookups in CatalogWriteService.

**Architecture:** Add a boolean column to `ingredient_catalogs`, migrate existing sentinel data, extend IngredientResolver with `omitted?` and `omit_set` methods, thread the resolver through RecipeNutritionJob so CatalogWriteService can share one across N recalculations, and mechanically update all sites that checked `aisle == 'omit'`.

**Tech Stack:** Rails 8, SQLite, Minitest, Stimulus (JS), ERB views

---

### Task 0: Migration — add `omit_from_shopping` column

**Files:**
- Create: `db/migrate/003_add_omit_from_shopping_to_ingredient_catalog.rb`
- Modify: `db/migrate/001_create_schema.rb` (consolidate pre-v1.0)

**Step 1: Write the migration**

```ruby
# db/migrate/003_add_omit_from_shopping_to_ingredient_catalog.rb
class AddOmitFromShoppingToIngredientCatalog < ActiveRecord::Migration[8.0]
  def up
    add_column :ingredient_catalog, :omit_from_shopping, :boolean, default: false, null: false
    execute "UPDATE ingredient_catalog SET omit_from_shopping = 1, aisle = NULL WHERE aisle = 'omit'"
  end

  def down
    execute "UPDATE ingredient_catalog SET aisle = 'omit' WHERE omit_from_shopping = 1"
    remove_column :ingredient_catalog, :omit_from_shopping
  end
end
```

**Step 2: Consolidate into 001_create_schema.rb**

Per project convention (pre-v1.0, consolidate all migrations into a single file), fold the new column into the `create_table :ingredient_catalog` block in `001_create_schema.rb`. Add `t.boolean :omit_from_shopping, default: false, null: false` after the `aisle` column. Also add the data migration for `aisle = 'omit'` rows into the migration's seed-fixup section if one exists — otherwise the seed YAML update in Task 7 handles fresh installs.

**Step 3: Run migration and verify**

Run: `rake db:migrate`
Expected: Column exists, 3 rows (Ice, Poolish, Water) have `omit_from_shopping: true` and `aisle: nil`.

Verify: `rails runner "puts IngredientCatalog.where(omit_from_shopping: true).pluck(:ingredient_name).sort.inspect"`
Expected: `["Ice", "Poolish", "Water"]`

Also verify: `rails runner "puts IngredientCatalog.where(aisle: 'omit').count"` → `0`

**Step 4: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat: add omit_from_shopping boolean to ingredient_catalog"
```

---

### Task 1: IngredientResolver — add omit methods

**Files:**
- Modify: `app/services/ingredient_resolver.rb`
- Test: `test/services/ingredient_resolver_test.rb`

**Step 1: Write the failing tests**

Add these tests to the existing resolver test file:

```ruby
test 'omitted? returns true for entries with omit_from_shopping' do
  catalog = {
    'Water' => OpenStruct.new(ingredient_name: 'Water', omit_from_shopping: true),
    'Salt' => OpenStruct.new(ingredient_name: 'Salt', omit_from_shopping: false)
  }
  resolver = IngredientResolver.new(catalog)

  assert resolver.omitted?('Water')
  assert_not resolver.omitted?('Salt')
end

test 'omitted? returns false for uncataloged ingredients' do
  resolver = IngredientResolver.new({})
  assert_not resolver.omitted?('Unknown')
end

test 'omit_set returns downcased names of omitted entries' do
  catalog = {
    'Water' => OpenStruct.new(ingredient_name: 'Water', omit_from_shopping: true),
    'Ice' => OpenStruct.new(ingredient_name: 'Ice', omit_from_shopping: true),
    'Salt' => OpenStruct.new(ingredient_name: 'Salt', omit_from_shopping: false)
  }
  resolver = IngredientResolver.new(catalog)

  assert_equal Set['water', 'ice'], resolver.omit_set
end

test 'omit_set is memoized' do
  catalog = {
    'Water' => OpenStruct.new(ingredient_name: 'Water', omit_from_shopping: true)
  }
  resolver = IngredientResolver.new(catalog)

  assert_same resolver.omit_set, resolver.omit_set
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/ingredient_resolver_test.rb`
Expected: FAIL — `omitted?` and `omit_set` not defined

**Step 3: Implement**

In `app/services/ingredient_resolver.rb`, add two public methods after `all_keys_for`:

```ruby
def omitted?(name)
  find_entry(name)&.omit_from_shopping == true
end

def omit_set
  @omit_set ||= @lookup.each_value
                        .select(&:omit_from_shopping)
                        .to_set { |e| e.ingredient_name.downcase }
end
```

Update the header comment to add `RecipeNutritionJob` as a collaborator and mention omit-set ownership.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_resolver_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/services/ingredient_resolver.rb test/services/ingredient_resolver_test.rb
git commit -m "feat: add omitted? and omit_set to IngredientResolver"
```

---

### Task 2: RecipeNutritionJob — accept optional resolver

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Test: `test/jobs/recipe_nutrition_job_test.rb`

**Step 1: Write the failing test**

Add a test that verifies the job uses a provided resolver instead of calling `lookup_for`:

```ruby
test 'uses provided resolver instead of querying catalog' do
  resolver = IngredientCatalog.resolver_for(@kitchen)
  # If the job uses the resolver, it won't call lookup_for again
  RecipeNutritionJob.perform_now(@recipe, resolver: resolver)
  # Verify nutrition was calculated (recipe has nutrition_data)
  assert @recipe.reload.nutrition_data.present?
end
```

Check the existing test file structure first. The key change: `perform` signature changes from `perform(recipe)` to `perform(recipe, resolver: nil)`.

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: FAIL — `perform` doesn't accept `resolver:` keyword

**Step 3: Implement**

Change `app/jobs/recipe_nutrition_job.rb`:

```ruby
def perform(recipe, resolver: nil)
  loaded = eager_load_recipe(recipe)
  resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)
  return if resolver.lookup.empty?

  nutrition_data = build_nutrition_data(resolver.lookup)
  calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: resolver.omit_set)
  result = calculator.calculate(loaded, {})

  recipe.update_column(:nutrition_data, serialize_result(result)) # rubocop:disable Rails/SkipsModelValidations
end
```

Delete the `extract_omit_set` method entirely. Remove the line `catalog = IngredientCatalog.lookup_for(loaded.kitchen)`.

Update header comment: mention resolver acceptance and omit delegation.

**Step 4: Run all job tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All pass

**Step 5: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb test/jobs/recipe_nutrition_job_test.rb
git commit -m "refactor: RecipeNutritionJob accepts optional resolver, delegates omit to it"
```

---

### Task 3: CatalogWriteService — share resolver, fix N+1

**Files:**
- Modify: `app/services/catalog_write_service.rb`
- Test: `test/services/catalog_write_service_test.rb`

**Step 1: Write the failing test**

The N+1 fix is a performance improvement. Add a test that verifies a single resolver is shared. The simplest approach: add a test that confirms nutrition recalculation works correctly after the refactor (existing tests likely cover this). Focus on verifying the `resolver:` kwarg is threaded through.

Check existing tests first — existing tests for `upsert` and `bulk_import` that verify nutrition recalculation should continue to pass after the refactor. No new test needed if existing coverage is sufficient.

**Step 2: Refactor recalculate methods**

In `app/services/catalog_write_service.rb`, change `recalculate_affected_recipes`:

```ruby
def recalculate_affected_recipes
  resolver = IngredientCatalog.resolver_for(kitchen)
  raw_names = resolver.all_keys_for(ingredient_name)
  kitchen.recipes
         .joins(steps: :ingredients)
         .where(ingredients: { name: raw_names })
         .distinct
         .find_each { |recipe| RecipeNutritionJob.perform_now(recipe, resolver:) }
end
```

And `recalculate_all_affected_recipes`:

```ruby
def recalculate_all_affected_recipes(entries_hash)
  return if kitchen.recipes.none?

  resolver = IngredientCatalog.resolver_for(kitchen)
  raw_names = entries_hash.keys.flat_map { |name| resolver.all_keys_for(name) }.uniq
  kitchen.recipes
         .joins(steps: :ingredients)
         .where(ingredients: { name: raw_names })
         .distinct
         .find_each { |recipe| RecipeNutritionJob.perform_now(recipe, resolver:) }
end
```

The only change in each method is adding `resolver:` to the `perform_now` call. The resolver was already being built for `all_keys_for` — now it's also passed to the job.

**Step 3: Run tests**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass

**Step 4: Commit**

```bash
git add app/services/catalog_write_service.rb
git commit -m "fix: share resolver across RecipeNutritionJob calls to eliminate N+1 catalog lookups"
```

---

### Task 4: RecipeAvailabilityCalculator — use resolver.omitted?

**Files:**
- Modify: `app/services/recipe_availability_calculator.rb`
- Test: `test/services/recipe_availability_calculator_test.rb`

**Step 1: Update existing tests**

Existing tests create catalog entries with `aisle: 'omit'`. Update them to use `omit_from_shopping: true` instead. Find the test at `test/services/recipe_availability_calculator_test.rb:38`:

```ruby
# Change from:
create_catalog_entry('Water', basis_grams: 240, aisle: 'omit')
# To:
create_catalog_entry('Water', basis_grams: 240, omit_from_shopping: true)
```

Check what `create_catalog_entry` helper does — it may need updating if it doesn't pass through `omit_from_shopping`.

**Step 2: Refactor the calculator**

In `app/services/recipe_availability_calculator.rb`:

- Remove `@omitted = build_omit_set` from `initialize`
- Delete the `build_omit_set` method
- Change `needed_ingredients` to use `@resolver.omitted?`:

```ruby
def needed_ingredients(names)
  names.map { |name| canonical_name(name) }
       .reject { |name| @resolver.omitted?(name) }
       .uniq
end
```

**Step 3: Run tests**

Run: `ruby -Itest test/services/recipe_availability_calculator_test.rb`
Expected: All pass

**Step 4: Commit**

```bash
git add app/services/recipe_availability_calculator.rb test/services/recipe_availability_calculator_test.rb
git commit -m "refactor: RecipeAvailabilityCalculator uses resolver.omitted? instead of own omit set"
```

---

### Task 5: ShoppingListBuilder — use resolver.omitted?

**Files:**
- Modify: `app/services/shopping_list_builder.rb`
- Test: `test/services/shopping_list_builder_test.rb`

**Step 1: Update existing tests**

Find tests that set `aisle: 'omit'` (lines ~52-53, ~567-568):

```ruby
# Change from:
IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: 'omit')
# To:
IngredientCatalog.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(omit_from_shopping: true)
```

**Step 2: Refactor the builder**

In `app/services/shopping_list_builder.rb`, change line 90 in `organize_by_aisle`:

```ruby
# From:
visible = ingredients.reject { |name, _| aisle_for(name) == 'omit' }
# To:
visible = ingredients.reject { |name, _| @resolver.omitted?(name) }
```

**Step 3: Run tests**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All pass

**Step 4: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "refactor: ShoppingListBuilder uses resolver.omitted? instead of aisle string check"
```

---

### Task 6: AisleWriteService, Kitchen, IngredientsHelper — remove sentinel guards

**Files:**
- Modify: `app/services/aisle_write_service.rb:48-49,56-57`
- Modify: `app/models/kitchen.rb:62`
- Modify: `app/helpers/ingredients_helper.rb:43-47`
- Test: `test/services/aisle_write_service_test.rb`
- Test: `test/models/kitchen_test.rb`
- Test: `test/helpers/ingredients_helper_test.rb`

**Step 1: Update tests**

In `test/services/aisle_write_service_test.rb`, tests around lines 185-190 and 223-231 test that `'omit'` is skipped. These tests should be deleted — `'omit'` is no longer a special string in the aisle context. If someone has an aisle literally called "omit" it should be treated like any other aisle name. (This won't happen in practice because the UI no longer offers it as an aisle option.)

In `test/models/kitchen_test.rb` around line 74-77, the test that `all_aisles` excludes `'omit'` should be updated: change the catalog entry to use `omit_from_shopping: true` with a real aisle (or nil aisle), and assert the real aisle appears or nil aisle doesn't appear.

In `test/helpers/ingredients_helper_test.rb`, if there's a test for `display_aisle('omit')` → `'Omit'`, delete it.

**Step 2: Remove guards**

In `app/services/aisle_write_service.rb`:
- Line 49: Delete `return if aisle == 'omit'`
- Line 57: Change `new_aisles = aisles.reject { |a| a == 'omit' }.uniq` to `new_aisles = aisles.uniq`

In `app/models/kitchen.rb`:
- Line 62: Change `.where.not(aisle: [nil, '', 'omit'])` to `.where.not(aisle: [nil, ''])`

In `app/helpers/ingredients_helper.rb`:
- Lines 43-47: Simplify `display_aisle`:
```ruby
def display_aisle(aisle)
  aisle || "\u2014"
end
```

**Step 3: Run tests**

Run: `ruby -Itest test/services/aisle_write_service_test.rb test/models/kitchen_test.rb test/helpers/ingredients_helper_test.rb`
Expected: All pass

**Step 4: Commit**

```bash
git add app/services/aisle_write_service.rb app/models/kitchen.rb app/helpers/ingredients_helper.rb \
        test/services/aisle_write_service_test.rb test/models/kitchen_test.rb test/helpers/ingredients_helper_test.rb
git commit -m "refactor: remove aisle='omit' sentinel guards from AisleWriteService, Kitchen, helper"
```

---

### Task 7: Seed YAML, attrs_from_yaml, export — handle boolean

**Files:**
- Modify: `db/seeds/resources/ingredient-catalog.yaml` (lines 1119, 1746, 2568)
- Modify: `app/models/ingredient_catalog.rb:65-84` (`attrs_from_yaml`)
- Modify: `app/services/export_service.rb:82-91` (`entry_to_hash`)
- Test: `test/services/export_service_test.rb`

**Step 1: Update seed YAML**

Change the three entries from `aisle: omit` to `omit_from_shopping: true`:

```yaml
Ice:
  omit_from_shopping: true

Poolish:
  omit_from_shopping: true

Water:
  omit_from_shopping: true
```

**Step 2: Update attrs_from_yaml**

In `app/models/ingredient_catalog.rb`, method `attrs_from_yaml` (line 65), add handling for the new key:

```ruby
def self.attrs_from_yaml(entry)
  attrs = { aisle: entry['aisle'] }
  attrs[:omit_from_shopping] = true if entry['omit_from_shopping']

  # Backward compat: treat aisle='omit' from old-format imports
  if attrs[:aisle] == 'omit'
    attrs[:aisle] = nil
    attrs[:omit_from_shopping] = true
  end

  # ... rest unchanged
end
```

**Step 3: Update ExportService**

In `app/services/export_service.rb`, `entry_to_hash` method, add:

```ruby
def entry_to_hash(entry)
  h = {}
  h['aisle'] = entry.aisle if entry.aisle.present?
  h['omit_from_shopping'] = true if entry.omit_from_shopping
  h['aliases'] = entry.aliases if entry.aliases.present?
  # ... rest unchanged
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/services/export_service_test.rb`
Expected: All pass

Also run: `rake catalog:sync` to verify seed YAML loads correctly.

**Step 5: Commit**

```bash
git add db/seeds/resources/ingredient-catalog.yaml app/models/ingredient_catalog.rb \
        app/services/export_service.rb
git commit -m "feat: seed YAML and import/export use omit_from_shopping boolean"
```

---

### Task 8: Editor UI — checkbox replaces dropdown option

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb:84-104`
- Modify: `app/views/ingredients/_aisle_selector.html.erb:9-10`
- Modify: `app/javascript/controllers/nutrition_editor_controller.js:279,406-412`
- Modify: `app/controllers/nutrition_entries_controller.rb` (accept new param)

**Step 1: Update the editor form**

In `app/views/ingredients/_editor_form.html.erb`, replace the omit option in the aisle dropdown (lines 95-96) and add a checkbox. Remove the `<option value="omit">` line and its surrounding separators. Add a checkbox after the aisle fieldset:

```erb
<fieldset class="editor-section aisle-section">
  <legend class="editor-section-title">Grocery Aisle</legend>
  <div class="form-row aisle-row">
    <select class="aisle-form-select"
            data-nutrition-editor-target="aisleSelect"
            data-action="change->nutrition-editor#aisleChanged"
            aria-label="Grocery aisle">
      <option value="">(none)</option>
      <%- available_aisles.each do |aisle| -%>
        <option value="<%= aisle %>" <%= 'selected' if entry&.aisle == aisle %>><%= aisle %></option>
      <%- end -%>
      <option disabled>&#x2500;&#x2500;&#x2500;</option>
      <option value="__other__">New aisle&hellip;</option>
    </select>
    <input type="text" class="aisle-new-input" placeholder="New aisle name" hidden
           data-nutrition-editor-target="aisleInput"
           data-action="keydown->nutrition-editor#aisleInputKeydown">
  </div>
  <label class="form-row omit-row">
    <input type="checkbox"
           data-nutrition-editor-target="omitCheckbox"
           <%= 'checked' if entry&.omit_from_shopping %>>
    Omit from grocery list
  </label>
</fieldset>
```

**Step 2: Update the aisle selector partial**

In `app/views/ingredients/_aisle_selector.html.erb`, remove the omit option (line 10) and its separator (line 9):

```erb
<%# locals: (aisles:) %>
<select id="nutrition-editor-aisle" class="aisle-select" aria-label="Grocery aisle"
        data-nutrition-editor-target="aisleSelect"
        data-action="change->nutrition-editor#aisleChanged">
  <option value="">(none)</option>
  <%- aisles.each do |aisle| -%>
  <option value="<%= aisle %>"><%= aisle %></option>
  <%- end -%>
  <option disabled>&#x2500;&#x2500;&#x2500;</option>
  <option value="__other__">New aisle&hellip;</option>
</select>
<input type="text" id="nutrition-editor-aisle-input" class="aisle-input" placeholder="New aisle name" hidden
       data-nutrition-editor-target="aisleInput"
       data-action="keydown->nutrition-editor#aisleInputKeydown">
<span class="editor-footer-spacer"></span>
```

**Step 3: Update the Stimulus controller**

In `app/javascript/controllers/nutrition_editor_controller.js`:

Add `"omitCheckbox"` to the `static targets` array (line 21).

Update `collectFormData()` (line 274) to include the checkbox:

```javascript
collectFormData() {
  return {
    nutrients: this.collectNutrients(),
    density: this.collectDensity(),
    portions: this.collectPortions(),
    aisle: this.currentAisle(),
    aliases: this.collectAliases(),
    omit_from_shopping: this.hasOmitCheckboxTarget && this.omitCheckboxTarget.checked
  }
}
```

The `currentAisle()` method (line 406) no longer needs to handle `"omit"` as a value — it already only handles `"__other__"` and regular values, so no change needed there.

Update the dirty-detection snapshot logic to include the checkbox state. Check how `takeSnapshot` / `isDirty` work and add `omitCheckbox` to the snapshot.

**Step 4: Update the controller (server-side)**

In `app/controllers/nutrition_entries_controller.rb`, the params likely flow through `CatalogWriteService.upsert` → `assign_from_params`. Check how params are extracted and ensure `omit_from_shopping` is passed through.

In `app/models/ingredient_catalog.rb`, update `assign_from_params` to accept and set `omit_from_shopping`:

```ruby
def assign_from_params(nutrients:, density:, portions:, aisle:, sources:, aliases: nil, omit_from_shopping: false)
  assign_nutrients(nutrients)
  assign_density(density)
  self.portions = normalize_portions_hash(portions)
  self.aisle = aisle if aisle
  self.sources = sources
  self.aliases = aliases unless aliases.nil?
  self.omit_from_shopping = omit_from_shopping
end
```

**Step 5: Run tests**

Run: `rake test`
Expected: All pass

**Step 6: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb app/views/ingredients/_aisle_selector.html.erb \
        app/javascript/controllers/nutrition_editor_controller.js \
        app/models/ingredient_catalog.rb app/controllers/nutrition_entries_controller.rb
git commit -m "feat: replace omit dropdown option with checkbox in ingredient editor"
```

---

### Task 9: BuildValidator and TUI — update omit checks

**Files:**
- Modify: `lib/familyrecipes/build_validator.rb:51`
- Modify: `lib/nutrition_tui/data.rb:253-256`
- Modify: `bin/nutrition:54`

**Step 1: Update BuildValidator**

In `lib/familyrecipes/build_validator.rb`, line 51:

```ruby
# From:
omit_set = IngredientCatalog.where(aisle: 'omit').pluck(:ingredient_name).to_set(&:downcase)
# To:
omit_set = IngredientCatalog.where(omit_from_shopping: true).pluck(:ingredient_name).to_set(&:downcase)
```

**Step 2: Update NutritionTui::Data**

In `lib/nutrition_tui/data.rb`, `build_omit_set` method (lines 253-256):

```ruby
def build_omit_set(catalog)
  catalog.each_with_object(Set.new) do |(name, entry), set|
    set << name.downcase if entry['omit_from_shopping']
  end
end
```

Also remove the mirror comment about `RecipeNutritionJob#extract_omit_set` — that method no longer exists.

**Step 3: Update bin/nutrition**

In `bin/nutrition`, line 54:

```ruby
# From:
omitted = nutrition_data.count { |_, e| e['aisle'] == 'omit' }
# To:
omitted = nutrition_data.count { |_, e| e['omit_from_shopping'] }
```

**Step 4: Run the full test suite and TUI smoke test**

Run: `rake test`
Expected: All pass

Run: `ruby bin/nutrition --coverage` (if seed data is loaded)
Expected: Shows correct omitted count (3)

**Step 5: Commit**

```bash
git add lib/familyrecipes/build_validator.rb lib/nutrition_tui/data.rb bin/nutrition
git commit -m "refactor: BuildValidator and TUI use omit_from_shopping boolean"
```

---

### Task 10: IngredientCatalog model — add validation and update header

**Files:**
- Modify: `app/models/ingredient_catalog.rb`

**Step 1: Verify no remaining `'omit'` references**

Run: `grep -r "== 'omit'" app/ lib/ --include='*.rb'`
Expected: No matches in Rails pipeline. Only `lib/nutrition_tui/` may still reference YAML keys (which is fine — the YAML key changed).

Run: `grep -r "'omit'" app/ lib/ --include='*.rb'`
Expected: No matches except possibly in test files or comments referencing the old sentinel.

Also: `grep -r "'omit'" app/ lib/ --include='*.erb' --include='*.js'`
Expected: No matches.

**Step 2: Clean up IngredientCatalog**

If `aisle` validation still allows `'omit'` as a value, no change needed — it's now just treated as a regular string. But optionally add a validation that prevents `aisle: 'omit'` to catch old-format data leaking in:

Actually, skip this — YAGNI. The `attrs_from_yaml` backward compat handles imports, and the UI no longer offers it.

Update the header comment on `IngredientCatalog` to mention `omit_from_shopping`.

**Step 3: Commit if any changes**

```bash
git add app/models/ingredient_catalog.rb
git commit -m "docs: update IngredientCatalog header comment for omit_from_shopping"
```

---

### Task 11: Full test suite + lint + CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (if architecture section references omit)
- Run: `rake` (lint + test)

**Step 1: Run the full suite**

Run: `rake`
Expected: 0 RuboCop offenses, all tests pass

**Step 2: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass (no new `.html_safe` calls)

**Step 3: Check for stale references**

Run: `grep -rn "aisle.*omit\|omit.*aisle" app/ lib/ test/ --include='*.rb' --include='*.erb' --include='*.js'`

Any remaining hits should be in:
- Test files that were already updated
- Comments referencing the old design (update or remove)
- `attrs_from_yaml` backward compat (intentional)

**Step 4: Update CLAUDE.md if needed**

Check if the Architecture section or Nutrition pipeline section mentions `aisle: 'omit'`. If so, update to reference `omit_from_shopping`.

**Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final cleanup — lint, stale references, CLAUDE.md"
```

---

### Task 12: Manual smoke test

**No files to modify — verification only.**

**Step 1: Start the dev server**

Run: `bin/dev`

**Step 2: Test the ingredient editor**

- Open the ingredients page
- Click an ingredient to edit
- Verify the aisle dropdown no longer has an "Omit from Grocery List" option
- Verify a checkbox labeled "Omit from grocery list" appears below the aisle selector
- For an omitted ingredient (Water, Ice, Poolish), verify the checkbox is checked
- Toggle the checkbox, save, verify it persists

**Step 3: Test the grocery list**

- Select recipes on the menu page
- Go to the grocery list
- Verify omitted ingredients (Water, Ice, Poolish) don't appear
- Verify non-omitted ingredients with aisles appear under their correct aisle

**Step 4: Test import/export round-trip**

- Export kitchen data
- Inspect the YAML: omitted entries should have `omit_from_shopping: true`
- Re-import: verify omit state is preserved

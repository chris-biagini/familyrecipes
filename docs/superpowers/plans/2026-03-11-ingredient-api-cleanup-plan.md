# Ingredient API Cleanup Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix four code smells in the ingredient editor API layer — an imperative loop, unnecessary calculator coupling, duplicated source queries, and manual Data.define destructuring.

**Architecture:** Pure refactoring — no new features, no schema changes, no route changes. Each task is independent (except docs, which comes last). All existing tests must continue to pass; new tests added where coverage gaps exist.

**Tech Stack:** Ruby/Rails, Minitest

---

### Task 1: Fix CatalogWriteService#save_all_entries imperative loop

**Files:**
- Modify: `app/services/catalog_write_service.rb:90-105`
- Test: `test/services/catalog_write_service_test.rb` (existing tests cover this path)

**Step 1: Rewrite save_all_entries with each_with_object**

Replace the `each` + accumulator pattern:

```ruby
# BEFORE (lines 90-105)
def save_all_entries(entries_hash)
  persisted = 0
  errors = []

  entries_hash.each do |name, entry|
    record = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name: name)
    record.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))
    if record.save
      persisted += 1
    else
      errors << "#{name}: #{record.errors.full_messages.join(', ')}"
    end
  end

  [persisted, errors]
end
```

```ruby
# AFTER
def save_all_entries(entries_hash)
  saved, failed = entries_hash.each_with_object([[], []]) do |(name, entry), (ok, err)|
    record = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name: name)
    record.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))
    if record.save
      ok << record
    else
      err << "#{name}: #{record.errors.full_messages.join(', ')}"
    end
  end

  [saved.size, failed]
end
```

**Step 2: Run existing tests**

```bash
ruby -Itest test/services/catalog_write_service_test.rb
```

Expected: all pass — behavior is identical.

**Step 3: Run lint**

```bash
bundle exec rubocop app/services/catalog_write_service.rb
```

**Step 4: Commit**

```bash
git add app/services/catalog_write_service.rb
git commit -m "refactor: replace imperative loop in CatalogWriteService#save_all_entries"
```

---

### Task 2: Remove NutritionCalculator coupling from IngredientRowBuilder

**Files:**
- Modify: `app/services/ingredient_row_builder.rb:41-52, 117-124, 189-212`
- Test: `test/services/ingredient_row_builder_test.rb` (existing tests cover needed_units and coverage)

The current code instantiates `NutritionCalculator` in `needed_units` and `find_bad_units` solely to call `resolvable?`. The resolution logic is straightforward — it checks: (1) weight unit? (2) named portion exists? (3) volume unit with density? (4) bare count with ~unitless portion? We can check these directly from the entry.

**Step 1: Add a private `unit_resolvable?` method to IngredientRowBuilder**

This replaces the calculator-based resolution check. The logic mirrors `NutritionCalculator#to_grams` but only needs boolean answers, not gram values.

```ruby
def unit_resolvable?(unit, entry)
  return false if entry&.basis_grams.blank?
  return true if weight_unit?(unit)
  return portion_defined?(entry, unit) if unit && !volume_unit?(unit)
  return density_defined?(entry) if unit && volume_unit?(unit)

  # Bare count (unit is nil) — needs ~unitless portion
  entry.portions&.key?('~unitless')
end

def volume_unit?(unit)
  unit && VOLUME_UNITS.include?(unit.downcase)
end

def portion_defined?(entry, unit)
  return false if entry.portions.blank?

  entry.portions.any? { |k, _| k.casecmp(unit).zero? }
end

def density_defined?(entry)
  entry.density_grams.present? && entry.density_volume.present? && entry.density_unit.present?
end
```

**Step 2: Rewrite `needed_units` to use `unit_resolvable?` directly**

```ruby
def needed_units(ingredient_name)
  entry = @resolver.catalog_entry(ingredient_name)
  units = collect_units_for(ingredient_name)
  return [] if units.empty?

  units.map do |unit|
    resolvable = unit_resolvable?(unit, entry)
    { unit:, resolvable:, method: resolution_method(unit, resolvable, entry) }
  end
end
```

**Step 3: Rewrite `find_bad_units` to use `unit_resolvable?` directly**

```ruby
def find_bad_units(_name, entry, units)
  return units.map { |u| { unit: u, method: 'no nutrition data' } } if entry&.basis_grams.blank?

  units.reject { |u| unit_resolvable?(u, entry) }
       .map { |u| { unit: u, method: resolution_method(u, false, entry) } }
end
```

**Step 4: Remove `build_unit_row` (absorbed into `needed_units`)**

Delete the `build_unit_row` method entirely — it's no longer called.

**Step 5: Run existing tests**

```bash
ruby -Itest test/services/ingredient_row_builder_test.rb
```

Expected: all 22 tests pass — behavior is identical.

**Step 6: Add test for portion-based resolution**

Add a test verifying that a named portion resolves correctly without density:

```ruby
test 'needed_units marks named portion as resolvable' do
  create_catalog_entry('Yeast', basis_grams: 3)
  entry = IngredientCatalog.find_by(ingredient_name: 'Yeast', kitchen_id: nil)
  entry.update!(portions: { 'packet' => 7.0 })

  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  units = builder.needed_units('Yeast')

  packet_entry = units.find { |u| u[:unit] == 'packet' }

  assert packet_entry, 'expected a packet unit entry'
  assert packet_entry[:resolvable]
end
```

**Step 7: Run full tests and lint**

```bash
ruby -Itest test/services/ingredient_row_builder_test.rb
bundle exec rubocop app/services/ingredient_row_builder.rb
```

**Step 8: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "refactor: remove NutritionCalculator coupling from IngredientRowBuilder"
```

---

### Task 3: Move sources_for_ingredient into IngredientRowBuilder

**Files:**
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `app/controllers/ingredients_controller.rb:47-61`
- Test: `test/services/ingredient_row_builder_test.rb`
- Test: `test/controllers/ingredients_controller_test.rb` (existing edit tests)

`IngredientsController#sources_for_ingredient` duplicates the recipe-by-ingredient query that `IngredientRowBuilder` already computes in `recipes_by_ingredient`. The controller also has `quick_bites_using` which reimplements quick bite lookup. Move both into the builder.

**Step 1: Add `sources_for(name)` to IngredientRowBuilder**

```ruby
def sources_for(name)
  recipes_by_ingredient[name] || []
end
```

This returns the same array of `Recipe` and `QuickBiteSource` objects already computed by `compute_recipes_by_ingredient`.

**Step 2: Update IngredientsController#edit to use the builder**

```ruby
def edit
  ingredient_name, entry = load_ingredient_data
  aisles = current_kitchen.all_aisles
  sources = row_builder.sources_for(ingredient_name)
  needed_units = row_builder.needed_units(ingredient_name)

  render partial: 'ingredients/editor_form',
         locals: { ingredient_name:, entry:, available_aisles: aisles, sources:, needed_units: }
end
```

**Step 3: Delete `sources_for_ingredient` and `quick_bites_using` from IngredientsController**

Remove both private methods entirely (lines 47-61).

**Step 4: Add test for `sources_for` in IngredientRowBuilderTest**

```ruby
test 'sources_for returns recipes using the ingredient' do
  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  sources = builder.sources_for('Flour')

  assert_equal 2, sources.size
  assert(sources.all? { |s| s.is_a?(Recipe) })
end

test 'sources_for includes quick bite sources' do
  @kitchen.update!(quick_bites_content: <<~MD)
    Snacks:
    - Toast: Flour, Butter
  MD

  builder = IngredientRowBuilder.new(kitchen: @kitchen)
  sources = builder.sources_for('Flour')

  assert_equal 3, sources.size
  assert(sources.any? { |s| s.is_a?(IngredientRowBuilder::QuickBiteSource) })
end

test 'sources_for returns empty array for unknown ingredient' do
  builder = IngredientRowBuilder.new(kitchen: @kitchen)

  assert_empty builder.sources_for('Nonexistent')
end
```

**Step 5: Run tests and lint**

```bash
ruby -Itest test/services/ingredient_row_builder_test.rb
ruby -Itest test/controllers/ingredients_controller_test.rb
bundle exec rubocop app/services/ingredient_row_builder.rb app/controllers/ingredients_controller.rb
```

**Step 6: Commit**

```bash
git add app/services/ingredient_row_builder.rb app/controllers/ingredients_controller.rb test/services/ingredient_row_builder_test.rb
git commit -m "refactor: consolidate sources_for_ingredient into IngredientRowBuilder"
```

---

### Task 4: Add as_json to UsdaImportService::Result, remove import_json

**Files:**
- Modify: `app/services/usda_import_service.rb:14`
- Modify: `app/controllers/usda_search_controller.rb:25-26, 43-46`
- Test: `test/services/usda_import_service_test.rb`
- Test: `test/controllers/usda_search_controller_test.rb` (existing tests)

**Step 1: Add `as_json` to UsdaImportService::Result**

Following the project convention (see `NutritionCalculator::Result#as_json`):

```ruby
Result = Data.define(:nutrients, :density, :source, :portions, :density_candidates) do
  def as_json(_options = nil)
    to_h
  end
end
```

Note: Unlike `NutritionCalculator::Result` which needs key/value transforms, this Result's members are already plain hashes/arrays — `to_h` suffices.

**Step 2: Update UsdaSearchController#show to use render json: import**

```ruby
def show
  detail = usda_client.fetch(fdc_id: params[:fdc_id])
  import = UsdaImportService.call(detail)
  render json: import
end
```

**Step 3: Delete `import_json` private method from UsdaSearchController**

Remove the method entirely (lines 43-46).

**Step 4: Add test for Result#as_json**

In `test/services/usda_import_service_test.rb`:

```ruby
test 'Result#as_json returns hash with all keys' do
  result = UsdaImportService.call(@detail)
  json = result.as_json

  assert_kind_of Hash, json
  assert_equal %i[density density_candidates nutrients portions source], json.keys.sort
  assert_in_delta 52.0, json[:nutrients][:calories]
end
```

**Step 5: Run tests and lint**

```bash
ruby -Itest test/services/usda_import_service_test.rb
ruby -Itest test/controllers/usda_search_controller_test.rb
bundle exec rubocop app/services/usda_import_service.rb app/controllers/usda_search_controller.rb
```

**Step 6: Commit**

```bash
git add app/services/usda_import_service.rb app/controllers/usda_search_controller.rb test/services/usda_import_service_test.rb
git commit -m "refactor: add as_json to UsdaImportService::Result, remove manual destructuring"
```

---

### Task 5: Update architectural comments and CLAUDE.md

**Files:**
- Modify: `app/services/ingredient_row_builder.rb` (header comment)
- Modify: `app/controllers/ingredients_controller.rb` (header comment)
- Modify: `app/services/usda_import_service.rb` (header comment — add Result mention)
- Modify: `CLAUDE.md` (if any cross-cutting change; likely minimal)

**Step 1: Update IngredientRowBuilder header comment**

Remove mention of NutritionCalculator as a collaborator (no longer used). Add mention of `sources_for` in the role description.

**Step 2: Update IngredientsController header comment**

Remove mention of source-finding responsibility — now delegated to IngredientRowBuilder.

**Step 3: Update UsdaImportService header comment**

Note that `Result#as_json` enables direct `render json:` in controllers.

**Step 4: Review CLAUDE.md for needed updates**

Check if `IngredientRowBuilder` description in CLAUDE.md mentions NutritionCalculator or resolution checking — update if so. The `IngredientRowBuilder` bullet currently says it "computes per-ingredient `needed_units` (unit resolution status)" which remains accurate.

**Step 5: Run lint on all modified files**

```bash
bundle exec rubocop app/services/ingredient_row_builder.rb app/controllers/ingredients_controller.rb app/services/usda_import_service.rb
```

**Step 6: Commit**

```bash
git add app/services/ingredient_row_builder.rb app/controllers/ingredients_controller.rb app/services/usda_import_service.rb CLAUDE.md
git commit -m "docs: update architectural comments after ingredient API cleanup"
```

# Import Write Path Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix ImportService to route catalog entries through CatalogWriteService, reorder import phases so nutrition is correct on first calculation, and export/import aisle and category ordering.

**Architecture:** Buffer ZIP entries by type, process in phased order (settings → catalog → quick bites → recipes → category positions). New `CatalogWriteService.bulk_import` handles batch persistence with single-pass aisle sync and nutrition recalc. Export gains two new settings files.

**Tech Stack:** Rails 8, Minitest, rubyzip

---

### Task 1: Add `bulk_import` to CatalogWriteService — tests

**Files:**
- Modify: `test/services/catalog_write_service_test.rb`

**Step 1: Write failing tests for bulk_import**

Add a new test section after the existing `destroy` tests (after line 239), before the `private` section. Move the `private` keyword and helpers below the new tests.

```ruby
# --- bulk_import ---

test 'bulk_import creates entries from YAML hash' do
  entries = {
    'Special Flour' => { 'aisle' => 'Baking', 'sources' => [{ 'type' => 'import' }] },
    'Fancy Salt' => { 'aisle' => 'Pantry' }
  }

  result = CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: entries)

  assert_equal 2, result.persisted_count
  assert_empty result.errors
  assert_equal 'Baking', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Special Flour').aisle
  assert_equal 'Pantry', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Fancy Salt').aisle
end

test 'bulk_import upserts existing entries' do
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Special Flour', aisle: 'Old Aisle')

  result = CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'Special Flour' => { 'aisle' => 'New Aisle' }
  })

  assert_equal 1, result.persisted_count
  assert_equal 1, IngredientCatalog.where(kitchen: @kitchen, ingredient_name: 'Special Flour').size
  assert_equal 'New Aisle', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Special Flour').aisle
end

test 'bulk_import syncs new aisles to kitchen aisle_order in one pass' do
  @kitchen.update!(aisle_order: 'Produce')

  CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'flour' => { 'aisle' => 'Baking' },
    'milk' => { 'aisle' => 'Dairy' }
  })

  order = @kitchen.reload.parsed_aisle_order
  assert_includes order, 'Baking'
  assert_includes order, 'Dairy'
  assert_includes order, 'Produce'
end

test 'bulk_import skips omit aisles during sync' do
  CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'vanilla' => { 'aisle' => 'omit' }
  })

  assert_not_includes @kitchen.reload.parsed_aisle_order.to_a, 'omit'
end

test 'bulk_import does not duplicate existing aisles' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'flour' => { 'aisle' => 'Baking' }
  })

  assert_equal 1, @kitchen.reload.parsed_aisle_order.count('Baking')
end

test 'bulk_import recalculates nutrition for existing affected recipes' do
  create_catalog_entry('flour', basis_grams: 100, calories: 364, aisle: 'Baking')

  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
    # Bread


    ## Mix (combine)

    - flour, 200 g

    Stir together.
  MD

  recipe = @kitchen.recipes.find_by!(slug: 'bread')
  recipe.update_column(:nutrition_data, nil) # rubocop:disable Rails/SkipsModelValidations

  CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'flour' => { 'aisle' => 'Baking', 'nutrients' => { 'basis_grams' => 30, 'calories' => 110 } }
  })

  assert_not_nil recipe.reload.nutrition_data
end

test 'bulk_import returns errors for invalid entries without aborting' do
  result = CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
    'good' => { 'aisle' => 'Pantry' },
    'bad' => { 'nutrients' => { 'basis_grams' => 0, 'calories' => 100 } }
  })

  assert_equal 1, result.persisted_count
  assert_equal 1, result.errors.size
  assert_match(/bad/, result.errors.first)
end

test 'bulk_import is a no-op for empty hash' do
  result = CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {})

  assert_equal 0, result.persisted_count
  assert_empty result.errors
end

test 'bulk_import does not broadcast' do
  assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
    CatalogWriteService.bulk_import(kitchen: @kitchen, entries_hash: {
      'flour' => { 'aisle' => 'Baking' }
    })
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: Failures — `NoMethodError: undefined method 'bulk_import' for CatalogWriteService`

**Step 3: Commit**

```bash
git add test/services/catalog_write_service_test.rb
git commit -m "test: add failing tests for CatalogWriteService.bulk_import"
```

---

### Task 2: Implement `CatalogWriteService.bulk_import`

**Files:**
- Modify: `app/services/catalog_write_service.rb:13-71`

**Step 1: Add BulkResult and bulk_import class method**

Add `BulkResult` below the existing `Result` (line 14), and add the `bulk_import` class method after `destroy` (line 24):

```ruby
BulkResult = Data.define(:persisted_count, :errors)

def self.bulk_import(kitchen:, entries_hash:)
  new(kitchen:, ingredient_name: nil).bulk_import(entries_hash:)
end
```

**Step 2: Add the bulk_import instance method**

Add after the `destroy` method (after line 49), before the `private` keyword:

```ruby
def bulk_import(entries_hash:)
  return BulkResult.new(persisted_count: 0, errors: []) if entries_hash.blank?

  persisted_count, errors = save_all_entries(entries_hash)
  sync_all_aisles(entries_hash)
  recalculate_all_affected_recipes(entries_hash)
  BulkResult.new(persisted_count:, errors:)
end
```

**Step 3: Add private helper methods**

Add these in the private section, after the existing `recalculate_affected_recipes` method:

```ruby
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

def sync_all_aisles(entries_hash)
  new_aisles = entries_hash.values
                           .filter_map { |e| e['aisle'] }
                           .reject { |a| a == 'omit' }
                           .uniq

  return if new_aisles.empty?

  existing = kitchen.parsed_aisle_order.to_set(&:downcase)
  additions = new_aisles.reject { |a| existing.include?(a.downcase) }
  return if additions.empty?

  combined = [kitchen.aisle_order.to_s, *additions].reject(&:empty?).join("\n")
  kitchen.update!(aisle_order: combined)
end

def recalculate_all_affected_recipes(entries_hash)
  return if kitchen.recipes.none?

  resolver = IngredientCatalog.resolver_for(kitchen)
  raw_names = entries_hash.keys.flat_map { |name| resolver.all_keys_for(name) }.uniq
  kitchen.recipes
         .joins(steps: :ingredients)
         .where(ingredients: { name: raw_names })
         .distinct
         .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
end
```

**Step 4: Update the header comment**

Update the class header comment to document the new method. Add `bulk_import` to the description:

```ruby
# Orchestrates IngredientCatalog create/update/destroy with post-write side
# effects: syncing new aisles to the kitchen's aisle_order, recalculating
# nutrition for affected recipes, and broadcasting a page-refresh morph.
# Mirrors RecipeWriteService — controllers call class methods, never inline
# post-save logic. Also provides bulk_import for ImportService: batch save
# with single-pass aisle sync and nutrition recalc, no per-entry broadcast.
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass, including new bulk_import tests.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All green — no regressions.

**Step 7: Commit**

```bash
git add app/services/catalog_write_service.rb
git commit -m "feat: add CatalogWriteService.bulk_import for batch catalog imports"
```

---

### Task 3: Add aisle and category order to ExportService — tests

**Files:**
- Modify: `test/services/export_service_test.rb`

**Step 1: Write failing tests for new export files**

Add after the `filename` test (line 113), before the `private` keyword:

```ruby
test 'includes aisle-order.txt when kitchen has aisle_order' do
  @kitchen.update!(aisle_order: "Produce\nBaking\nDairy")
  zip_data = ExportService.call(kitchen: @kitchen)

  assert_includes zip_entry_names(zip_data), 'aisle-order.txt'
  assert_equal "Produce\nBaking\nDairy", zip_entry_content(zip_data, 'aisle-order.txt')
end

test 'omits aisle-order.txt when aisle_order is blank' do
  @kitchen.update!(aisle_order: nil)
  zip_data = ExportService.call(kitchen: @kitchen)

  assert_not_includes zip_entry_names(zip_data), 'aisle-order.txt'
end

test 'includes category-order.txt with categories in position order' do
  @category.update!(position: 1)
  @desserts.update!(position: 0)
  zip_data = ExportService.call(kitchen: @kitchen)

  assert_includes zip_entry_names(zip_data), 'category-order.txt'
  assert_equal "Desserts\nBread", zip_entry_content(zip_data, 'category-order.txt')
end

test 'omits category-order.txt when no categories exist' do
  @kitchen.recipes.destroy_all
  @kitchen.categories.destroy_all
  zip_data = ExportService.call(kitchen: @kitchen)

  assert_not_includes zip_entry_names(zip_data), 'category-order.txt'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/export_service_test.rb`
Expected: Failures — missing `aisle-order.txt` and `category-order.txt`

**Step 3: Commit**

```bash
git add test/services/export_service_test.rb
git commit -m "test: add failing tests for aisle and category order export"
```

---

### Task 4: Implement ExportService changes

**Files:**
- Modify: `app/services/export_service.rb:23-30`

**Step 1: Add new methods and update build_zip**

Replace `build_zip` (lines 23-30) with:

```ruby
def build_zip
  buffer = Zip::OutputStream.write_buffer do |zos|
    add_aisle_order(zos)
    add_category_order(zos)
    add_custom_ingredients(zos)
    add_quick_bites(zos)
    add_recipes(zos)
  end
  buffer.string
end
```

Add the two new private methods after `add_quick_bites` (after line 46):

```ruby
def add_aisle_order(zos)
  return if @kitchen.aisle_order.blank?

  zos.put_next_entry('aisle-order.txt')
  zos.write(@kitchen.aisle_order)
end

def add_category_order(zos)
  names = @kitchen.categories.ordered.pluck(:name)
  return if names.empty?

  zos.put_next_entry('category-order.txt')
  zos.write(names.join("\n"))
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/export_service_test.rb`
Expected: All pass.

**Step 3: Commit**

```bash
git add app/services/export_service.rb
git commit -m "feat: export aisle and category ordering in ZIP"
```

---

### Task 5: Rewrite ImportService — tests

**Files:**
- Modify: `test/services/import_service_test.rb`

**Step 1: Update existing ingredient tests and add new tests**

Update the `imports custom ingredients YAML from ZIP` test (line 162) to also verify aisle sync:

```ruby
test 'imports custom ingredients YAML from ZIP' do
  yaml_content = { 'Special Flour' => { 'aisle' => 'Pantry' } }.to_yaml
  zip = build_zip('custom-ingredients.yaml' => yaml_content)
  result = import_files(uploaded_file('export.zip', zip))

  assert_equal 1, result.ingredients

  entry = IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Special Flour')

  assert_equal 'Pantry', entry.aisle
  assert_includes @kitchen.reload.parsed_aisle_order, 'Pantry'
end
```

Add new tests after the `malformed YAML reports error` test (after line 192):

```ruby
# --- Aisle order ---

test 'imports aisle-order.txt from ZIP' do
  zip = build_zip('aisle-order.txt' => "Produce\nBaking\nDairy")
  import_files(uploaded_file('export.zip', zip))

  assert_equal "Produce\nBaking\nDairy", @kitchen.reload.aisle_order
end

test 'missing aisle-order.txt is gracefully skipped' do
  zip = build_zip('Bread/Focaccia.md' => simple_recipe('Focaccia'))
  import_files(uploaded_file('export.zip', zip))

  assert_nil @kitchen.reload.aisle_order
end

# --- Category order ---

test 'imports category-order.txt and sets positions after recipe import' do
  zip = build_zip(
    'category-order.txt' => "Desserts\nBread",
    'Bread/Focaccia.md' => simple_recipe('Focaccia'),
    'Desserts/Brownies.md' => simple_recipe('Brownies')
  )
  import_files(uploaded_file('export.zip', zip))

  bread = @kitchen.categories.find_by(name: 'Bread')
  desserts = @kitchen.categories.find_by(name: 'Desserts')

  assert bread.position > desserts.position,
         "Expected Desserts (#{desserts.position}) before Bread (#{bread.position})"
end

test 'missing category-order.txt is gracefully skipped' do
  zip = build_zip('Bread/Focaccia.md' => simple_recipe('Focaccia'))
  import_files(uploaded_file('export.zip', zip))

  assert @kitchen.categories.find_by(name: 'Bread')
end

# --- Import ordering: catalog before recipes ---

test 'recipes imported after catalog get correct nutrition on first pass' do
  create_catalog_entry('Flour', basis_grams: 100, calories: 364, aisle: 'Baking')

  yaml_content = { 'Flour' => { 'aisle' => 'Baking',
                                 'nutrients' => { 'basis_grams' => 30, 'calories' => 110 } } }.to_yaml

  zip = build_zip(
    'custom-ingredients.yaml' => yaml_content,
    'Bread/Focaccia.md' => simple_recipe_with_ingredient('Focaccia', 'Flour', '200 g')
  )
  import_files(uploaded_file('export.zip', zip))

  recipe = @kitchen.recipes.find_by!(title: 'Focaccia')

  assert_not_nil recipe.nutrition_data
  # Custom entry: 110 cal per 30g → 200g = 733.3 cal (not 364 * 2 = 728 from global)
  assert_in_delta 733.3, recipe.nutrition_data['totals']['calories'], 1.0
end

# --- Round-trip ---

test 'export then import into empty kitchen preserves all data' do
  @kitchen.update!(aisle_order: "Produce\nBaking")
  IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Test Flour', aisle: 'Baking')
  @kitchen.categories.ordered.each_with_index { |c, i| c.update!(position: i) }

  zip_data = ExportService.call(kitchen: @kitchen)

  # Clear the kitchen
  @kitchen.recipes.destroy_all
  @kitchen.categories.destroy_all
  IngredientCatalog.where(kitchen: @kitchen).delete_all
  @kitchen.update!(aisle_order: nil)

  import_files(uploaded_file('export.zip', zip_data))

  assert_equal "Produce\nBaking", @kitchen.reload.aisle_order
  assert IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Test Flour')
  assert @kitchen.recipes.any?
  assert @kitchen.categories.any?
end
```

Add a new helper method in the `private` section:

```ruby
def simple_recipe_with_ingredient(title, ingredient, quantity)
  <<~MD
    # #{title}


    ## Steps

    - #{ingredient}, #{quantity}

    Do the thing.
  MD
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: New tests fail (aisle order not imported, category order not imported, nutrition computed against global catalog).

**Step 3: Commit**

```bash
git add test/services/import_service_test.rb
git commit -m "test: add failing tests for import ordering, aisle/category order"
```

---

### Task 6: Rewrite ImportService

**Files:**
- Modify: `app/services/import_service.rb`

This is the largest change. Replace the stream-and-process approach with buffer-and-phase.

**Step 1: Rewrite ImportService**

Replace the entire file content. Keep the class structure, Result, and constants. Replace the internals:

```ruby
# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Buffers ZIP entries by type, then processes in phased order: settings files
# first (aisle/category order), then catalog entries via CatalogWriteService,
# then quick bites, then recipes. This ordering ensures catalog data is in
# place before recipes compute nutrition.
#
# - CatalogWriteService: batch catalog upsert with aisle sync + nutrition recalc
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
# - Kitchen: tenant container receiving imported data
# - ExportService: produces the ZIP format this service consumes
class ImportService
  Result = Data.define(:recipes, :ingredients, :quick_bites, :errors) do
    def self.empty
      new(recipes: 0, ingredients: 0, quick_bites: false, errors: [])
    end
  end

  RECIPE_EXTENSIONS = %w[.md .txt .text].freeze
  QUICK_BITES_PATTERN = /\Aquick[- ]?bites\z/i

  def self.call(kitchen:, files:)
    new(kitchen, files).import
  end

  def initialize(kitchen, files)
    @kitchen = kitchen
    @files = files
    @recipes_count = 0
    @ingredients_count = 0
    @quick_bites_imported = false
    @errors = []
  end

  def import
    zip_file = files.find { |f| File.extname(f.original_filename).casecmp('.zip').zero? }
    zip_file ? import_zip(zip_file) : files.each { |f| import_recipe_file(f, 'Miscellaneous') }
    kitchen.broadcast_update
    build_result
  end

  private

  attr_reader :kitchen, :files

  def build_result
    Result.new(recipes: @recipes_count, ingredients: @ingredients_count,
               quick_bites: @quick_bites_imported, errors: @errors)
  end

  # --- ZIP buffering ---

  def import_zip(zip_file)
    buffered = buffer_zip_entries(zip_file)
    process_buffered_entries(buffered)
  end

  def buffer_zip_entries(zip_file)
    entries = { aisle_order: nil, category_order: nil, catalog: nil,
                quick_bites: nil, recipes: [] }

    Zip::InputStream.open(StringIO.new(zip_file.read)) do |zis|
      while (entry = zis.get_next_entry)
        name = entry.name.force_encoding('UTF-8')
        content = zis.read.force_encoding('UTF-8')
        classify_entry(entries, name, content)
      end
    end

    entries
  end

  def classify_entry(entries, name, content)
    basename = File.basename(name, '.*')
    ext = File.extname(name)

    if name == 'aisle-order.txt'
      entries[:aisle_order] = content
    elsif name == 'category-order.txt'
      entries[:category_order] = content
    elsif quick_bites?(basename, ext)
      entries[:quick_bites] = content
    elsif custom_ingredients?(name)
      entries[:catalog] = content
    elsif recipe_file?(ext) && !directory_entry?(name)
      entries[:recipes] << { content:, category: category_from_path(name), filename: name }
    end
  end

  # --- Phased processing ---

  def process_buffered_entries(entries)
    import_aisle_order(entries[:aisle_order])
    category_names = parse_category_order(entries[:category_order])
    import_catalog(entries[:catalog])
    import_quick_bites(entries[:quick_bites])
    entries[:recipes].each { |r| import_recipe_content(r[:content], r[:category], r[:filename]) }
    apply_category_order(category_names)
  end

  def import_aisle_order(content)
    return if content.blank?

    kitchen.update!(aisle_order: content.strip)
  end

  def parse_category_order(content)
    return [] if content.blank?

    content.lines.map(&:strip).reject(&:empty?)
  end

  def import_catalog(content)
    return if content.blank?

    data = YAML.safe_load(content)
    result = CatalogWriteService.bulk_import(kitchen:, entries_hash: data)
    @ingredients_count = result.persisted_count
    @errors.concat(result.errors)
  rescue StandardError => error
    @errors << "custom-ingredients.yaml: #{error.message}"
  end

  def import_quick_bites(content)
    return if content.blank?

    kitchen.update!(quick_bites_content: content)
    @quick_bites_imported = true
  end

  def import_recipe_content(content, category_name, filename)
    RecipeWriteService.create(markdown: content, kitchen:, category_name:)
    @recipes_count += 1
  rescue StandardError => error
    @errors << "#{filename}: #{error.message}"
  end

  def apply_category_order(category_names)
    return if category_names.empty?

    category_names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name)).update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # --- Classification helpers ---

  def quick_bites?(basename, ext)
    RECIPE_EXTENSIONS.include?(ext.downcase) && basename.match?(QUICK_BITES_PATTERN)
  end

  def custom_ingredients?(name)
    File.basename(name).casecmp('custom-ingredients.yaml').zero?
  end

  def recipe_file?(ext)
    RECIPE_EXTENSIONS.include?(ext.downcase)
  end

  def directory_entry?(name)
    name.end_with?('/')
  end

  def category_from_path(name)
    parts = name.split('/')
    parts.size > 1 ? parts[-2] : 'Miscellaneous'
  end

  # --- Non-ZIP import (individual files) ---

  def import_recipe_file(file, category_name)
    import_recipe_content(file.read.force_encoding('UTF-8'), category_name, file.original_filename)
  end
end
```

**Step 2: Run import service tests**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: All pass.

**Step 3: Run catalog write service tests**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass.

**Step 4: Run full test suite**

Run: `rake test`
Expected: All green.

**Step 5: Run lint**

Run: `bundle exec rubocop app/services/import_service.rb app/services/catalog_write_service.rb app/services/export_service.rb`
Expected: No offenses. If line-length or method-length offenses appear, refactor to fix.

**Step 6: Commit**

```bash
git add app/services/import_service.rb
git commit -m "fix: rewrite ImportService with phased import ordering

Catalog entries are now imported before recipes so nutrition is computed
correctly on first pass. Aisle and category ordering are restored from
new settings files in the ZIP. Catalog imports route through
CatalogWriteService.bulk_import for proper aisle sync and nutrition
recalc."
```

---

### Task 7: Update html_safe allowlist if needed

**Files:**
- Possibly modify: `config/html_safe_allowlist.yml`

**Step 1: Check if line number shifts broke the allowlist**

Run: `rake lint:html_safe`
Expected: Pass. If it reports shifted line numbers, update the allowlist file to match the new line numbers.

**Step 2: Run full lint**

Run: `rake lint`
Expected: No offenses.

**Step 3: Commit (only if changes needed)**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```

---

### Task 8: Final verification

**Step 1: Run full test suite**

Run: `rake test`
Expected: All green.

**Step 2: Run full lint suite**

Run: `rake lint`
Expected: No offenses.

**Step 3: Manual smoke test (optional)**

Start the dev server with `bin/dev`. Export a kitchen's data, clear the kitchen, re-import. Verify:
- Aisle order is preserved on the grocery page
- Category order is preserved on the homepage
- Nutrition data is correct for recipes with custom catalog entries

# Import Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add an Import button to the homepage that accepts ZIP files or individual recipe files and upserts data into the kitchen.

**Architecture:** New `ImportService` handles ZIP extraction and file routing, delegating to existing `RecipeWriteService` and `CatalogWriteService` for writes. `ImportsController` is a thin POST adapter. A Stimulus controller manages the hidden file input and form submission.

**Tech Stack:** Rails controller, service object, rubyzip, Stimulus, multipart form upload.

**Design doc:** `docs/plans/2026-03-06-import-design.md`

---

### Task 0: Add route and controller shell

**Files:**
- Create: `app/controllers/imports_controller.rb`
- Modify: `config/routes.rb:38` (add import route next to export)
- Create: `test/controllers/imports_controller_test.rb`

**Step 1: Write the failing test**

```ruby
# test/controllers/imports_controller_test.rb
require 'test_helper'

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    setup_test_category
  end

  test 'create requires membership' do
    post import_path(kitchen_slug: kitchen_slug)

    assert_response :forbidden
  end

  test 'create with no files redirects with flash' do
    log_in
    post import_path(kitchen_slug: kitchen_slug)

    assert_redirected_to home_path
    assert_match(/no importable files/i, flash[:notice])
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/imports_controller_test.rb`
Expected: FAIL — undefined route / controller

**Step 3: Add route and controller**

Add to `config/routes.rb` inside the `scope` block, after the export line:

```ruby
post 'import', to: 'imports#create', as: :import
```

Create `app/controllers/imports_controller.rb`:

```ruby
# frozen_string_literal: true

# Accepts uploaded files (ZIP or individual recipe files) and delegates to
# ImportService for upsert into the current kitchen. Thin adapter — all logic
# lives in ImportService.
#
# - ImportService: handles ZIP extraction, file routing, and delegation
# - Authentication concern: require_membership gates access to members only
# - Kitchen: tenant container receiving imported data
class ImportsController < ApplicationController
  before_action :require_membership

  def create
    files = Array(params[:files])

    if files.empty?
      redirect_to home_path, notice: 'No importable files found.'
      return
    end

    result = ImportService.call(kitchen: current_kitchen, files:)
    redirect_to home_path, notice: import_summary(result)
  end

  private

  def import_summary(result)
    parts = []
    parts << "#{result.recipes} recipe#{'s' unless result.recipes == 1}" if result.recipes.positive?
    parts << "#{result.ingredients} ingredient#{'s' unless result.ingredients == 1}" if result.ingredients.positive?
    parts << 'Quick Bites' if result.quick_bites

    if parts.empty? && result.errors.empty?
      return 'No importable files found.'
    end

    summary = parts.any? ? "Imported #{parts.join(', ')}." : ''
    error_detail = result.errors.any? ? " Failed: #{result.errors.join(', ')}." : ''
    "#{summary}#{error_detail}".strip
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/controllers/imports_controller_test.rb`
Expected: FAIL — ImportService not yet defined (but route and membership tests should work conceptually). We'll stub it in step 5.

**Step 5: Create a minimal ImportService stub**

Create `app/services/import_service.rb`:

```ruby
# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Routes each file to the appropriate handler: RecipeWriteService for recipes,
# CatalogWriteService for ingredients, direct assignment for Quick Bites.
#
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
# - CatalogWriteService: ingredient catalog upsert by name
# - Kitchen: tenant container receiving imported data
# - ExportService: produces the ZIP format this service consumes
class ImportService
  Result = Data.define(:recipes, :ingredients, :quick_bites, :errors) do
    def self.empty
      new(recipes: 0, ingredients: 0, quick_bites: false, errors: [])
    end
  end

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
    Result.empty
  end

  private

  attr_reader :kitchen, :files
end
```

**Step 6: Run test to verify it passes**

Run: `ruby -Itest test/controllers/imports_controller_test.rb`
Expected: PASS

**Step 7: Run full test suite**

Run: `rake test`
Expected: PASS — no regressions

**Step 8: Run linter**

Run: `bundle exec rubocop app/controllers/imports_controller.rb app/services/import_service.rb`

**Step 9: Commit**

```bash
git add app/controllers/imports_controller.rb app/services/import_service.rb \
  config/routes.rb test/controllers/imports_controller_test.rb
git commit -m "feat: add import route, controller shell, and service stub"
```

---

### Task 1: ImportService — individual recipe file import

**Files:**
- Modify: `app/services/import_service.rb`
- Create: `test/services/import_service_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/import_service_test.rb
require 'test_helper'

class ImportServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Miscellaneous')
  end

  # --- Individual file import ---

  test 'imports a single .md file as a recipe in Miscellaneous' do
    file = uploaded_file('Bagels.md', "# Bagels\n\n## Boil\n\n- Flour, 3 cups\n\nBoil them.")
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.recipes
    assert_empty result.errors
    recipe = @kitchen.recipes.find_by!(slug: 'bagels')
    assert_equal 'Miscellaneous', recipe.category.name
  end

  test 'imports multiple individual files' do
    files = [
      uploaded_file('Bagels.md', "# Bagels\n\n## Boil\n\n- Flour, 3 cups\n\nBoil them."),
      uploaded_file('Soup.txt', "# Soup\n\n## Cook\n\n- Broth, 2 cups\n\nSimmer.")
    ]
    result = ImportService.call(kitchen: @kitchen, files:)

    assert_equal 2, result.recipes
  end

  test 'accepts .txt and .text extensions' do
    files = [
      uploaded_file('A.txt', "# Recipe A\n\n## Step\n\n- Salt, 1 tsp\n\nDo it."),
      uploaded_file('B.text', "# Recipe B\n\n## Step\n\n- Pepper, 1 tsp\n\nDo it.")
    ]
    result = ImportService.call(kitchen: @kitchen, files:)

    assert_equal 2, result.recipes
  end

  test 'overwrites existing recipe on slug conflict' do
    RecipeWriteService.create(
      markdown: "# Bagels\n\n## Old step\n\n- Water, 1 cup\n\nOld instructions.",
      kitchen: @kitchen, category_name: 'Miscellaneous'
    )

    file = uploaded_file('Bagels.md', "# Bagels\n\n## New step\n\n- Flour, 3 cups\n\nNew instructions.")
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.recipes
    recipe = @kitchen.recipes.find_by!(slug: 'bagels')
    assert_includes recipe.markdown_source, 'New instructions'
  end

  test 'collects parse errors without aborting' do
    files = [
      uploaded_file('Good.md', "# Good Recipe\n\n## Step\n\n- Salt, 1 tsp\n\nDo it."),
      uploaded_file('Bad.md', 'not a valid recipe at all')
    ]
    result = ImportService.call(kitchen: @kitchen, files:)

    assert_equal 1, result.recipes
    assert_equal 1, result.errors.size
    assert_match(/Bad\.md/, result.errors.first)
  end

  private

  def uploaded_file(filename, content, content_type: 'text/plain')
    Rack::Test::UploadedFile.new(
      StringIO.new(content), content_type, original_filename: filename
    )
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: FAIL — `import` returns empty result

**Step 3: Implement individual file import**

Update `app/services/import_service.rb`:

```ruby
# frozen_string_literal: true

# Processes uploaded files for import into a kitchen. Accepts ZIP archives
# (matching export format) or individual recipe files (.md, .txt, .text).
# Routes each file to the appropriate handler: RecipeWriteService for recipes,
# CatalogWriteService for ingredient catalog entries, direct assignment for
# Quick Bites.
#
# - RecipeWriteService: recipe upsert (create or overwrite by slug)
# - CatalogWriteService: ingredient catalog upsert by name
# - Kitchen: tenant container receiving imported data
# - ExportService: produces the ZIP format this service consumes
class ImportService
  RECIPE_EXTENSIONS = %w[.md .txt .text].freeze

  Result = Data.define(:recipes, :ingredients, :quick_bites, :errors) do
    def self.empty
      new(recipes: 0, ingredients: 0, quick_bites: false, errors: [])
    end
  end

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

    if zip_file
      import_zip(zip_file)
    else
      import_individual_files
    end

    kitchen.broadcast_update
    build_result
  end

  private

  attr_reader :kitchen, :files

  def import_individual_files
    files.each { |file| import_recipe_file(file.original_filename, file.read, category_name: 'Miscellaneous') }
  end

  def import_recipe_file(filename, content, category_name:)
    RecipeWriteService.create(markdown: content, kitchen:, category_name:)
    @recipes_count += 1
  rescue StandardError => e
    @errors << "#{filename}: #{e.message}"
  end

  def build_result
    Result.new(recipes: @recipes_count, ingredients: @ingredients_count,
               quick_bites: @quick_bites_imported, errors: @errors)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: PASS

**Step 5: Run linter**

Run: `bundle exec rubocop app/services/import_service.rb`

**Step 6: Commit**

```bash
git add app/services/import_service.rb test/services/import_service_test.rb
git commit -m "feat: ImportService handles individual recipe file imports"
```

---

### Task 2: ImportService — ZIP import with category folders

**Files:**
- Modify: `app/services/import_service.rb`
- Modify: `test/services/import_service_test.rb`

**Step 1: Write the failing tests**

Add to `test/services/import_service_test.rb`:

```ruby
  # --- ZIP import ---

  test 'imports recipes from ZIP with category folders' do
    zip_data = build_zip('Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.")
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.recipes
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    assert_equal 'Bread', recipe.category.name
  end

  test 'ZIP root-level recipes go to Miscellaneous' do
    zip_data = build_zip('Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.")
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.recipes
    recipe = @kitchen.recipes.find_by!(slug: 'focaccia')
    assert_equal 'Miscellaneous', recipe.category.name
  end

  test 'ZIP skips non-recipe files silently' do
    zip_data = build_zip(
      'Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.",
      '.DS_Store' => 'junk',
      '__MACOSX/foo' => 'junk',
      'photo.jpg' => 'binary'
    )
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.recipes
    assert_empty result.errors
  end

  test 'ZIP prefers first zip file when multiple files include a zip' do
    zip_data = build_zip('Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.")
    files = [
      uploaded_file('export.zip', zip_data, content_type: 'application/zip'),
      uploaded_file('Extra.md', "# Extra\n\n## Step\n\n- Salt, 1 tsp\n\nDo it.")
    ]
    result = ImportService.call(kitchen: @kitchen, files:)

    assert_equal 1, result.recipes
    assert @kitchen.recipes.find_by(slug: 'focaccia')
    assert_not @kitchen.recipes.find_by(slug: 'extra')
  end
```

Add to the private section:

```ruby
  def build_zip(entries = {})
    buffer = Zip::OutputStream.write_buffer do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    buffer.string
  end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: FAIL — ZIP handling not implemented

**Step 3: Implement ZIP import**

Add these methods to `ImportService`:

```ruby
  def import_zip(zip_file)
    Zip::InputStream.open(zip_file) do |zis|
      while (entry = zis.get_next_entry)
        next if entry.directory?

        process_zip_entry(entry.name, zis.read)
      end
    end
  end

  def process_zip_entry(entry_name, content)
    basename = File.basename(entry_name)
    ext = File.extname(basename).downcase

    if quick_bites_filename?(basename)
      import_quick_bites(content)
    elsif basename.casecmp('custom-ingredients.yaml').zero?
      import_ingredients_yaml(content)
    elsif RECIPE_EXTENSIONS.include?(ext)
      category_name = category_from_zip_path(entry_name)
      import_recipe_file(basename, content, category_name:)
    end
  end

  def category_from_zip_path(entry_name)
    parts = entry_name.split('/')
    parts.size > 1 ? parts[-2] : 'Miscellaneous'
  end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/import_service.rb test/services/import_service_test.rb
git commit -m "feat: ImportService handles ZIP import with category folders"
```

---

### Task 3: ImportService — Quick Bites and ingredient catalog import

**Files:**
- Modify: `app/services/import_service.rb`
- Modify: `test/services/import_service_test.rb`

**Step 1: Write the failing tests**

Add to `test/services/import_service_test.rb`:

```ruby
  # --- Quick Bites ---

  test 'imports quick-bites.txt from ZIP' do
    zip_data = build_zip('quick-bites.txt' => "Chips: tortilla chips\nSalsa: salsa")
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert result.quick_bites
    assert_equal "Chips: tortilla chips\nSalsa: salsa", @kitchen.reload.quick_bites_content
  end

  test 'accepts Quick Bites filename variants' do
    %w[quick-bites.txt quickbites.md Quick-Bites.text QUICKBITES.TXT quick\ bites.md].each do |name|
      @kitchen.update!(quick_bites_content: nil)
      zip_data = build_zip(name => 'Test content')
      file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
      result = ImportService.call(kitchen: @kitchen, files: [file])

      assert result.quick_bites, "Expected '#{name}' to be recognized as Quick Bites"
      assert_equal 'Test content', @kitchen.reload.quick_bites_content
    end
  end

  # --- Custom ingredients ---

  test 'imports custom-ingredients.yaml from ZIP' do
    yaml = {
      'Special Flour' => {
        'aisle' => 'Pantry',
        'nutrients' => { 'basis_grams' => 100.0, 'calories' => 350.0 }
      }
    }.to_yaml
    zip_data = build_zip('custom-ingredients.yaml' => yaml)
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.ingredients
    entry = IngredientCatalog.find_by!(kitchen: @kitchen, ingredient_name: 'Special Flour')
    assert_equal 'Pantry', entry.aisle
    assert_in_delta 350.0, entry.calories
  end

  test 'upserts existing ingredient catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Special Flour', aisle: 'Old Aisle')

    yaml = { 'Special Flour' => { 'aisle' => 'New Aisle' } }.to_yaml
    zip_data = build_zip('custom-ingredients.yaml' => yaml)
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 1, result.ingredients
    assert_equal 'New Aisle', IngredientCatalog.find_by!(kitchen: @kitchen, ingredient_name: 'Special Flour').aisle
  end

  test 'reports malformed YAML as error' do
    zip_data = build_zip('custom-ingredients.yaml' => "not: [valid: yaml: {{")
    file = uploaded_file('export.zip', zip_data, content_type: 'application/zip')
    result = ImportService.call(kitchen: @kitchen, files: [file])

    assert_equal 0, result.ingredients
    assert result.errors.any? { |e| e.include?('custom-ingredients.yaml') }
  end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: FAIL — `import_quick_bites` and `import_ingredients_yaml` not defined

**Step 3: Implement Quick Bites and ingredient import**

Add to `ImportService`:

```ruby
  QUICK_BITES_BASENAMES = /\Aquick[- ]?bites\z/i

  def quick_bites_filename?(basename)
    name_without_ext = File.basename(basename, File.extname(basename))
    RECIPE_EXTENSIONS.include?(File.extname(basename).downcase) &&
      name_without_ext.match?(QUICK_BITES_BASENAMES)
  end

  def import_quick_bites(content)
    kitchen.update!(quick_bites_content: content)
    @quick_bites_imported = true
  end

  def import_ingredients_yaml(content)
    data = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
    return if data.blank?

    data.each do |name, entry|
      attrs = IngredientCatalog.attrs_from_yaml(entry)
      catalog = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name: name)
      catalog.assign_attributes(attrs)
      catalog.save!
      @ingredients_count += 1
    end
  rescue StandardError => e
    @errors << "custom-ingredients.yaml: #{e.message}"
  end
```

Also update `quick_bites_filename?` to also accept `.txt`:

The `RECIPE_EXTENSIONS` constant already covers `.txt`, `.md`, `.text` — but Quick Bites also uses `.txt`. Update the check to accept all three extensions. Actually, we need to include `.txt` in the check too. Let's refactor:

```ruby
  QUICK_BITES_EXTENSIONS = %w[.txt .md .text].freeze

  def quick_bites_filename?(basename)
    ext = File.extname(basename).downcase
    name_without_ext = File.basename(basename, ext)
    QUICK_BITES_EXTENSIONS.include?(ext) && name_without_ext.match?(QUICK_BITES_BASENAMES)
  end
```

Since `QUICK_BITES_EXTENSIONS` is the same as `RECIPE_EXTENSIONS`, just use `RECIPE_EXTENSIONS` and drop the extra constant.

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: PASS

**Step 5: Run full test suite and linter**

Run: `rake test && bundle exec rubocop app/services/import_service.rb`

**Step 6: Commit**

```bash
git add app/services/import_service.rb test/services/import_service_test.rb
git commit -m "feat: ImportService handles Quick Bites and ingredient catalog from ZIP"
```

---

### Task 4: Stimulus controller and view

**Files:**
- Create: `app/javascript/controllers/import_controller.js`
- Modify: `app/views/homepage/show.html.erb:24-28`

**Step 1: Create the Stimulus controller**

```javascript
// app/javascript/controllers/import_controller.js
import { Controller } from "@hotwired/stimulus"

/**
 * Manages file selection and form submission for kitchen data import.
 * Programmatically opens a hidden file input when the Import button is
 * clicked, then submits the enclosing form when files are selected.
 *
 * - ImportsController: receives the multipart POST
 */
export default class extends Controller {
  static targets = ["fileInput"]

  choose() {
    this.fileInputTarget.click()
  }

  submit() {
    if (this.fileInputTarget.files.length > 0) {
      this.element.requestSubmit()
    }
  }
}
```

**Step 2: Update the homepage view**

Replace the `#export-actions` div (lines 24-28 of `app/views/homepage/show.html.erb`) with:

```erb
  <div id="export-actions">
    <div data-controller="export" data-export-url-value="<%= export_path %>">
      <button type="button" class="btn" data-action="export#download">Export All Data</button>
    </div>
    <%= form_with url: import_path, method: :post, data: { controller: 'import' } do |f| %>
      <%= f.file_field :files, multiple: true, accept: '.zip,.md,.txt,.text',
          data: { import_target: 'fileInput', action: 'change->import#submit' },
          hidden: true, name: 'files[]' %>
      <button type="button" class="btn" data-action="import#choose">Import</button>
    <% end %>
  </div>
```

**Step 3: Verify Stimulus controller auto-registers**

Stimulus controllers under `app/javascript/controllers/` are auto-registered via `pin_all_from` in `config/importmap.rb`. No manual pin needed.

**Step 4: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 5: Run linter**

Run: `bundle exec rubocop`

**Step 6: Commit**

```bash
git add app/javascript/controllers/import_controller.js app/views/homepage/show.html.erb
git commit -m "feat: add Import button with Stimulus controller and hidden file input"
```

---

### Task 5: Controller integration tests

**Files:**
- Modify: `test/controllers/imports_controller_test.rb`

**Step 1: Add integration tests for the full flow**

```ruby
  test 'imports a recipe file via POST' do
    log_in
    file = Rack::Test::UploadedFile.new(
      StringIO.new("# Bagels\n\n## Boil\n\n- Flour, 3 cups\n\nBoil them."),
      'text/plain', original_filename: 'Bagels.md'
    )
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_redirected_to home_path
    follow_redirect!
    assert_match(/1 recipe/, response.body)
    assert @kitchen.recipes.find_by(slug: 'bagels')
  end

  test 'imports a ZIP file via POST' do
    log_in
    zip_data = build_zip('Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.")
    file = Rack::Test::UploadedFile.new(
      StringIO.new(zip_data), 'application/zip', original_filename: 'export.zip'
    )
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_redirected_to home_path
    assert @kitchen.recipes.find_by(slug: 'focaccia')
  end

  test 'flash summarizes multiple data types' do
    log_in
    yaml = { 'Test Ingredient' => { 'aisle' => 'Pantry' } }.to_yaml
    zip_data = build_zip(
      'Bread/Focaccia.md' => "# Focaccia\n\n## Mix\n\n- Flour, 3 cups\n\nMix.",
      'quick-bites.txt' => "Chips\nSalsa",
      'custom-ingredients.yaml' => yaml
    )
    file = Rack::Test::UploadedFile.new(
      StringIO.new(zip_data), 'application/zip', original_filename: 'export.zip'
    )
    post import_path(kitchen_slug: kitchen_slug), params: { files: [file] }

    assert_redirected_to home_path
    assert_match(/1 recipe/, flash[:notice])
    assert_match(/1 ingredient/, flash[:notice])
    assert_match(/Quick Bites/, flash[:notice])
  end

  private

  def build_zip(entries = {})
    buffer = Zip::OutputStream.write_buffer do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    buffer.string
  end
```

**Step 2: Run tests**

Run: `ruby -Itest test/controllers/imports_controller_test.rb`
Expected: PASS

**Step 3: Run full test suite and linter**

Run: `rake`
Expected: PASS

**Step 4: Commit**

```bash
git add test/controllers/imports_controller_test.rb
git commit -m "test: add import controller integration tests"
```

---

### Task 6: Manual smoke test and broadcast verification

**Step 1: Start the dev server**

Run: `bin/dev`

**Step 2: Manual test checklist**

1. Log in and verify the Import button appears next to Export All Data
2. Click Import — file picker should open
3. Select a single `.md` file — should redirect with flash "Imported 1 recipe."
4. Click Export All Data to get a ZIP
5. Click Import and select the exported ZIP — should redirect with flash showing recipes, ingredients, Quick Bites as applicable
6. Verify the imported recipes appear on the homepage
7. Verify the flash message disappears on next navigation

**Step 3: Verify broadcast**

Open two browser tabs. Import in one tab. The other tab should auto-refresh via Turbo morph (Kitchen#broadcast_update is called once at the end of import).

**Step 4: Update html_safe allowlist if needed**

Run: `rake lint:html_safe`

If the view changes shifted line numbers for any existing `.html_safe` calls, update `config/html_safe_allowlist.yml`.

**Step 5: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: post-smoke-test cleanup"
```

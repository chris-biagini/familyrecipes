# Data Export Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Members can download a ZIP of all kitchen data (recipes as Markdown, Quick Bites as text, custom ingredients as YAML).

**Architecture:** New `ExportService` builds a ZIP in-memory via rubyzip. `ExportsController#show` is a members-only GET endpoint that streams the ZIP. A `confirm()` button on the homepage triggers the download.

**Tech Stack:** rubyzip gem, Rails controller with `send_data`, vanilla JS `confirm()` + `window.location`.

---

### Task 1: Add rubyzip gem

**Files:**
- Modify: `Gemfile`

**Step 1: Add gem**

Add to `Gemfile` (after the `redcarpet` line):

```ruby
gem 'rubyzip', require: 'zip'
```

**Step 2: Install**

Run: `bundle install`

**Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add rubyzip gem for data export"
```

---

### Task 2: ExportService with tests (TDD)

**Files:**
- Create: `app/services/export_service.rb`
- Create: `test/services/export_service_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/export_service_test.rb
# frozen_string_literal: true

require 'test_helper'

class ExportServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0)
    @mains = Category.create!(name: 'Mains', slug: 'mains', position: 1)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread
      Serves: 4

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pizza

      Category: Mains
      Serves: 2

      ## Assemble (build)

      - Cheese, 1 cup

      Layer it up.
    MD
  end

  test 'generates a ZIP with recipes organized by category' do
    zip_data = ExportService.call(kitchen: @kitchen)
    entries = zip_entry_names(zip_data)

    assert_includes entries, 'Bread/Focaccia.md'
    assert_includes entries, 'Mains/Pizza.md'
  end

  test 'recipe files contain markdown_source' do
    zip_data = ExportService.call(kitchen: @kitchen)
    content = zip_entry_content(zip_data, 'Bread/Focaccia.md')

    assert_includes content, '# Focaccia'
    assert_includes content, '- Flour, 3 cups'
  end

  test 'includes quick bites when present' do
    @kitchen.update!(quick_bites_content: "## Quick Bites: Snacks\n\n- Chips\n- Salsa")
    zip_data = ExportService.call(kitchen: @kitchen)
    content = zip_entry_content(zip_data, 'quick-bites.txt')

    assert_includes content, 'Chips'
  end

  test 'omits quick bites file when content is blank' do
    @kitchen.update!(quick_bites_content: nil)
    zip_data = ExportService.call(kitchen: @kitchen)
    entries = zip_entry_names(zip_data)

    assert_not_includes entries, 'quick-bites.txt'
  end

  test 'includes custom ingredients as YAML' do
    IngredientCatalog.create!(
      kitchen: @kitchen, ingredient_name: 'Special Flour',
      aisle: 'Pantry', basis_grams: 100, calories: 350
    )
    zip_data = ExportService.call(kitchen: @kitchen)
    content = zip_entry_content(zip_data, 'custom-ingredients.yaml')
    parsed = YAML.safe_load(content)

    assert_equal 'Pantry', parsed['Special Flour']['aisle']
    assert_equal 100, parsed['Special Flour']['nutrients']['basis_grams']
    assert_equal 350, parsed['Special Flour']['nutrients']['calories']
  end

  test 'omits custom ingredients file when none exist' do
    zip_data = ExportService.call(kitchen: @kitchen)
    entries = zip_entry_names(zip_data)

    assert_not_includes entries, 'custom-ingredients.yaml'
  end

  test 'filename uses kitchen slug and current date' do
    filename = ExportService.filename(kitchen: @kitchen)

    assert_equal "test-kitchen-#{Date.current.iso8601}.zip", filename
  end

  private

  def zip_entry_names(zip_data)
    entries = []
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        entries << entry.name
      end
    end
    entries
  end

  def zip_entry_content(zip_data, name)
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        return zis.read if entry.name == name
      end
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/export_service_test.rb`
Expected: NameError — `ExportService` not defined.

**Step 3: Implement ExportService**

```ruby
# app/services/export_service.rb
# frozen_string_literal: true

# Builds an in-memory ZIP archive of all kitchen data for user export.
# Includes recipes as Markdown (organized by category), Quick Bites as
# plain text, and kitchen-specific ingredient catalog entries as YAML.
#
# Collaborators:
# - ExportsController (sole caller)
# - Kitchen, Recipe, Category, IngredientCatalog (data sources)
class ExportService
  def self.call(kitchen:)
    new(kitchen).call
  end

  def self.filename(kitchen:)
    "#{kitchen.slug}-#{Date.current.iso8601}.zip"
  end

  def initialize(kitchen)
    @kitchen = kitchen
  end

  def call
    buffer = Zip::OutputStream.write_buffer do |zip|
      add_recipes(zip)
      add_quick_bites(zip)
      add_custom_ingredients(zip)
    end
    buffer.string
  end

  private

  def add_recipes(zip)
    @kitchen.recipes.includes(:category).find_each do |recipe|
      zip.put_next_entry("#{recipe.category.name}/#{recipe.title}.md")
      zip.write(recipe.markdown_source)
    end
  end

  def add_quick_bites(zip)
    return if @kitchen.quick_bites_content.blank?

    zip.put_next_entry('quick-bites.txt')
    zip.write(@kitchen.quick_bites_content)
  end

  def add_custom_ingredients(zip)
    entries = IngredientCatalog.for_kitchen(@kitchen).order(:ingredient_name)
    return if entries.none?

    zip.put_next_entry('custom-ingredients.yaml')
    zip.write(catalog_to_yaml(entries))
  end

  def catalog_to_yaml(entries)
    hash = entries.each_with_object({}) do |entry, acc|
      acc[entry.ingredient_name] = entry_to_hash(entry)
    end
    hash.to_yaml
  end

  def entry_to_hash(entry)
    hash = {}
    hash['aisle'] = entry.aisle if entry.aisle.present?
    hash['aliases'] = entry.aliases if entry.aliases.present?
    add_nutrients(hash, entry)
    add_density(hash, entry)
    add_portions(hash, entry)
    hash['sources'] = entry.sources if entry.sources.present?
    hash
  end

  def add_nutrients(hash, entry)
    return unless entry.basis_grams

    nutrients = { 'basis_grams' => entry.basis_grams }
    IngredientCatalog::NUTRIENT_COLUMNS.each do |col|
      value = entry.public_send(col)
      nutrients[col.to_s] = value if value
    end
    hash['nutrients'] = nutrients
  end

  def add_density(hash, entry)
    return unless entry.density_grams

    hash['density'] = {
      'grams' => entry.density_grams,
      'volume' => entry.density_volume,
      'unit' => entry.density_unit
    }
  end

  def add_portions(hash, entry)
    return if entry.portions.blank?

    hash['portions'] = entry.portions
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/export_service_test.rb`
Expected: All 7 tests pass.

**Step 5: Run linter**

Run: `bundle exec rubocop app/services/export_service.rb test/services/export_service_test.rb`
Expected: No offenses.

**Step 6: Commit**

```bash
git add app/services/export_service.rb test/services/export_service_test.rb
git commit -m "feat: add ExportService for kitchen data ZIP export"
```

---

### Task 3: ExportsController with tests (TDD)

**Files:**
- Create: `app/controllers/exports_controller.rb`
- Create: `test/controllers/exports_controller_test.rb`
- Modify: `config/routes.rb:21-38` (add route inside scope)

**Step 1: Write the failing tests**

```ruby
# test/controllers/exports_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread
      Serves: 4

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD
  end

  test 'requires membership' do
    get export_path(kitchen_slug: kitchen_slug)
    assert_response :forbidden
  end

  test 'downloads ZIP for members' do
    log_in
    get export_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_equal 'application/zip', response.content_type
    assert_match(/test-kitchen-.*\.zip/, response.headers['Content-Disposition'])
  end

  test 'ZIP contains recipe files' do
    log_in
    get export_path(kitchen_slug: kitchen_slug)

    entries = zip_entry_names(response.body)
    assert_includes entries, 'Bread/Focaccia.md'
  end

  private

  def zip_entry_names(zip_data)
    entries = []
    Zip::InputStream.open(StringIO.new(zip_data)) do |zis|
      while (entry = zis.get_next_entry)
        entries << entry.name
      end
    end
    entries
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/exports_controller_test.rb`
Expected: RoutingError — no route for `/export`.

**Step 3: Add route**

In `config/routes.rb`, inside the `scope '(/kitchens/:kitchen_slug)'` block, add after the groceries routes (around line 35):

```ruby
get 'export', to: 'exports#show', as: :export
```

**Step 4: Implement controller**

```ruby
# app/controllers/exports_controller.rb
# frozen_string_literal: true

# Serves a ZIP download of all kitchen data — recipes, Quick Bites, and
# custom ingredient catalog entries. Members only. Delegates ZIP assembly
# to ExportService and streams the result via send_data.
#
# Collaborators:
# - ExportService (ZIP generation)
# - ApplicationController (authentication, tenant scoping)
class ExportsController < ApplicationController
  before_action :require_membership

  def show
    zip_data = ExportService.call(kitchen: current_kitchen)
    filename = ExportService.filename(kitchen: current_kitchen)

    send_data zip_data, filename: filename, type: 'application/zip', disposition: :attachment
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/exports_controller_test.rb`
Expected: All 3 tests pass.

**Step 6: Run linter**

Run: `bundle exec rubocop app/controllers/exports_controller.rb test/controllers/exports_controller_test.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add app/controllers/exports_controller.rb test/controllers/exports_controller_test.rb config/routes.rb
git commit -m "feat: add ExportsController with members-only ZIP download"
```

---

### Task 4: Homepage UI — export button

**Files:**
- Modify: `app/views/homepage/show.html.erb:15-26`

**Step 1: Add export button between hr and footer**

The current homepage view has the recipe listings followed by a `<footer>`. Insert the export button section between them, wrapped in a `current_member?` check. The structure:

```erb
<article class="homepage">
  <header>
    <h1><%= @site_config.homepage_heading %></h1>
    <p><%= @site_config.homepage_subtitle %></p>
  </header>

  <%= render 'homepage/recipe_listings', categories: @categories %>

  <% if current_member? %>
  <div id="export-actions">
    <button type="button" class="btn"
            onclick="if (confirm('Export all recipes, Quick Bites, and custom ingredients?')) window.location = '<%= export_path %>'">
      Export All Data
    </button>
  </div>
  <% end %>

  <footer>
    <p>For more information, visit <a href="<%= @site_config.github_url %>">our project page on GitHub</a>.</p>
  </footer>
</article>
```

Note: The `<hr>` is generated via CSS pseudo-element on the `#export-actions` div (or a `border-top`), matching how `#menu-actions` uses `border-top` in `menu.css`.

**Step 2: Verify in browser**

Run: `bin/dev`
Visit the homepage as a logged-in member. Verify:
- Export button appears below the last category
- Clicking it shows a confirm dialog
- Clicking OK downloads a ZIP
- Button is hidden for non-members

**Step 3: Commit**

```bash
git add app/views/homepage/show.html.erb
git commit -m "feat: add export button to homepage"
```

---

### Task 5: CSS styling for export actions

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add export-actions styles**

Add after the existing `.homepage` styles (around line 548) in `style.css`:

```css
#export-actions {
  margin-top: 1.5rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--separator-color);
  text-align: center;
}
```

And in the existing `@media print` block, add:

```css
#export-actions {
  display: none;
}
```

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 3: Run linter**

Run: `rake lint`
Expected: No offenses.

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "style: add export-actions styling with print-media hiding"
```

# Quick Bites & Grocery Aisles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Store Quick Bites and grocery aisle data in the database with web-based editing, and restore the Quick Bites section on the groceries page.

**Architecture:** A single `site_documents` table stores two text blobs (Quick Bites markdown and grocery aisles markdown). The groceries controller loads from the DB, parses at render time (same "parsed bridge" pattern as recipes), and exposes PATCH endpoints for saving edits. The existing `recipe-editor.js` is generalized to a data-driven dialog handler so all editor dialogs share one codebase.

**Tech Stack:** Rails 8, PostgreSQL, Minitest, vanilla JS, native `<dialog>` element.

**Design doc:** `docs/plans/2026-02-22-quick-bites-and-aisles-design.md`

---

### Task 1: Migration + Model

**Files:**
- Create: `db/migrate/YYYYMMDD_create_site_documents.rb`
- Create: `app/models/site_document.rb`
- Create: `test/models/site_document_test.rb`

**Step 1: Write the failing test**

```ruby
# test/models/site_document_test.rb
# frozen_string_literal: true

require 'test_helper'

class SiteDocumentTest < ActiveSupport::TestCase
  test 'requires name' do
    doc = SiteDocument.new(content: 'hello')

    assert_not doc.valid?
    assert_includes doc.errors[:name], "can't be blank"
  end

  test 'requires content' do
    doc = SiteDocument.new(name: 'test')

    assert_not doc.valid?
    assert_includes doc.errors[:content], "can't be blank"
  end

  test 'enforces unique name' do
    SiteDocument.create!(name: 'quick_bites', content: 'hello')
    dup = SiteDocument.new(name: 'quick_bites', content: 'world')

    assert_not dup.valid?
    assert_includes dup.errors[:name], 'has already been taken'
  end
end
```

**Step 2: Run test to verify it fails**

Run: `rake test TEST=test/models/site_document_test.rb`
Expected: FAIL — `SiteDocument` not defined.

**Step 3: Generate migration and create model**

Run: `rails generate migration CreateSiteDocuments name:string:uniq content:text`

Then edit the migration to add `null: false` constraints:

```ruby
class CreateSiteDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :site_documents do |t|
      t.string :name, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :site_documents, :name, unique: true
  end
end
```

Create the model:

```ruby
# app/models/site_document.rb
# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :content, presence: true
end
```

**Step 4: Run migration and tests**

Run: `rails db:migrate && rake test TEST=test/models/site_document_test.rb`
Expected: 3 tests PASS.

**Step 5: Commit**

```
feat: add site_documents table and model
```

---

### Task 2: Grocery aisles markdown parser

**Files:**
- Modify: `lib/familyrecipes.rb`
- Modify: `test/familyrecipes_test.rb`

**Step 1: Write the failing tests**

Add to `test/familyrecipes_test.rb`:

```ruby
def test_parse_grocery_aisles_markdown_basic
  content = <<~MD
    ## Produce
    - Apples
    - Bananas

    ## Baking
    - Flour
  MD

  result = FamilyRecipes.parse_grocery_aisles_markdown(content)

  assert_equal %w[Produce Baking], result.keys
  assert_equal 'Apples', result['Produce'].first[:name]
  assert_equal 'Bananas', result['Produce'].last[:name]
  assert_equal 'Flour', result['Baking'].first[:name]
end

def test_parse_grocery_aisles_markdown_omit_from_list
  content = <<~MD
    ## Produce
    - Garlic

    ## Omit From List
    - Water
    - Sourdough starter
  MD

  result = FamilyRecipes.parse_grocery_aisles_markdown(content)

  assert_equal %w[Produce Omit From List], result.keys
  assert_equal 'Water', result['Omit From List'].first[:name]
end

def test_parse_grocery_aisles_markdown_ignores_non_list_lines
  content = <<~MD
    # Grocery Aisles

    Some description text.

    ## Produce
    - Apples

    Random text between aisles.

    ## Baking
    - Flour
  MD

  result = FamilyRecipes.parse_grocery_aisles_markdown(content)

  assert_equal %w[Produce Baking], result.keys
end

def test_build_alias_map_without_aliases
  grocery_aisles = {
    'Produce' => [{ name: 'Apples' }]
  }

  alias_map = FamilyRecipes.build_alias_map(grocery_aisles)

  assert_equal 'Apples', alias_map['apples']
  assert_equal 'Apples', alias_map['apple']
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/familyrecipes_test.rb`
Expected: FAIL — `parse_grocery_aisles_markdown` not defined.

**Step 3: Implement the parser**

Add to `lib/familyrecipes.rb`:

```ruby
# Parse grocery aisles from markdown format
# ## Aisle Name → aisle heading, - Item → ingredient in that aisle
def self.parse_grocery_aisles_markdown(content)
  aisles = {}
  current_aisle = nil

  content.each_line do |line|
    case line
    when /^##\s+(.*)/
      current_aisle = ::Regexp.last_match(1).strip
      aisles[current_aisle] = []
    when /^\s*-\s+(.*)/
      next unless current_aisle

      aisles[current_aisle] << { name: ::Regexp.last_match(1).strip }
    end
  end

  aisles
end
```

Also update `build_alias_map` to handle items without the `:aliases` key (the new format omits it). Replace the existing method:

```ruby
def self.build_alias_map(grocery_aisles)
  grocery_aisles.each_value.with_object({}) do |items, alias_map|
    items.each do |item|
      canonical = item[:name]
      aliases = item[:aliases] || []

      alias_map[canonical.downcase] = canonical

      aliases.each { |al| alias_map[al.downcase] = canonical }

      singular = Inflector.singular(canonical)
      alias_map[singular.downcase] = canonical unless singular.downcase == canonical.downcase

      aliases.each do |al|
        singular = Inflector.singular(al)
        alias_map[singular.downcase] = canonical unless singular.downcase == al.downcase
      end
    end
  end
end
```

(This is a minimal change — adds `|| []` fallback so items from the new parser that lack `:aliases` don't crash.)

Similarly update `build_known_ingredients`:

```ruby
def self.build_known_ingredients(grocery_aisles, alias_map)
  grocery_aisles.each_value.with_object(Set.new) do |items, known|
    items.each do |item|
      known << item[:name].downcase
      (item[:aliases] || []).each { |al| known << al.downcase }
    end
  end.merge(alias_map.keys)
end
```

**Step 4: Run all tests**

Run: `rake test TEST=test/familyrecipes_test.rb`
Expected: All tests PASS (old and new).

**Step 5: Commit**

```
feat: add markdown parser for grocery aisles
```

---

### Task 3: String-based Quick Bites parser

**Files:**
- Modify: `lib/familyrecipes.rb`
- Modify: `test/familyrecipes_test.rb` (or `test/quick_bite_test.rb`)

**Step 1: Write the failing test**

Add to `test/familyrecipes_test.rb`:

```ruby
def test_parse_quick_bites_content
  content = <<~MD
    # Quick Bites

    ## Snacks
      - Peanut Butter on Bread: Peanut butter, Bread
      - Goldfish

    ## Breakfast
      - Cereal with Milk: Cereal, Milk
  MD

  result = FamilyRecipes.parse_quick_bites_content(content)

  assert_equal 3, result.size
  assert_equal 'Peanut Butter on Bread', result[0].title
  assert_equal %w[Peanut\ butter Bread], result[0].ingredients
  assert_equal 'Quick Bites: Snacks', result[0].category
  assert_equal 'Goldfish', result[1].title
  assert_equal ['Goldfish'], result[1].ingredients
  assert_equal 'Quick Bites: Breakfast', result[2].category
end
```

**Step 2: Run test to verify it fails**

Run: `rake test TEST=test/familyrecipes_test.rb TESTOPTS="--name=test_parse_quick_bites_content"`
Expected: FAIL — method not defined.

**Step 3: Implement**

Add to `lib/familyrecipes.rb`:

```ruby
# Parse Quick Bites from a markdown string (instead of a file path)
def self.parse_quick_bites_content(content)
  quick_bites = []
  current_subcat = nil

  content.each_line do |line|
    case line
    when /^##\s+(.*)/
      current_subcat = ::Regexp.last_match(1).strip
    when /^\s*-\s+(.*)/
      category = [CONFIG[:quick_bites_category], current_subcat].compact.join(': ')
      quick_bites << QuickBite.new(text_source: ::Regexp.last_match(1).strip, category: category)
    end
  end

  quick_bites
end
```

**Step 4: Run tests**

Run: `rake test TEST=test/familyrecipes_test.rb`
Expected: PASS.

**Step 5: Commit**

```
feat: add string-based Quick Bites parser
```

---

### Task 4: Seed site_documents from files

**Files:**
- Modify: `db/seeds.rb`

The YAML-to-markdown conversion happens here. This is a one-time transformation baked into the seed.

**Step 1: Update seeds**

Add to the end of `db/seeds.rb`:

```ruby
# Seed Quick Bites document
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  SiteDocument.find_or_create_by!(name: 'quick_bites') do |doc|
    doc.content = File.read(quick_bites_path)
  end
  puts 'Quick Bites document loaded.'
end

# Seed Grocery Aisles document (convert YAML to markdown)
grocery_yaml_path = Rails.root.join('resources/grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  SiteDocument.find_or_create_by!(name: 'grocery_aisles') do |doc|
    raw = YAML.safe_load_file(grocery_yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    lines = []
    raw.each do |aisle, items|
      display_aisle = aisle.tr('_', ' ')
      lines << "## #{display_aisle}"
      items.each do |item|
        name = item.is_a?(Hash) ? item['name'] : item
        lines << "- #{name}"
      end
      lines << ''
    end
    doc.content = lines.join("\n")
  end
  puts 'Grocery Aisles document loaded.'
end
```

**Step 2: Run seed**

Run: `rails db:seed`
Expected: Prints "Quick Bites document loaded." and "Grocery Aisles document loaded." Verify with: `rails runner "puts SiteDocument.pluck(:name)"`

**Step 3: Verify re-run is idempotent**

Run: `rails db:seed` again.
Expected: No duplicate errors (find_or_create_by! skips existing).

**Step 4: Commit**

```
feat: seed site_documents from Quick Bites and grocery files
```

---

### Task 5: Update GroceriesController to load from DB

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Write failing tests**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
test 'renders Quick Bites section when document exists' do
  SiteDocument.create!(name: 'quick_bites', content: <<~MD)
    ## Snacks
      - Goldfish
      - Hummus with Pretzels: Hummus, Pretzels
  MD

  get groceries_path

  assert_response :success
  assert_select '.quick-bites h2', 'Quick Bites'
  assert_select '.quick-bites .subsection h3', 'Snacks'
  assert_select '.quick-bites input[type=checkbox][data-title="Goldfish"]'
  assert_select '.quick-bites input[type=checkbox][data-title="Hummus with Pretzels"]'
end

test 'renders gracefully without site documents' do
  SiteDocument.where(name: %w[quick_bites grocery_aisles]).destroy_all

  get groceries_path

  assert_response :success
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/controllers/groceries_controller_test.rb`
Expected: FAIL — no `.quick-bites` in current view.

**Step 3: Update the controller**

Replace `app/controllers/groceries_controller.rb`:

```ruby
# frozen_string_literal: true

class GroceriesController < ApplicationController
  def show
    @categories = Category.ordered.includes(recipes: { steps: :ingredients })
    @grocery_aisles = load_grocery_aisles
    @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
    @omit_set = build_omit_set
    @recipe_map = build_recipe_map
    @unit_plurals = collect_unit_plurals
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = quick_bites_document&.content || ''
    @grocery_aisles_content = grocery_aisles_document&.content || ''
  end

  private

  def load_grocery_aisles
    doc = grocery_aisles_document
    return fallback_grocery_aisles unless doc

    FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
  end

  def fallback_grocery_aisles
    yaml_path = Rails.root.join('resources/grocery-info.yaml')
    return {} unless File.exist?(yaml_path)

    FamilyRecipes.parse_grocery_info(yaml_path)
  end

  def build_omit_set
    omit_key = @grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    @grocery_aisles[omit_key].map { |item| item[:name].downcase }.to_set
  end

  def build_recipe_map
    Recipe.includes(:category).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end

  def collect_unit_plurals
    @recipe_map.values
               .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
               .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
               .uniq
               .to_h { |u| [u, FamilyRecipes::Inflector.unit_display(u, 2)] }
  end

  def load_quick_bites_by_subsection
    doc = quick_bites_document
    return {} unless doc

    FamilyRecipes.parse_quick_bites_content(doc.content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def quick_bites_document
    @quick_bites_document ||= SiteDocument.find_by(name: 'quick_bites')
  end

  def grocery_aisles_document
    @grocery_aisles_document ||= SiteDocument.find_by(name: 'grocery_aisles')
  end
end
```

**Step 4: Run tests**

Run: `rake test TEST=test/controllers/groceries_controller_test.rb`
Expected: The Quick Bites test still fails (view not updated yet). The "renders gracefully" test should pass. Existing tests may need updating since the aisle data now comes from the DB — see Task 5 notes below.

**Note:** The existing controller tests that check for aisle data (like `renders aisle sections from grocery data`) depend on the YAML file existing. After this change, they load from the DB instead. Two options: (a) create a `SiteDocument` in setup, or (b) rely on the YAML fallback. The fallback is intentional for exactly this transition period, so existing tests should still pass. Verify and adjust if needed.

**Step 5: Commit**

```
feat: load grocery aisles and quick bites from database
```

---

### Task 6: Update RecipesController to load from DB

**Files:**
- Modify: `app/controllers/recipes_controller.rb`

The `RecipesController` uses grocery data for nutrition calculations. It needs the same DB-first-with-fallback pattern.

**Step 1: Update the private methods**

Replace the `grocery_aisles` and `omit_set` methods in `app/controllers/recipes_controller.rb`:

```ruby
def grocery_aisles
  @grocery_aisles ||= load_grocery_aisles
end

def load_grocery_aisles
  doc = SiteDocument.find_by(name: 'grocery_aisles')
  return FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml')) unless doc

  FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
end

def omit_set
  @omit_set ||= begin
    omit_key = grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    grocery_aisles[omit_key].map { |item| item[:name].downcase }.to_set
  end
end
```

**Step 2: Run existing recipe controller tests**

Run: `rake test TEST=test/controllers/recipes_controller_test.rb`
Expected: All PASS — the fallback path covers the test environment.

**Step 3: Commit**

```
refactor: load grocery aisles from DB in RecipesController
```

---

### Task 7: Add update actions + routes

**Files:**
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `config/routes.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Write failing tests**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
test 'update_quick_bites saves valid content' do
  SiteDocument.create!(name: 'quick_bites', content: 'old content')

  patch groceries_quick_bites_path,
        params: { content: "## Snacks\n  - Goldfish" },
        as: :json

  assert_response :success

  doc = SiteDocument.find_by(name: 'quick_bites')

  assert_equal "## Snacks\n  - Goldfish", doc.content
end

test 'update_quick_bites creates document if missing' do
  patch groceries_quick_bites_path,
        params: { content: "## Snacks\n  - Goldfish" },
        as: :json

  assert_response :success
  assert SiteDocument.exists?(name: 'quick_bites')
end

test 'update_quick_bites rejects blank content' do
  SiteDocument.create!(name: 'quick_bites', content: 'old content')

  patch groceries_quick_bites_path,
        params: { content: '' },
        as: :json

  assert_response :unprocessable_entity
end

test 'update_grocery_aisles saves valid content' do
  SiteDocument.create!(name: 'grocery_aisles', content: 'old')

  new_content = "## Produce\n- Apples\n\n## Baking\n- Flour"
  patch groceries_grocery_aisles_path,
        params: { content: new_content },
        as: :json

  assert_response :success

  doc = SiteDocument.find_by(name: 'grocery_aisles')

  assert_equal new_content, doc.content
end

test 'update_grocery_aisles rejects content with no aisles' do
  SiteDocument.create!(name: 'grocery_aisles', content: 'old')

  patch groceries_grocery_aisles_path,
        params: { content: 'just some text with no headings' },
        as: :json

  assert_response :unprocessable_entity
  json = JSON.parse(response.body)

  assert_includes json['errors'], 'Must have at least one aisle (## Aisle Name).'
end
```

**Step 2: Run tests to verify they fail**

Run: `rake test TEST=test/controllers/groceries_controller_test.rb`
Expected: FAIL — routes and actions don't exist yet.

**Step 3: Add routes**

In `config/routes.rb`, add the PATCH routes:

```ruby
get 'groceries', to: 'groceries#show', as: :groceries
patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
```

**Step 4: Add controller actions**

Add to `GroceriesController`:

```ruby
def update_quick_bites
  content = params[:content].to_s
  return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_entity if content.blank?

  doc = SiteDocument.find_or_initialize_by(name: 'quick_bites')
  doc.content = content
  doc.save!

  render json: { status: 'ok' }
end

def update_grocery_aisles
  content = params[:content].to_s
  errors = validate_grocery_aisles(content)
  return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

  doc = SiteDocument.find_or_initialize_by(name: 'grocery_aisles')
  doc.content = content
  doc.save!

  render json: { status: 'ok' }
end
```

Add private validation:

```ruby
def validate_grocery_aisles(content)
  errors = []
  errors << 'Content cannot be blank.' if content.blank?
  return errors if errors.any?

  parsed = FamilyRecipes.parse_grocery_aisles_markdown(content)
  errors << 'Must have at least one aisle (## Aisle Name).' if parsed.empty?
  errors
end
```

**Step 5: Run tests**

Run: `rake test TEST=test/controllers/groceries_controller_test.rb`
Expected: PASS.

**Step 6: Commit**

```
feat: add PATCH endpoints for quick bites and grocery aisles
```

---

### Task 8: Generalize editor dialog CSS

**Files:**
- Modify: `app/assets/stylesheets/style.css`

The current CSS uses `#recipe-editor` (ID selector). We need a shared class so all editor dialogs get the same styles.

**Step 1: Update CSS**

Change the dialog styles in `style.css` (lines 602-686) from ID-based to class-based. Replace `#recipe-editor` with `.editor-dialog` everywhere, keeping `#recipe-editor` as a backward-compat alias (or update the recipe dialog markup in the same step). The cleanest approach: use the class `.editor-dialog` for all shared styles, remove the ID-based rules.

```css
/* Editor Dialog (shared) */

.editor-dialog {
  border: 1px solid var(--border-color);
  border-radius: 0.25rem;
  background: var(--content-background-color);
  padding: 0;
  width: min(90vw, 50rem);
  max-height: 90vh;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.15);
}

.editor-dialog[open] {
  display: flex;
  flex-direction: column;
}

.editor-dialog::backdrop {
  background: rgba(0, 0, 0, 0.5);
}
```

Keep `.editor-header`, `.editor-footer`, `.editor-footer-spacer` rules unchanged (they're already class-based). Update the `#editor-errors` and `#editor-textarea` rules to class selectors:

```css
.editor-errors {
  padding: 0.75rem 1.5rem;
  color: var(--danger-color);
  font-family: "Futura", sans-serif;
  font-size: 0.85rem;
  border-bottom: 1px solid var(--separator-color);
}

.editor-errors ul {
  margin: 0;
  padding: 0 0 0 1.25rem;
}

.editor-textarea {
  flex: 1;
  min-height: 60vh;
  padding: 1.5rem;
  border: none;
  font-family: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace;
  font-size: 0.85rem;
  line-height: 1.6;
  resize: none;
  outline: none;
  color: var(--text-color);
  background: var(--content-background-color);
}
```

**Step 2: Update the recipe editor dialog markup**

In `app/views/recipes/_editor_dialog.html.erb`, change the HTML to use classes instead of IDs:

- `id="recipe-editor"` → keep the ID but add `class="editor-dialog"`
- `id="editor-errors"` → add `class="editor-errors"` (keep ID for JS)
- `id="editor-textarea"` → add `class="editor-textarea"` (keep ID for JS)

**Step 3: Verify visually**

Run: `bin/dev` and check that the recipe editor dialog on the homepage still looks correct.

**Step 4: Commit**

```
refactor: generalize editor dialog CSS from ID to class selectors
```

---

### Task 9: Generalize recipe-editor.js for multiple dialogs

**Files:**
- Modify: `app/assets/javascripts/recipe-editor.js`

The current JS is hardcoded to `#recipe-editor`. Generalize it to handle any `dialog.editor-dialog` by reading data attributes. Each dialog manages its own state independently.

**Step 1: Refactor the JS**

The key changes:
- Find all `.editor-dialog` elements and wire each up independently.
- Each dialog declares its open button via `data-editor-open` (CSS selector for the button that opens it).
- Save URL comes from `data-editor-url` (already exists).
- Save HTTP method comes from `data-editor-method` (default: PATCH).
- On-success behavior comes from `data-editor-on-success`: `"redirect"` (default, for recipe editor) or `"reload"` (for grocery editors).
- Recipe-specific features (delete button, cross-reference toasts) remain gated on element presence — no changes needed.

```javascript
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.editor-dialog').forEach(initEditor);

  // Cross-reference toast (recipe-specific, fires once on page load)
  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});

function initEditor(dialog) {
  const openSelector = dialog.dataset.editorOpen;
  const openBtn = openSelector ? document.querySelector(openSelector) : null;
  const closeBtn = dialog.querySelector('.editor-close');
  const cancelBtn = dialog.querySelector('.editor-cancel');
  const saveBtn = dialog.querySelector('.editor-save');
  const deleteBtn = dialog.querySelector('.editor-delete');
  const textarea = dialog.querySelector('.editor-textarea');
  const errorsDiv = dialog.querySelector('.editor-errors');
  const actionUrl = dialog.dataset.editorUrl;
  const method = dialog.dataset.editorMethod || 'PATCH';
  const onSuccess = dialog.dataset.editorOnSuccess || 'redirect';
  const bodyKey = dialog.dataset.editorBodyKey || 'markdown_source';

  if (!openBtn || !textarea) return;

  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  let originalContent = textarea.value;
  let saving = false;

  function isModified() {
    return textarea.value !== originalContent;
  }

  function showErrors(errors) {
    const list = document.createElement('ul');
    errors.forEach(msg => {
      const li = document.createElement('li');
      li.textContent = msg;
      list.appendChild(li);
    });
    errorsDiv.replaceChildren(list);
    errorsDiv.hidden = false;
  }

  function clearErrors() {
    errorsDiv.replaceChildren();
    errorsDiv.hidden = true;
  }

  function closeDialog() {
    if (isModified() && !confirm('You have unsaved changes. Discard them?')) {
      return;
    }
    textarea.value = originalContent;
    clearErrors();
    dialog.close();
  }

  openBtn.addEventListener('click', () => {
    originalContent = textarea.value;
    clearErrors();
    dialog.showModal();
  });

  closeBtn.addEventListener('click', closeDialog);
  cancelBtn.addEventListener('click', closeDialog);

  dialog.addEventListener('cancel', (event) => {
    if (isModified()) {
      event.preventDefault();
      closeDialog();
    }
  });

  // Save
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors();

    try {
      const response = await fetch(actionUrl, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ [bodyKey]: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        saving = true;

        if (onSuccess === 'reload') {
          window.location.reload();
        } else {
          let redirectUrl = data.redirect_url;
          if (data.updated_references?.length > 0) {
            const param = encodeURIComponent(data.updated_references.join(', '));
            const separator = redirectUrl.includes('?') ? '&' : '?';
            redirectUrl += `${separator}refs_updated=${param}`;
          }
          window.location = redirectUrl;
        }
      } else if (response.status === 422) {
        const data = await response.json();
        showErrors(data.errors);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      } else {
        showErrors([`Server error (${response.status}). Please try again.`]);
        saveBtn.disabled = false;
        saveBtn.textContent = 'Save';
      }
    } catch {
      showErrors(['Network error. Please check your connection and try again.']);
      saveBtn.disabled = false;
      saveBtn.textContent = 'Save';
    }
  });

  // Delete (recipe editor only)
  if (deleteBtn) {
    deleteBtn.addEventListener('click', async () => {
      const title = deleteBtn.dataset.recipeTitle;
      const slug = deleteBtn.dataset.recipeSlug;
      const referencing = JSON.parse(deleteBtn.dataset.referencingRecipes || '[]');

      let message;
      if (referencing.length > 0) {
        message = `Delete "${title}"?\n\nCross-references in ${referencing.join(', ')} will be converted to plain text.\n\nThis cannot be undone.`;
      } else {
        message = `Delete "${title}"?\n\nThis cannot be undone.`;
      }

      if (!confirm(message)) return;

      deleteBtn.disabled = true;
      deleteBtn.textContent = 'Deleting\u2026';

      try {
        const response = await fetch(`/recipes/${slug}`, {
          method: 'DELETE',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken
          }
        });

        if (response.ok) {
          const data = await response.json();
          saving = true;
          window.location = data.redirect_url;
        } else {
          showErrors([`Failed to delete (${response.status}). Please try again.`]);
          deleteBtn.disabled = false;
          deleteBtn.textContent = 'Delete';
        }
      } catch {
        showErrors(['Network error. Please check your connection and try again.']);
        deleteBtn.disabled = false;
        deleteBtn.textContent = 'Delete';
      }
    });
  }

  // Warn on page navigation with unsaved changes
  window.addEventListener('beforeunload', (event) => {
    if (!saving && dialog.open && isModified()) {
      event.preventDefault();
    }
  });
}
```

**Step 2: Update recipe editor dialog markup**

In `app/views/recipes/_editor_dialog.html.erb`, update data attributes and classes:

```erb
<%# locals: (mode:, content:, action_url:, recipe: nil) %>
<dialog id="recipe-editor"
        class="editor-dialog"
        data-editor-open="<%= mode == :create ? '#new-recipe-button' : '#edit-button' %>"
        data-editor-url="<%= action_url %>"
        data-editor-method="<%= mode == :create ? 'POST' : 'PATCH' %>"
        data-editor-on-success="redirect"
        data-editor-body-key="markdown_source">
  <div class="editor-header">
    <h2><%= mode == :create ? 'New Recipe' : "Editing: #{recipe.title}" %></h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <textarea class="editor-textarea" spellcheck="false"><%= content %></textarea>
  <div class="editor-footer">
    <%- if mode == :edit -%>
    <button type="button" class="btn btn-danger editor-delete"
            data-recipe-title="<%= recipe.title %>"
            data-recipe-slug="<%= recipe.slug %>"
            data-referencing-recipes="<%= recipe.referencing_recipes.pluck(:title).to_json %>">Delete</button>
    <span class="editor-footer-spacer"></span>
    <%- end -%>
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>
```

**Step 3: Run existing tests**

Run: `rake test`
Expected: All PASS. The recipe editor behavior is unchanged.

**Step 4: Verify visually**

Run `bin/dev`, test creating and editing a recipe via the dialog. Confirm unsaved-changes warning, save, and delete all still work.

**Step 5: Commit**

```
refactor: generalize recipe-editor.js to handle multiple editor dialogs
```

---

### Task 10: Add editor dialogs and Quick Bites to groceries view

**Files:**
- Modify: `app/views/groceries/show.html.erb`

**Step 1: Add edit buttons to the nav area**

At the top of the file, add the `extra_nav` content block and include the editor JS:

```erb
<% content_for(:extra_nav) do %>
  <div>
    <button type="button" id="edit-quick-bites-button" class="btn">Edit Quick Bites</button>
    <button type="button" id="edit-aisles-button" class="btn">Edit Aisles</button>
  </div>
<% end %>

<% content_for(:scripts) do %>
  <script>
    window.UNIT_PLURALS = <%= @unit_plurals.to_json.html_safe %>;
  </script>
  <%= javascript_include_tag 'notify', defer: true %>
  <%= javascript_include_tag 'wake-lock', defer: true %>
  <%= javascript_include_tag 'qrcodegen', defer: true %>
  <%= javascript_include_tag 'groceries', defer: true %>
  <%= javascript_include_tag 'recipe-editor', defer: true %>
<% end %>
```

**Step 2: Add the Quick Bites section to the recipe selector**

After the categories loop (line 45, before the closing `</div>` of `#recipe-selector`), add:

```erb
  <%- if @quick_bites_by_subsection.any? -%>
  <div class="quick-bites">
    <h2>Quick Bites</h2>
    <div class="subsections">
      <%- @quick_bites_by_subsection.each do |subsection, items| -%>
      <div class="subsection">
        <h3><%= subsection %></h3>
        <ul>
        <%- items.each do |item| -%>
          <%- filtered_ingredients = item.ingredients_with_quantities.reject { |name, _| @omit_set.include?(name.downcase) } -%>
          <li>
            <input type="checkbox" id="<%= item.id %>-checkbox" data-title="<%= h item.title %>" data-ingredients="<%= h filtered_ingredients.to_json %>">
            <label for="<%= item.id %>-checkbox" title="Ingredients: <%= h filtered_ingredients.map(&:first).join(', ') %>"><%= item.title %></label>
          </li>
        <%- end -%>
        </ul>
      </div>
      <%- end -%>
    </div>
  </div>
  <%- end -%>
```

**Step 3: Add the two editor dialogs at the bottom**

After the grocery preview section, before the end of the file:

```erb
<dialog class="editor-dialog"
        data-editor-open="#edit-quick-bites-button"
        data-editor-url="<%= groceries_quick_bites_path %>"
        data-editor-method="PATCH"
        data-editor-on-success="reload"
        data-editor-body-key="content">
  <div class="editor-header">
    <h2>Edit Quick Bites</h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <textarea class="editor-textarea" spellcheck="false"><%= @quick_bites_content %></textarea>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>

<dialog class="editor-dialog"
        data-editor-open="#edit-aisles-button"
        data-editor-url="<%= groceries_grocery_aisles_path %>"
        data-editor-method="PATCH"
        data-editor-on-success="reload"
        data-editor-body-key="content">
  <div class="editor-header">
    <h2>Edit Aisles</h2>
    <button type="button" class="btn editor-close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" hidden></div>
  <textarea class="editor-textarea" spellcheck="false"><%= @grocery_aisles_content %></textarea>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary editor-save">Save</button>
  </div>
</dialog>
```

**Step 4: Update the Omit_From_List check in the view**

The aisle loop on line 78 currently checks `aisle == 'Omit_From_List'`. With the new markdown format, the key is `'Omit From List'`. Update:

```erb
<%- next if aisle.downcase.tr('_', ' ') == 'omit from list' -%>
```

**Step 5: Run tests**

Run: `rake test TEST=test/controllers/groceries_controller_test.rb`
Expected: All PASS including the Quick Bites tests from Task 5.

**Step 6: Commit**

```
feat: add Quick Bites section and editor dialogs to groceries page
```

---

### Task 11: Integration testing

**Files:**
- Modify: `test/integration/end_to_end_test.rb`

**Step 1: Write integration tests**

Add to the integration test file:

```ruby
test 'edit and save Quick Bites document' do
  SiteDocument.create!(name: 'quick_bites', content: "## Snacks\n  - Goldfish")

  patch groceries_quick_bites_path,
        params: { content: "## Snacks\n  - Goldfish\n  - Pretzels" },
        as: :json

  assert_response :success

  get groceries_path

  assert_response :success
  assert_select 'input[data-title="Pretzels"]'
end

test 'edit and save grocery aisles document' do
  SiteDocument.create!(name: 'grocery_aisles', content: "## Produce\n- Apples")

  patch groceries_grocery_aisles_path,
        params: { content: "## Produce\n- Apples\n- Bananas\n\n## Baking\n- Flour" },
        as: :json

  assert_response :success

  get groceries_path

  assert_response :success
  assert_select 'details.aisle summary', /Baking/
end
```

**Step 2: Run integration tests**

Run: `rake test TEST=test/integration/end_to_end_test.rb`
Expected: PASS.

**Step 3: Run full test suite**

Run: `rake test`
Expected: All PASS.

**Step 4: Run lint**

Run: `rake lint`
Expected: No offenses.

**Step 5: Commit**

```
test: add integration tests for Quick Bites and aisles editing
```

---

### Task 12: Visual verification and cleanup

**Step 1: Seed and start the server**

Run: `rails db:seed && bin/dev`

**Step 2: Verify the groceries page**

- Visit `http://localhost:3030/groceries`
- Confirm Quick Bites section appears below recipe categories with subsections
- Check a Quick Bites item and verify its ingredients appear in the shopping list
- Click "Edit Quick Bites" — dialog opens with current markdown content
- Edit, save, and confirm page reloads with changes
- Click "Edit Aisles" — dialog opens with markdown content
- Edit, save, and confirm aisle list updates
- Test unsaved-changes warning (edit text, click Cancel, confirm dialog)
- Test the recipe editor still works (go to homepage, create a recipe)

**Step 3: Check responsive and print**

- Resize browser to mobile width — Quick Bites should stack in single column
- Resize to desktop — Quick Bites subsections should be 3-column grid
- Print preview — Quick Bites should be included, only checked items visible

**Step 4: Final full test + lint**

Run: `rake`
Expected: All tests pass, no lint offenses.

**Step 5: Final commit (if any cleanup needed)**

```
chore: final cleanup for Quick Bites and aisles feature
```

---

Plan complete and saved to `docs/plans/2026-02-22-quick-bites-and-aisles-plan.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Parallel Session (separate)** — Open a new session with executing-plans, batch execution with checkpoints.

Which approach?

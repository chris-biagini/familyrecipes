# Categories Refinement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Move recipe categories from front matter to a dropdown in the recipe editor, add a dedicated Edit Categories dialog on the homepage, and extract shared ordered-list-editor infrastructure from the existing aisle editor.

**Architecture:** Four milestones: (1) remove Category from the parser pipeline and front matter, shifting category assignment to `RecipeWriteService`; (2) add a category dropdown to the recipe editor; (3) extract shared ordered-list-editor utilities from the aisle editor; (4) build the category editor dialog on the homepage. TDD throughout.

**Tech Stack:** Rails 8, SQLite, Stimulus, Turbo, Minitest

---

## Milestone 1: Remove Category from Parser Pipeline

Strip `Category:` from the parser, move category assignment to the service layer, migrate stored data.

### Task 1: Remove Category from LineClassifier

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb:16`
- Modify: `test/line_classifier_test.rb`

**Step 1: Update the failing test**

Find any test that asserts `Category:` produces a `:front_matter` token and change it to assert `:prose` (or remove it). Add a new test:

```ruby
test 'Category line is classified as prose' do
  type, content = LineClassifier.classify_line('Category: Bread')
  assert_equal :prose, type
  assert_equal 'Category: Bread', content
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/line_classifier_test.rb -n test_Category_line_is_classified_as_prose`
Expected: FAIL — currently classifies as `:front_matter`

**Step 3: Update the regex**

In `line_classifier.rb:16`, change:
```ruby
front_matter: /^(Category|Makes|Serves):\s+(.+)$/,
```
to:
```ruby
front_matter: /^(Makes|Serves):\s+(.+)$/,
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/line_classifier_test.rb`
Expected: PASS. Some existing tests that feed `Category:` lines through the full pipeline may now fail — that's expected and will be fixed in subsequent tasks.

**Step 5: Commit**

```bash
git add lib/familyrecipes/line_classifier.rb test/line_classifier_test.rb
git commit -m "refactor: remove Category from LineClassifier front matter regex"
```

---

### Task 2: Remove Category from FamilyRecipes::Recipe

**Files:**
- Modify: `lib/familyrecipes/recipe.rb:13,21,107-125`
- Modify: `test/recipe_test.rb`

**Step 1: Update tests**

Remove or update any test that expects `category` to be parsed from markdown or validates category presence. The `validate_category_match` and `validate_front_matter` category checks should be removed. Find tests that construct `FamilyRecipes::Recipe.new(markdown_source:, id:, category:)` and update them.

Since `category` is now removed as a constructor param and attribute:
- Remove `category:` from all `FamilyRecipes::Recipe.new` calls in tests
- Remove tests for "missing Category" validation
- Remove tests for "category mismatch" validation
- Keep tests for `validate_makes_has_unit_noun`

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/recipe_test.rb`

**Step 3: Update the model**

In `recipe.rb`:
- Line 13: Remove `:category` from `attr_reader`
- Line 21: Remove `category:` parameter from `initialize`
- Line 24: Remove `@category = category`
- Lines 107-111: In `apply_front_matter`, remove `@front_matter_category = fields[:category]`
- Lines 113-118: In `validate_front_matter`, remove the category presence check and `validate_category_match` call
- Lines 120-125: Delete `validate_category_match` method entirely

**Step 4: Run tests**

Run: `ruby -Itest test/recipe_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes/recipe.rb test/recipe_test.rb
git commit -m "refactor: remove category attribute from FamilyRecipes::Recipe"
```

---

### Task 3: Remove Category from MarkdownValidator

**Files:**
- Modify: `app/services/markdown_validator.rb:21`
- Modify: `test/services/markdown_validator_test.rb:30-43`

**Step 1: Update the test**

In `markdown_validator_test.rb`, remove the `'missing category returns error'` test (lines 30-43). Update the `'valid markdown returns no errors'` test to remove the `Category: Bread` line from its markdown fixture.

```ruby
test 'valid markdown returns no errors' do
  markdown = <<~MD
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix everything.
  MD

  errors = MarkdownValidator.validate(markdown)
  assert_empty errors
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/markdown_validator_test.rb`
Expected: The valid markdown test may fail because the parser might choke without Category.

**Step 3: Update the validator**

In `markdown_validator.rb:21`, remove:
```ruby
errors << 'Category is required in front matter (e.g., "Category: Bread").' unless parsed[:front_matter][:category]
```

Update the header comment to remove mention of "missing category".

**Step 4: Run tests**

Run: `ruby -Itest test/services/markdown_validator_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/markdown_validator.rb test/services/markdown_validator_test.rb
git commit -m "refactor: remove category validation from MarkdownValidator"
```

---

### Task 4: Update MarkdownImporter — Remove Category Logic

**Files:**
- Modify: `app/services/markdown_importer.rb:64-87`
- Modify: `test/services/markdown_importer_test.rb` (if exists, or relevant integration tests)

**Step 1: Write the failing test**

The importer should no longer create categories. It should accept a `category:` keyword (an AR Category object) and assign it directly. Update existing importer tests to pass a category object:

```ruby
test 'import assigns provided category to recipe' do
  category = Category.create!(name: 'Bread', slug: 'bread', position: 0)
  markdown = <<~MD
    # Focaccia

    ## Mix (combine)

    - Flour, 3 cups

    Mix.
  MD

  recipe = MarkdownImporter.import(markdown, kitchen: @kitchen, category: category)
  assert_equal category, recipe.category
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: FAIL — `MarkdownImporter.import` doesn't accept `category:` yet

**Step 3: Update MarkdownImporter**

- Add `category:` keyword to `self.import` and `initialize`
- In `update_recipe_attributes` (line 64-78): replace `find_or_create_category(parsed[:front_matter][:category])` with the passed-in `@category`
- Delete `find_or_create_category` method (lines 81-87)
- Update the header comment

```ruby
def self.import(markdown_source, kitchen:, category:)
  new(markdown_source, kitchen: kitchen, category: category).import
end

def initialize(markdown_source, kitchen:, category:)
  @markdown_source = markdown_source
  @kitchen = kitchen
  @category = category
  @parsed = parse_markdown
end
```

In `update_recipe_attributes`:
```ruby
def update_recipe_attributes(recipe)
  makes_qty, makes_unit = FamilyRecipes::Recipe.parse_makes(parsed[:front_matter][:makes])

  recipe.assign_attributes(
    title: parsed[:title],
    description: parsed[:description],
    category: category,
    kitchen: kitchen,
    makes_quantity: makes_qty,
    makes_unit_noun: makes_unit,
    serves: parsed[:front_matter][:serves]&.to_i,
    footer: parsed[:footer],
    markdown_source: markdown_source
  )
end
```

Add `category` to the `attr_reader` line.

**Step 4: Run tests**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/markdown_importer.rb test/services/markdown_importer_test.rb
git commit -m "refactor: MarkdownImporter accepts category as parameter instead of parsing from front matter"
```

---

### Task 5: Update RecipeWriteService — Add category_name Parameter

**Files:**
- Modify: `app/services/recipe_write_service.rb:13-65`
- Modify: `test/services/recipe_write_service_test.rb`

**Step 1: Write the failing test**

Update `BASIC_MARKDOWN` to remove `Category: Bread`. Update all test calls to pass `category_name:`:

```ruby
BASIC_MARKDOWN = <<~MD
  # Focaccia

  A simple flatbread.

  Serves: 8

  ## Make the dough (combine ingredients)

  - Flour, 3 cups
  - Salt, 1 tsp

  Mix everything together.
MD

test 'create imports recipe with category_name and returns Result' do
  result = RecipeWriteService.create(
    markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread'
  )

  assert_equal 'Focaccia', result.recipe.title
  assert_equal 'Bread', result.recipe.category.name
end

test 'create defaults to Miscellaneous when category_name is blank' do
  result = RecipeWriteService.create(
    markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: ''
  )

  assert_equal 'Miscellaneous', result.recipe.category.name
end
```

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`

**Step 3: Update RecipeWriteService**

Add `category_name:` to all entry points, with a default of `'Miscellaneous'`:

```ruby
def self.create(markdown:, kitchen:, category_name: 'Miscellaneous')
  new(kitchen:).create(markdown:, category_name:)
end

def self.update(slug:, markdown:, kitchen:, category_name: 'Miscellaneous')
  new(kitchen:).update(slug:, markdown:, category_name:)
end

def create(markdown:, category_name:)
  category = find_or_create_category(category_name)
  recipe = import_and_timestamp(markdown, category:)
  kitchen.broadcast_update
  post_write_cleanup
  Result.new(recipe:, updated_references: [])
end

def update(slug:, markdown:, category_name:)
  old_recipe = kitchen.recipes.find_by!(slug:)
  category = find_or_create_category(category_name)
  recipe = import_and_timestamp(markdown, category:)
  updated_references = rename_cross_references(old_recipe, recipe)
  handle_slug_change(old_recipe, recipe)
  kitchen.broadcast_update
  post_write_cleanup
  Result.new(recipe:, updated_references:)
end
```

Add the `find_or_create_category` method (moved from MarkdownImporter):

```ruby
def find_or_create_category(name)
  name = 'Miscellaneous' if name.blank?
  slug = FamilyRecipes.slugify(name)
  kitchen.categories.find_or_create_by!(slug: slug) do |cat|
    cat.name = name
    cat.position = kitchen.categories.maximum(:position).to_i + 1
  end
end
```

Update `import_and_timestamp` to pass category through:

```ruby
def import_and_timestamp(markdown, category:)
  recipe = MarkdownImporter.import(markdown, kitchen:, category:)
  recipe.update!(edited_at: Time.current)
  recipe
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/services/recipe_write_service_test.rb`
Expected: PASS

**Step 5: Update all other tests that call RecipeWriteService or MarkdownImporter**

Search for all usages of `RecipeWriteService.create`, `RecipeWriteService.update`, and `MarkdownImporter.import` across the test suite and update them to pass the required `category:` / `category_name:` parameter. Also update the `BASIC_MARKDOWN` constants to remove `Category:` lines.

Run: `rake test`
Expected: PASS (or identify remaining failures for next step)

**Step 6: Commit**

```bash
git add app/services/recipe_write_service.rb test/
git commit -m "feat: RecipeWriteService accepts category_name, defaults to Miscellaneous"
```

---

### Task 6: Update RecipesController — Pass Category from Params

**Files:**
- Modify: `app/controllers/recipes_controller.rb:15-34`
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Update controller tests**

Update all test markdown fixtures to remove `Category:` lines. Add `category: 'Bread'` to params in create/update calls:

```ruby
test 'create saves valid markdown and returns redirect URL' do
  markdown = <<~MD
    # Ciabatta

    A rustic bread.

    ## Mix (combine ingredients)

    - Flour, 4 cups
    - Water, 2 cups

    Mix and rest overnight.
  MD

  log_in
  post recipes_path(kitchen_slug: kitchen_slug),
       params: { markdown_source: markdown, category: 'Bread' },
       as: :json

  assert_response :success
  body = response.parsed_body
  assert_equal recipe_path('ciabatta', kitchen_slug: kitchen_slug), body['redirect_url']
  assert Recipe.find_by(slug: 'ciabatta')
end
```

**Step 2: Run tests to verify failures**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`

**Step 3: Update the controller**

```ruby
def create
  return render_validation_errors if validation_errors.any?

  result = RecipeWriteService.create(
    markdown: params[:markdown_source],
    kitchen: current_kitchen,
    category_name: params[:category]
  )
  render json: { redirect_url: recipe_path(result.recipe.slug) }
rescue ActiveRecord::RecordInvalid, RuntimeError => error
  render json: { errors: [error.message] }, status: :unprocessable_content
end

def update
  current_kitchen.recipes.find_by!(slug: params[:slug])
  return render_validation_errors if validation_errors.any?

  result = RecipeWriteService.update(
    slug: params[:slug],
    markdown: params[:markdown_source],
    kitchen: current_kitchen,
    category_name: params[:category]
  )
  render json: update_response(result)
rescue ActiveRecord::RecordInvalid, RuntimeError => error
  render json: { errors: [error.message] }, status: :unprocessable_content
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: RecipesController passes category param to RecipeWriteService"
```

---

### Task 7: Update Seed Files and Seeder

**Files:**
- Modify: All `db/seeds/recipes/**/*.md` files — remove `Category: X` lines
- Modify: `db/seeds.rb:38-52`

**Step 1: Strip Category lines from seed files**

Write a script or manually remove all `Category: X` lines from every `.md` file in `db/seeds/recipes/`. The category will now be inferred from the directory name.

```bash
find db/seeds/recipes -name '*.md' -exec sed -i '/^Category: /d' {} \;
```

Verify with: `grep -r "^Category:" db/seeds/recipes/` — should return nothing.

**Step 2: Update db/seeds.rb**

Replace the seeder's recipe import section. Instead of relying on front matter, infer category from the parent directory:

```ruby
recipe_files.each do |path|
  markdown = File.read(path)
  category_name = File.basename(File.dirname(path))

  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = kitchen.recipes.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  category_slug = FamilyRecipes.slugify(category_name)
  category = kitchen.categories.find_or_create_by!(slug: category_slug) do |cat|
    cat.name = category_name
    cat.position = kitchen.categories.maximum(:position).to_i + 1
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen, category: category)
  puts "  #{recipe.title} (#{recipe.category.name})"
end
```

**Step 3: Verify seeder works**

Run: `rails db:drop db:create db:migrate db:seed`
Expected: All recipes imported with correct categories inferred from directories.

**Step 4: Commit**

```bash
git add db/seeds/ db/seeds.rb
git commit -m "refactor: strip Category from seed files, infer from directory name"
```

---

### Task 8: Data Migration — Strip Category from Stored Markdown

**Files:**
- Create: `db/migrate/TIMESTAMP_strip_category_from_markdown_source.rb`

**Step 1: Generate migration**

```bash
rails generate migration StripCategoryFromMarkdownSource
```

**Step 2: Write the migration**

```ruby
class StripCategoryFromMarkdownSource < ActiveRecord::Migration[8.0]
  def up
    Recipe.find_each do |recipe|
      cleaned = recipe.markdown_source.gsub(/^Category: .+\n\n?/, '')
      recipe.update_column(:markdown_source, cleaned)
    end
  end

  def down
    # Cannot restore — category info lives in category association
    raise ActiveRecord::IrreversibleMigration
  end
end
```

**Step 3: Run migration**

Run: `rails db:migrate`

**Step 4: Verify**

Run: `rails runner "puts Recipe.where('markdown_source LIKE ?', '%Category:%').count"`
Expected: `0`

**Step 5: Commit**

```bash
git add db/migrate/
git commit -m "data: strip Category lines from stored markdown_source"
```

---

### Task 9: Update Remaining Tests and Full Suite Green

**Files:**
- Modify: Any remaining test files that use `Category:` in markdown fixtures

**Step 1: Find all remaining test fixtures with Category**

```bash
grep -rn "Category:" test/ --include="*.rb"
```

Update every markdown fixture to remove `Category:` lines. Update every `MarkdownImporter.import` call to pass `category:`. Update every `RecipeWriteService` call to pass `category_name:`.

**Step 2: Run full test suite**

Run: `rake test`
Expected: ALL PASS

**Step 3: Run linter**

Run: `rake lint`
Expected: 0 offenses

**Step 4: Commit**

```bash
git add test/
git commit -m "test: update all fixtures to remove Category from front matter"
```

---

## Milestone 2: Recipe Editor Category Dropdown

### Task 10: Add Category Dropdown to Recipe Editor Views

**Files:**
- Modify: `app/views/homepage/show.html.erb:34-46` (new recipe editor)
- Modify: `app/views/recipes/show.html.erb:40-51` (edit recipe editor)
- Modify: `app/controllers/homepage_controller.rb` (pass categories to view)
- Modify: `app/controllers/recipes_controller.rb:10-13` (pass categories to view)

**Step 1: Write controller tests**

```ruby
test 'recipe page includes category dropdown in editor' do
  log_in
  get recipe_path('focaccia', kitchen_slug: kitchen_slug)

  assert_select '#recipe-editor select.category-select'
  assert_select '#recipe-editor select.category-select option', text: 'Bread'
end

test 'homepage includes category dropdown in new recipe editor' do
  log_in
  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '#recipe-editor select.category-select'
  assert_select '#recipe-editor select.category-select option', text: 'Miscellaneous'
end
```

**Step 2: Run tests to verify failure**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb test/controllers/homepage_controller_test.rb`

**Step 3: Update controllers**

In `homepage_controller.rb`, add `@all_categories` for the editor dropdown:
```ruby
def show
  @categories = current_kitchen.categories.ordered.with_recipes.includes(:recipes)
  @all_categories = current_kitchen.categories.ordered
  @site_config = SiteDocument.content_for(:homepage)
end
```

In `recipes_controller.rb#show`:
```ruby
def show
  @recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  @nutrition = @recipe.nutrition_data
  @all_categories = current_kitchen.categories.ordered
end
```

**Step 4: Update views**

In `homepage/show.html.erb`, update the new recipe editor dialog (lines 34-46). Add a category dropdown below the textarea, inside the yield block. The dropdown defaults to "Miscellaneous":

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'New Recipe',
              id: 'recipe-editor',
              dialog_data: { editor_open: '#new-recipe-button',
                             editor_url: recipes_path,
                             editor_method: 'POST',
                             editor_on_success: 'redirect',
                             editor_body_key: 'markdown_source',
                             extra_controllers: 'recipe-editor' } } do %>
  <textarea class="editor-textarea" data-editor-target="textarea" data-recipe-editor-target="textarea" spellcheck="false"><%= "# Recipe Title\n\nOptional description.\n\nMakes: 4 servings\nServes: 4\n\n## Step Name (short summary)\n\n- Ingredient, quantity: prep note\n\nInstructions here.\n\n---\n\nOptional notes or source." %></textarea>
  <div class="editor-category-row">
    <label for="new-recipe-category">Category</label>
    <select id="new-recipe-category" class="category-select" data-recipe-editor-target="categorySelect">
      <% @all_categories.each do |cat| %>
        <option value="<%= cat.name %>" <%= 'selected' if cat.name == 'Miscellaneous' %>><%= cat.name %></option>
      <% end %>
      <option disabled>&#x2500;&#x2500;&#x2500;</option>
      <option value="__new__">New category&hellip;</option>
    </select>
    <input type="text" class="category-new-input" placeholder="New category name"
           data-recipe-editor-target="categoryInput"
           hidden maxlength="50">
  </div>
<% end %>
```

In `recipes/show.html.erb`, update the edit recipe editor dialog similarly, pre-selecting the recipe's current category:

```erb
<div class="editor-category-row">
  <label for="edit-recipe-category">Category</label>
  <select id="edit-recipe-category" class="category-select" data-recipe-editor-target="categorySelect">
    <% @all_categories.each do |cat| %>
      <option value="<%= cat.name %>" <%= 'selected' if cat == @recipe.category %>><%= cat.name %></option>
    <% end %>
    <option disabled>&#x2500;&#x2500;&#x2500;</option>
    <option value="__new__">New category&hellip;</option>
  </select>
  <input type="text" class="category-new-input" placeholder="New category name"
         data-recipe-editor-target="categoryInput"
         hidden maxlength="50">
</div>
```

**Step 5: Add CSS for the category row**

In `style.css`, add styles for `.editor-category-row`:

```css
.editor-category-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  border-top: 1px solid var(--border-color);
}

.editor-category-row label {
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted-text);
}

.category-select {
  flex: 1;
  max-width: 16rem;
}

.category-new-input {
  flex: 1;
  max-width: 16rem;
}
```

**Step 6: Run tests**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb test/controllers/homepage_controller_test.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add app/views/ app/controllers/ app/assets/stylesheets/style.css
git commit -m "feat: add category dropdown to recipe editor dialogs"
```

---

### Task 11: Update recipe_editor_controller.js — Category Handling

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

**Step 1: Add category targets and editor:collect hook**

The recipe-editor controller needs to:
1. Declare `categorySelect` and `categoryInput` as targets
2. Listen for `editor:collect` event from the parent editor controller
3. Include the selected category in the save payload
4. Handle the "New category..." sentinel

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "categorySelect", "categoryInput"]

  connect() {
    this.cursorInitialized = false
    this.boundCollect = (e) => this.handleCollect(e)
    this.boundModified = (e) => this.handleModified(e)
    this.element.addEventListener("editor:collect", this.boundCollect)
    this.element.addEventListener("editor:modified", this.boundModified)
  }

  disconnect() {
    this.teardownTextarea()
    this.element.removeEventListener("editor:collect", this.boundCollect)
    this.element.removeEventListener("editor:modified", this.boundModified)
  }

  // ... existing textarea methods unchanged ...

  handleCollect(event) {
    event.detail.handled = true
    event.detail.data = {
      markdown_source: this.hasTextareaTarget ? this.textareaTarget.value : null,
      category: this.selectedCategory()
    }
  }

  handleModified(event) {
    // Let editor_controller handle textarea modification detection,
    // but also flag if category changed
    if (this.hasCategorySelectTarget && this.originalCategory !== undefined) {
      if (this.selectedCategory() !== this.originalCategory) {
        event.detail.handled = true
        event.detail.modified = true
      }
    }
  }

  selectedCategory() {
    if (!this.hasCategorySelectTarget) return null
    const val = this.categorySelectTarget.value
    if (val === "__new__") {
      return this.hasCategoryInputTarget ? this.categoryInputTarget.value.trim() : null
    }
    return val
  }
```

Add the sentinel toggle (when user selects "New category..."):

```javascript
  categorySelectTargetConnected(element) {
    this.originalCategory = element.value
    element.addEventListener("change", () => this.handleCategoryChange())
  }

  handleCategoryChange() {
    if (!this.hasCategorySelectTarget || !this.hasCategoryInputTarget) return

    if (this.categorySelectTarget.value === "__new__") {
      this.categoryInputTarget.hidden = false
      this.categorySelectTarget.hidden = true
      this.categoryInputTarget.focus()
    }
  }
```

Also handle Escape on the new-category input to revert:

```javascript
  categoryInputTargetConnected(element) {
    element.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        this.categoryInputTarget.hidden = true
        this.categorySelectTarget.hidden = false
        this.categorySelectTarget.value = this.originalCategory
      }
    })
  }
```

**Step 2: Update syntax highlighter**

In `classifyLine`, change line 122 from:
```javascript
} else if (/^(Category|Makes|Serves):\s+.+$/.test(line)) {
```
to:
```javascript
} else if (/^(Makes|Serves):\s+.+$/.test(line)) {
```

**Step 3: Update placeholder**

In `setPlaceholder`, remove the `"Category: Dinner",` line.

**Step 4: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 5: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: recipe editor includes category in save payload, handles new-category sentinel"
```

---

### Task 12: Rename "Add New Recipe" to "Add Recipe"

**Files:**
- Modify: `app/views/homepage/show.html.erb:6`

**Step 1: Update the button text**

Change line 6 from:
```erb
<button type="button" id="new-recipe-button" class="btn">Add New Recipe</button>
```
to:
```erb
<button type="button" id="new-recipe-button" class="btn">Add Recipe</button>
```

**Step 2: Update any test that asserts the button text**

Search for "Add New Recipe" in tests and update.

**Step 3: Commit**

```bash
git add app/views/homepage/show.html.erb test/
git commit -m "chore: rename 'Add New Recipe' to 'Add Recipe'"
```

---

## Milestone 3: Shared Ordered List Editor Infrastructure

### Task 13: Extract ordered_list_editor_utils.js

**Files:**
- Create: `app/javascript/utilities/ordered_list_editor_utils.js`
- Modify: `config/importmap.rb` (pin the new module)

**Step 1: Identify shared logic in aisle_order_editor_controller.js**

The following functions should be extracted:
- `createItem(originalName)` — creates `{ originalName, currentName, deleted }` object
- `buildPayload(items)` — returns `{ order: [], renames: {}, deletes: [] }`
- `isModified(items, initialSnapshot)` — compares against snapshot
- `renderRows(container, items, callbacks)` — generates row HTML
- `buildRowElement(item, index, totalLive, callbacks)` — single row with buttons
- `swapItems(items, indexA, indexB)` — array swap
- `animateSwap(rowA, rowB, callback)` — CSS transition swap animation
- `startInlineRename(nameButton, item, onDone)` — click-to-edit
- `checkDuplicate(items, name, excludeIndex)` — case-insensitive check
- `updateDisabledStates(container)` — first/last button states

**Step 2: Create the utility module**

```javascript
/**
 * Shared utilities for ordered-list editor dialogs (aisles, categories).
 * Provides changeset tracking, row rendering, inline rename, reorder
 * animations, and payload serialization. Each Stimulus controller owns
 * its dialog lifecycle and fetch calls; this module handles the list logic.
 *
 * - aisle_order_editor_controller: first consumer (grocery aisles)
 * - category_order_editor_controller: second consumer (recipe categories)
 * - editor_utils: CSRF, errors, save helpers (separate concern)
 */
```

Write each function as a named export. The `renderRows` function should accept a `callbacks` object with `{ onRename, onMoveUp, onMoveDown, onDelete, onUndo, buildExtra }` so consumers can customize behavior.

**Step 3: Pin in importmap**

```ruby
pin "utilities/ordered_list_editor_utils"
```

**Step 4: Commit**

```bash
git add app/javascript/utilities/ordered_list_editor_utils.js config/importmap.rb
git commit -m "feat: extract ordered_list_editor_utils.js from aisle editor"
```

---

### Task 14: Refactor aisle_order_editor_controller.js to Use Shared Utils

**Files:**
- Modify: `app/javascript/controllers/aisle_order_editor_controller.js`

**Step 1: Import and delegate**

Replace inline logic with calls to the shared utility functions. The controller should shrink significantly — it keeps:
- Stimulus targets/values/connect/disconnect
- `open()`, `close()`, `save()` (dialog lifecycle)
- `loadAisles()` (fetch from server)
- Domain-specific payload shape (aisle_order as newline string)

**Step 2: Verify manually**

Start dev server, open groceries page, test the aisle editor:
- Open dialog, verify aisles load
- Rename an aisle, verify yellow highlight
- Reorder aisles, verify animation
- Add a new aisle, verify green highlight
- Delete an aisle, verify strikethrough + undo
- Save, verify changes persist
- Cancel with changes, verify confirmation prompt

**Step 3: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 4: Commit**

```bash
git add app/javascript/controllers/aisle_order_editor_controller.js
git commit -m "refactor: aisle editor delegates to ordered_list_editor_utils"
```

---

### Task 15: Extract Rails OrderedListEditor Concern

**Files:**
- Create: `app/controllers/concerns/ordered_list_editor.rb`
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `test/controllers/groceries_controller_test.rb`

**Step 1: Identify shared backend logic**

From `GroceriesController#update_aisle_order` (lines 39-54), extract:
- Validation helpers (max items, max name length, duplicate checking)
- Transaction wrapper pattern
- `broadcast_update` call

The concern should provide:
```ruby
module OrderedListEditor
  extend ActiveSupport::Concern

  private

  def validate_ordered_list(items, max_items:, max_name_length:)
    errors = []
    errors << "Too many items (maximum #{max_items})." if items.size > max_items
    items.each do |name|
      errors << "\"#{name}\" is too long (maximum #{max_name_length} characters)." if name.size > max_name_length
    end
    errors
  end
end
```

**Step 2: Refactor GroceriesController to use concern**

```ruby
class GroceriesController < ApplicationController
  include OrderedListEditor
  # ... existing code, using validate_ordered_list ...
end
```

**Step 3: Run tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: PASS

**Step 4: Commit**

```bash
git add app/controllers/concerns/ordered_list_editor.rb app/controllers/groceries_controller.rb
git commit -m "refactor: extract OrderedListEditor concern from GroceriesController"
```

---

## Milestone 4: Category Editor Dialog

### Task 16: Add Category Order Routes

**Files:**
- Modify: `config/routes.rb`

**Step 1: Add routes**

Inside the kitchen scope, add:
```ruby
patch 'categories/order', to: 'categories#update_order', as: :categories_order
get 'categories/order_content', to: 'categories#order_content', as: :categories_order_content
```

**Step 2: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add category order routes"
```

---

### Task 17: Create CategoriesController

**Files:**
- Create: `app/controllers/categories_controller.rb`
- Create: `test/controllers/categories_controller_test.rb`

**Step 1: Write the tests**

```ruby
class CategoriesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    create_kitchen_and_user
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    @dessert = Category.create!(name: 'Dessert', slug: 'dessert', position: 1, kitchen: @kitchen)
  end

  test 'order_content returns categories as JSON' do
    log_in
    get categories_order_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body['categories'].size
    assert_equal 'Bread', body['categories'][0]['name']
  end

  test 'update_order renames a category' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: %w[Artisan\ Bread Dessert],
            renames: { 'Bread' => 'Artisan Bread' },
            deletes: []
          }, as: :json

    assert_response :success
    @bread.reload
    assert_equal 'Artisan Bread', @bread.name
  end

  test 'update_order deletes a category and reassigns recipes to Miscellaneous' do
    MarkdownImporter.import("# Rolls\n\n## Mix (do it)\n\n- Flour, 1 cup\n\nMix.",
                            kitchen: @kitchen, category: @bread)

    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: %w[Dessert],
            renames: {},
            deletes: %w[Bread]
          }, as: :json

    assert_response :success
    assert_nil Category.find_by(name: 'Bread')
    assert_equal 'Miscellaneous', Recipe.find_by!(slug: 'rolls').category.name
  end

  test 'update_order reorders categories' do
    log_in
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: {
            category_order: %w[Dessert Bread],
            renames: {},
            deletes: []
          }, as: :json

    assert_response :success
    assert_equal 0, Category.find_by!(name: 'Dessert').position
    assert_equal 1, Category.find_by!(name: 'Bread').position
  end

  test 'update_order requires membership' do
    patch categories_order_path(kitchen_slug: kitchen_slug),
          params: { category_order: [], renames: {}, deletes: [] }, as: :json

    assert_response :forbidden
  end

  test 'update_order broadcasts to kitchen updates stream' do
    log_in
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      patch categories_order_path(kitchen_slug: kitchen_slug),
            params: { category_order: %w[Bread Dessert], renames: {}, deletes: [] },
            as: :json
    end
  end
end
```

**Step 2: Run tests to verify failure**

Run: `ruby -Itest test/controllers/categories_controller_test.rb`
Expected: FAIL — controller doesn't exist yet

**Step 3: Create the controller**

```ruby
# frozen_string_literal: true

# Manages category ordering, renaming, and deletion via the Edit Categories
# dialog on the homepage. Uses the same staged-changeset pattern as the aisle
# editor: client tracks renames/deletes/reorders, submits them in a single PATCH.
#
# - OrderedListEditor concern: shared validation
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - Category: AR model with position column for ordering
class CategoriesController < ApplicationController
  include OrderedListEditor

  before_action :require_membership, only: [:update_order]

  MAX_CATEGORIES = 50
  MAX_NAME_LENGTH = 50

  def order_content
    categories = current_kitchen.categories.ordered
    render json: {
      categories: categories.map { |c| { name: c.name, position: c.position, recipe_count: c.recipes.size } }
    }
  end

  def update_order
    names = Array(params[:category_order])
    errors = validate_ordered_list(names, max_items: MAX_CATEGORIES, max_name_length: MAX_NAME_LENGTH)
    return render(json: { errors: }, status: :unprocessable_content) if errors.any?

    ActiveRecord::Base.transaction do
      cascade_category_renames
      cascade_category_deletes
      update_category_positions(names)
    end

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end

  private

  def cascade_category_renames
    renames = params[:renames]
    return unless renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      category = current_kitchen.categories.find_by!(name: old_name)
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def cascade_category_deletes
    deletes = Array(params[:deletes])
    return if deletes.empty?

    misc = find_or_create_miscellaneous

    deletes.each do |name|
      category = current_kitchen.categories.find_by(name: name)
      next unless category

      category.recipes.update_all(category_id: misc.id)
      category.destroy!
    end
  end

  def find_or_create_miscellaneous
    slug = FamilyRecipes.slugify('Miscellaneous')
    current_kitchen.categories.find_or_create_by!(slug: slug) do |cat|
      cat.name = 'Miscellaneous'
      cat.position = current_kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def update_category_positions(names)
    names.each_with_index do |name, index|
      current_kitchen.categories.where(name: name).update_all(position: index)
    end
  end
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/controllers/categories_controller_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/categories_controller.rb test/controllers/categories_controller_test.rb
git commit -m "feat: CategoriesController with order/rename/delete support"
```

---

### Task 18: Build category_order_editor_controller.js

**Files:**
- Create: `app/javascript/controllers/category_order_editor_controller.js`
- Modify: `config/importmap.rb` (auto-registers via `pin_all_from`)

**Step 1: Create the controller**

Build using the shared `ordered_list_editor_utils.js`. Structure mirrors `aisle_order_editor_controller.js` but is thinner. Key differences from aisle editor:
- Loads categories as `[{ name, position, recipe_count }]` from server
- Recipe count shown as a badge on each row (e.g., "Bread (12)")
- Payload uses `category_order` (array) instead of `aisle_order` (newline string)
- Prevents deletion of "Miscellaneous" if it would orphan recipes (or just reassigns)

```javascript
/**
 * Rich list editor for recipe categories. Provides inline rename, drag-free
 * reordering (up/down buttons), add/delete with undo, and visual state feedback.
 * Submits staged changes as a single PATCH. Uses ordered_list_editor_utils for
 * shared list logic; this controller owns the dialog lifecycle and fetch calls.
 *
 * - ordered_list_editor_utils: changeset, row rendering, animation, payload
 * - editor_utils: CSRF tokens, error display
 * - CategoriesController: backend for load/save
 */
```

**Step 2: Verify manually**

Start dev server, test the category editor on the homepage:
- Open dialog, verify categories load with recipe counts
- Rename, reorder, add, delete — verify visual states
- Save, verify changes persist and homepage reflects new order

**Step 3: Commit**

```bash
git add app/javascript/controllers/category_order_editor_controller.js
git commit -m "feat: category order editor Stimulus controller"
```

---

### Task 19: Add Edit Categories Dialog to Homepage

**Files:**
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add the button and dialog**

In `homepage/show.html.erb`, update the `extra_nav` content block to include the Edit Categories button alongside Add Recipe:

```erb
<% if current_member? %>
<% content_for(:extra_nav) do %>
    <div>
      <button type="button" id="edit-categories-button" class="btn">Edit Categories</button>
      <button type="button" id="new-recipe-button" class="btn">Add Recipe</button>
    </div>
<% end %>
<% end %>
```

Add the category editor dialog at the bottom (before the recipe editor dialog), following the same pattern as the aisle editor dialog in `groceries/show.html.erb`:

```erb
<% if current_member? %>
<dialog class="editor-dialog"
        data-controller="category-order-editor"
        data-category-order-editor-load-url-value="<%= categories_order_content_path %>"
        data-category-order-editor-save-url-value="<%= categories_order_path %>">
  <div class="editor-header">
    <h2>Categories</h2>
    <button type="button" class="btn editor-close" data-action="click->category-order-editor#close" aria-label="Close">&times;</button>
  </div>
  <div class="editor-errors" data-category-order-editor-target="errors" hidden></div>
  <div class="aisle-order-body">
    <div class="aisle-list" data-category-order-editor-target="list"></div>
    <div class="aisle-add-row">
      <label for="new-category-input" class="sr-only">New category name</label>
      <input type="text" id="new-category-input" class="aisle-add-input" placeholder="Add a category..."
             data-category-order-editor-target="newCategoryName"
             data-action="keydown->category-order-editor#addCategoryOnEnter"
             maxlength="50">
      <button type="button" class="aisle-btn aisle-btn--add" aria-label="Add category"
              data-action="click->category-order-editor#addCategory">
        <svg viewBox="0 0 24 24" width="18" height="18">
          <line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          <line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
        </svg>
      </button>
    </div>
  </div>
  <div class="editor-footer">
    <button type="button" class="btn editor-cancel" data-action="click->category-order-editor#close">Cancel</button>
    <button type="button" class="btn btn-primary editor-save" data-category-order-editor-target="saveButton" data-action="click->category-order-editor#save">Save</button>
  </div>
</dialog>
<% end %>
```

Note: we reuse the `.aisle-order-body`, `.aisle-list`, `.aisle-add-row`, `.aisle-row` CSS classes for the category editor since the styling is identical. No new CSS classes needed for the rows.

**Step 2: Write tests**

```ruby
test 'homepage renders Edit Categories button for members' do
  log_in
  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '#edit-categories-button'
end

test 'homepage does not render Edit Categories for non-members' do
  get kitchen_root_path(kitchen_slug: kitchen_slug)

  assert_select '#edit-categories-button', count: 0
end
```

**Step 3: Run tests**

Run: `ruby -Itest test/controllers/homepage_controller_test.rb`
Expected: PASS

**Step 4: Commit**

```bash
git add app/views/homepage/show.html.erb app/assets/stylesheets/style.css test/
git commit -m "feat: Edit Categories dialog on homepage"
```

---

### Task 20: Update html_safe Allowlist and Final Cleanup

**Files:**
- Modify: `config/html_safe_allowlist.yml` (if line numbers shifted)
- Run: `rake lint:html_safe`

**Step 1: Run the html_safe audit**

```bash
rake lint:html_safe
```

If any failures, update the allowlist with new line numbers.

**Step 2: Run full test suite**

```bash
rake test
```

**Step 3: Run linter**

```bash
rake lint
```

**Step 4: Fix any failures**

Address any RuboCop offenses or test failures.

**Step 5: Commit**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for category editor changes"
```

---

### Task 21: Final Integration Test

**Step 1: Manual verification**

Start `bin/dev` and verify end-to-end:
- Homepage shows categories in correct order
- Edit Categories dialog: rename, reorder, add, delete all work
- Deleting a category reassigns recipes to Miscellaneous
- New recipe defaults to Miscellaneous in dropdown
- Editing a recipe shows correct current category
- Changing a recipe's category via dropdown works
- "New category..." sentinel creates a new category
- Export still organizes recipes into category-named folders

**Step 2: Run full suite one last time**

```bash
rake
```
Expected: 0 offenses, all tests pass.

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "feat: categories refinement — complete implementation (GH #185)"
```

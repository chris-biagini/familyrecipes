# Recipe Web Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a web-based recipe editor that lets users edit the raw markdown of any recipe via a `<dialog>` modal, validate it, save it, and reload the page with updated content.

**Architecture:** A native `<dialog>` element on the recipe page opens a textarea with the raw markdown. Save sends a `PATCH` request to `RecipesController#update`, which validates the markdown through the parser pipeline, runs `MarkdownImporter.import`, and responds with a redirect URL. The JS does a full page reload. An `edited_at` column protects web edits from being overwritten by `db:seed`.

**Tech Stack:** Rails 8, PostgreSQL, vanilla JS, native `<dialog>` element, Minitest

**Design doc:** `docs/plans/2026-02-21-recipe-web-editor-design.md`

---

### Task 1: Database migration — add `edited_at` to recipes

**Files:**
- Create: `db/migrate/XXXXXX_add_edited_at_to_recipes.rb`

**Step 1: Generate the migration**

```bash
rails generate migration AddEditedAtToRecipes edited_at:datetime
```

**Step 2: Verify the migration file**

Open the generated migration and confirm it contains:

```ruby
add_column :recipes, :edited_at, :datetime
```

No `null: false` — null means "never web-edited."

**Step 3: Run the migration**

```bash
rails db:migrate
```

**Step 4: Verify schema.rb**

Check `db/schema.rb` — the `recipes` table should now include `t.datetime "edited_at"`.

**Step 5: Commit**

```bash
git add db/migrate/*_add_edited_at_to_recipes.rb db/schema.rb
git commit -m "db: add edited_at timestamp to recipes table"
```

---

### Task 2: Protect web-edited recipes in `db/seeds.rb`

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Write the test**

No separate test file needed — this is seed logic. But we should verify the behavior manually after implementation.

**Step 2: Update seeds to skip web-edited recipes**

Modify `db/seeds.rb` to check for `edited_at` before importing. The current code is:

```ruby
recipe_files.each do |path|
  markdown = File.read(path)
  recipe = MarkdownImporter.import(markdown)
  puts "  #{recipe.title} (#{recipe.category.name})"
end
```

Change to:

```ruby
recipe_files.each do |path|
  markdown = File.read(path)
  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = Recipe.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  recipe = MarkdownImporter.import(markdown)
  puts "  #{recipe.title} (#{recipe.category.name})"
end
```

**Step 3: Test manually**

```bash
rails db:seed
```

Verify all recipes import normally (none have `edited_at` yet).

**Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: skip web-edited recipes during db:seed"
```

---

### Task 3: Add CSRF meta tags to layout

**Files:**
- Modify: `app/views/layouts/application.html.erb:7` (in `<head>`, after `<title>`)

**Step 1: Add the CSRF meta tags**

Insert `<%= csrf_meta_tags %>` after the `<title>` tag in `application.html.erb`:

```erb
<title><%= content_for?(:title) ? content_for(:title) : 'Biagini Family Recipes' %></title>
<%= csrf_meta_tags %>
<%= stylesheet_link_tag 'style' %>
```

**Step 2: Verify**

```bash
rails server -p 3030 &
curl -s http://localhost:3030 | grep csrf
```

Should see `<meta name="csrf-token" ...>` and `<meta name="csrf-param" ...>` in the output.

**Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -m "feat: add CSRF meta tags to layout for write endpoints"
```

---

### Task 4: Markdown validation service

**Files:**
- Create: `app/services/markdown_validator.rb`
- Create: `test/services/markdown_validator_test.rb`

**Step 1: Write the failing tests**

Create `test/services/markdown_validator_test.rb`:

```ruby
# frozen_string_literal: true

require_relative '../test_helper'

class MarkdownValidatorTest < ActiveSupport::TestCase
  test 'valid markdown returns no errors' do
    markdown = <<~MD
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MD

    errors = MarkdownValidator.validate(markdown)

    assert_empty errors
  end

  test 'missing title returns error' do
    errors = MarkdownValidator.validate('just some text')

    assert errors.any? { |e| e.include?('title') || e.include?('header') }
  end

  test 'missing category returns error' do
    markdown = <<~MD
      # Focaccia

      ## Mix (combine)

      - Flour, 3 cups

      Mix everything.
    MD

    errors = MarkdownValidator.validate(markdown)

    assert errors.any? { |e| e.include?('Category') }
  end

  test 'empty markdown returns error' do
    errors = MarkdownValidator.validate('')

    assert_not_empty errors
  end

  test 'blank markdown returns error' do
    errors = MarkdownValidator.validate('   ')

    assert_not_empty errors
  end

  test 'markdown with no steps returns error' do
    markdown = <<~MD
      # Focaccia

      Category: Bread
    MD

    errors = MarkdownValidator.validate(markdown)

    assert errors.any? { |e| e.include?('step') }
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
rake test TEST=test/services/markdown_validator_test.rb
```

Expected: failures (class doesn't exist yet).

**Step 3: Implement MarkdownValidator**

Create `app/services/markdown_validator.rb`:

```ruby
# frozen_string_literal: true

class MarkdownValidator
  def self.validate(markdown_source)
    new(markdown_source).validate
  end

  def initialize(markdown_source)
    @markdown_source = markdown_source
  end

  def validate
    errors = []
    errors << 'Recipe cannot be blank.' and return errors if @markdown_source.blank?

    parsed = parse
    return errors unless parsed

    errors << 'Category is required in front matter (e.g., "Category: Bread").' unless parsed[:front_matter][:category]
    errors << 'Recipe must have at least one step (## Step Name).' if parsed[:steps].empty?
    errors
  rescue StandardError => error
    [error.message]
  end

  private

  def parse
    tokens = LineClassifier.classify(@markdown_source)
    RecipeBuilder.new(tokens).build
  end
end
```

**Step 4: Run tests to verify they pass**

```bash
rake test TEST=test/services/markdown_validator_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add app/services/markdown_validator.rb test/services/markdown_validator_test.rb
git commit -m "feat: add MarkdownValidator for pre-save validation"
```

---

### Task 5: RecipesController#update action

**Files:**
- Modify: `config/routes.rb:6`
- Modify: `app/controllers/recipes_controller.rb`

**Step 1: Write the failing tests**

Add tests to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'update saves valid markdown and returns redirect URL' do
  updated_markdown = <<~MD
    # Focaccia

    A revised flatbread.

    Category: Bread
    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 4 cups
    - Water, 1.5 cups: Warm.
    - Salt, 1 tsp

    Mix everything together and let rest for 1 hour.

    ## Bake (put it in the oven)

    Bake at 425 degrees for 20 minutes.

    ---

    A classic Italian bread.
  MD

  patch recipe_path('focaccia'),
        params: { markdown_source: updated_markdown },
        as: :json

  assert_response :success
  body = JSON.parse(response.body)

  assert_equal recipe_path('focaccia'), body['redirect_url']

  recipe = Recipe.find_by!(slug: 'focaccia')

  assert_equal 'A revised flatbread.', recipe.description
  assert_not_nil recipe.edited_at
end

test 'update rejects invalid markdown' do
  patch recipe_path('focaccia'),
        params: { markdown_source: 'not valid markdown' },
        as: :json

  assert_response :unprocessable_entity
  body = JSON.parse(response.body)

  assert body['errors'].any?
end

test 'update returns 404 for unknown recipe' do
  patch recipe_path('nonexistent'),
        params: { markdown_source: '# Whatever' },
        as: :json

  assert_response :not_found
end

test 'update handles title change with new slug' do
  updated_markdown = <<~MD
    # Rosemary Focaccia

    A revised flatbread.

    Category: Bread
    Serves: 8

    ## Make the dough (combine ingredients)

    - Flour, 4 cups

    Mix everything together.
  MD

  patch recipe_path('focaccia'),
        params: { markdown_source: updated_markdown },
        as: :json

  assert_response :success
  body = JSON.parse(response.body)

  assert_equal recipe_path('rosemary-focaccia'), body['redirect_url']
  assert_nil Recipe.find_by(slug: 'focaccia')
  assert Recipe.find_by(slug: 'rosemary-focaccia')
end

test 'update cleans up empty categories' do
  updated_markdown = <<~MD
    # Focaccia

    Category: Pastry

    ## Make it (do the thing)

    - Flour, 3 cups

    Mix everything.
  MD

  patch recipe_path('focaccia'),
        params: { markdown_source: updated_markdown },
        as: :json

  assert_response :success
  assert_nil Category.find_by(slug: 'bread')
  assert Category.find_by(slug: 'pastry')
end
```

**Step 2: Run tests to verify they fail**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

Expected: failures (no `update` action or route).

**Step 3: Add the route**

In `config/routes.rb`, change:

```ruby
resources :recipes, only: [:show], param: :slug
```

to:

```ruby
resources :recipes, only: [:show, :update], param: :slug
```

**Step 4: Implement the update action**

Add to `app/controllers/recipes_controller.rb`:

```ruby
def update
  @recipe = Recipe.find_by!(slug: params[:slug])

  errors = MarkdownValidator.validate(params[:markdown_source])
  if errors.any?
    render json: { errors: errors }, status: :unprocessable_entity
    return
  end

  recipe = MarkdownImporter.import(params[:markdown_source])
  recipe.update!(edited_at: Time.current)
  Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

  render json: { redirect_url: recipe_path(recipe.slug) }
rescue ActiveRecord::RecordNotFound
  head :not_found
end
```

Note: The `rescue` from `show` should be extracted or this action needs its own. The cleanest approach: add the rescue to both `show` and `update`, or use `rescue_from` at the controller level. Since `show` already has an inline rescue, match the pattern for `update`.

**Step 5: Run tests to verify they pass**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

Expected: all pass.

**Step 6: Run full test suite**

```bash
rake test
```

Expected: all pass.

**Step 7: Commit**

```bash
git add config/routes.rb app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: add RecipesController#update for recipe editing"
```

---

### Task 6: Fix `recipe_map` to use database instead of disk

**Files:**
- Modify: `app/controllers/recipes_controller.rb:51-53`

**Step 1: Understand the problem**

`RecipesController#recipe_map` currently parses all `.md` files from disk:

```ruby
def recipe_map
  @recipe_map ||= FamilyRecipes.parse_recipes(Rails.root.join('recipes')).to_h { |r| [r.id, r] }
end
```

Once the database is the source of truth, edited recipes on disk may be stale. The `recipe_map` is used by `NutritionCalculator` to resolve cross-recipe nutrition references. We need to build it from the database instead.

**Step 2: Update recipe_map**

Replace the `recipe_map` method in `app/controllers/recipes_controller.rb`:

```ruby
def recipe_map
  @recipe_map ||= Recipe.all.to_h do |r|
    parsed = FamilyRecipes::Recipe.new(
      markdown_source: r.markdown_source,
      id: r.slug,
      category: r.category.name
    )
    [r.slug, parsed]
  end
end
```

This builds parsed recipe objects from database-stored markdown, not from disk files.

**Step 3: Verify existing tests pass**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

**Step 4: Verify the recipe page still renders with nutrition**

Start the dev server and manually check a recipe page with nutrition data to confirm it still renders correctly.

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "fix: build recipe_map from database, not disk files"
```

---

### Task 7: Editor dialog markup in recipe view

**Files:**
- Modify: `app/views/recipes/show.html.erb`

**Step 1: Add the edit button next to the scale button**

In `app/views/recipes/show.html.erb`, change the `content_for(:extra_nav)` block (lines 7-11):

```erb
<% content_for(:extra_nav) do %>
    <div>
      <button type="button" id="edit-button" class="btn">Edit</button>
      <button type="button" id="scale-button" class="btn">Scale</button>
    </div>
<% end %>
```

**Step 2: Add the dialog element**

Add after the closing `</article>` tag (after line 47), before the end of the file:

```erb
<dialog id="recipe-editor">
  <div class="editor-header">
    <h2>Editing: <%= @recipe.title %></h2>
    <button type="button" class="btn" id="editor-close" aria-label="Close">&times;</button>
  </div>
  <div id="editor-errors" hidden></div>
  <textarea id="editor-textarea" spellcheck="false"><%= @recipe.markdown_source %></textarea>
  <div class="editor-footer">
    <button type="button" class="btn" id="editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary" id="editor-save">Save</button>
  </div>
</dialog>
```

**Step 3: Add the editor JS include**

In the `content_for(:scripts)` block (lines 13-17), add:

```erb
<%= javascript_include_tag 'recipe-editor', defer: true %>
```

**Step 4: Write a controller test for the edit button**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'renders edit button' do
  get recipe_path('focaccia')

  assert_select '#edit-button'
end

test 'renders editor dialog with markdown source' do
  get recipe_path('focaccia')

  assert_select '#recipe-editor'
  assert_select '#editor-textarea'
end
```

**Step 5: Run tests**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

**Step 6: Commit**

```bash
git add app/views/recipes/show.html.erb test/controllers/recipes_controller_test.rb
git commit -m "feat: add editor dialog markup and edit button to recipe page"
```

---

### Task 8: Editor CSS

**Files:**
- Modify: `app/assets/stylesheets/style.css`

**Step 1: Add dialog and editor styles**

Add the following to `style.css`, after the `.btn:focus-visible` block (after line 224) for the `btn-primary` variant, and before the print media query (before line 628) for the dialog styles:

After the `.btn:focus-visible` block (line 224), add the `btn-primary` variant:

```css
.btn-primary {
  background: var(--accent-color);
  color: white;
  border-color: var(--accent-color);
}

.btn-primary:hover {
  background: rgb(135, 8, 20);
  border-color: rgb(135, 8, 20);
}
```

Before the notification toast section (before line 569), add the editor dialog styles:

```css
/************************/
/* Recipe editor dialog */
/************************/

#recipe-editor {
  border: 1px solid var(--border-color);
  border-radius: 0.25rem;
  background: var(--content-background-color);
  padding: 0;
  width: min(90vw, 50rem);
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.15);
}

#recipe-editor::backdrop {
  background: rgba(0, 0, 0, 0.5);
}

.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--separator-color);
}

.editor-header h2 {
  font-family: "Futura", sans-serif;
  font-size: 1rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin: 0;
  border: none;
  padding: 0;
}

.editor-header .btn {
  font-size: 1.25rem;
  line-height: 1;
  padding: 0.2rem 0.5rem;
  border: none;
  background: none;
}

#editor-errors {
  padding: 0.75rem 1.5rem;
  color: var(--danger-color);
  font-family: "Futura", sans-serif;
  font-size: 0.85rem;
  border-bottom: 1px solid var(--separator-color);
}

#editor-errors ul {
  margin: 0;
  padding: 0 0 0 1.25rem;
}

#editor-textarea {
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

.editor-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 1rem 1.5rem;
  border-top: 1px solid var(--separator-color);
}

@media screen and (max-width: 600px) {
  #recipe-editor {
    width: 100vw;
    max-height: 100vh;
    height: 100vh;
    border-radius: 0;
  }
}
```

**Step 2: Also hide the editor dialog in print media**

In the `@media print` block (around line 648-649 where `nav, .notify-bar` are hidden), add `#recipe-editor`:

```css
nav,
.notify-bar,
#recipe-editor {
  display: none;
}
```

**Step 3: Verify visually**

Start the dev server, open a recipe page, and inspect the edit button and dialog styling. The dialog won't open yet (no JS), but you can verify the button is styled correctly.

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add editor dialog and btn-primary CSS"
```

---

### Task 9: Editor JavaScript

**Files:**
- Create: `app/assets/javascripts/recipe-editor.js`

**Step 1: Create the editor JavaScript**

Create `app/assets/javascripts/recipe-editor.js`:

```javascript
document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('recipe-editor');
  const editBtn = document.getElementById('edit-button');
  const closeBtn = document.getElementById('editor-close');
  const cancelBtn = document.getElementById('editor-cancel');
  const saveBtn = document.getElementById('editor-save');
  const textarea = document.getElementById('editor-textarea');
  const errorsDiv = document.getElementById('editor-errors');

  if (!dialog || !editBtn) return;

  const recipeSlug = document.body.dataset.recipeId;
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  let originalContent = textarea.value;

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

  // Open
  editBtn.addEventListener('click', () => {
    originalContent = textarea.value;
    clearErrors();
    dialog.showModal();
  });

  // Close buttons
  closeBtn.addEventListener('click', closeDialog);
  cancelBtn.addEventListener('click', closeDialog);

  // Escape key — intercept to check for unsaved changes
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
      const response = await fetch(`/recipes/${recipeSlug}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ markdown_source: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        window.location = data.redirect_url;
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

  // Warn on page navigation with unsaved changes
  window.addEventListener('beforeunload', (event) => {
    if (dialog.open && isModified()) {
      event.preventDefault();
    }
  });
});
```

**Step 2: Verify the JS file is picked up by Propshaft**

Start the dev server and check that the file is served:

```bash
curl -s http://localhost:3030/assets/recipe-editor.js | head -5
```

**Step 3: Commit**

```bash
git add app/assets/javascripts/recipe-editor.js
git commit -m "feat: add recipe editor JavaScript"
```

---

### Task 10: End-to-end integration test

**Files:**
- Modify: `test/integration/end_to_end_test.rb` or create a new test file

**Step 1: Write integration tests**

Add to the existing integration test file or create `test/controllers/recipes_controller_test.rb` (already has tests — add more). The controller tests in Task 5 already cover the `update` action. Let's add a round-trip test that verifies the full flow:

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'full edit round-trip: edit, save, re-render' do
  updated_markdown = <<~MD
    # Focaccia

    An updated description.

    Category: Bread
    Serves: 12

    ## Make the dough (combine ingredients)

    - Flour, 4 cups
    - Water, 1.5 cups: Warm.
    - Salt, 2 tsp
    - Olive oil, 3 tbsp

    Mix everything together and let rest for 2 hours.

    ## Bake (put it in the oven)

    Bake at 450 degrees for 25 minutes.

    ---

    Updated notes.
  MD

  # Save the edit
  patch recipe_path('focaccia'),
        params: { markdown_source: updated_markdown },
        as: :json

  assert_response :success

  # Re-render the page
  get recipe_path('focaccia')

  assert_response :success
  assert_select 'h1', 'Focaccia'
  assert_select '.recipe-meta', /Serves 12/
  assert_select '.ingredients li', 4
  assert_select 'b', 'Olive oil'
end
```

**Step 2: Run the test**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

**Step 3: Run the full test suite**

```bash
rake test
```

**Step 4: Run lint**

```bash
rake lint
```

Fix any RuboCop offenses.

**Step 5: Commit**

```bash
git add test/controllers/recipes_controller_test.rb
git commit -m "test: add full edit round-trip integration test"
```

---

### Task 11: Manual verification and polish

**Step 1: Start the dev server**

```bash
bin/dev
```

**Step 2: Open a recipe page in the browser**

Navigate to a recipe. Verify:
- Edit button appears next to Scale button
- Clicking Edit opens the dialog with markdown source
- The dialog has the dimmed backdrop
- Textarea is monospace, full-height
- Cancel closes without saving
- Escape prompts for unsaved changes (if modified)

**Step 3: Test saving an edit**

- Make a small change (e.g., edit the description)
- Click Save
- Page reloads with the updated content
- Scale state is reset (version hash changed)

**Step 4: Test validation**

- Open the editor
- Delete the Category line
- Click Save
- Verify error message appears in the dialog
- Dialog stays open

**Step 5: Test title change**

- Change the recipe title
- Save
- Verify the URL changes to the new slug
- Verify the old URL returns 404

**Step 6: Test mobile layout**

- Resize the browser to mobile width
- Verify the dialog is full-screen
- Verify the edit button is still accessible

**Step 7: Run seeds to verify protection**

```bash
rails db:seed
```

Verify that web-edited recipes show `[skipped]` in the output.

**Step 8: Final commit (if any polish changes were needed)**

```bash
git add -A
git commit -m "fix: editor polish and cleanup"
```

---

## Summary of all files touched

**Created:**
- `db/migrate/XXXXXX_add_edited_at_to_recipes.rb`
- `app/services/markdown_validator.rb`
- `test/services/markdown_validator_test.rb`
- `app/assets/javascripts/recipe-editor.js`

**Modified:**
- `db/schema.rb` (auto-updated by migration)
- `db/seeds.rb` (skip web-edited recipes)
- `app/views/layouts/application.html.erb` (CSRF meta tags)
- `config/routes.rb` (add `:update` to recipes)
- `app/controllers/recipes_controller.rb` (update action, fix recipe_map)
- `app/views/recipes/show.html.erb` (edit button, dialog, editor JS include)
- `app/assets/stylesheets/style.css` (dialog styles, btn-primary)
- `test/controllers/recipes_controller_test.rb` (new tests)

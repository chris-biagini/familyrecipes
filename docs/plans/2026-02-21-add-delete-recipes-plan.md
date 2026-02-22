# Add/Delete Recipe Workflow — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add create and delete recipe workflows with cross-reference maintenance on rename/delete.

**Architecture:** Extend `RecipesController` with `create` and `destroy` actions. Extract the editor dialog into a shared partial used by both the homepage (create) and recipe page (edit + delete). A new `CrossReferenceUpdater` service handles renaming and stripping `@[references]` across recipes. All endpoints return JSON with a `redirect_url`, consistent with the existing update action.

**Tech Stack:** Rails 8, PostgreSQL, vanilla JS, native `<dialog>`, Minitest

---

### Task 1: CrossReferenceUpdater service — strip_references

The service that removes `@[Title]` syntax (keeping plain `Title`) from recipes that reference a given recipe. Needed before a recipe can be destroyed.

**Files:**
- Create: `app/services/cross_reference_updater.rb`
- Test: `test/services/cross_reference_updater_test.rb`

**Step 1: Write the failing test**

```ruby
# test/services/cross_reference_updater_test.rb
# frozen_string_literal: true

require 'test_helper'

class CrossReferenceUpdaterTest < ActiveSupport::TestCase
  setup do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)

    @dough = MarkdownImporter.import(<<~MD)
      # Pizza Dough

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 3 cups

      Mix together.
    MD

    @pizza = MarkdownImporter.import(<<~MD)
      # Margherita Pizza

      Category: Bread

      ## Assemble (put it together)

      - @[Pizza Dough], 1 ball
      - Mozzarella, 8 oz

      Stretch dough and top.
    MD
  end

  test 'strip_references replaces @[Title] with plain Title in referencing recipes' do
    CrossReferenceUpdater.strip_references(@dough)

    @pizza.reload
    assert_includes @pizza.markdown_source, 'Pizza Dough'
    assert_not_includes @pizza.markdown_source, '@[Pizza Dough]'
  end

  test 'strip_references returns titles of updated recipes' do
    updated = CrossReferenceUpdater.strip_references(@dough)

    assert_includes updated, 'Margherita Pizza'
  end

  test 'strip_references removes inbound dependencies' do
    CrossReferenceUpdater.strip_references(@dough)

    assert_empty @dough.reload.inbound_dependencies
  end

  test 'strip_references is a no-op when no recipes reference this one' do
    updated = CrossReferenceUpdater.strip_references(@pizza)

    assert_empty updated
  end
end
```

**Step 2: Run the test to verify it fails**

```bash
rake test TEST=test/services/cross_reference_updater_test.rb
```

Expected: NameError — `CrossReferenceUpdater` not defined.

**Step 3: Write the implementation**

```ruby
# app/services/cross_reference_updater.rb
# frozen_string_literal: true

class CrossReferenceUpdater
  def self.strip_references(recipe)
    new(recipe).strip_references
  end

  def self.rename_references(old_title:, new_title:)
    slug = FamilyRecipes.slugify(old_title)
    recipe = Recipe.find_by(slug: slug)
    return [] unless recipe

    new(recipe).rename_references(new_title)
  end

  def initialize(recipe)
    @recipe = recipe
  end

  def strip_references
    update_referencing_recipes { |source, title| source.gsub("@[#{title}]", title) }
  end

  def rename_references(new_title)
    old_title = @recipe.title
    update_referencing_recipes { |source, _| source.gsub("@[#{old_title}]", "@[#{new_title}]") }
  end

  private

  def update_referencing_recipes(&block)
    referencing = @recipe.referencing_recipes.includes(:category)
    return [] if referencing.empty?

    referencing.map do |ref_recipe|
      updated_source = block.call(ref_recipe.markdown_source, @recipe.title)
      MarkdownImporter.import(updated_source)
      ref_recipe.title
    end
  end
end
```

**Step 4: Run the test to verify it passes**

```bash
rake test TEST=test/services/cross_reference_updater_test.rb
```

Expected: all 4 tests pass.

**Step 5: Commit**

```bash
git add app/services/cross_reference_updater.rb test/services/cross_reference_updater_test.rb
git commit -m "feat: add CrossReferenceUpdater#strip_references"
```

---

### Task 2: CrossReferenceUpdater — rename_references

Add `rename_references` and wire it into the existing update action with toast support.

**Files:**
- Modify: `app/services/cross_reference_updater.rb` (already created)
- Modify: `app/controllers/recipes_controller.rb:12-26` (update action)
- Test: `test/services/cross_reference_updater_test.rb` (add tests)
- Test: `test/controllers/recipes_controller_test.rb` (add test)

**Step 1: Write the failing tests**

Append to `test/services/cross_reference_updater_test.rb`:

```ruby
  test 'rename_references updates @[Old] to @[New] in referencing recipes' do
    CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough')

    @pizza.reload
    assert_includes @pizza.markdown_source, '@[Neapolitan Dough]'
    assert_not_includes @pizza.markdown_source, '@[Pizza Dough]'
  end

  test 'rename_references returns titles of updated recipes' do
    updated = CrossReferenceUpdater.rename_references(old_title: 'Pizza Dough', new_title: 'Neapolitan Dough')

    assert_includes updated, 'Margherita Pizza'
  end
```

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
  test 'update returns updated_references when title changes and cross-references exist' do
    # Create a recipe that references Focaccia
    MarkdownImporter.import(<<~MD)
      # Panzanella

      Category: Bread

      ## Assemble (put it together)

      - @[Focaccia], 1 loaf: Day-old.
      - Tomatoes, 3

      Tear bread and toss with tomatoes.
    MD

    updated_markdown = <<~MD
      # Rosemary Focaccia

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

    assert_includes body['updated_references'], 'Panzanella'

    panzanella = Recipe.find_by!(slug: 'panzanella')
    assert_includes panzanella.markdown_source, '@[Rosemary Focaccia]'
    assert_not_includes panzanella.markdown_source, '@[Focaccia]'
  end
```

**Step 2: Run tests to verify they fail**

```bash
rake test TEST=test/services/cross_reference_updater_test.rb
rake test TEST=test/controllers/recipes_controller_test.rb TESTOPTS="--name='/updated_references/'"
```

Expected: service tests pass (rename_references is already implemented in Task 1). Controller test fails — `updated_references` not in JSON response.

**Step 3: Wire rename_references into the update action**

Modify `app/controllers/recipes_controller.rb` update action (lines 12-26):

```ruby
  def update
    @recipe = Recipe.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source])
    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    updated_references = title_changed?(old_title, recipe.title) ?
      CrossReferenceUpdater.rename_references(old_title: old_title, new_title: recipe.title) : []

    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
```

Add private helper:

```ruby
  def title_changed?(old_title, new_title)
    old_title != new_title
  end
```

**Step 4: Run all tests**

```bash
rake test TEST=test/services/cross_reference_updater_test.rb test/controllers/recipes_controller_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add app/services/cross_reference_updater.rb app/controllers/recipes_controller.rb \
       test/services/cross_reference_updater_test.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: rename cross-references when recipe title changes"
```

---

### Task 3: Change inbound_dependencies to dependent: :destroy

Now that `CrossReferenceUpdater` strips references before deletion, the `:restrict_with_error` constraint is no longer needed. Change it to `:destroy` as a safety net.

**Files:**
- Modify: `app/models/recipe.rb:14-16`

**Step 1: Run existing tests to verify green baseline**

```bash
rake test
```

**Step 2: Change the dependent strategy**

In `app/models/recipe.rb`, change line 15:

```ruby
  # Before:
  has_many :inbound_dependencies, class_name: 'RecipeDependency',
                                  foreign_key: :target_recipe_id,
                                  dependent: :restrict_with_error,
                                  inverse_of: :target_recipe

  # After:
  has_many :inbound_dependencies, class_name: 'RecipeDependency',
                                  foreign_key: :target_recipe_id,
                                  dependent: :destroy,
                                  inverse_of: :target_recipe
```

**Step 3: Run tests to verify nothing breaks**

```bash
rake test
```

Expected: all pass.

**Step 4: Commit**

```bash
git add app/models/recipe.rb
git commit -m "fix: change inbound_dependencies to dependent: :destroy

CrossReferenceUpdater now strips references before deletion, so the
restrict_with_error guard is no longer needed."
```

---

### Task 4: Routes — add create and destroy

**Files:**
- Modify: `config/routes.rb:6`

**Step 1: Update routes**

Change line 6 from:

```ruby
  resources :recipes, only: %i[show update], param: :slug
```

to:

```ruby
  resources :recipes, only: %i[show create update destroy], param: :slug
```

**Step 2: Verify routes exist**

```bash
rails routes | grep recipes
```

Expected: POST /recipes, DELETE /recipes/:slug appear alongside existing GET and PATCH.

**Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add create and destroy recipe routes"
```

---

### Task 5: RecipesController#create

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Write failing tests**

Append to `test/controllers/recipes_controller_test.rb`:

```ruby
  test 'create saves valid markdown and returns redirect URL' do
    markdown = <<~MD
      # Ciabatta

      A rustic bread.

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 4 cups
      - Water, 2 cups

      Mix and rest overnight.
    MD

    post recipes_path,
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal recipe_path('ciabatta'), body['redirect_url']
    assert Recipe.find_by(slug: 'ciabatta')
  end

  test 'create rejects invalid markdown' do
    post recipes_path,
         params: { markdown_source: 'not valid' },
         as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)

    assert_predicate body['errors'], :any?
  end

  test 'create sets edited_at timestamp' do
    markdown = <<~MD
      # Ciabatta

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 4 cups

      Mix it.
    MD

    post recipes_path,
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    assert_not_nil Recipe.find_by!(slug: 'ciabatta').edited_at
  end
```

**Step 2: Run tests to verify they fail**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb TESTOPTS="--name='/create/'"
```

Expected: fail — `create` action not defined.

**Step 3: Add create action**

In `app/controllers/recipes_controller.rb`, add after the `show` method (line 10):

```ruby
  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source])
    recipe.update!(edited_at: Time.current)

    render json: { redirect_url: recipe_path(recipe.slug) }
  end
```

**Step 4: Run tests**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: add RecipesController#create"
```

---

### Task 6: RecipesController#destroy

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Write failing tests**

Append to `test/controllers/recipes_controller_test.rb`:

```ruby
  test 'destroy deletes recipe and returns redirect to homepage' do
    delete recipe_path('focaccia'), as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal root_path, body['redirect_url']
    assert_nil Recipe.find_by(slug: 'focaccia')
  end

  test 'destroy cleans up empty categories' do
    delete recipe_path('focaccia'), as: :json

    assert_response :success
    assert_nil Category.find_by(slug: 'bread')
  end

  test 'destroy strips cross-references from referencing recipes' do
    MarkdownImporter.import(<<~MD)
      # Panzanella

      Category: Bread

      ## Assemble (put it together)

      - @[Focaccia], 1 loaf
      - Tomatoes, 3

      Tear bread and toss.
    MD

    delete recipe_path('focaccia'), as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_includes body['updated_references'], 'Panzanella'

    panzanella = Recipe.find_by!(slug: 'panzanella')
    assert_includes panzanella.markdown_source, 'Focaccia'
    assert_not_includes panzanella.markdown_source, '@[Focaccia]'
  end

  test 'destroy returns 404 for unknown recipe' do
    delete recipe_path('nonexistent'), as: :json

    assert_response :not_found
  end
```

**Step 2: Run tests to verify they fail**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb TESTOPTS="--name='/destroy/'"
```

Expected: fail — `destroy` action not defined.

**Step 3: Add destroy action**

In `app/controllers/recipes_controller.rb`, add after the `update` method:

```ruby
  def destroy
    @recipe = Recipe.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    @recipe.destroy!
    Category.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: root_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
```

**Step 4: Run tests**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: add RecipesController#destroy with cross-reference cleanup"
```

---

### Task 7: Extract editor dialog partial

Extract the `<dialog>` from `recipes/show.html.erb` into a shared partial that supports both create and edit modes.

**Files:**
- Create: `app/views/recipes/_editor_dialog.html.erb`
- Modify: `app/views/recipes/show.html.erb:51-62`
- Test: `test/controllers/recipes_controller_test.rb` (existing tests verify dialog markup)

**Step 1: Run existing tests for green baseline**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

**Step 2: Create the shared partial**

```erb
<%# app/views/recipes/_editor_dialog.html.erb %>
<%# locals: (mode:, content:, action_url:, recipe: nil) %>
<dialog id="recipe-editor"
        data-editor-mode="<%= mode %>"
        data-editor-url="<%= action_url %>">
  <div class="editor-header">
    <h2><%= mode == :create ? 'New Recipe' : "Editing: #{recipe.title}" %></h2>
    <button type="button" class="btn" id="editor-close" aria-label="Close">&times;</button>
  </div>
  <div id="editor-errors" hidden></div>
  <textarea id="editor-textarea" spellcheck="false"><%= content %></textarea>
  <div class="editor-footer">
    <%- if mode == :edit -%>
    <button type="button" class="btn btn-danger" id="editor-delete"
            data-recipe-title="<%= recipe.title %>"
            data-recipe-slug="<%= recipe.slug %>"
            data-referencing-recipes="<%= recipe.referencing_recipes.pluck(:title).to_json %>">Delete</button>
    <span class="editor-footer-spacer"></span>
    <%- end -%>
    <button type="button" class="btn" id="editor-cancel">Cancel</button>
    <button type="button" class="btn btn-primary" id="editor-save">Save</button>
  </div>
</dialog>
```

**Step 3: Update recipes/show.html.erb to use the partial**

Replace lines 51-62 with:

```erb
<%= render 'editor_dialog',
           mode: :edit,
           content: @recipe.markdown_source,
           action_url: recipe_path(@recipe.slug),
           recipe: @recipe %>
```

**Step 4: Run existing tests to verify nothing broke**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

Expected: all pass — the dialog structure is the same, just extracted.

**Step 5: Commit**

```bash
git add app/views/recipes/_editor_dialog.html.erb app/views/recipes/show.html.erb
git commit -m "refactor: extract editor dialog into shared partial"
```

---

### Task 8: Homepage "New" button and create dialog

Add the "+ New" button and editor dialog to the homepage.

**Files:**
- Modify: `app/views/homepage/show.html.erb`
- Test: `test/controllers/homepage_controller_test.rb` (or `test/integration/end_to_end_test.rb`)

**Step 1: Write failing test**

Add to the homepage tests (find the appropriate test file — likely `test/integration/end_to_end_test.rb` or create `test/controllers/homepage_controller_test.rb`):

```ruby
  test 'homepage renders new recipe button' do
    get root_path

    assert_select '#new-recipe-button'
  end

  test 'homepage renders editor dialog in create mode' do
    get root_path

    assert_select '#recipe-editor[data-editor-mode="create"]'
    assert_select '#editor-textarea'
  end
```

**Step 2: Run to verify failure**

```bash
rake test TESTOPTS="--name='/homepage renders new/'"
```

**Step 3: Add button and dialog to homepage view**

In `app/views/homepage/show.html.erb`, add before line 2 (`<article>`):

```erb
<% content_for(:extra_nav) do %>
    <div>
      <button type="button" id="new-recipe-button" class="btn">+ New</button>
    </div>
<% end %>

<% content_for(:scripts) do %>
  <%= javascript_include_tag 'notify', defer: true %>
  <%= javascript_include_tag 'recipe-editor', defer: true %>
<% end %>
```

After the closing `</article>` tag (line 31), add:

```erb
<%= render 'recipes/editor_dialog',
           mode: :create,
           content: "# Recipe Title\n\nOptional description.\n\nCategory: \nMakes: \nServes: \n\n## Step Name (short summary)\n\n- Ingredient, quantity: prep note\n\nInstructions here.\n\n---\n\nOptional notes or source.",
           action_url: recipes_path %>
```

**Step 4: Run tests**

```bash
rake test
```

Expected: all pass.

**Step 5: Commit**

```bash
git add app/views/homepage/show.html.erb
git commit -m "feat: add New Recipe button and create dialog to homepage"
```

---

### Task 9: CSS for delete button and editor footer layout

Add `.btn-danger` styling and adjust the editor footer to push Delete left and Cancel/Save right.

**Files:**
- Modify: `app/assets/stylesheets/style.css:664-670`

**Step 1: Add CSS**

After the `.btn-primary:hover` rule (line 237), add:

```css
.btn-danger {
  color: var(--danger-color);
  border-color: var(--danger-color);
}

.btn-danger:hover {
  background: var(--danger-color);
  color: white;
  border-color: var(--danger-color);
}
```

Update the `.editor-footer` rule (line 664) to support the spacer:

```css
.editor-footer {
  display: flex;
  gap: 0.5rem;
  padding: 1rem 1.5rem;
  border-top: 1px solid var(--separator-color);
}

.editor-footer-spacer {
  flex: 1;
}
```

Note: Remove `justify-content: flex-end` from `.editor-footer` — the spacer handles positioning. When there's no delete button (create mode), Cancel and Save will naturally align left, which is fine, but if you want them right-aligned in both modes, wrap Cancel+Save in a `<span>` with `margin-left: auto` instead. The spacer approach is simpler.

Actually, keep it simpler: use `margin-left: auto` on the Cancel button when there's no delete button. The spacer element in the partial handles edit mode. For create mode without the spacer, add:

```css
.editor-footer .btn:nth-last-child(2):first-child {
  margin-left: auto;
}
```

Wait — that's getting overly clever. Simpler approach: always include the spacer in the partial (even in create mode), or just use `justify-content: flex-end` by default and override with the spacer. Let's keep the spacer only in edit mode and rely on `justify-content: flex-end` for create mode:

```css
.editor-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 1rem 1.5rem;
  border-top: 1px solid var(--separator-color);
}

.editor-footer-spacer {
  flex: 1;
}
```

This works because: in create mode there's no spacer, so `justify-content: flex-end` pushes Cancel+Save right. In edit mode, the spacer element has `flex: 1`, which overrides the justify-content and pushes Cancel+Save right while Delete stays left.

**Step 2: Verify visually**

Start the dev server and check both the homepage dialog (create mode) and a recipe page dialog (edit mode).

**Step 3: Run lint**

```bash
rake lint
```

**Step 4: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: add btn-danger style and editor footer layout for delete button"
```

---

### Task 10: Update recipe-editor.js for create, delete, and toast

Rework the JS to handle all three modes: create (POST), edit (PATCH), and delete (DELETE). Add toast support for cross-reference updates.

**Files:**
- Modify: `app/assets/javascripts/recipe-editor.js`

**Step 1: Rewrite recipe-editor.js**

```javascript
document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.getElementById('recipe-editor');
  if (!dialog) return;

  const mode = dialog.dataset.editorMode;           // 'create' or 'edit'
  const actionUrl = dialog.dataset.editorUrl;        // POST or PATCH target
  const openBtn = mode === 'create'
    ? document.getElementById('new-recipe-button')
    : document.getElementById('edit-button');
  const closeBtn = document.getElementById('editor-close');
  const cancelBtn = document.getElementById('editor-cancel');
  const saveBtn = document.getElementById('editor-save');
  const deleteBtn = document.getElementById('editor-delete');
  const textarea = document.getElementById('editor-textarea');
  const errorsDiv = document.getElementById('editor-errors');

  if (!openBtn) return;

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

  // Open
  openBtn.addEventListener('click', () => {
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

  // Save (create or update)
  saveBtn.addEventListener('click', async () => {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving\u2026';
    clearErrors();

    const method = mode === 'create' ? 'POST' : 'PATCH';

    try {
      const response = await fetch(actionUrl, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify({ markdown_source: textarea.value })
      });

      if (response.ok) {
        const data = await response.json();
        saving = true;

        // Pass updated_references via URL param for toast on next page
        let redirectUrl = data.redirect_url;
        if (data.updated_references && data.updated_references.length > 0) {
          const param = encodeURIComponent(data.updated_references.join(', '));
          const separator = redirectUrl.includes('?') ? '&' : '?';
          redirectUrl += `${separator}refs_updated=${param}`;
        }
        window.location = redirectUrl;
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

  // Delete (edit mode only)
  if (deleteBtn) {
    deleteBtn.addEventListener('click', async () => {
      const title = deleteBtn.dataset.recipeTitle;
      const slug = deleteBtn.dataset.recipeSlug;
      const referencingRaw = deleteBtn.dataset.referencingRecipes;
      const referencing = JSON.parse(referencingRaw || '[]');

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

  // Show toast for cross-reference updates (from URL param)
  const params = new URLSearchParams(window.location.search);
  const refsUpdated = params.get('refs_updated');
  if (refsUpdated && typeof Notify !== 'undefined') {
    Notify.show(`Updated references in ${refsUpdated}.`);
    // Clean URL without reloading
    const cleanUrl = window.location.pathname + window.location.hash;
    history.replaceState(null, '', cleanUrl);
  }
});
```

**Step 2: Verify the existing edit tests still pass**

```bash
rake test TEST=test/controllers/recipes_controller_test.rb
```

**Step 3: Start dev server and test manually**

```bash
bin/dev
```

- Visit homepage → click "+ New" → dialog opens in create mode → type a recipe → Save → redirects to new recipe page
- Visit a recipe → click "Edit" → dialog opens in edit mode with Delete button → change title → Save → cross-references toast appears
- Visit a recipe → click "Edit" → click Delete → confirm → redirects to homepage

**Step 4: Commit**

```bash
git add app/assets/javascripts/recipe-editor.js
git commit -m "feat: update recipe-editor.js for create, delete, and rename toast"
```

---

### Task 11: Integration tests for create and delete flows

Add end-to-end integration tests covering the full create and delete workflows.

**Files:**
- Modify: `test/integration/end_to_end_test.rb`

**Step 1: Add integration tests**

```ruby
  test 'new recipe button appears on homepage' do
    get root_path

    assert_select '#new-recipe-button'
    assert_select '#recipe-editor[data-editor-mode="create"]'
  end

  test 'create and then visit new recipe' do
    markdown = <<~MD
      # Sourdough Boule

      A tangy loaf.

      Category: Bread

      ## Mix (combine ingredients)

      - Flour, 4 cups
      - Starter, 1 cup

      Mix and bulk ferment.
    MD

    post recipes_path,
         params: { markdown_source: markdown },
         as: :json

    assert_response :success
    body = JSON.parse(response.body)

    get body['redirect_url']

    assert_response :success
    assert_select 'h1', 'Sourdough Boule'
  end

  test 'delete recipe removes it from homepage' do
    get root_path
    assert_select 'a', text: 'Focaccia'

    delete recipe_path('focaccia'), as: :json

    assert_response :success

    get root_path
    assert_select 'a', text: 'Focaccia', count: 0
  end
```

**Step 2: Run integration tests**

```bash
rake test TEST=test/integration/end_to_end_test.rb
```

Expected: all pass.

**Step 3: Run full test suite**

```bash
rake test
```

Expected: all pass.

**Step 4: Run lint**

```bash
rake lint
```

Expected: clean.

**Step 5: Commit**

```bash
git add test/integration/end_to_end_test.rb
git commit -m "test: add integration tests for create and delete recipe workflows"
```

---

### Task 12: Final verification

**Step 1: Run full test suite and lint**

```bash
rake
```

Expected: lint clean, all tests pass.

**Step 2: Manual smoke test**

Start `bin/dev` and verify:

1. Homepage shows "+ New" button in nav
2. Click "+ New" → dialog opens with template → fill in recipe → Save → redirected to new recipe page
3. New recipe appears on homepage
4. Click "Edit" on new recipe → Delete button visible at bottom-left → click Delete → confirm → redirected to homepage → recipe gone
5. Create a recipe referencing another → edit the referenced recipe's title → toast shows which recipes were updated
6. Delete a recipe that's cross-referenced → confirm dialog mentions affected recipes → after delete, referencing recipes have plain text instead of `@[links]`

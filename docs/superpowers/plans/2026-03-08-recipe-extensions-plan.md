# Recipe .md and .html Extensions — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Serve raw markdown and rendered HTML for any recipe via `.md` and `.html` URL extensions.

**Architecture:** Two explicit routes (`recipes/:slug.md`, `recipes/:slug.html`) inside the existing kitchen scope, pointing to new actions on `RecipesController`. Raw markdown served as `text/plain; charset=utf-8`. Rendered HTML uses the existing `FamilyRecipes::Recipe::MARKDOWN` Redcarpet instance, wrapped in a minimal HTML document.

**Tech Stack:** Rails routes, RecipesController, Redcarpet (already in Gemfile), Minitest integration tests.

---

### Task 1: Add routes

**Files:**
- Modify: `config/routes.rb:21-22`

**Step 1: Add the two routes inside the kitchen scope, above `resources :recipes`**

```ruby
scope '(/kitchens/:kitchen_slug)' do
  get 'recipes/:slug.md', to: 'recipes#show_markdown', as: :recipe_markdown, defaults: { format: 'text' }
  get 'recipes/:slug.html', to: 'recipes#show_html', as: :recipe_html, defaults: { format: 'html' }
  resources :recipes, only: %i[show create update destroy], param: :slug
```

**Step 2: Verify routes are recognized**

Run: `bin/rails routes | grep recipe_markdown`
Expected: route pointing to `recipes#show_markdown`

Run: `bin/rails routes | grep recipe_html`
Expected: route pointing to `recipes#show_html`

**Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add .md and .html routes for recipes (#205)"
```

---

### Task 2: Write failing tests for show_markdown

**Files:**
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing tests**

Add these tests to `RecipesControllerTest`:

```ruby
test 'show_markdown serves raw markdown as text/plain UTF-8' do
  get recipe_markdown_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_equal 'text/plain; charset=utf-8', response.content_type
  assert_equal @kitchen.recipes.find_by!(slug: 'focaccia').markdown_source, response.body
end

test 'show_markdown returns 404 for unknown recipe' do
  get recipe_markdown_path('nonexistent', kitchen_slug: kitchen_slug)

  assert_response :not_found
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /show_markdown/`
Expected: FAIL — `show_markdown` action not defined

**Step 3: Commit**

```bash
git add test/controllers/recipes_controller_test.rb
git commit -m "test: add failing tests for show_markdown (#205)"
```

---

### Task 3: Implement show_markdown

**Files:**
- Modify: `app/controllers/recipes_controller.rb`

**Step 1: Add the show_markdown action**

Add after the `show` action:

```ruby
def show_markdown
  recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  render plain: recipe.markdown_source, content_type: 'text/plain; charset=utf-8'
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /show_markdown/`
Expected: PASS

**Step 3: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "feat: implement show_markdown action (#205)"
```

---

### Task 4: Write failing tests for show_html

**Files:**
- Modify: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
test 'show_html serves rendered markdown as minimal HTML document' do
  get recipe_html_path('focaccia', kitchen_slug: kitchen_slug)

  assert_response :success
  assert_equal 'text/html; charset=utf-8', response.content_type
  assert_includes response.body, '<!DOCTYPE html>'
  assert_includes response.body, '<meta charset="utf-8">'
  assert_includes response.body, '<title>Focaccia</title>'
  assert_includes response.body, '<h2>'
  assert_not_includes response.body, '<script'
  assert_not_includes response.body, '<link'
end

test 'show_html returns 404 for unknown recipe' do
  get recipe_html_path('nonexistent', kitchen_slug: kitchen_slug)

  assert_response :not_found
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /show_html/`
Expected: FAIL — `show_html` action not defined

**Step 3: Commit**

```bash
git add test/controllers/recipes_controller_test.rb
git commit -m "test: add failing tests for show_html (#205)"
```

---

### Task 5: Implement show_html

**Files:**
- Modify: `app/controllers/recipes_controller.rb`

**Step 1: Add the show_html action**

Add after `show_markdown`:

```ruby
def show_html
  recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  rendered = FamilyRecipes::Recipe::MARKDOWN.render(recipe.markdown_source)
  html = <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>#{ERB::Util.html_escape(recipe.title)}</title>
    </head>
    <body>
    #{rendered}
    </body>
    </html>
  HTML
  render html: html.html_safe, layout: false # rubocop:disable Rails/OutputSafety
end
```

Note: `rendered` comes from Redcarpet with `escape_html: true`, so user content in the markdown is already escaped. The title is escaped via `ERB::Util.html_escape`.

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /show_html/`
Expected: PASS

**Step 3: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "feat: implement show_html action (#205)"
```

---

### Task 6: Update html_safe allowlist and run full test suite

**Files:**
- Modify: `config/html_safe_allowlist.yml` (update line number for new `.html_safe` call)

**Step 1: Run the html_safe lint**

Run: `rake lint:html_safe`
Expected: may flag the new `.html_safe` in `show_html`

**Step 2: Update allowlist if needed**

Add the new `recipes_controller.rb:<line>` entry to `config/html_safe_allowlist.yml`.

**Step 3: Run full test suite**

Run: `rake test`
Expected: all tests pass

**Step 4: Run linter**

Run: `rake lint`
Expected: no offenses

**Step 5: Commit**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for show_html (#205)"
```

---

### Task 7: Update architectural comment on RecipesController

**Files:**
- Modify: `app/controllers/recipes_controller.rb:1-6`

**Step 1: Update the header comment**

Update the controller's architectural comment to mention the new actions:

```ruby
# Thin HTTP adapter for recipe CRUD and raw exports. Show is public; writes
# require membership. Validates Markdown params, delegates to RecipeWriteService
# for orchestration, and renders JSON responses for writes. Also serves raw
# markdown (.md) and rendered HTML (.html) as easter-egg endpoints — no UI
# links to these. All domain logic (import, broadcast, cleanup) lives in the
# service.
```

**Step 2: Run linter**

Run: `rake lint`
Expected: no offenses

**Step 3: Commit**

```bash
git add app/controllers/recipes_controller.rb
git commit -m "docs: update RecipesController header comment (#205)"
```

# Slug Collision Detection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Prevent silent overwrites when two recipes with different titles slugify to the same value.

**Architecture:** Add a `SlugCollisionError` to `MarkdownImporter` that fires when `find_or_initialize_by(slug:)` finds a persisted recipe whose title differs from the incoming title. Callers already rescue errors — no new error handling needed in controllers or ImportService.

**Tech Stack:** Ruby, Rails, Minitest

---

### Task 1: Add SlugCollisionError and collision check to MarkdownImporter

**Files:**
- Modify: `app/services/markdown_importer.rb:61-64`
- Test: `test/services/markdown_importer_test.rb`

**Step 1: Write the failing tests**

Add to `test/services/markdown_importer_test.rb`:

```ruby
test 'raises SlugCollisionError when slug matches but title differs' do
  MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

  colliding_markdown = BASIC_RECIPE.sub('# Focaccia', '# Focaccia!')

  error = assert_raises(MarkdownImporter::SlugCollisionError) do
    MarkdownImporter.import(colliding_markdown, kitchen: @kitchen, category: @bread)
  end
  assert_includes error.message, 'Focaccia'
end

test 'same-title reimport still works after collision check' do
  first = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)
  second = MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen, category: @bread)

  assert_equal first.id, second.id
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n /collision|reimport/`
Expected: FAIL — `SlugCollisionError` not defined

**Step 3: Implement SlugCollisionError and collision check**

In `app/services/markdown_importer.rb`, add the error class inside `MarkdownImporter`:

```ruby
class MarkdownImporter
  class SlugCollisionError < RuntimeError; end
```

Replace `find_or_initialize_recipe`:

```ruby
def find_or_initialize_recipe
  slug = FamilyRecipes.slugify(parsed[:title])
  recipe = kitchen.recipes.find_or_initialize_by(slug: slug)
  check_slug_collision!(recipe)
  recipe
end

def check_slug_collision!(recipe)
  return unless recipe.persisted?
  return if recipe.title == parsed[:title]

  raise SlugCollisionError,
    "A recipe with a similar name already exists: '#{recipe.title}'"
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: ALL PASS

**Step 5: Commit**

```bash
git add app/services/markdown_importer.rb test/services/markdown_importer_test.rb
git commit -m "feat: raise SlugCollisionError on title-mismatched slug collision (#197)"
```

---

### Task 2: Add collision tests to RecipeWriteService and RecipesController

**Files:**
- Test: `test/services/recipe_write_service_test.rb`
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Write the RecipeWriteService collision tests**

Add to `test/services/recipe_write_service_test.rb`:

```ruby
test 'create raises SlugCollisionError when slug collides with different title' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

  colliding = BASIC_MARKDOWN.sub('# Focaccia', '# Focaccia!')

  assert_raises(MarkdownImporter::SlugCollisionError) do
    RecipeWriteService.create(markdown: colliding, kitchen: @kitchen, category_name: 'Bread')
  end
end

test 'update raises SlugCollisionError when renamed title collides with another recipe' do
  RecipeWriteService.create(markdown: BASIC_MARKDOWN, kitchen: @kitchen, category_name: 'Bread')

  other_md = <<~MD
    # Ciabatta

    ## Mix (combine)

    - Flour, 4 cups

    Mix.
  MD
  RecipeWriteService.create(markdown: other_md, kitchen: @kitchen, category_name: 'Bread')

  # Rename Ciabatta to "Focaccia!" which slugifies to "focaccia" — collision
  renamed = other_md.sub('# Ciabatta', '# Focaccia!')

  assert_raises(MarkdownImporter::SlugCollisionError) do
    RecipeWriteService.update(slug: 'ciabatta', markdown: renamed, kitchen: @kitchen, category_name: 'Bread')
  end
end
```

**Step 2: Write the RecipesController collision tests**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'create returns 422 when slug collides with different title' do
  colliding = <<~MD
    # Focaccia!

    ## Mix (do it)

    - Flour, 1 cup

    Mix.
  MD

  log_in
  post recipes_path(kitchen_slug: kitchen_slug),
       params: { markdown_source: colliding, category: 'Bread' },
       as: :json

  assert_response :unprocessable_entity
  body = response.parsed_body
  assert body['errors'].any? { |e| e.include?('Focaccia') }
end

test 'update returns 422 when renamed title collides with another recipe' do
  MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @bread)
    # Ciabatta

    ## Mix (combine)

    - Flour, 4 cups

    Mix.
  MD

  # Rename Ciabatta to "Focaccia!" — collides with existing "Focaccia"
  colliding = <<~MD
    # Focaccia!

    ## Mix (do it)

    - Flour, 1 cup

    Mix.
  MD

  log_in
  patch recipe_path('ciabatta', kitchen_slug: kitchen_slug),
        params: { markdown_source: colliding, category: 'Bread' },
        as: :json

  assert_response :unprocessable_entity
  body = response.parsed_body
  assert body['errors'].any? { |e| e.include?('Focaccia') }
end
```

**Step 3: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_test.rb -n /collision|collides/`
Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /collid/`
Expected: ALL PASS

**Step 4: Commit**

```bash
git add test/services/recipe_write_service_test.rb test/controllers/recipes_controller_test.rb
git commit -m "test: slug collision propagation through service and controller (#197)"
```

---

### Task 3: Update ImportService tests for collision skip-and-report

**Files:**
- Modify: `test/services/import_service_test.rb`

**Step 1: Update the existing overwrite test and add collision tests**

The existing test `'overwrites existing recipe on slug conflict'` (line 40-47) tests
same-title reimport. Rename it for clarity and add new collision tests:

```ruby
test 'same-title reimport overwrites existing recipe' do
  RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

  result = import_files(uploaded_file('Pancakes.md', simple_recipe('Pancakes')))

  assert_equal 1, result.recipes
  assert_equal 1, @kitchen.recipes.where(title: 'Pancakes').count
end

test 'single file import reports collision as error when slug matches different title' do
  RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

  result = import_files(uploaded_file('Pancakes!.md', simple_recipe('Pancakes!')))

  assert_equal 0, result.recipes
  assert_equal 1, result.errors.size
  assert_match(/similar name already exists/, result.errors.first)
  assert_equal 'Pancakes', @kitchen.recipes.find_by(slug: 'pancakes').title
end

test 'ZIP import skips colliding recipe and reports error' do
  RecipeWriteService.create(markdown: simple_recipe('Pancakes'), kitchen: @kitchen)

  zip = build_zip('Bread/Pancakes!.md' => simple_recipe('Pancakes!'))
  result = import_files(uploaded_file('export.zip', zip))

  assert_equal 0, result.recipes
  assert_equal 1, result.errors.size
  assert_match(/similar name already exists/, result.errors.first)
end

test 'ZIP with internal slug collision skips second file and reports error' do
  zip = build_zip(
    'Bread/Cookies.md' => simple_recipe('Cookies'),
    'Desserts/Cookies!.md' => simple_recipe('Cookies!')
  )
  result = import_files(uploaded_file('export.zip', zip))

  assert_equal 1, result.recipes
  assert_equal 1, result.errors.size
  assert_match(/similar name already exists/, result.errors.first)
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/import_service_test.rb`
Expected: ALL PASS

**Step 3: Run full test suite**

Run: `rake test`
Expected: ALL PASS, 0 failures

**Step 4: Commit**

```bash
git add test/services/import_service_test.rb
git commit -m "test: slug collision skip-and-report for import service (#197)"
```

# Write Path Simplification Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop `markdown_source` column, unify dual import paths, and make AR records the acknowledged sole source of truth.

**Architecture:** Both editor paths (markdown and IR) converge after the IR stage. MarkdownImporter works from the IR hash; markdown is generated on demand by RecipeSerializer. RecipeWriteService's four-method duplication collapses to two methods plus shared internals.

**Tech Stack:** Rails 8, SQLite, Minitest

**Spec:** `docs/plans/2026-03-16-write-path-simplification-design.md`

**Ordering note:** The migration drops the column first (after removing the model validation),
so that subsequent code changes don't hit the `NOT NULL` database constraint. Tests that
create Recipe records with `markdown_source:` will fail after the migration — those are fixed
in Tasks 5-6.

---

## Chunk 1: Migration and Model

### Task 1: Recipe model — remove validation and update comment

**Files:**
- Modify: `app/models/recipe.rb:4,35`

- [ ] **Step 1: Remove the validation and update the header comment**

In `app/models/recipe.rb`, remove line 35:
```ruby
validates :markdown_source, presence: true
```

Update the header comment (lines 3-6) from:
```ruby
# Persistent recipe record, populated by MarkdownImporter from parsed Markdown.
# Stores the original markdown_source plus pre-computed data (nutrition_data JSON,
# processed instructions with scalable number markup). Views render entirely from
# this model and its associations — the parser is never invoked on the read path.
```
to:
```ruby
# Persistent recipe record, populated by MarkdownImporter from parsed Markdown
# or IR hashes. AR records are the sole source of truth — markdown is generated
# on demand by RecipeSerializer for export and editor loading. Views render from
# this model and its associations; the parser runs only on the write path.
```

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `rake test`
Expected: All tests pass (existing tests always provide `markdown_source`, so removing
the Rails validation has no effect yet).

- [ ] **Step 3: Commit**

```bash
git add app/models/recipe.rb
git commit -m "refactor: remove markdown_source validation from Recipe model"
```

---

### Task 2: Migration — drop the column

The column must go before code stops writing it, because the DB has `null: false`.

**Files:**
- Create: `db/migrate/005_drop_markdown_source.rb`

- [ ] **Step 1: Create the migration**

```ruby
# frozen_string_literal: true

class DropMarkdownSource < ActiveRecord::Migration[8.0]
  def change
    remove_column :recipes, :markdown_source, :text, null: false
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `rails db:migrate`
Expected: Column dropped, `schema.rb` updated.

- [ ] **Step 3: Run tests — expect failures**

Run: `rake test`
Expected: Many failures — tests that pass `markdown_source:` to `Recipe.create!` get
`ActiveModel::UnknownAttributeError`, and code that reads `recipe.markdown_source` gets
`NoMethodError`. This is expected; we fix everything in Tasks 3-8.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/005_drop_markdown_source.rb db/schema.rb
git commit -m "migrate: drop markdown_source column from recipes"
```

---

## Chunk 2: Code Changes

### Task 3: MarkdownImporter — stop storing markdown, simplify structure path

**Files:**
- Modify: `app/services/markdown_importer.rb`

- [ ] **Step 1: Simplify `import_from_structure` to pass IR directly**

Replace `import_from_structure` (lines 23-25):
```ruby
def self.import_from_structure(ir_hash, kitchen:, category:)
  markdown_source = FamilyRecipes::RecipeSerializer.serialize(ir_hash)
  new(markdown_source, kitchen:, category:, parsed: ir_hash).run
end
```
with:
```ruby
def self.import_from_structure(ir_hash, kitchen:, category:)
  new(kitchen:, category:, parsed: ir_hash).run
end
```

- [ ] **Step 2: Update the constructor to make markdown_source optional**

Replace the constructor (lines 27-32):
```ruby
def initialize(markdown_source, kitchen:, category:, parsed: nil)
  @markdown_source = markdown_source
  @kitchen = kitchen
  @category = category
  @parsed = parsed || parse_markdown
end
```
with:
```ruby
def initialize(markdown_source = nil, kitchen:, category:, parsed: nil)
  @kitchen = kitchen
  @category = category
  @parsed = parsed || parse_markdown(markdown_source)
end
```

- [ ] **Step 3: Update `parse_markdown` to accept the markdown string**

Replace `parse_markdown` (lines 57-59):
```ruby
def parse_markdown
  RecipeBuilder.new(LineClassifier.classify(markdown_source)).build
end
```
with:
```ruby
def parse_markdown(markdown_source)
  raise ArgumentError, 'markdown_source required when parsed IR not provided' unless markdown_source

  RecipeBuilder.new(LineClassifier.classify(markdown_source)).build
end
```

- [ ] **Step 4: Remove `markdown_source` from attribute assignment and attr_reader**

In `update_recipe_attributes` (line 76-89), remove line 88:
```ruby
markdown_source: markdown_source
```
so the `assign_attributes` call ends with `footer: parsed[:footer]`.

In the `attr_reader` line (line 45), change:
```ruby
attr_reader :markdown_source, :kitchen, :category, :parsed
```
to:
```ruby
attr_reader :kitchen, :category, :parsed
```

- [ ] **Step 5: Update the header comment**

Replace lines 1-13:
```ruby
# The sole write path for getting recipes into the database. Two entry points:
# `import` parses Markdown via the parser pipeline, `import_from_structure`
# accepts a pre-parsed IR hash and generates markdown via RecipeSerializer.
# Both converge on `run`, which upserts the Recipe and its child records,
# resolves pending cross-references, and computes nutrition.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline (import path)
# - RecipeSerializer — IR → Markdown (import_from_structure path)
# - RecipeWriteService — primary caller for web operations
# - RecipeNutritionJob, CascadeNutritionJob — post-import nutrition
```
with:
```ruby
# The sole write path for getting recipes into the database. Two entry points:
# `import` parses Markdown via the parser pipeline, `import_from_structure`
# accepts a pre-parsed IR hash directly. Both converge on `run`, which upserts
# the Recipe and its child records, resolves pending cross-references, and
# computes nutrition. AR records are the sole source of truth — no markdown
# is stored.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline (import path)
# - RecipeWriteService — primary caller for web operations
# - RecipeNutritionJob, CascadeNutritionJob — post-import nutrition
```

- [ ] **Step 6: Commit**

```bash
git add app/services/markdown_importer.rb
git commit -m "refactor: stop storing markdown_source in MarkdownImporter"
```

---

### Task 4: RecipeWriteService — collapse dual-path duplication

**Files:**
- Modify: `app/services/recipe_write_service.rb`

The static `self.create_from_structure` and `self.update_from_structure` class methods
(lines 28-33) are retained unchanged — they delegate to the instance methods which now
themselves delegate to `create`/`update`.

- [ ] **Step 1: Make `create_from_structure` delegate to `create`**

Replace `create_from_structure` (lines 57-69):
```ruby
def create_from_structure(structure:)
  recipe = nil

  ActiveRecord::Base.transaction do
    category = find_or_create_category(structure.dig(:front_matter, :category))
    recipe = import_structure_and_timestamp(structure, category:)
    sync_tags(recipe, structure.dig(:front_matter, :tags))
  end

  finalize
  Result.new(recipe:, updated_references: [])
end
```
with:
```ruby
def create_from_structure(structure:)
  create(markdown: nil, structure:,
         category_name: structure.dig(:front_matter, :category),
         tags: structure.dig(:front_matter, :tags))
end
```

- [ ] **Step 2: Make `update_from_structure` delegate to `update`**

Replace `update_from_structure` (lines 87-101):
```ruby
def update_from_structure(slug:, structure:)
  updated_references = []
  recipe = nil

  ActiveRecord::Base.transaction do
    old_recipe = kitchen.recipes.find_by!(slug:)
    category = find_or_create_category(structure.dig(:front_matter, :category))
    recipe = import_structure_and_timestamp(structure, category:)
    sync_tags(recipe, structure.dig(:front_matter, :tags))
    updated_references = rename_cross_references(old_recipe, recipe)
    handle_slug_change(old_recipe, recipe)
  end

  finalize
  Result.new(recipe:, updated_references:)
end
```
with:
```ruby
def update_from_structure(slug:, structure:)
  update(slug:, markdown: nil, structure:,
         category_name: structure.dig(:front_matter, :category),
         tags: structure.dig(:front_matter, :tags))
end
```

- [ ] **Step 3: Add `structure:` keyword to `create` and `update`**

Update `create` (lines 43-55) to accept and route the structure:
```ruby
def create(markdown: nil, structure: nil, category_name: nil, tags: nil)
  recipe = nil
  front_matter_tags = nil

  ActiveRecord::Base.transaction do
    category = find_or_create_category(category_name)
    recipe, front_matter_tags = import_recipe(markdown:, structure:, category:)
    sync_tags(recipe, tags || front_matter_tags)
  end

  finalize
  Result.new(recipe:, updated_references: [])
end
```

Update `update` similarly:
```ruby
def update(slug:, markdown: nil, structure: nil, category_name: nil, tags: nil)
  updated_references = []
  recipe = nil

  ActiveRecord::Base.transaction do
    old_recipe = kitchen.recipes.find_by!(slug:)
    category = find_or_create_category(category_name)
    recipe, front_matter_tags = import_recipe(markdown:, structure:, category:)
    sync_tags(recipe, tags || front_matter_tags)
    updated_references = rename_cross_references(old_recipe, recipe)
    handle_slug_change(old_recipe, recipe)
  end

  finalize
  Result.new(recipe:, updated_references:)
end
```

- [ ] **Step 4: Replace import helpers with unified method**

Replace `import_and_timestamp` and `import_structure_and_timestamp` (lines 124-132):
```ruby
def import_and_timestamp(markdown, category:)
  result = MarkdownImporter.import(markdown, kitchen:, category:)
  result.recipe.update!(edited_at: Time.current)
  [result.recipe, result.front_matter_tags]
end

def import_structure_and_timestamp(structure, category:)
  result = MarkdownImporter.import_from_structure(structure, kitchen:, category:)
  result.recipe.update!(edited_at: Time.current)
  result.recipe
end
```
with:
```ruby
def import_recipe(markdown:, structure:, category:)
  result = structure ? import_structure(structure, category:) : import_markdown(markdown, category:)
  result.recipe.update!(edited_at: Time.current)
  [result.recipe, result.front_matter_tags]
end

def import_markdown(markdown, category:)
  MarkdownImporter.import(markdown, kitchen:, category:)
end

def import_structure(structure, category:)
  MarkdownImporter.import_from_structure(structure, kitchen:, category:)
end
```

- [ ] **Step 5: Update the class-level static methods**

Update the static `create` (line 20) to pass the new keywords:
```ruby
def self.create(markdown: nil, structure: nil, kitchen:, category_name: nil, tags: nil)
  new(kitchen:).create(markdown:, structure:, category_name:, tags:)
end
```

Update the static `update` (line 24):
```ruby
def self.update(slug:, markdown: nil, structure: nil, kitchen:, category_name: nil, tags: nil)
  new(kitchen:).update(slug:, markdown:, structure:, category_name:, tags:)
end
```

- [ ] **Step 6: Update the header comment**

Replace the header comment (lines 1-16) with:
```ruby
# Orchestrates recipe create/update/destroy. Accepts either raw Markdown
# (text editor, file import) or IR hashes (graphical editor) — both converge
# on MarkdownImporter. `_from_structure` methods are thin normalizers that
# extract front matter and delegate. Owns the full post-write pipeline:
# import, tag sync, rename cascades, orphan cleanup (categories + tags),
# and meal plan reconciliation.
#
# - MarkdownImporter: parses markdown / IR hashes into AR records
# - Tag: created inline during sync; orphans cleaned in finalize
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
# - RecipeBroadcaster: targeted delete notifications and rename redirects
# - CrossReferenceUpdater: renames cross-references on title change
# - MealPlan#reconcile!: prunes stale selections and checked-off items
```

- [ ] **Step 7: Commit**

```bash
git add app/services/recipe_write_service.rb
git commit -m "refactor: collapse RecipeWriteService dual-path duplication"
```

---

### Task 5: Remaining code changes — CrossReferenceUpdater, ExportService, controller, views

**Files:**
- Modify: `app/services/cross_reference_updater.rb`
- Modify: `app/services/export_service.rb:38-43`
- Modify: `app/controllers/recipes_controller.rb:41-48`
- Modify: `app/views/recipes/show.html.erb:4`
- Modify: `app/views/recipes/_embedded_recipe.html.erb:12`

- [ ] **Step 1: Update CrossReferenceUpdater to generate markdown**

Replace `update_referencing_recipes` (lines 28-36):
```ruby
def update_referencing_recipes
  referencing = @recipe.referencing_recipes.includes(:category)
  return [] if referencing.empty?

  referencing.map do |ref_recipe|
    updated_source = yield(ref_recipe.markdown_source, @recipe.title)
    MarkdownImporter.import(updated_source, kitchen: ref_recipe.kitchen, category: ref_recipe.category)
    ref_recipe.title
  end
end
```
with:
```ruby
def update_referencing_recipes
  referencing = @recipe.referencing_recipes.includes(:category, :tags,
                                                      steps: [:ingredients, :cross_references])
  return [] if referencing.empty?

  referencing.map do |ref_recipe|
    markdown = generate_markdown(ref_recipe)
    updated_markdown = yield(markdown, @recipe.title)
    MarkdownImporter.import(updated_markdown, kitchen: ref_recipe.kitchen, category: ref_recipe.category)
    ref_recipe.title
  end
end

def generate_markdown(recipe)
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
  FamilyRecipes::RecipeSerializer.serialize(ir)
end
```

Update the header comment (lines 1-7) to:
```ruby
# Cascading Markdown updates when a recipe is renamed. Generates markdown
# from AR records via RecipeSerializer, rewrites "@[Old Title]" →
# "@[New Title]", and re-imports. Returns affected recipe titles.
# Recipe deletion relies on dependent: :nullify on
# inbound_cross_references — no Markdown rewriting needed.
```

- [ ] **Step 2: Update ExportService to generate markdown**

Replace `add_recipes` (lines 38-43):
```ruby
def add_recipes(zos)
  @kitchen.recipes.includes(:category).find_each do |recipe|
    zos.put_next_entry("#{recipe.category.name}/#{recipe.title}.md")
    zos.write(recipe.markdown_source)
  end
end
```
with:
```ruby
def add_recipes(zos)
  @kitchen.recipes.includes(:category, :tags, steps: [:ingredients, :cross_references]).find_each do |recipe|
    zos.put_next_entry("#{recipe.category.name}/#{recipe.title}.md")
    ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
    zos.write(FamilyRecipes::RecipeSerializer.serialize(ir))
  end
end
```

- [ ] **Step 3: Update RecipesController `show_markdown` and `show_html`**

Replace `show_markdown` (lines 41-43):
```ruby
def show_markdown
  recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  render plain: recipe.markdown_source, content_type: 'text/plain; charset=utf-8'
end
```
with:
```ruby
def show_markdown
  recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  render plain: generate_markdown(recipe), content_type: 'text/plain; charset=utf-8'
end
```

Replace `show_html` (lines 45-48):
```ruby
def show_html
  recipe = current_kitchen.recipes.find_by!(slug: params[:slug])
  body = FamilyRecipes::Recipe::MARKDOWN.render(recipe.markdown_source)
  render html: minimal_html_document(title: recipe.title, body:), layout: false
end
```
with:
```ruby
def show_html
  recipe = current_kitchen.recipes.with_full_tree.find_by!(slug: params[:slug])
  body = FamilyRecipes::Recipe::MARKDOWN.render(generate_markdown(recipe))
  render html: minimal_html_document(title: recipe.title, body:), layout: false
end
```

Add to the `private` section:
```ruby
def generate_markdown(recipe)
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
  FamilyRecipes::RecipeSerializer.serialize(ir)
end
```

- [ ] **Step 4: Update view version hashes**

In `app/views/recipes/show.html.erb`, replace line 4:
```erb
data-recipe-id="<%= @recipe.slug %>" data-version-hash="<%= Digest::SHA256.hexdigest(@recipe.markdown_source) %>"
```
with:
```erb
data-recipe-id="<%= @recipe.slug %>" data-version-hash="<%= @recipe.updated_at.to_i %>"
```

In `app/views/recipes/_embedded_recipe.html.erb`, replace line 12:
```erb
data-recipe-state-version-hash-value="<%= Digest::SHA256.hexdigest(target.markdown_source) %>"
```
with:
```erb
data-recipe-state-version-hash-value="<%= target.updated_at.to_i %>"
```

- [ ] **Step 5: Commit**

```bash
git add app/services/cross_reference_updater.rb app/services/export_service.rb \
        app/controllers/recipes_controller.rb \
        app/views/recipes/show.html.erb app/views/recipes/_embedded_recipe.html.erb
git commit -m "refactor: remaining code generates markdown on demand via serializer"
```

---

## Chunk 3: Test Fixes and Docs

### Task 6: Fix tests — remove markdown_source from AR Recipe creation

All test files that call `Recipe.create!`, `Recipe.new`, or `Recipe.find_or_create_by!` with
`markdown_source:` need that keyword argument removed (`ActiveModel::UnknownAttributeError`
since the column no longer exists).

**Files:**
- Modify: `test/models/recipe_model_test.rb` (~20 occurrences)
- Modify: `test/models/recipe_aggregation_test.rb` (~7 occurrences)
- Modify: `test/models/tag_test.rb` (2 occurrences)
- Modify: `test/models/step_test.rb` (~4 occurrences)
- Modify: `test/models/cross_reference_test.rb` (~8 occurrences)
- Modify: `test/models/recipe_tag_test.rb` (1 occurrence)
- Modify: `test/models/ingredient_test.rb` (1 occurrence)
- Modify: `test/models/category_test.rb` (1 occurrence)
- Modify: `test/helpers/search_data_helper_test.rb` (1 occurrence)

- [ ] **Step 1: Remove `markdown_source:` from all AR Recipe creation calls**

In every file above, remove the `markdown_source:` keyword argument from `Recipe.create!`,
`Recipe.new`, and `Recipe.find_or_create_by!` calls.

Also remove any `BASIC_MD` or similar constants that existed solely to provide markdown_source
values, if they're no longer used for anything else (check before deleting — some may be used
as import input for MarkdownImporter tests).

- [ ] **Step 2: Run model tests**

Run: `rake test TEST=test/models`
Expected: Model tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/models/ test/helpers/
git commit -m "test: remove markdown_source from AR Recipe creation in model tests"
```

---

### Task 7: Fix tests — update service and controller test assertions

**Files:**
- Modify: `test/services/markdown_importer_test.rb`
- Modify: `test/services/structured_import_test.rb`
- Modify: `test/services/cross_reference_updater_test.rb`
- Modify: `test/services/export_service_test.rb`
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: MarkdownImporter test — remove markdown_source assertion**

Remove any assertion like `assert_equal BASIC_RECIPE, recipe.markdown_source`. The importer
no longer stores markdown. Keep assertions that verify AR records (title, steps, ingredients).

- [ ] **Step 2: Structured import test — update round-trip assertions**

In `test/services/structured_import_test.rb`, assertions on `recipe.markdown_source` must
change. The recipe no longer has that attribute. Change assertions to verify AR record
state (title, steps, ingredients, front matter fields) rather than stored markdown.

- [ ] **Step 3: CrossReferenceUpdater test — change to AR-based assertions**

Replace assertions that read `recipe.markdown_source` (e.g., lines 42-43):
```ruby
assert_includes @pizza.markdown_source, '@[Neapolitan Dough]'
assert_not_includes @pizza.markdown_source, '@[Pizza Dough]'
```
with assertions on the AR cross-reference records or generated markdown:
```ruby
@pizza.reload
xref = @pizza.cross_references.find_by(target_title: 'Neapolitan Dough')
assert xref, 'cross-reference to Neapolitan Dough should exist'
assert_nil @pizza.cross_references.find_by(target_title: 'Pizza Dough')
```

- [ ] **Step 4: ExportService test — assert on serializer output**

The export test currently asserts `recipe.markdown_source` matches exported content.
Since the column is gone, generate expected markdown via the serializer:
```ruby
ir = FamilyRecipes::RecipeSerializer.from_record(recipe)
expected = FamilyRecipes::RecipeSerializer.serialize(ir)
assert_equal expected, exported_content
```

- [ ] **Step 5: RecipesController test — update specific assertions**

These lines read the AR attribute `recipe.markdown_source` and must change:

- **Lines 256-257** (cross-reference rename assertions): change to AR-based assertions
  on cross-reference records, same pattern as Step 3.
- **Line 352** (`original_source = panzanella.markdown_source`): replace with an AR-based
  check that the recipe is unchanged (e.g., check title/step count before and after).
- **Line 364** (`assert_equal original_source, panzanella.reload.markdown_source`): replace
  with assertion that recipe AR state is unchanged.
- **Line 615** (`show_markdown` response body equals `recipe.markdown_source`): assert
  response body equals serializer-generated markdown instead.
- **Line 733** (`focaccia_markdown = ...recipes...markdown_source`): generate markdown
  via serializer instead.

Lines reading `body['markdown_source']` from the `content` endpoint's JSON response (lines
675-676, 686, 701-702) are fine — that's the HTTP response key, not the AR attribute.

- [ ] **Step 6: Run full test suite**

Run: `rake test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/services/ test/controllers/
git commit -m "test: update service and controller tests for markdown_source removal"
```

---

### Task 8: Verify from-scratch setup and docs

**Files:**
- Modify: `docs/how-your-rails-app-works.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Verify from-scratch setup works**

Run: `rails db:drop db:create db:migrate db:seed`
Expected: Clean setup with no errors.

- [ ] **Step 2: Run full test suite**

Run: `rake`
Expected: Lint clean, all tests pass.

- [ ] **Step 3: Update how-your-rails-app-works.md**

Search for `markdown_source` references and update to reflect that markdown is generated
on demand, not stored. Key changes:
- Remove references to "raw source stored in markdown_source"
- Update MarkdownImporter description to reflect it no longer stores markdown
- Update the recipe editor flow to note markdown is generated by RecipeSerializer

- [ ] **Step 4: Update CLAUDE.md**

In the Architecture section, update the write path and MarkdownImporter descriptions:
- Both entry points converge on the IR
- AR records are the sole source of truth
- `RecipeSerializer` generates markdown on demand (export, editor loading, raw endpoints)
- Remove references to `markdown_source` storage

- [ ] **Step 5: Final lint and test run**

Run: `rake`
Expected: Lint clean, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add docs/how-your-rails-app-works.md CLAUDE.md
git commit -m "docs: update for markdown_source removal and write path simplification"
```

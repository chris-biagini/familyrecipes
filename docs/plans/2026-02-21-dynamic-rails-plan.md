# Dynamic Rails App — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the static site generator with a fully dynamic Rails 8 app serving all pages from PostgreSQL, using proper Rails conventions.

**Architecture:** ActiveRecord models backed by PostgreSQL. Markdown import pipeline converts existing recipe files into structured DB rows. Proper Rails layouts/partials/helpers replace lambda-based templates. Propshaft for asset fingerprinting.

**Tech Stack:** Rails 8, PostgreSQL, Propshaft, Minitest, Redcarpet (markdown)

**Design doc:** `docs/plans/2026-02-21-dynamic-rails-design.md`

---

## Task 1: Set Up Propshaft and Move Assets

Propshaft provides asset fingerprinting with zero build step. Move hand-written CSS/JS/images from `resources/web/` into `app/assets/` where Propshaft serves them.

**Files:**
- Modify: `Gemfile` — add `gem 'propshaft'`
- Create: `app/assets/stylesheets/style.css` (copy from `resources/web/style.css`)
- Create: `app/assets/stylesheets/groceries.css` (copy from `resources/web/groceries.css`)
- Create: `app/assets/javascripts/recipe-state-manager.js` (copy from `resources/web/recipe-state-manager.js`)
- Create: `app/assets/javascripts/groceries.js` (copy from `resources/web/groceries.js`)
- Create: `app/assets/javascripts/notify.js` (copy from `resources/web/notify.js`)
- Create: `app/assets/javascripts/wake-lock.js` (copy from `resources/web/wake-lock.js`)
- Create: `app/assets/javascripts/qrcodegen.js` (copy from `resources/web/qrcodegen.js`)
- Create: `app/assets/images/favicon.svg` (copy from `resources/web/favicon.svg`)
- Create: `app/assets/images/favicon.ico` (copy from `resources/web/favicon.ico`)
- Create: `app/assets/images/apple-touch-icon.png` (copy from `resources/web/apple-touch-icon.png`)

**Steps:**

1. Add `gem 'propshaft'` to the Gemfile (outside any group — needed in all environments).
2. Run `bundle install`.
3. Copy asset files from `resources/web/` to their new `app/assets/` locations (maintain flat structure within each subdirectory).
4. Verify Propshaft serves assets by starting the Rails server and requesting `/assets/style.css`.
5. Commit: `feat: set up Propshaft and move assets to app/assets/`

**Notes:**
- Do NOT delete `resources/web/` yet — the static generator still uses it until Task 13.
- The `404.html` file from `resources/web/` can move to `public/404.html` (Rails convention).
- Propshaft config should be minimal — Rails 8 autoconfigures it when the gem is present.

---

## Task 2: Namespace Parser Classes Under FamilyRecipes

The domain classes (`Recipe`, `Step`, `Ingredient`, `CrossReference`, `QuickBite`) are currently top-level. ActiveRecord models need those names. Move the parser classes under the `FamilyRecipes` namespace.

**Files:**
- Modify: `lib/familyrecipes/recipe.rb` — wrap in `module FamilyRecipes; class Recipe; end; end`
- Modify: `lib/familyrecipes/step.rb` — wrap in `module FamilyRecipes`
- Modify: `lib/familyrecipes/ingredient.rb` — wrap in `module FamilyRecipes`
- Modify: `lib/familyrecipes/cross_reference.rb` — wrap in `module FamilyRecipes`
- Modify: `lib/familyrecipes/quick_bite.rb` — wrap in `module FamilyRecipes`
- Modify: `lib/familyrecipes.rb` — update `parse_recipes` and `parse_quick_bites` to use `FamilyRecipes::Recipe.new(...)` and `FamilyRecipes::QuickBite.new(...)`
- Modify: `lib/familyrecipes/recipe.rb` — internal references: `Step.new` → `FamilyRecipes::Step.new`, `Ingredient.new` → `FamilyRecipes::Ingredient.new`, `CrossReference.new` → `FamilyRecipes::CrossReference.new`. Since these are inside the module, just `Step.new` etc. will resolve correctly — no change needed there.
- Modify: `lib/familyrecipes/step.rb` — `ingredient_list_items.grep(Ingredient)` → `ingredient_list_items.grep(FamilyRecipes::Ingredient)`, same for `CrossReference`. Actually, since Step is now inside `FamilyRecipes` module, `Ingredient` will resolve to `FamilyRecipes::Ingredient` automatically. **Verify this works.**
- Modify: All test files — update `Recipe.new` → `FamilyRecipes::Recipe.new`, `Step.new` → `FamilyRecipes::Step.new`, `Ingredient.new` → `FamilyRecipes::Ingredient.new`, `CrossReference.new` → `FamilyRecipes::CrossReference.new`, `QuickBite.new` → `FamilyRecipes::QuickBite.new`.
- Modify: `app/services/recipe_finder.rb` — `Recipe.new` → `FamilyRecipes::Recipe.new`
- Modify: `app/services/recipe_renderer.rb` — if it references domain classes directly

**Steps:**

1. Wrap each parser class in `module FamilyRecipes ... end`. Since these files are inside `lib/familyrecipes/`, the namespace is natural.
2. Verify internal references resolve (e.g., `Step` inside `FamilyRecipes::Recipe` should find `FamilyRecipes::Step`).
3. Update test files. Use find-and-replace but verify each change — some tests construct objects directly.
4. Update `recipe_finder.rb` and `recipe_renderer.rb` service references.
5. Run the full test suite: `rake test` — all existing tests must pass.
6. Run `rake lint` and fix any RuboCop issues.
7. Commit: `refactor: namespace parser classes under FamilyRecipes module`

**Critical detail:** The `Step` class uses `.grep(Ingredient)` and `.grep(CrossReference)` to separate ingredient types (line 20-21 of step.rb). Since Step will be inside the FamilyRecipes module, `Ingredient` should resolve correctly. Verify this.

---

## Task 3: Replace Migrations and Create New Schema

Delete the existing migrations/models from the previous database layer attempt and create fresh ones matching the approved design.

**Files to delete:**
- `db/migrate/001_create_recipes.rb`
- `db/migrate/002_create_steps.rb`
- `db/migrate/003_create_ingredients.rb`
- `db/migrate/004_create_cross_references.rb`
- `db/migrate/005_create_nutrition_entries.rb`
- `app/models/recipe_record.rb`
- `app/models/step_record.rb`
- `app/models/ingredient_record.rb`
- `app/models/cross_reference_record.rb`
- `app/models/nutrition_entry_record.rb`

**Files to create:**
- `db/migrate/001_create_categories.rb`
- `db/migrate/002_create_recipes.rb`
- `db/migrate/003_create_steps.rb`
- `db/migrate/004_create_ingredients.rb`
- `db/migrate/005_create_recipe_dependencies.rb`

**Steps:**

1. Delete all existing migration files and `Record`-suffixed model files.
2. Drop and recreate the dev/test databases: `rails db:drop db:create` (if they exist; ignore errors if they don't).
3. Write the new migrations:

**001_create_categories.rb:**
```ruby
# frozen_string_literal: true

class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :categories, :slug, unique: true
    add_index :categories, :position
  end
end
```

**002_create_recipes.rb:**
```ruby
# frozen_string_literal: true

class CreateRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :recipes do |t|
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.decimal :makes_quantity
      t.string :makes_unit_noun
      t.integer :serves
      t.text :footer
      t.text :markdown_source, null: false

      t.timestamps
    end

    add_index :recipes, :slug, unique: true
  end
end
```

**003_create_steps.rb:**
```ruby
# frozen_string_literal: true

class CreateSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :steps do |t|
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.text :instructions

      t.timestamps
    end
  end
end
```

**004_create_ingredients.rb:**
```ruby
# frozen_string_literal: true

class CreateIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :ingredients do |t|
      t.references :step, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.string :quantity
      t.string :unit
      t.string :prep_note

      t.timestamps
    end
  end
end
```

**005_create_recipe_dependencies.rb:**
```ruby
# frozen_string_literal: true

class CreateRecipeDependencies < ActiveRecord::Migration[8.0]
  def change
    create_table :recipe_dependencies do |t|
      t.references :source_recipe, null: false, foreign_key: { to_table: :recipes }
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }

      t.timestamps
    end

    add_index :recipe_dependencies, %i[source_recipe_id target_recipe_id], unique: true
  end
end
```

4. Run `rails db:migrate` to create the schema.
5. Verify `db/schema.rb` was generated and looks correct.
6. Commit: `feat: create database schema for categories, recipes, steps, ingredients, dependencies`

**Design notes:**
- `steps.title` corresponds to the `tldr` field in the parser. Using `title` is more Rails-conventional.
- `ingredients.unit` is split out from `quantity` (the parser stores them together as a string like `"2 cups"`). The importer will split them. Having separate columns enables proper grocery aggregation in SQL later.
- `ingredients.quantity` stores the numeric part as a string (to preserve fractions like `"1/2"`). The importer can also store a `quantity_value` decimal if useful — but for now a string is fine since the JS handles scaling.
- Recipe `markdown_source` stores the original markdown for the future editor.
- No `version_hash` column — we can compute it from `markdown_source` if needed, or use `updated_at`.

---

## Task 4: Create ActiveRecord Models

**Files to create:**
- `app/models/category.rb`
- `app/models/recipe.rb`
- `app/models/step.rb`
- `app/models/ingredient.rb`
- `app/models/recipe_dependency.rb`

**Steps:**

1. Write the models:

**app/models/category.rb:**
```ruby
# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :recipes, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  scope :ordered, -> { order(:position, :name) }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(name)
end
```

**app/models/recipe.rb:**
```ruby
# frozen_string_literal: true

class Recipe < ApplicationRecord
  belongs_to :category

  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps

  has_many :outbound_dependencies, class_name: 'RecipeDependency',
                                   foreign_key: :source_recipe_id,
                                   dependent: :destroy,
                                   inverse_of: :source_recipe
  has_many :inbound_dependencies, class_name: 'RecipeDependency',
                                  foreign_key: :target_recipe_id,
                                  dependent: :restrict_with_error,
                                  inverse_of: :target_recipe
  has_many :referenced_recipes, through: :outbound_dependencies, source: :target_recipe
  has_many :referencing_recipes, through: :inbound_dependencies, source: :source_recipe

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :markdown_source, presence: true

  scope :alphabetical, -> { order(:title) }

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  def makes
    return unless makes_quantity

    unit = makes_unit_noun
    "#{makes_quantity.to_i == makes_quantity ? makes_quantity.to_i : makes_quantity} #{unit}"
  end

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(title)
end
```

**app/models/step.rb:**
```ruby
# frozen_string_literal: true

class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps

  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  validates :title, presence: true
  validates :position, presence: true
end
```

**app/models/ingredient.rb:**
```ruby
# frozen_string_literal: true

class Ingredient < ApplicationRecord
  belongs_to :step, inverse_of: :ingredients

  validates :name, presence: true
  validates :position, presence: true

  def quantity_display
    [quantity, unit].compact.join(' ').presence
  end

  def quantity_value
    return unless quantity

    FamilyRecipes::Ingredient.new(name: name, quantity: quantity_display).quantity_value
  end

  def quantity_unit
    return unless unit

    FamilyRecipes::Inflector.normalize_unit(unit)
  end
end
```

**app/models/recipe_dependency.rb:**
```ruby
# frozen_string_literal: true

class RecipeDependency < ApplicationRecord
  belongs_to :source_recipe, class_name: 'Recipe', inverse_of: :outbound_dependencies
  belongs_to :target_recipe, class_name: 'Recipe', inverse_of: :inbound_dependencies

  validates :target_recipe_id, uniqueness: { scope: :source_recipe_id }
end
```

2. Update `config/application.rb` — remove the conditional ActiveRecord skip logic. ActiveRecord is now always required:

```ruby
require "active_record/railtie"
```

Remove the `unless defined?(ActiveRecord)` block that skips model autoloading.

3. Move `pg` gem out of the `:database` group into the main section of the Gemfile (it's now required, not optional).

4. Run `rails db:migrate` and verify schema loads.
5. Open a Rails console (`rails c`) and verify `Category.new`, `Recipe.new`, etc. work.
6. Run `rake lint` and fix any issues.
7. Commit: `feat: add ActiveRecord models for Category, Recipe, Step, Ingredient, RecipeDependency`

**Notes:**
- The `Ingredient` AR model delegates `quantity_value` and `quantity_unit` to the parser's `Ingredient` class. This avoids duplicating parsing logic while giving the AR model the same interface the views expect.
- `Recipe#makes` reconstructs the display string from split columns — this is what the template expects.
- No `quick_bite` flag yet — Quick Bites are out of v1 scope.

---

## Task 5: Build the Markdown Importer

A service that takes a markdown string and creates/updates all associated database records. This is the bridge between the parser and the database.

**Files:**
- Create: `app/services/markdown_importer.rb`
- Create: `test/services/markdown_importer_test.rb`

**Steps:**

1. Write the failing test first:

```ruby
# frozen_string_literal: true

require 'test_helper'

class MarkdownImporterTest < ActiveSupport::TestCase
  SAMPLE_RECIPE = <<~MARKDOWN
    # Test Recipe

    A simple test recipe.

    Category: Bread

    ## Mix the dough (combine ingredients)

    - Flour, 2 cups
    - Water, 1 cup: Warm.
    - Salt, 1 tsp

    Mix everything together.

    ## Bake (put it in the oven)

    Let it bake for 30 minutes.

    ---

    This is a classic recipe.
  MARKDOWN

  test 'imports a recipe from markdown' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)

    recipe = MarkdownImporter.import(SAMPLE_RECIPE)

    assert_equal 'Test Recipe', recipe.title
    assert_equal 'test-recipe', recipe.slug
    assert_equal 'A simple test recipe.', recipe.description
    assert_equal 'Bread', recipe.category.name
    assert_equal 2, recipe.steps.size

    step = recipe.steps.first
    assert_equal 'Mix the dough (combine ingredients)', step.title
    assert_equal 3, step.ingredients.size

    flour = step.ingredients.find_by(name: 'Flour')
    assert_equal '2', flour.quantity
    assert_equal 'cups', flour.unit
    assert_nil flour.prep_note

    water = step.ingredients.find_by(name: 'Water')
    assert_equal '1', water.quantity
    assert_equal 'cup', water.unit
    assert_equal 'Warm.', water.prep_note
  end

  test 'importing the same recipe twice updates instead of duplicating' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)

    recipe1 = MarkdownImporter.import(SAMPLE_RECIPE)
    recipe2 = MarkdownImporter.import(SAMPLE_RECIPE)

    assert_equal recipe1.id, recipe2.id
    assert_equal 1, Recipe.count
  end

  test 'imports makes and serves from front matter' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)

    markdown = <<~MARKDOWN
      # Rolls

      Category: Bread
      Makes: 12 rolls
      Serves: 4

      ## Shape (form the dough)

      - Dough, 1 batch

      Shape into rolls.
    MARKDOWN

    recipe = MarkdownImporter.import(markdown)

    assert_equal 12, recipe.makes_quantity
    assert_equal 'rolls', recipe.makes_unit_noun
    assert_equal 4, recipe.serves
  end
end
```

2. Run test to verify it fails.

3. Write the importer:

```ruby
# frozen_string_literal: true

class MarkdownImporter
  def self.import(markdown_source)
    new(markdown_source).import
  end

  def initialize(markdown_source)
    @markdown_source = markdown_source
    @parsed = parse_markdown
  end

  def import
    ActiveRecord::Base.transaction do
      recipe = find_or_initialize_recipe
      update_recipe_attributes(recipe)
      recipe.save!
      replace_steps(recipe)
      rebuild_dependencies(recipe)
      recipe
    end
  end

  private

  attr_reader :markdown_source, :parsed

  def parse_markdown
    tokens = FamilyRecipes::LineClassifier.classify(markdown_source)
    FamilyRecipes::RecipeBuilder.new(tokens).build
  end

  def find_or_initialize_recipe
    slug = FamilyRecipes.slugify(parsed[:title])
    Recipe.find_or_initialize_by(slug: slug)
  end

  def update_recipe_attributes(recipe)
    category = find_or_create_category(parsed[:front_matter][:category])
    makes_qty, makes_unit = parse_makes(parsed[:front_matter][:makes])

    recipe.assign_attributes(
      title: parsed[:title],
      description: parsed[:description],
      category: category,
      makes_quantity: makes_qty,
      makes_unit_noun: makes_unit,
      serves: parsed[:front_matter][:serves]&.to_i,
      footer: parsed[:footer],
      markdown_source: markdown_source
    )
  end

  def find_or_create_category(name)
    slug = FamilyRecipes.slugify(name)
    Category.find_or_create_by!(slug: slug) do |cat|
      cat.name = name
      cat.position = Category.maximum(:position).to_i + 1
    end
  end

  def parse_makes(makes_string)
    return [nil, nil] unless makes_string

    match = makes_string.match(/\A(\S+)\s+(.+)/)
    return [nil, nil] unless match

    [match[1].to_f, match[2]]
  end

  def replace_steps(recipe)
    recipe.steps.destroy_all

    parsed[:steps].each_with_index do |step_data, index|
      step = recipe.steps.create!(
        title: step_data[:tldr],
        instructions: step_data[:instructions],
        position: index
      )

      import_ingredients(step, step_data[:ingredients])
    end
  end

  def import_ingredients(step, ingredient_data_list)
    ingredient_data_list.each_with_index do |data, index|
      next if data[:cross_reference] # Cross-references stay in markdown

      qty, unit = split_quantity(data[:quantity])

      step.ingredients.create!(
        name: data[:name],
        quantity: qty,
        unit: unit,
        prep_note: data[:prep_note],
        position: index
      )
    end
  end

  def split_quantity(quantity_string)
    return [nil, nil] if quantity_string.nil? || quantity_string.strip.empty?

    parts = quantity_string.strip.split(' ', 2)
    [parts[0], parts[1]]
  end

  def rebuild_dependencies(recipe)
    recipe.outbound_dependencies.destroy_all

    cross_refs = parsed[:steps].flat_map { |s| s[:ingredients].select { |i| i[:cross_reference] } }
    target_slugs = cross_refs.map { |ref| FamilyRecipes.slugify(ref[:target_title]) }.uniq

    target_slugs.each do |slug|
      target = Recipe.find_by(slug: slug)
      next unless target

      recipe.outbound_dependencies.create!(target_recipe: target)
    end
  end
end
```

4. Run test to verify it passes.
5. Run `rake lint`.
6. Commit: `feat: add MarkdownImporter service for markdown-to-database conversion`

---

## Task 6: Seed the Database

Create a seed task that imports all recipe files and sets up category ordering.

**Files:**
- Modify: `db/seeds.rb`
- Create: `lib/tasks/import.rake` (optional — for `rake import` convenience)

**Steps:**

1. Write `db/seeds.rb`:

```ruby
# frozen_string_literal: true

recipes_dir = Rails.root.join('recipes')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  recipe = MarkdownImporter.import(markdown)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."
```

2. Run `rails db:seed` and verify all recipes import successfully.
3. Open `rails console` and spot-check:
   - `Recipe.count` matches expected number
   - `Recipe.find_by(slug: 'focaccia').steps.count` is reasonable
   - `Recipe.find_by(slug: 'focaccia').ingredients.count` is reasonable
   - `Category.ordered.pluck(:name)` shows all categories
4. Commit: `feat: add database seed task for recipe import`

---

## Task 7: Application Layout and Shared Partials

Replace the lambda-based `_head.html.erb` and `_nav.html.erb` with a proper Rails layout.

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/views/shared/_nav.html.erb`

**Steps:**

1. Write the application layout. This replaces `_head.html.erb` — same HTML structure, but using Rails asset helpers instead of relative paths:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <meta name="theme-color" content="rgb(205, 71, 84)">
  <title><%= content_for(:title) || 'Biagini Family Recipes' %></title>
  <%= stylesheet_link_tag 'style' %>
  <link rel="icon" type="image/svg+xml" href="<%= image_path('favicon.svg') %>">
  <link rel="shortcut icon" href="<%= image_path('favicon.ico') %>">
  <link rel="apple-touch-icon" sizes="180x180" href="<%= image_path('apple-touch-icon.png') %>">
  <%= yield :head %>
</head>
<body <%= yield :body_attrs %>>
  <%= render 'shared/nav' %>
  <main>
    <%= yield %>
  </main>
  <%= yield :scripts %>
</body>
</html>
```

2. Write the nav partial:

```erb
<%# app/views/shared/_nav.html.erb %>
  <nav>
    <div>
      <%= link_to 'Home', root_path, class: 'home', title: 'Home (Table of Contents)' %>
      <%= link_to 'Index', ingredients_path, class: 'index', title: 'Index of ingredients' %>
      <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Printable grocery list' %>
    </div>
    <%= yield :extra_nav if content_for?(:extra_nav) %>
  </nav>
```

3. The nav uses named route helpers (`root_path`, `ingredients_path`, `groceries_path`). These won't resolve until routes exist (Task 8). That's fine — we're building clean-room.
4. Commit: `feat: add application layout and nav partial`

**Notes:**
- No `<base href>` tag — Rails route helpers generate correct paths.
- `content_for(:title)` lets each page set its own title.
- `yield :head` lets pages inject extra stylesheets (groceries page needs `groceries.css`).
- `yield :scripts` lets pages inject page-specific JS at the end of body.
- `yield :body_attrs` lets the recipe page set `data-recipe-id` and `data-version-hash`.
- `yield :extra_nav` lets the recipe page inject the Scale button.

---

## Task 8: Routes

**Files:**
- Modify: `config/routes.rb`

**Steps:**

1. Replace the existing catch-all route with the new routes:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  root 'homepage#show'

  resources :recipes, only: [:show], param: :slug

  get 'index', to: 'ingredients#index', as: :ingredients
  get 'groceries', to: 'groceries#show', as: :groceries
end
```

2. Verify with `rails routes`:
   - `root GET / homepage#show`
   - `recipe GET /recipes/:slug recipes#show`
   - `ingredients GET /index ingredients#index`
   - `groceries GET /groceries groceries#show`

3. Commit: `feat: add routes for homepage, recipes, ingredients, groceries`

**Notes:**
- `as: :ingredients` gives us `ingredients_path` helper.
- The URL is `/index` (matching the static site's path) but the route name is `ingredients`.
- `param: :slug` means `params[:slug]` instead of `params[:id]` in the recipes controller.

---

## Task 9: Homepage Controller and View

**Files:**
- Create: `app/controllers/homepage_controller.rb`
- Create: `app/views/homepage/show.html.erb`
- Create: `test/controllers/homepage_controller_test.rb`

**Steps:**

1. Write the failing test:

```ruby
# frozen_string_literal: true

require 'test_helper'

class HomepageControllerTest < ActionDispatch::IntegrationTest
  test 'renders the homepage with categories and recipes' do
    category = Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      A simple flatbread.

      Category: Bread

      ## Make the dough (mix ingredients)

      - Flour, 3 cups

      Mix well.
    MD

    get root_path

    assert_response :success
    assert_select 'h1', 'Our Recipes'
    assert_select 'a[href=?]', recipe_path('focaccia'), text: 'Focaccia'
  end
end
```

2. Run test, verify it fails.

3. Write the controller:

```ruby
# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @categories = Category.ordered.includes(recipes: :category)
  end
end
```

4. Write the view (ported from `homepage-template.html.erb`):

```erb
<%# app/views/homepage/show.html.erb %>
<article class="homepage">
  <header>
    <h1>Our Recipes</h1>
    <p>A collection of our family's favorite recipes.</p>
  </header>

  <div class="toc_nav">
    <ul>
      <%- @categories.each do |category| -%>
      <li><%= link_to category.name, "##{category.slug}" %></li>
      <%- end -%>
    </ul>
  </div>

  <%- @categories.each do |category| -%>
  <section id="<%= category.slug %>">
    <h2><%= category.name %></h2>
    <ul>
      <%- category.recipes.alphabetical.each do |recipe| -%>
      <li><%= link_to recipe.title, recipe_path(recipe.slug), title: recipe.description %></li>
      <%- end -%>
    </ul>
  </section>
  <%- end -%>

  <footer>
    <p>For more information, visit <a href="https://github.com/chris-biagini/familyrecipes">our project page on GitHub</a>.</p>
  </footer>
</article>
```

5. Run test, verify it passes.
6. Run `rake lint`.
7. Commit: `feat: add homepage controller and view`

**Notes:**
- Site config values (`site_title`, `homepage_heading`, `homepage_subtitle`, `github_url`) are currently in `resources/site-config.yaml`. For the homepage, we can hardcode them initially and extract to a config later if the values need to be dynamic. Or load them from YAML in an initializer. Keep it simple — hardcode for now.
- The PDF download link from the old homepage footer is removed (PDF is retired).

---

## Task 10: Recipe Controller and View

This is the most complex page. The recipe view needs to render steps, ingredients, cross-references, nutrition facts, and include page-specific JS for scaling/cross-off.

**Files:**
- Modify: `app/controllers/recipes_controller.rb` (replace existing)
- Create: `app/views/recipes/show.html.erb`
- Create: `app/views/recipes/_step.html.erb`
- Create: `app/views/recipes/_nutrition_table.html.erb`
- Create: `app/helpers/recipes_helper.rb`
- Modify: `test/controllers/recipes_controller_test.rb` (replace existing)

**Steps:**

1. Write the failing test:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      A simple flatbread.

      Category: Bread
      Serves: 8

      ## Make the dough (combine ingredients)

      - Flour, 3 cups
      - Water, 1 cup: Warm.
      - Salt, 1 tsp

      Mix everything together and let rest for 1* hour.

      ## Bake (put it in the oven)

      Bake at 425* degrees for 20* minutes.

      ---

      A classic Italian bread.
    MD
  end

  test 'renders a recipe page' do
    get recipe_path('focaccia')

    assert_response :success
    assert_select 'h1', 'Focaccia'
    assert_select '.recipe-meta', /Bread/
    assert_select '.recipe-meta', /Serves 8/
    assert_select 'h2', 'Make the dough (combine ingredients)'
    assert_select '.ingredients li', 3
    assert_select 'b', 'Flour'
  end

  test 'returns 404 for unknown recipe' do
    get recipe_path('nonexistent')

    assert_response :not_found
  end

  test 'includes recipe JavaScript' do
    get recipe_path('focaccia')

    assert_select 'script[src*="recipe-state-manager"]'
  end
end
```

2. Run test, verify it fails.

3. Write the controller:

```ruby
# frozen_string_literal: true

class RecipesController < ApplicationController
  def show
    @recipe = Recipe.includes(steps: :ingredients).find_by!(slug: params[:slug])
    @nutrition = calculate_nutrition
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def calculate_nutrition
    parsed = FamilyRecipes::Recipe.new(
      markdown_source: @recipe.markdown_source,
      id: @recipe.slug,
      category: @recipe.category.name
    )

    nutrition_data = load_nutrition_data
    return unless nutrition_data

    alias_map = load_alias_map
    recipe_map = build_recipe_map

    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: load_omit_set)
    calculator.calculate(parsed, alias_map, recipe_map)
  end

  def load_nutrition_data
    path = Rails.root.join('resources/nutrition-data.yaml')
    return unless File.exist?(path)

    YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def load_alias_map
    grocery_aisles = FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
    FamilyRecipes.build_alias_map(grocery_aisles)
  end

  def load_omit_set
    grocery_aisles = FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
    (grocery_aisles['Omit_From_List'] || []).flat_map do |item|
      [item[:name], *item[:aliases]].map(&:downcase)
    end.to_set
  end

  def build_recipe_map
    recipes_dir = Rails.root.join('recipes')
    FamilyRecipes.parse_recipes(recipes_dir).to_h { |r| [r.id, r] }
  end
end
```

**Important note about nutrition:** The nutrition calculator works with the parser's `FamilyRecipes::Recipe` object, not the AR model. For now, we re-parse the markdown to get a parser Recipe, then feed it to the calculator. This is inelegant but correct — it reuses existing nutrition logic without rewriting it. In the future, the nutrition calculator should work with AR models directly, or nutrition data should move into the database.

The `load_alias_map`, `load_omit_set`, and `build_recipe_map` methods are expensive. For now, they run on every request. This is fine per the "no caching" decision — optimize later.

4. Write the recipe helper:

```ruby
# frozen_string_literal: true

module RecipesHelper
  def render_markdown(text)
    return '' if text.blank?

    markdown = Redcarpet::Markdown.new(
      Redcarpet::Render::SmartyHTML.new,
      autolink: true,
      no_intra_emphasis: true
    )
    markdown.render(text).html_safe
  end

  def scalable_instructions(text)
    return '' if text.blank?

    processed = ScalableNumberPreprocessor.process_instructions(text)
    render_markdown(processed)
  end

  def format_yield_line(text)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_line(text).html_safe
  end

  def format_yield_with_unit(text, singular, plural)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_with_unit(text, singular, plural).html_safe
  end
end
```

5. Write the recipe view (`app/views/recipes/show.html.erb`). Port from `recipe-template.html.erb` but use Rails conventions:

```erb
<% content_for(:title) { @recipe.title } %>

<% content_for(:body_attrs) do %>
  data-recipe-id="<%= @recipe.slug %>" data-version-hash="<%= Digest::SHA256.hexdigest(@recipe.markdown_source) %>"
<% end %>

<% content_for(:extra_nav) do %>
    <div>
      <button type="button" id="scale-button" class="btn">Scale</button>
    </div>
<% end %>

<% content_for(:scripts) do %>
  <%= javascript_include_tag 'notify', defer: true %>
  <%= javascript_include_tag 'wake-lock', defer: true %>
  <%= javascript_include_tag 'recipe-state-manager', defer: true %>
<% end %>

<article class="recipe">
  <header>
    <h1><%= @recipe.title %></h1>
    <%- if @recipe.description.present? -%>
    <p><%= @recipe.description %></p>
    <%- end -%>
    <p class="recipe-meta">
      <%= link_to @recipe.category.name, root_path(anchor: @recipe.category.slug) %><%- if @recipe.makes -%>
      <%- if @nutrition&.makes_unit_singular -%>
      · Makes <%= format_yield_with_unit(@recipe.makes, @nutrition.makes_unit_singular, @nutrition.makes_unit_plural) %><%- else -%>
      · Makes <%= format_yield_line(@recipe.makes) %><%- end -%><%- end -%><%- if @recipe.serves -%>
      · Serves <%= format_yield_line(@recipe.serves.to_s) %><%- end -%>
    </p>
  </header>

  <% @recipe.steps.each do |step| %>
    <%= render 'step', step: step %>
  <% end %>

  <footer>
    <%- if @recipe.footer.present? -%>
    <%= render_markdown(@recipe.footer) %>
    <%- end -%>
  </footer>

  <%- if @nutrition && @nutrition.totals.values.any? { |v| v > 0 } -%>
    <%= render 'nutrition_table', nutrition: @nutrition %>
  <%- end -%>
</article>
```

6. Write the step partial. This needs to handle both regular ingredients (from DB) and cross-references (resolved from markdown at render time). The step partial should iterate the DB ingredients. Cross-references need a different rendering path — they're parsed from markdown.

**This is the tricky part.** The existing template iterates `step.ingredient_list_items` which interleaves `Ingredient` and `CrossReference` objects. Our DB only stores real ingredients. Cross-references live in the markdown.

**Solution:** Build a combined ingredient list in the controller (or a presenter/decorator) that merges DB ingredients with parsed cross-references in their original order. The `position` column on ingredients was designed to preserve order, but cross-references need positions too.

**Revised approach for the step partial:** Re-parse the markdown to get the original `ingredient_list_items` order (which interleaves ingredients and cross-references), then render each item — real ingredients show DB data, cross-references render as links. This preserves the exact rendering behavior.

Add a method to the controller that builds the step rendering data:

```ruby
# In RecipesController, add to show action:
@parsed_recipe = FamilyRecipes::Recipe.new(
  markdown_source: @recipe.markdown_source,
  id: @recipe.slug,
  category: @recipe.category.name
)
```

The view uses `@parsed_recipe.steps` for rendering (which has the full ingredient_list_items), while `@recipe` provides the AR model data. This is a pragmatic bridge: the parser knows how to interleave ingredients and cross-references; the DB stores structured data.

**Simplified step partial using the parsed recipe:**

```erb
<%# app/views/recipes/_step.html.erb %>
<%
  # Find the matching parsed step by position
  parsed_step = @parsed_recipe.steps[step.position]
%>
<section>
  <h2><%= step.title %></h2>
  <div>
    <%- if parsed_step && parsed_step.ingredient_list_items.any? -%>
    <div class="ingredients">
      <ul>
        <%- parsed_step.ingredient_list_items.each do |item| -%>
        <%- if item.is_a?(FamilyRecipes::CrossReference) -%>
        <li class="cross-reference"><b><%= link_to item.target_title, recipe_path(item.target_slug) %></b><% if item.multiplier != 1.0 %>, <span class="quantity"><%= item.multiplier == item.multiplier.to_i ? item.multiplier.to_i : item.multiplier %></span><% end %>
        <%- if item.prep_note -%>
          <small><%= item.prep_note %></small>
        <%- end -%>
        </li>
        <%- else -%>
        <li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2)}") if item.quantity_unit %><% end %>>
          <b><%= item.name %></b><% if item.quantity %>, <span class="quantity"><%= item.quantity %></span><% end %>
        <%- if item.prep_note -%>
          <small><%= item.prep_note %></small>
        <%- end -%>
        </li>
        <%- end -%>
        <%- end -%>
      </ul>
    </div>
    <%- end -%>

    <%- if parsed_step && parsed_step.instructions.present? -%>
    <div class="instructions">
      <%= scalable_instructions(parsed_step.instructions) %>
    </div>
    <%- end -%>
  </div>
</section>
```

**Note:** Yes, this uses the parsed recipe for rendering rather than the AR model. This is intentional for v1 — it preserves exact rendering parity with the static site. The AR model is the source of truth for data; the parser handles rendering details (cross-reference interleaving, scalable number markup). Over time, as cross-references evolve, this rendering approach can change without DB migrations.

7. Write the nutrition table partial (port from `recipe-template.html.erb` lines 71-138):

```erb
<%# app/views/recipes/_nutrition_table.html.erb %>
<aside class="nutrition-facts">
  <h2>Nutrition Facts</h2>
  <%
    has_per_unit = nutrition.per_unit && nutrition.makes_quantity && nutrition.makes_quantity > 0
    has_per_serving = nutrition.per_serving && nutrition.serving_count

    columns = []

    if has_per_unit
      columns << ["Per #{nutrition.makes_unit_singular.capitalize}", nutrition.per_unit, false]
      if has_per_serving && nutrition.units_per_serving
        ups = nutrition.units_per_serving
        formatted_ups = FamilyRecipes::VulgarFractions.format(ups)
        singular = FamilyRecipes::VulgarFractions.singular_noun?(ups)
        ups_unit = singular ? nutrition.makes_unit_singular : nutrition.makes_unit_plural
        columns << ["Per Serving<br>(#{formatted_ups} #{ups_unit})".html_safe, nutrition.per_serving, false]
      end
      columns << ['Total', nutrition.totals, true]
    elsif has_per_serving
      columns << ['Per Serving', nutrition.per_serving, false]
      columns << ['Total', nutrition.totals, true]
    else
      columns << ['Total', nutrition.totals, true]
    end
  %>
  <table>
    <thead>
      <tr>
        <th></th>
        <%- columns.each do |label, _, _| -%>
        <th><%= label %></th>
        <%- end -%>
      </tr>
    </thead>
    <tbody>
      <%- [
        ['Calories', :calories, '', 0],
        ['Total Fat', :fat, 'g', 0],
        ['Sat. Fat', :saturated_fat, 'g', 1],
        ['Trans Fat', :trans_fat, 'g', 1],
        ['Cholesterol', :cholesterol, 'mg', 0],
        ['Sodium', :sodium, 'mg', 0],
        ['Total Carbs', :carbs, 'g', 0],
        ['Fiber', :fiber, 'g', 1],
        ['Total Sugars', :total_sugars, 'g', 1],
        ['Added Sugars', :added_sugars, 'g', 2],
        ['Protein', :protein, 'g', 0],
      ].each do |label, key, unit_label, indent| -%>
      <tr<%= %( class="indent-#{indent}").html_safe if indent > 0 %>>
        <td><%= label %></td>
        <%- columns.each do |_, values, is_scalable| -%>
        <td<%= %( data-nutrient="#{key}" data-base-value="#{values[key].round(1)}").html_safe if is_scalable %>><%= values[key].round %><%= unit_label %></td>
        <%- end -%>
      </tr>
      <%- end -%>
    </tbody>
  </table>
  <%- unless nutrition.complete? -%>
  <p class="nutrition-note">*Approximate. Data unavailable for: <%= (nutrition.missing_ingredients + nutrition.partial_ingredients).uniq.join(', ') %>.</p>
  <%- end -%>
</aside>
```

8. Run tests, verify they pass.
9. Run `rake lint`.
10. Commit: `feat: add recipe controller, views, and helpers`

---

## Task 11: Ingredients Index Controller and View

**Files:**
- Create: `app/controllers/ingredients_controller.rb`
- Create: `app/views/ingredients/index.html.erb`
- Create: `test/controllers/ingredients_controller_test.rb`

**Steps:**

1. Write the failing test:

```ruby
# frozen_string_literal: true

require 'test_helper'

class IngredientsControllerTest < ActionDispatch::IntegrationTest
  test 'renders ingredient index grouped by ingredient name' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    get ingredients_path

    assert_response :success
    assert_select 'h1', 'Ingredient Index'
    assert_select 'h2', 'Flour'
    assert_select 'a[href=?]', recipe_path('focaccia'), text: 'Focaccia'
  end
end
```

2. Run test, verify it fails.

3. Write the controller. The ingredient index needs to group recipes by ingredient name. Use the parser's alias map for canonical names:

```ruby
# frozen_string_literal: true

class IngredientsController < ApplicationController
  def index
    @ingredients_with_recipes = build_ingredient_index
  end

  private

  def build_ingredient_index
    alias_map = load_alias_map

    index = Hash.new { |h, k| h[k] = [] }

    Recipe.includes(steps: :ingredients).find_each do |recipe|
      recipe.ingredients.each do |ingredient|
        canonical = alias_map[ingredient.name.downcase] || ingredient.name
        index[canonical] << recipe unless index[canonical].include?(recipe)
      end
    end

    index.sort_by { |name, _| name.downcase }
  end

  def load_alias_map
    grocery_aisles = FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
    FamilyRecipes.build_alias_map(grocery_aisles)
  end
end
```

4. Write the view:

```erb
<%# app/views/ingredients/index.html.erb %>
<% content_for(:title) { 'Biagini Family Recipes: Index' } %>

<article class="index">
  <header>
    <h1>Ingredient Index</h1>
  </header>

  <%- @ingredients_with_recipes.each do |ingredient, recipes| -%>
  <section>
    <h2><%= ingredient %></h2>
    <ul>
      <%- recipes.each do |recipe| -%>
      <li><%= link_to recipe.title, recipe_path(recipe.slug), title: recipe.description %></li>
      <%- end -%>
    </ul>
  </section>
  <%- end -%>
</article>
```

5. Run tests, verify they pass.
6. Commit: `feat: add ingredients index controller and view`

---

## Task 12: Groceries Controller and View

The groceries page is the most JS-heavy page. The view generates the recipe selector checkboxes with ingredient data attributes, the aisle-organized grocery list, and includes QR/share functionality.

**Files:**
- Create: `app/controllers/groceries_controller.rb`
- Create: `app/views/groceries/show.html.erb`
- Create: `app/helpers/groceries_helper.rb`
- Create: `test/controllers/groceries_controller_test.rb`

**Steps:**

1. Write the failing test:

```ruby
# frozen_string_literal: true

require 'test_helper'

class GroceriesControllerTest < ActionDispatch::IntegrationTest
  test 'renders the groceries page with recipe checkboxes' do
    Category.create!(name: 'Bread', slug: 'bread', position: 0)
    MarkdownImporter.import(<<~MD)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD

    get groceries_path

    assert_response :success
    assert_select 'h1', 'Groceries'
    assert_select 'input[type=checkbox][data-title="Focaccia"]'
  end
end
```

2. Run test, verify it fails.

3. Write the controller. This needs to load recipes with ingredients, build the grocery database, compute ingredient quantities for each recipe (with cross-reference expansion), and pass it all to the view:

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
  end

  private

  def load_grocery_aisles
    FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
  end

  def build_omit_set
    (@grocery_aisles['Omit_From_List'] || []).flat_map do |item|
      [item[:name], *item[:aliases]].map(&:downcase)
    end.to_set
  end

  def build_recipe_map
    recipes_dir = Rails.root.join('recipes')
    FamilyRecipes.parse_recipes(recipes_dir).to_h { |r| [r.id, r] }
  end

  def collect_unit_plurals
    parsed_recipes = @recipe_map.values
    parsed_recipes
      .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
      .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
      .uniq
      .to_h { |u| [u, FamilyRecipes::Inflector.unit_display(u, 2)] }
  end
end
```

4. Write a helper for HTML escaping in data attributes:

```ruby
# frozen_string_literal: true

module GroceriesHelper
  def recipe_ingredients_json(parsed_recipe)
    ingredients = parsed_recipe.all_ingredients_with_quantities(@alias_map, @recipe_map)
    filtered = ingredients.reject { |name, _| @omit_set.include?(name.downcase) }
    filtered.to_json
  end
end
```

5. Write the view. Port from `groceries-template.html.erb`. This is a large template — port it faithfully, replacing lambda calls with Rails helpers:

```erb
<%# app/views/groceries/show.html.erb %>
<% content_for(:title) { 'Biagini Family Recipes: Groceries' } %>

<% content_for(:head) do %>
  <%= stylesheet_link_tag 'groceries' %>
<% end %>

<% content_for(:scripts) do %>
  <script>
    window.UNIT_PLURALS = <%= @unit_plurals.to_json.html_safe %>;
  </script>
  <%= javascript_include_tag 'notify', defer: true %>
  <%= javascript_include_tag 'wake-lock', defer: true %>
  <%= javascript_include_tag 'qrcodegen', defer: true %>
  <%= javascript_include_tag 'groceries', defer: true %>
<% end %>

<header id="groceries-header">
  <h1>Groceries</h1>
</header>

<noscript>
  <p><em>This page requires JavaScript to build your shopping list.</em></p>
</noscript>

<p id="instructions" class="hidden-until-js">Select recipes to build your shopping list.</p>

<div id="recipe-selector" class="hidden-until-js">
  <%- @categories.each do |category| -%>
  <%- next if category.recipes.empty? -%>
  <div class="category">
    <h2><%= category.name %></h2>
    <ul>
    <%- category.recipes.alphabetical.each do |recipe| -%>
      <%- parsed = @recipe_map[recipe.slug] -%>
      <%- next unless parsed -%>
      <%- filtered_ingredients = parsed.all_ingredients_with_quantities(@alias_map, @recipe_map).reject { |name, _| @omit_set.include?(name.downcase) } -%>
      <li>
        <input type="checkbox" id="<%= recipe.slug %>-checkbox" data-title="<%= h recipe.title %>" data-ingredients="<%= h filtered_ingredients.to_json %>">
        <label for="<%= recipe.slug %>-checkbox" title="Ingredients: <%= h filtered_ingredients.map(&:first).join(', ') %>"><%= recipe.title %></label>
        <%= link_to '→', recipe_path(recipe.slug), class: 'recipe-link', title: "Open #{recipe.title} in new tab", target: '_blank' %>
      </li>
    <%- end -%>
    </ul>
  </div>
  <%- end -%>
</div>

<div id="custom-items-section" class="hidden-until-js">
  <h2>Additional Items</h2>
  <div id="custom-input-row">
    <label for="custom-input" class="sr-only">Add a custom item</label>
    <input type="text" id="custom-input" placeholder="Add an item...">
    <button id="custom-add" type="button" aria-label="Add item"><svg viewBox="0 0 24 24" width="18" height="18"><line x1="12" y1="5" x2="12" y2="19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
  </div>
  <ul id="custom-items-list"></ul>
</div>

<div id="share-section" class="hidden-until-js">
  <h2>Share</h2>
  <p id="share-hint">Scan the QR code or copy the link below to open this list on another device.</p>
  <div id="qr-container"></div>
  <div id="share-url-row">
    <code id="share-url"></code>
    <button id="share-action" type="button" aria-label="Share or copy link"></button>
  </div>
  <p id="share-feedback" hidden></p>
</div>

<div id="grocery-preview" class="hidden-until-js">
  <div id="grocery-preview-header">
    <h2>Shopping List</h2>
    <span class="item-count" id="item-count"></span>
  </div>
  <p id="grocery-preview-empty">Select recipes above to build your shopping list.</p>

  <section id="grocery-list">
  <%- @grocery_aisles.each do |aisle, ingredients| -%>
  <%- next if aisle == 'Omit_From_List' -%>
  <details class="aisle">
    <summary><%= aisle %> <span class="aisle-count"></span></summary>
    <ul>
      <%- ingredients.each do |ingredient| -%>
        <li data-item="<%= h ingredient[:name] %>" hidden>
          <label class="check-off">
            <input type="checkbox">
            <span><%= ingredient[:name] %><span class="qty"></span></span>
          </label>
        </li>
      <%- end -%>
    </ul>
  </details>
  <%- end -%>

  <details class="aisle" id="misc-aisle">
    <summary>Miscellaneous <span class="aisle-count"></span></summary>
    <ul id="misc-items"></ul>
  </details>
  </section>
</div>
```

6. Run tests, verify they pass.
7. Manually verify the groceries page renders correctly in a browser (start `rails s`, navigate to `/groceries`).
8. Commit: `feat: add groceries controller and view`

**Notes:**
- The groceries page uses the parser's `Recipe` objects for ingredient aggregation with cross-reference expansion. This is the same pattern as the recipe page — the parser handles cross-reference resolution while the DB stores structured data.
- Quick Bites are excluded from v1 as noted in the design. The Quick Bites section of the template is omitted.

---

## Task 13: Retire the Static Pipeline

Remove all static site generation code and related infrastructure.

**Files to delete:**
- `bin/generate`
- `bin/serve`
- `lib/familyrecipes/site_generator.rb`
- `lib/familyrecipes/pdf_generator.rb`
- `templates/web/` (entire directory)
- `output/` (entire directory, if present)
- `app/middleware/static_output_middleware.rb`
- `app/services/recipe_finder.rb`
- `app/services/recipe_renderer.rb`
- `config/initializers/recipe_watcher.rb`
- `test/site_generator_test.rb`
- `test/controllers/recipes_controller_test.rb` (old version, replaced in Task 10)
- `test/middleware/static_output_middleware_test.rb`

**Files to modify:**
- `lib/familyrecipes.rb` — remove `require_relative` for `site_generator` and `pdf_generator`
- `config/environments/development.rb` — remove `StaticOutputMiddleware` insertion
- `config/initializers/familyrecipes.rb` — remove `FamilyRecipes.template_dir =` line (no longer needed for static rendering; may still be needed for parser tests — check)
- `Gemfile` — remove `webrick` from development group (no longer serving static files)
- `lib/tasks/familyrecipes.rake` — remove `:build` task that calls `bin/generate`

**Steps:**

1. Delete all files listed above.
2. Update `lib/familyrecipes.rb` to remove `site_generator` and `pdf_generator` requires.
3. Remove `StaticOutputMiddleware` from development config.
4. Remove `recipe_watcher.rb` initializer.
5. Check if `FamilyRecipes.template_dir` is still needed anywhere (tests for `Recipe#to_html` use it). If so, keep the template_dir accessor but set it only in test_helper. If not, remove it.
6. Run `rake test` — fix any broken tests that depended on deleted code.
7. Run `rake lint`.
8. Commit: `feat: retire static site generator and related infrastructure`

**Notes:**
- `resources/web/` can also be deleted now since assets live in `app/assets/`. But verify first that nothing else references it.
- The `test/test_helper.rb` sets `FamilyRecipes.template_dir` — this is only needed if parser tests call `Recipe#to_html`. If we keep the parser's `to_html` method (for now), keep the template_dir in test_helper. Otherwise, those tests should be rewritten to test through the controller.

---

## Task 14: Simplify bin/dev and Configuration

**Files:**
- Modify: `bin/dev` — simplify to just start Puma
- Modify: `config/initializers/familyrecipes.rb` — just load the domain model
- Modify: `Rakefile` and `lib/tasks/familyrecipes.rake` — update task list
- Modify: `config/application.rb` — clean up conditional ActiveRecord logic

**Steps:**

1. Simplify `bin/dev` to just start the Rails server:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

exec 'bin/rails', 'server', '-p', '3030'
```

Or even simpler — just use `bin/rails server`. But keeping `bin/dev` as a convention is fine.

2. Update `config/initializers/familyrecipes.rb`:

```ruby
# frozen_string_literal: true

require_relative '../../lib/familyrecipes'
```

No more `template_dir` setting — views are handled by Rails.

3. Update rake tasks:
- Remove `:build` task
- Remove `:clean` task (no output directory)
- Keep `:test` and `:lint`
- Add `db:seed` to the setup workflow

4. Clean up `config/application.rb`:
- Remove conditional `ActiveRecord` loading — it's always loaded now
- Remove the `unless defined?(ActiveRecord)` model path exclusion

5. Run full test suite.
6. Commit: `chore: simplify bin/dev and clean up configuration`

---

## Task 15: End-to-End Verification and Test Cleanup

**Files:**
- Modify: various test files
- Create: `test/integration/` tests if needed

**Steps:**

1. Run `rails db:reset` (drop, create, migrate, seed) from scratch.
2. Start the server with `bin/dev`.
3. Manually verify each page:
   - `http://localhost:3030/` — homepage loads, categories displayed, recipe links work
   - `http://localhost:3030/recipes/focaccia` — recipe renders with ingredients, steps, nutrition
   - `http://localhost:3030/index` — ingredient index renders
   - `http://localhost:3030/groceries` — grocery page renders, checkboxes work, JS functional
4. Verify scaling works on a recipe page (click Scale, enter 2).
5. Verify cross-off works (click an ingredient).
6. Verify the grocery list builds when selecting recipes.
7. Fix any issues discovered during manual testing.
8. Update/add integration tests for any gaps.
9. Run `rake` (lint + test) — everything green.
10. Commit: `test: add integration tests and fix verification issues`

---

## Execution Notes

**Database requirement:** PostgreSQL must be running locally. Create databases with `rails db:create`.

**Order matters:** Tasks 1-6 build the foundation. Tasks 7-8 set up the Rails plumbing. Tasks 9-12 build the four pages. Tasks 13-14 clean up. Task 15 verifies everything.

**The parsed-recipe bridge pattern:** Tasks 10 and 12 use a pragmatic bridge: the controller re-parses the markdown into parser `FamilyRecipes::Recipe` objects for rendering (nutrition calculation, cross-reference resolution, scalable number preprocessing). This is intentional — it preserves rendering parity without rewriting the parser's rendering logic into the AR model layer. As the app evolves (especially the editor), these concerns will migrate into proper AR model methods or service objects.

**What's NOT covered here:**
- Quick Bites (deferred — can be a follow-up task)
- Authentication (deferred until editor)
- Docker packaging (deferred)
- CI updates for this branch (deferred until merge to main)
- Caching (not needed yet)

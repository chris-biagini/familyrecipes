# SQLite Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Migrate from PostgreSQL to SQLite with a three-database architecture (primary, cable, queue), clean up the schema, merge seed files, and simplify Docker deployment.

**Architecture:** Three SQLite databases (primary, cable, queue) running in Rails 8 multi-database mode. Solid Cable and Solid Queue each get their own database file to avoid write contention. Fresh schema migration replaces all legacy PG migrations.

**Tech Stack:** SQLite3, Solid Cable, Solid Queue, Rails 8 multi-database

**Design doc:** `docs/plans/2026-02-24-sqlite-migration-design.md`

---

### Task 0: Create worktree and branch

**Files:**
- None (git operation)

**Step 1: Create the working branch**

```bash
cd /home/claude/familyrecipes
git checkout -b sqlite-migration
```

**Step 2: Commit** — nothing to commit yet, branch is created.

---

### Task 1: Swap gems (pg → sqlite3, add solid_queue)

**Files:**
- Modify: `Gemfile`
- Modify: `Gemfile.lock` (via bundle)

**Step 1: Edit the Gemfile**

Replace `gem 'pg'` with `gem 'sqlite3'`. Add `gem 'solid_queue'` alongside `solid_cable`. The gems section should look like:

```ruby
gem 'propshaft'
gem 'puma', '>= 5'
gem 'rails', '~> 8.0'

gem 'minitest'
gem 'sqlite3'
gem 'rake'
gem 'redcarpet'

gem 'acts_as_tenant'
gem 'omniauth'
gem 'omniauth-rails_csrf_protection'
gem 'solid_cable'
gem 'solid_queue'
```

**Step 2: Bundle install**

Run: `bundle install`
Expected: success, Gemfile.lock updated

**Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: swap pg gem for sqlite3, add solid_queue"
```

---

### Task 2: Configure three-database architecture

**Files:**
- Rewrite: `config/database.yml`
- Modify: `config/cable.yml`
- Create: `config/queue.yml`
- Modify: `config/puma.rb`

**Step 1: Rewrite database.yml**

```yaml
default: &default
  adapter: sqlite3
  pool: 5
  timeout: 5000
  idle_timeout: 300
  pragmas:
    journal_mode: wal
    synchronous: normal
    mmap_size: 134217728
    cache_size: -64000

development:
  primary:
    <<: *default
    database: storage/development.sqlite3
  cable:
    <<: *default
    database: storage/development_cable.sqlite3
    migrations_paths: db/cable_migrate
  queue:
    <<: *default
    database: storage/development_queue.sqlite3
    migrations_paths: db/queue_migrate

test:
  primary:
    <<: *default
    database: storage/test.sqlite3
  cable:
    <<: *default
    database: storage/test_cable.sqlite3
    migrations_paths: db/cable_migrate
  queue:
    <<: *default
    database: storage/test_queue.sqlite3
    migrations_paths: db/queue_migrate

production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  cable:
    <<: *default
    database: storage/production_cable.sqlite3
    migrations_paths: db/cable_migrate
  queue:
    <<: *default
    database: storage/production_queue.sqlite3
    migrations_paths: db/queue_migrate
```

**Step 2: Update cable.yml to reference the cable database**

```yaml
development:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day

test:
  adapter: test

production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

**Step 3: Create config/queue.yml**

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 1
      polling_interval: 0.1

development:
  <<: *default

production:
  <<: *default
```

**Step 4: Add Solid Cable and Solid Queue plugins to puma.rb**

Add these two lines after the `plugin :tmp_restart` line in `config/puma.rb`:

```ruby
plugin :solid_cable
plugin :solid_queue
```

**Step 5: Create storage/ directory**

```bash
mkdir -p storage
touch storage/.keep
```

Make sure `.gitignore` ignores `storage/*.sqlite3*` but keeps `.keep`.

**Step 6: Commit**

```bash
git add config/database.yml config/cable.yml config/queue.yml config/puma.rb storage/.keep
git commit -m "feat: configure three-database SQLite architecture"
```

---

### Task 3: Fresh schema migration for primary database

**Files:**
- Delete: all files in `db/migrate/`
- Create: `db/migrate/001_create_schema.rb`

**Step 1: Delete all existing migrations**

```bash
rm -f db/migrate/*.rb
```

**Step 2: Write the fresh schema migration**

Create `db/migrate/001_create_schema.rb` with the clean schema. Key changes from the old schema:

- No `enable_extension "pg_catalog.plpgsql"`
- No `recipe_dependencies` table
- No `site_documents` table
- No `solid_cable_messages` table (managed by cable DB)
- `ingredient_profiles` → `ingredient_catalog`
- `jsonb` → `json`
- `kitchens` gets `quick_bites_content` text column

```ruby
# frozen_string_literal: true

class CreateSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchens do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :quick_bites_content
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
      t.index :email, unique: true
    end

    create_table :memberships do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'member'
      t.timestamps
      t.index %i[kitchen_id user_id], unique: true
    end

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :connected_services do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
      t.index %i[provider uid], unique: true
    end

    create_table :categories do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[kitchen_id slug], unique: true
      t.index :position
    end

    create_table :recipes do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.text :footer
      t.text :markdown_source, null: false
      t.decimal :makes_quantity
      t.string :makes_unit_noun
      t.integer :serves
      t.json :nutrition_data
      t.datetime :edited_at
      t.timestamps
      t.index %i[kitchen_id slug], unique: true
    end

    create_table :steps do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :position, null: false
      t.text :instructions
      t.text :processed_instructions
      t.timestamps
    end

    create_table :ingredients do |t|
      t.references :step, null: false, foreign_key: true
      t.string :name, null: false
      t.string :quantity
      t.string :unit
      t.string :prep_note
      t.integer :position, null: false
      t.timestamps
    end

    create_table :cross_references do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :step, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.decimal :multiplier, precision: 8, scale: 2, null: false, default: 1.0
      t.string :prep_note
      t.integer :position, null: false
      t.timestamps
      t.index %i[step_id position], unique: true
    end

    create_table :ingredient_catalog do |t|
      t.references :kitchen, foreign_key: true
      t.string :ingredient_name, null: false
      t.string :aisle
      t.decimal :basis_grams
      t.decimal :calories
      t.decimal :fat
      t.decimal :saturated_fat
      t.decimal :trans_fat
      t.decimal :cholesterol
      t.decimal :sodium
      t.decimal :carbs
      t.decimal :fiber
      t.decimal :total_sugars
      t.decimal :added_sugars
      t.decimal :protein
      t.decimal :density_grams
      t.decimal :density_volume
      t.string :density_unit
      t.json :portions, default: {}
      t.json :sources, default: []
      t.timestamps
      t.index :ingredient_name, unique: true, where: 'kitchen_id IS NULL',
              name: 'index_ingredient_catalog_global_unique'
      t.index %i[kitchen_id ingredient_name], unique: true
    end

    create_table :grocery_lists do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.json :state, null: false, default: {}
      t.integer :version, null: false, default: 0
      t.timestamps
      t.index :kitchen_id, unique: true
    end
  end
end
```

**Step 3: Verify migration runs**

```bash
bin/rails db:drop db:create db:migrate
```

Expected: databases created, schema applied, no errors.

**Step 4: Commit**

```bash
git add db/migrate/
git commit -m "feat: fresh schema migration for SQLite (drops PG-only tables)"
```

---

### Task 4: Set up Solid Cable and Solid Queue migrations

**Files:**
- Create: `db/cable_migrate/` (via Solid Cable install generator)
- Create: `db/queue_migrate/` (via Solid Queue install generator)

**Step 1: Generate Solid Cable migrations**

```bash
bin/rails solid_cable:install:migrations
```

This creates migration files in `db/cable_migrate/`. If the generator puts them elsewhere, move them manually.

**Step 2: Generate Solid Queue migrations**

```bash
bin/rails solid_queue:install:migrations
```

This creates migration files in `db/queue_migrate/`.

**Step 3: Run all migrations across all databases**

```bash
bin/rails db:migrate
```

Expected: primary, cable, and queue databases all migrated.

**Step 4: Commit**

```bash
git add db/cable_migrate/ db/queue_migrate/
git commit -m "feat: add Solid Cable and Solid Queue migrations for separate databases"
```

---

### Task 5: Rename IngredientProfile → IngredientCatalog

This is a mechanical rename across the codebase. Every reference changes.

**Files:**
- Rename: `app/models/ingredient_profile.rb` → `app/models/ingredient_catalog.rb`
- Rename: `test/models/ingredient_profile_test.rb` → `test/models/ingredient_catalog_test.rb`
- Modify: `app/models/kitchen.rb` (association name)
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Modify: `app/services/shopping_list_builder.rb`
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Modify: `lib/familyrecipes/build_validator.rb`
- Modify: `db/seeds.rb`
- Modify: all test files that reference IngredientProfile

**Step 1: Rename model file and update class name**

`app/models/ingredient_catalog.rb`:

```ruby
# frozen_string_literal: true

class IngredientCatalog < ApplicationRecord
  self.table_name = 'ingredient_catalog'

  belongs_to :kitchen, optional: true

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, numericality: { greater_than: 0 }, allow_nil: true

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  def self.lookup_for(kitchen)
    global.index_by(&:ingredient_name)
          .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
  end
end
```

Note: `self.table_name = 'ingredient_catalog'` is needed because Rails would pluralize the class name to `ingredient_catalogs`, but our table is `ingredient_catalog` (collective noun, not pluralized).

**Step 2: Delete old model file**

```bash
rm app/models/ingredient_profile.rb
```

**Step 3: Update Kitchen model association**

In `app/models/kitchen.rb`, change `has_many :ingredient_profiles` to `has_many :ingredient_catalog`. Remove the `:recipe_dependencies` and `:site_documents` associations too (those models are being deleted):

```ruby
# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :ingredient_catalog, dependent: :destroy, class_name: 'IngredientCatalog'
  has_one :grocery_list, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
  end
end
```

**Step 4: Rename in all other source files**

Find-and-replace `IngredientProfile` → `IngredientCatalog` in:
- `app/controllers/ingredients_controller.rb:6`
- `app/controllers/nutrition_entries_controller.rb:10,22`
- `app/services/shopping_list_builder.rb:7`
- `app/jobs/recipe_nutrition_job.rb:20,51`
- `lib/familyrecipes/build_validator.rb:28,46,97`
- `db/seeds.rb` (all references)

**Step 5: Rename and update test file**

Move `test/models/ingredient_profile_test.rb` → `test/models/ingredient_catalog_test.rb`. Update the class reference inside the file from `IngredientProfile` to `IngredientCatalog`.

Also update `IngredientProfile` → `IngredientCatalog` in all other test files:
- `test/build_validator_test.rb`
- `test/services/shopping_list_builder_test.rb`
- `test/controllers/nutrition_entries_controller_test.rb`
- `test/controllers/ingredients_controller_test.rb`
- `test/controllers/groceries_controller_test.rb`
- `test/jobs/recipe_nutrition_job_test.rb`

**Step 6: Run tests to verify rename**

```bash
rake test
```

Expected: all tests pass (they'll fail because DB isn't seeded, but the rename should be syntactically correct — no NameErrors).

**Step 7: Commit**

```bash
git add -A
git commit -m "refactor: rename IngredientProfile to IngredientCatalog"
```

---

### Task 6: Delete RecipeDependency model and all references

**Files:**
- Delete: `app/models/recipe_dependency.rb`
- Delete: `test/models/recipe_dependency_test.rb`
- Modify: `app/models/recipe.rb` (remove dependency associations)
- Modify: `app/services/markdown_importer.rb` (remove rebuild_dependencies)

**Step 1: Delete model and test files**

```bash
rm app/models/recipe_dependency.rb test/models/recipe_dependency_test.rb
```

**Step 2: Remove associations from Recipe model**

In `app/models/recipe.rb`, remove lines 10–19 (the outbound_dependencies, inbound_dependencies, referenced_recipes, referencing_recipes associations). The model should become:

```ruby
# frozen_string_literal: true

class Recipe < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :category

  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }
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

**Step 3: Remove rebuild_dependencies from MarkdownImporter**

In `app/services/markdown_importer.rb`:
- Remove the `rebuild_dependencies(recipe)` call from `save_recipe` (line 30)
- Remove the `rebuild_dependencies` method (lines 147–159)

**Step 4: Run tests**

```bash
rake test
```

Expected: tests pass (minus any that explicitly tested recipe_dependencies — those files are deleted).

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: drop RecipeDependency model (derive from CrossReference)"
```

---

### Task 7: Delete SiteDocument model, move Quick Bites to Kitchen

**Files:**
- Delete: `app/models/site_document.rb`
- Delete: `test/models/site_document_test.rb`
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `app/services/shopping_list_builder.rb`
- Modify: all tests that create SiteDocument fixtures

**Step 1: Delete model and test**

```bash
rm app/models/site_document.rb test/models/site_document_test.rb
```

**Step 2: Update GroceriesController**

Replace all SiteDocument references with `current_kitchen.quick_bites_content`:

```ruby
# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership, only: %i[select check update_custom_items clear update_quick_bites]

  def show
    @categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = current_kitchen.quick_bites_content || ''
  end

  def state
    list = GroceryList.for_kitchen(current_kitchen)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, grocery_list: list).build

    render json: {
      version: list.version,
      **list.state.slice(*GroceryList::STATE_KEYS),
      shopping_list: shopping_list
    }
  end

  def select
    apply_and_respond('select',
                      type: params[:type],
                      slug: params[:slug],
                      selected: params[:selected])
  end

  def check
    apply_and_respond('check',
                      item: params[:item],
                      checked: params[:checked])
  end

  def update_custom_items
    apply_and_respond('custom_items',
                      item: params[:item],
                      action: params[:action_type])
  end

  def clear
    list = GroceryList.for_kitchen(current_kitchen)
    list.clear!
    GroceryListChannel.broadcast_version(current_kitchen, list.version)
    render json: { version: list.version }
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_entity if content.blank?

    current_kitchen.update!(quick_bites_content: content)

    GroceryListChannel.broadcast_content_changed(current_kitchen)
    render json: { status: 'ok' }
  end

  private

  def apply_and_respond(action_type, **action_params)
    list = GroceryList.for_kitchen(current_kitchen)
    list.apply_action(action_type, **action_params)
    GroceryListChannel.broadcast_version(current_kitchen, list.version)
    render json: { version: list.version }
  end

  def load_quick_bites_by_subsection
    content = current_kitchen.quick_bites_content
    return {} unless content

    FamilyRecipes.parse_quick_bites_content(content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end
end
```

**Step 3: Update ShoppingListBuilder**

In `app/services/shopping_list_builder.rb`, change the `selected_quick_bites` method (line 40) from reading `@kitchen.site_documents.find_by(name: 'quick_bites')` to reading `@kitchen.quick_bites_content`:

```ruby
def selected_quick_bites
  slugs = @grocery_list.state.fetch('selected_quick_bites', [])
  return [] if slugs.empty?

  content = @kitchen.quick_bites_content
  return [] unless content

  all_bites = FamilyRecipes.parse_quick_bites_content(content)
  all_bites.select { |qb| slugs.include?(qb.id) }
end
```

**Step 4: Update all tests that create SiteDocument fixtures**

In any test file that creates `SiteDocument.create!(kitchen: @kitchen, name: 'quick_bites', content: ...)`, change to `@kitchen.update!(quick_bites_content: ...)` instead.

Files to update:
- `test/controllers/groceries_controller_test.rb`
- `test/services/shopping_list_builder_test.rb`
- `test/integration/end_to_end_test.rb`

For any test that creates `SiteDocument.create!(name: 'site_config', ...)`, remove those lines entirely (site config is now loaded from `config/site.yml` — see Task 8).

**Step 5: Run tests**

```bash
rake test
```

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move Quick Bites to Kitchen column, delete SiteDocument model"
```

---

### Task 8: Replace site_config SiteDocument with config/site.yml

**Files:**
- Create: `config/site.yml`
- Create: `config/initializers/site_config.rb`
- Modify: `app/controllers/homepage_controller.rb`
- Modify: `app/views/homepage/show.html.erb`
- Delete: `db/seeds/resources/site-config.yaml`
- Modify: test files that depend on site_config

**Step 1: Create config/site.yml**

```yaml
default: &default
  site_title: Biagini Family Recipes
  homepage_heading: Our Recipes
  homepage_subtitle: "A collection of our family's favorite recipes."
  github_url: https://github.com/chris-biagini/familyrecipes

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

**Step 2: Create initializer**

`config/initializers/site_config.rb`:

```ruby
# frozen_string_literal: true

Rails.configuration.site = Rails.application.config_for(:site)
```

**Step 3: Simplify HomepageController**

```ruby
# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @site_config = Rails.configuration.site
    @categories = categories_with_recipes
  end

  private

  def categories_with_recipes
    current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
```

**Step 4: Update homepage view**

In `app/views/homepage/show.html.erb`, the `@site_config` is now an `ActiveSupport::OrderedOptions` object, so change hash access from `@site_config['key']` to `@site_config.key`:

- Line 1: `@site_config['site_title']` → `@site_config.site_title`
- Line 18: `@site_config['homepage_heading']` → `@site_config.homepage_heading`
- Line 19: `@site_config['homepage_subtitle']` → `@site_config.homepage_subtitle`
- Line 42: `@site_config['github_url']` → `@site_config.github_url`

**Step 5: Delete the old seed file**

```bash
rm db/seeds/resources/site-config.yaml
```

**Step 6: Run tests**

```bash
rake test
```

**Step 7: Commit**

```bash
git add -A
git commit -m "refactor: replace site_config SiteDocument with config/site.yml"
```

---

### Task 9: Merge seed data into ingredient-catalog.yaml

**Files:**
- Create: `db/seeds/resources/ingredient-catalog.yaml`
- Delete: `db/seeds/resources/nutrition-data.yaml`
- Delete: `db/seeds/resources/grocery-info.yaml`
- Modify: `db/seeds.rb`
- Modify: `bin/nutrition`

**Step 1: Write a one-time merge script**

Create a temporary Ruby script that reads both YAML files and merges them into the new format. Run it once, inspect the output, then delete the script.

The merged file should:
- Include every ingredient from both sources
- Nest nutrition under `nutrients:`, density under `density:`
- Include `aisle:` from grocery-info.yaml
- Include `portions:` and `sources:` from nutrition-data.yaml
- Drop all alias entries (only keep the primary name)
- Normalize "Omit_From_List" to "omit" for the aisle value
- Sort alphabetically by ingredient name

**Step 2: Verify the merged file is correct**

Manually spot-check a few entries that exist in both files (e.g., Eggs should have both nutrition data and aisle "Refrigerated").

**Step 3: Delete old files**

```bash
rm db/seeds/resources/nutrition-data.yaml db/seeds/resources/grocery-info.yaml
```

**Step 4: Rewrite db/seeds.rb**

The new seed flow:
1. Create kitchen + user + membership
2. Import recipes via MarkdownImporter
3. Load Quick Bites onto kitchen
4. Seed ingredient_catalog from ingredient-catalog.yaml (single pass)

```ruby
# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

ActsAsTenant.current_tenant = kitchen
Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
seeds_dir = Rails.root.join('db/seeds')
recipes_dir = seeds_dir.join('recipes')
quick_bites_filename = 'Quick Bites.md'

recipe_files = Dir.glob(recipes_dir.join('**', '*.md')).reject do |path|
  File.basename(path) == quick_bites_filename
end

puts "Importing #{recipe_files.size} recipes..."

recipe_files.each do |path|
  markdown = File.read(path)
  tokens = LineClassifier.classify(markdown)
  parsed = RecipeBuilder.new(tokens).build
  slug = FamilyRecipes.slugify(parsed[:title])

  existing = kitchen.recipes.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites content onto kitchen
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  kitchen.update!(quick_bites_content: File.read(quick_bites_path))
  puts 'Quick Bites content loaded.'
end

# Seed ingredient catalog
catalog_path = seeds_dir.join('resources/ingredient-catalog.yaml')
if File.exist?(catalog_path)
  catalog_data = YAML.safe_load_file(catalog_path, permitted_classes: [], permitted_symbols: [], aliases: false)
  catalog_data.each do |name, entry|
    profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)

    attrs = { aisle: entry['aisle'] }

    if (nutrients = entry['nutrients'])
      attrs.merge!(
        basis_grams: nutrients['basis_grams'],
        calories: nutrients['calories'],
        fat: nutrients['fat'],
        saturated_fat: nutrients['saturated_fat'],
        trans_fat: nutrients['trans_fat'],
        cholesterol: nutrients['cholesterol'],
        sodium: nutrients['sodium'],
        carbs: nutrients['carbs'],
        fiber: nutrients['fiber'],
        total_sugars: nutrients['total_sugars'],
        added_sugars: nutrients['added_sugars'],
        protein: nutrients['protein']
      )
    end

    if (density = entry['density'])
      attrs.merge!(
        density_grams: density['grams'],
        density_volume: density['volume'],
        density_unit: density['unit']
      )
    end

    attrs[:portions] = entry['portions'] || {}
    attrs[:sources] = entry['sources'] || []

    profile.assign_attributes(attrs)
    profile.save!
  end

  puts "Seeded #{IngredientCatalog.global.count} ingredient catalog entries."
end
```

**Step 5: Update bin/nutrition file paths**

In `bin/nutrition`, change:
- Line 10: `NUTRITION_PATH` → `File.join(PROJECT_ROOT, 'db/seeds/resources/ingredient-catalog.yaml')`
- Line 11: Remove `GROCERY_PATH` constant
- Update `load_context` method to read omit set from the merged file instead of grocery-info.yaml. The omit set is now entries where `entry['aisle']` equals 'omit'.
- Update `save_nutrition_data` to use the new path constant name.

The `load_context` omit set logic becomes:

```ruby
def load_context
  recipes = FamilyRecipes.parse_recipes(RECIPES_DIR)
  recipe_map = recipes.to_h { |r| [r.id, r] }

  omit_set = Set.new
  catalog = load_nutrition_data
  catalog.each do |name, entry|
    omit_set << name.downcase if entry['aisle'] == 'omit'
  end

  { recipes: recipes, recipe_map: recipe_map, omit_set: omit_set }
end
```

Also rename references from "nutrition data" to "catalog" in user-facing messages as appropriate, and update the `--help` text to reference `ingredient-catalog.yaml` instead of `nutrition-data.yaml`.

**Step 6: Update build_validator.rb warning message**

In `lib/familyrecipes/build_validator.rb` line 162, change:
```
'Use bin/nutrition to add data, or edit db/seeds/resources/nutrition-data.yaml directly.'
```
to:
```
'Use bin/nutrition to add data, or edit db/seeds/resources/ingredient-catalog.yaml directly.'
```

**Step 7: Test the new seed flow**

```bash
bin/rails db:drop db:create db:migrate db:seed
```

Expected: all recipes imported, Quick Bites loaded, ingredient catalog seeded.

**Step 8: Run tests**

```bash
rake test
```

**Step 9: Commit**

```bash
git add -A
git commit -m "refactor: merge nutrition and grocery seed data into ingredient-catalog.yaml"
```

---

### Task 10: Update Docker and deployment configuration

**Files:**
- Modify: `Dockerfile`
- Rewrite: `docker-compose.example.yml`
- Modify: `.env.example`
- Modify: `bin/docker-entrypoint`

**Step 1: Update Dockerfile**

Builder stage: replace `libpq-dev` with `libsqlite3-dev`.
Runtime stage: replace `libpq5` with `libsqlite3-0`.
Add `storage/` to writable directories.

```dockerfile
# syntax=docker/dockerfile:1

# ---- Builder stage ----
FROM ruby:3.2-slim AS builder

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libsqlite3-dev libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development test" && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/cache /usr/local/bundle/cache

COPY . .

RUN SECRET_KEY_BASE=placeholder bin/rails assets:precompile

# ---- Runtime stage ----
FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libsqlite3-0 libyaml-0-2 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system rails && \
    useradd --system --gid rails --create-home rails

WORKDIR /app

ENV RAILS_ENV=production

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

RUN mkdir -p /app/tmp /app/log /app/storage && \
    chown -R rails:rails /app/tmp /app/log /app/db /app/storage

USER rails

EXPOSE 3030

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3030"]
```

**Step 2: Simplify docker-compose.example.yml**

```yaml
# docker-compose.example.yml
#
# Reference configuration for deploying familyrecipes.
# Copy to docker-compose.yml and fill in your values.
#
# Quick start:
#   1. cp docker-compose.example.yml docker-compose.yml
#   2. Generate a secret: docker run --rm ruby:3.2-slim ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
#   3. Fill in SECRET_KEY_BASE below
#   4. docker compose up -d

services:
  app:
    image: ghcr.io/chris-biagini/familyrecipes:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:3030:3030"
    environment:
      RAILS_ENV: production
      SECRET_KEY_BASE: CHANGE_ME
      RAILS_LOG_LEVEL: info
    volumes:
      - app_storage:/app/storage

volumes:
  app_storage:
```

**Step 3: Simplify .env.example**

```
# Server
PORT=3030
BINDING=0.0.0.0
RAILS_MAX_THREADS=3

# Rails
SECRET_KEY_BASE=
RAILS_LOG_LEVEL=info

# OAuth (Phase 2 — not yet needed)
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=

# Nutrition data (optional — for USDA API lookups)
# USDA_API_KEY=
```

**Step 4: Commit**

```bash
git add Dockerfile docker-compose.example.yml .env.example bin/docker-entrypoint
git commit -m "feat: update Docker config for SQLite (drop PostgreSQL container)"
```

---

### Task 11: Update .gitignore for SQLite

**Files:**
- Modify: `.gitignore`

**Step 1: Add SQLite patterns, remove PG-specific patterns if any**

Ensure `.gitignore` includes:

```
/storage/*.sqlite3
/storage/*.sqlite3-*
```

The `storage/.keep` file should still be tracked.

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for SQLite storage files"
```

---

### Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update all references**

Major changes:
- Database section: PostgreSQL → SQLite, three-database architecture
- Remove `DATABASE_*` env vars from setup instructions
- Update db:seed description to match new flow
- Update table list (drop recipe_dependencies, site_documents, solid_cable_messages from primary; add cable/queue databases)
- Rename IngredientProfile → IngredientCatalog throughout
- Update SiteDocument references (deleted)
- Update seed file references (merged ingredient-catalog.yaml)
- Update Docker instructions (no PostgreSQL)
- Update `.env.example` description
- Update Kitchen model docs (add quick_bites_content, remove site_documents/recipe_dependencies associations)
- Update HomepageController docs (config/site.yml instead of SiteDocument)
- Update GroceriesController docs (quick_bites_content on Kitchen)
- Update MarkdownImporter docs (no rebuild_dependencies)
- Update data files section (single ingredient-catalog.yaml)

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for SQLite migration"
```

---

### Task 13: Run full test suite and fix any remaining issues

**Files:**
- Various (depending on what breaks)

**Step 1: Reset and seed database**

```bash
bin/rails db:drop db:create db:migrate db:seed
```

**Step 2: Run lint**

```bash
rake lint
```

Fix any RuboCop issues.

**Step 3: Run tests**

```bash
rake test
```

Fix any failures. Common issues to watch for:
- Test files still referencing deleted models (IngredientProfile, SiteDocument, RecipeDependency)
- Test setup creating SiteDocuments that no longer exist
- Homepage tests expecting hash-style access to site_config
- Missing `require` statements after file renames

**Step 4: Run the dev server and smoke test**

```bash
bin/dev
```

Visit `http://localhost:3030` and verify:
- Homepage loads with correct title/heading/subtitle
- Recipes render correctly
- Ingredients page works
- Groceries page loads Quick Bites
- Grocery list selection/check-off works

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures from SQLite migration"
```

---

### Task 14: Verify Docker build

**Files:**
- None (verification only)

**Step 1: Build Docker image locally**

```bash
docker build -t familyrecipes:sqlite-test .
```

Expected: successful build without PostgreSQL dependencies.

**Step 2: Commit** — nothing to commit if build succeeds. If fixes needed, commit them.

---

### Milestone Summary

| Task | Description | Depends On |
|------|-------------|------------|
| 0 | Create branch | — |
| 1 | Swap gems | 0 |
| 2 | Configure three-database architecture | 1 |
| 3 | Fresh schema migration | 2 |
| 4 | Solid Cable + Queue migrations | 3 |
| 5 | Rename IngredientProfile → IngredientCatalog | 3 |
| 6 | Delete RecipeDependency | 3 |
| 7 | Delete SiteDocument, move Quick Bites | 3 |
| 8 | Replace site_config with config/site.yml | 7 |
| 9 | Merge seed data files | 5, 7 |
| 10 | Update Docker config | 1 |
| 11 | Update .gitignore | 2 |
| 12 | Update CLAUDE.md | 5, 6, 7, 8, 9, 10 |
| 13 | Full test suite + fixes | all above |
| 14 | Docker build verification | 10, 13 |

Tasks 5, 6, 7 can run in parallel after Task 3. Task 10 and 11 can run in parallel with 5–9.

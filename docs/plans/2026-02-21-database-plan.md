# Database Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add PostgreSQL-backed ActiveRecord models to the familyrecipes project, with seeds that populate the database from existing Markdown recipe files and nutrition YAML.

**Architecture:** Separate ActiveRecord models (`app/models/`) alongside existing pure-Ruby domain classes (`lib/familyrecipes/`). The domain classes continue to power the static site build; AR models are the persistence layer for the Rails app. Seeds bridge the two by parsing Markdown with domain classes and mapping the results into AR records.

**Tech Stack:** Rails 8.1.2, PostgreSQL, ActiveRecord, `pg` gem

**Design doc:** `docs/plans/2026-02-21-database-design.md`

---

### Task 1: Install PostgreSQL and add database dependencies

**Files:**
- Modify: `Gemfile`

**Step 1: Install PostgreSQL on the system**

```bash
sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib libpq-dev
sudo service postgresql start
```

Verify with `pg_isready` — should output "accepting connections".

**Step 2: Create database user**

```bash
sudo -u postgres createuser --createdb --superuser claude
```

**Step 3: Add `pg` and `activerecord` gems to Gemfile**

Add to the Gemfile (outside any group):

```ruby
gem 'pg'
```

Rails is already installed system-wide. The `pg` gem is needed for the PostgreSQL adapter.

**Step 4: Bundle install**

```bash
cd /home/claude/familyrecipes && bundle install
```

Expected: Resolves and installs `pg` gem successfully.

**Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add pg gem for PostgreSQL support"
```

---

### Task 2: Add Rails database configuration

**Files:**
- Create: `config/database.yml`
- Modify: `Rakefile` (add ActiveRecord tasks)

**Step 1: Create database.yml**

Create `config/database.yml`:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: 5
  host: localhost

development:
  <<: *default
  database: familyrecipes_development

test:
  <<: *default
  database: familyrecipes_test

production:
  <<: *default
  database: familyrecipes_production
  username: <%= ENV["DATABASE_USERNAME"] %>
  password: <%= ENV["DATABASE_PASSWORD"] %>
  host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>
```

**Step 2: Add ActiveRecord Rake tasks to Rakefile**

Add to the Rakefile, after `require 'bundler/setup'`:

```ruby
require 'active_record'

# Load database config and connect for AR rake tasks
db_dir = File.join(__dir__, 'db')
config_dir = File.join(__dir__, 'config')

namespace :db do
  task :environment do
    db_config = YAML.safe_load(
      ERB.new(File.read(File.join(config_dir, 'database.yml'))).result,
      permitted_classes: [],
      aliases: true
    )
    ActiveRecord::Base.establish_connection(db_config[ENV.fetch('RAILS_ENV', 'development')])
  end

  task :connection_config do
    @db_config = YAML.safe_load(
      ERB.new(File.read(File.join(config_dir, 'database.yml'))).result,
      permitted_classes: [],
      aliases: true
    )
  end

  desc 'Create the database'
  task create: :connection_config do
    config = @db_config[ENV.fetch('RAILS_ENV', 'development')]
    database = config['database']
    system("createdb #{database}") || puts("Database #{database} may already exist")
    puts "Created database #{database}"
  end

  desc 'Drop the database'
  task drop: :connection_config do
    config = @db_config[ENV.fetch('RAILS_ENV', 'development')]
    database = config['database']
    system("dropdb --if-exists #{database}")
    puts "Dropped database #{database}"
  end

  desc 'Run pending migrations'
  task migrate: :environment do
    ActiveRecord::MigrationContext.new(File.join(db_dir, 'migrate')).migrate
    Rake::Task['db:schema:dump'].invoke
  end

  desc 'Rollback the last migration'
  task rollback: :environment do
    ActiveRecord::MigrationContext.new(File.join(db_dir, 'migrate')).rollback
    Rake::Task['db:schema:dump'].invoke
  end

  desc 'Seed the database'
  task seed: :environment do
    load File.join(db_dir, 'seeds.rb')
  end

  desc 'Create, migrate, and seed the database'
  task setup: %i[create migrate seed]

  desc 'Drop, create, migrate, and seed the database'
  task reset: %i[drop setup]

  namespace :schema do
    desc 'Dump the schema to db/schema.rb'
    task dump: :environment do
      File.open(File.join(db_dir, 'schema.rb'), 'w') do |file|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
      end
      puts 'Schema dumped to db/schema.rb'
    end

    desc 'Load the schema from db/schema.rb'
    task load: :environment do
      load File.join(db_dir, 'schema.rb')
    end
  end
end
```

**Step 3: Create db/ directory structure**

```bash
mkdir -p db/migrate
```

**Step 4: Verify database creation**

```bash
rake db:create
```

Expected: "Created database familyrecipes_development"

**Step 5: Add db/schema.rb to .gitignore**

Check if `.gitignore` exists. Add `db/schema.rb` to it — it's generated, not tracked. Also add any other transient files if not already ignored.

**Step 6: Commit**

```bash
git add config/database.yml Rakefile db/ .gitignore
git commit -m "chore: add PostgreSQL database configuration and AR rake tasks"
```

---

### Task 3: Create recipes migration

**Files:**
- Create: `db/migrate/001_create_recipes.rb`

**Step 1: Write the migration**

Create `db/migrate/001_create_recipes.rb`:

```ruby
# frozen_string_literal: true

class CreateRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :recipes do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category, null: false
      t.string :makes
      t.integer :serves
      t.text :footer
      t.text :source_markdown, null: false
      t.string :version_hash, null: false
      t.boolean :quick_bite, null: false, default: false

      t.timestamps
    end

    add_index :recipes, :slug, unique: true
    add_index :recipes, :category
  end
end
```

**Step 2: Run the migration**

```bash
rake db:migrate
```

Expected: Creates `recipes` table, dumps schema.

**Step 3: Verify with psql**

```bash
psql familyrecipes_development -c '\d recipes'
```

Expected: Table with all columns, correct types, indexes on slug and category.

**Step 4: Commit**

```bash
git add db/migrate/001_create_recipes.rb
git commit -m "feat: add recipes table migration"
```

---

### Task 4: Create steps migration

**Files:**
- Create: `db/migrate/002_create_steps.rb`

**Step 1: Write the migration**

Create `db/migrate/002_create_steps.rb`:

```ruby
# frozen_string_literal: true

class CreateSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :steps do |t|
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :tldr, null: false
      t.text :instructions

      t.timestamps
    end
  end
end
```

**Step 2: Run the migration**

```bash
rake db:migrate
```

**Step 3: Commit**

```bash
git add db/migrate/002_create_steps.rb
git commit -m "feat: add steps table migration"
```

---

### Task 5: Create ingredients migration

**Files:**
- Create: `db/migrate/003_create_ingredients.rb`

**Step 1: Write the migration**

Create `db/migrate/003_create_ingredients.rb`:

```ruby
# frozen_string_literal: true

class CreateIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :ingredients do |t|
      t.references :step, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.string :quantity
      t.string :prep_note

      t.timestamps
    end
  end
end
```

Note: `step` reference is nullable (no `null: false`) for Quick Bites.

**Step 2: Run the migration**

```bash
rake db:migrate
```

**Step 3: Commit**

```bash
git add db/migrate/003_create_ingredients.rb
git commit -m "feat: add ingredients table migration"
```

---

### Task 6: Create cross_references migration

**Files:**
- Create: `db/migrate/004_create_cross_references.rb`

**Step 1: Write the migration**

Create `db/migrate/004_create_cross_references.rb`:

```ruby
# frozen_string_literal: true

class CreateCrossReferences < ActiveRecord::Migration[8.0]
  def change
    create_table :cross_references do |t|
      t.references :step, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.integer :position, null: false
      t.decimal :multiplier, null: false, default: 1.0
      t.string :prep_note

      t.timestamps
    end
  end
end
```

**Step 2: Run the migration**

```bash
rake db:migrate
```

**Step 3: Commit**

```bash
git add db/migrate/004_create_cross_references.rb
git commit -m "feat: add cross_references table migration"
```

---

### Task 7: Create nutrition_entries migration

**Files:**
- Create: `db/migrate/005_create_nutrition_entries.rb`

**Step 1: Write the migration**

Create `db/migrate/005_create_nutrition_entries.rb`:

```ruby
# frozen_string_literal: true

class CreateNutritionEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :nutrition_entries do |t|
      t.string :ingredient_name, null: false
      t.decimal :basis_grams, null: false
      t.decimal :calories, null: false
      t.decimal :fat, null: false
      t.decimal :saturated_fat, null: false
      t.decimal :trans_fat, null: false
      t.decimal :cholesterol, null: false
      t.decimal :sodium, null: false
      t.decimal :carbs, null: false
      t.decimal :fiber, null: false
      t.decimal :total_sugars, null: false
      t.decimal :added_sugars, null: false
      t.decimal :protein, null: false
      t.decimal :density_grams
      t.decimal :density_volume
      t.string :density_unit
      t.jsonb :portions
      t.jsonb :sources

      t.timestamps
    end

    add_index :nutrition_entries, :ingredient_name, unique: true
  end
end
```

**Step 2: Run the migration**

```bash
rake db:migrate
```

**Step 3: Verify all tables exist**

```bash
psql familyrecipes_development -c '\dt'
```

Expected: `recipes`, `steps`, `ingredients`, `cross_references`, `nutrition_entries` tables all listed.

**Step 4: Commit**

```bash
git add db/migrate/005_create_nutrition_entries.rb
git commit -m "feat: add nutrition_entries table migration"
```

---

### Task 8: Create ActiveRecord models

**Files:**
- Create: `app/models/recipe_record.rb`
- Create: `app/models/step_record.rb`
- Create: `app/models/ingredient_record.rb`
- Create: `app/models/cross_reference_record.rb`
- Create: `app/models/nutrition_entry_record.rb`

We name the AR models with a `Record` suffix to avoid collisions with the existing domain classes (`Recipe`, `Step`, `Ingredient`, `CrossReference`). This is a deliberate choice — the domain classes are the parsing/rendering layer, the Record classes are the persistence layer.

**Step 1: Create app/models directory**

```bash
mkdir -p app/models
```

**Step 2: Create RecipeRecord**

Create `app/models/recipe_record.rb`:

```ruby
# frozen_string_literal: true

class RecipeRecord < ActiveRecord::Base
  self.table_name = 'recipes'

  has_many :step_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :ingredient_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :cross_reference_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :inbound_cross_references, class_name: 'CrossReferenceRecord',
                                      foreign_key: :target_recipe_id,
                                      dependent: :nullify,
                                      inverse_of: :target_recipe

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :category, presence: true
  validates :source_markdown, presence: true
  validates :version_hash, presence: true

  scope :full_recipes, -> { where(quick_bite: false) }
  scope :quick_bites, -> { where(quick_bite: true) }
  scope :in_category, ->(cat) { where(category: cat) }
end
```

**Step 3: Create StepRecord**

Create `app/models/step_record.rb`:

```ruby
# frozen_string_literal: true

class StepRecord < ActiveRecord::Base
  self.table_name = 'steps'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :step_records

  has_many :ingredient_records, foreign_key: :step_id, dependent: :destroy, inverse_of: :step_record
  has_many :cross_reference_records, foreign_key: :step_id, dependent: :destroy, inverse_of: :step_record

  validates :tldr, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end
```

**Step 4: Create IngredientRecord**

Create `app/models/ingredient_record.rb`:

```ruby
# frozen_string_literal: true

class IngredientRecord < ActiveRecord::Base
  self.table_name = 'ingredients'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :ingredient_records
  belongs_to :step_record, foreign_key: :step_id, optional: true, inverse_of: :ingredient_records

  validates :name, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end
```

**Step 5: Create CrossReferenceRecord**

Create `app/models/cross_reference_record.rb`:

```ruby
# frozen_string_literal: true

class CrossReferenceRecord < ActiveRecord::Base
  self.table_name = 'cross_references'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :cross_reference_records
  belongs_to :step_record, foreign_key: :step_id, inverse_of: :cross_reference_records
  belongs_to :target_recipe, class_name: 'RecipeRecord', foreign_key: :target_recipe_id,
                             inverse_of: :inbound_cross_references

  validates :position, presence: true
  validates :multiplier, presence: true

  default_scope { order(:position) }
end
```

**Step 6: Create NutritionEntryRecord**

Create `app/models/nutrition_entry_record.rb`:

```ruby
# frozen_string_literal: true

class NutritionEntryRecord < ActiveRecord::Base
  self.table_name = 'nutrition_entries'

  validates :ingredient_name, presence: true, uniqueness: true
  validates :basis_grams, :calories, :fat, :saturated_fat, :trans_fat,
            :cholesterol, :sodium, :carbs, :fiber, :total_sugars,
            :added_sugars, :protein, presence: true
end
```

**Step 7: Require models in a load file**

Create `app/models.rb`:

```ruby
# frozen_string_literal: true

require 'active_record'

Dir[File.join(__dir__, 'models', '*.rb')].each { |f| require f }
```

**Step 8: Commit**

```bash
git add app/
git commit -m "feat: add ActiveRecord models for all tables"
```

---

### Task 9: Wire up ActiveRecord connection for Rake tasks

**Files:**
- Modify: `Rakefile`

The Rake tasks from Task 2 need to load the AR models. Update the `db:environment` task to also require the models.

**Step 1: Update db:environment task in Rakefile**

In the `db:environment` Rake task, after `establish_connection`, add:

```ruby
require_relative 'app/models'
```

**Step 2: Verify connection end-to-end**

```bash
rake db:migrate
```

Then open a Ruby console to test:

```bash
ruby -r bundler/setup -r ./app/models -e "
  require 'yaml'
  require 'erb'
  config = YAML.safe_load(ERB.new(File.read('config/database.yml')).result, permitted_classes: [], aliases: true)
  ActiveRecord::Base.establish_connection(config['development'])
  puts RecipeRecord.count
"
```

Expected: `0` (no recipes seeded yet).

**Step 3: Commit**

```bash
git add Rakefile
git commit -m "chore: wire up model loading in database rake tasks"
```

---

### Task 10: Write seeds for recipes

**Files:**
- Create: `db/seeds.rb`

**Step 1: Write the seed script**

Create `db/seeds.rb`:

```ruby
# frozen_string_literal: true

require_relative '../lib/familyrecipes'
require_relative '../app/models'

project_root = File.expand_path('..', __dir__)
recipes_dir = File.join(project_root, 'recipes')

# --- Seed full recipes ---

puts 'Seeding recipes...'
recipes = FamilyRecipes.parse_recipes(recipes_dir)

# First pass: create/update all recipe records (needed for cross-reference targets)
recipe_records = recipes.each_with_object({}) do |recipe, map|
  record = RecipeRecord.find_or_initialize_by(slug: recipe.id)
  record.assign_attributes(
    title: recipe.title,
    description: recipe.description,
    category: recipe.category,
    makes: recipe.makes,
    serves: recipe.serves,
    footer: recipe.footer,
    source_markdown: recipe.source,
    version_hash: recipe.version_hash,
    quick_bite: false
  )
  record.save!
  map[recipe.id] = { record: record, domain: recipe }
end

# Second pass: populate steps, ingredients, and cross-references
recipe_records.each_value do |entry|
  record = entry[:record]
  recipe = entry[:domain]

  # Clear existing children for idempotent re-seeding
  record.step_records.destroy_all

  recipe.steps.each_with_index do |step, step_idx|
    step_record = record.step_records.create!(
      position: step_idx,
      tldr: step.tldr,
      instructions: step.instructions
    )

    # Interleave ingredients and cross-references by original order
    position = 0

    step.ingredient_list_items.each do |item|
      case item
      when Ingredient
        record.ingredient_records.create!(
          step_record: step_record,
          position: position,
          name: item.name,
          quantity: item.quantity,
          prep_note: item.prep_note
        )
      when CrossReference
        target = RecipeRecord.find_by!(slug: item.target_slug)
        record.cross_reference_records.create!(
          step_record: step_record,
          target_recipe: target,
          position: position,
          multiplier: item.multiplier,
          prep_note: item.prep_note
        )
      end
      position += 1
    end
  end
end
puts "  #{recipe_records.size} recipes seeded."

# --- Seed Quick Bites ---

puts 'Seeding Quick Bites...'
quick_bites = FamilyRecipes.parse_quick_bites(recipes_dir)

quick_bites.each do |qb|
  record = RecipeRecord.find_or_initialize_by(slug: qb.id)
  record.assign_attributes(
    title: qb.title,
    category: qb.category,
    source_markdown: qb.text_source,
    version_hash: Digest::SHA256.hexdigest(qb.text_source),
    quick_bite: true,
    description: nil,
    makes: nil,
    serves: nil,
    footer: nil
  )
  record.save!

  # Clear and re-create ingredients (no steps for Quick Bites)
  record.ingredient_records.where(step_id: nil).destroy_all

  qb.ingredients.each_with_index do |name, idx|
    record.ingredient_records.create!(
      step_record: nil,
      position: idx,
      name: name
    )
  end
end
puts "  #{quick_bites.size} quick bites seeded."

# --- Seed nutrition data ---

puts 'Seeding nutrition data...'
nutrition_path = File.join(project_root, 'resources', 'nutrition-data.yaml')
nutrition_data = YAML.safe_load_file(nutrition_path, permitted_classes: [])

nutrition_data.each do |name, data|
  nutrients = data['nutrients']
  density = data['density']
  entry = NutritionEntryRecord.find_or_initialize_by(ingredient_name: name)
  entry.assign_attributes(
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
    protein: nutrients['protein'],
    density_grams: density&.fetch('grams', nil),
    density_volume: density&.fetch('volume', nil),
    density_unit: density&.fetch('unit', nil),
    portions: data['portions'],
    sources: data['sources']
  )
  entry.save!
end
puts "  #{nutrition_data.size} nutrition entries seeded."

puts 'Done!'
```

**Step 2: Run the seeds**

```bash
rake db:seed
```

Expected output:
```
Seeding recipes...
  N recipes seeded.
Seeding Quick Bites...
  N quick bites seeded.
Seeding nutrition data...
  N nutrition entries seeded.
Done!
```

**Step 3: Run seeds again to verify idempotency**

```bash
rake db:seed
```

Expected: Same output, no duplicate records. Verify counts:

```bash
psql familyrecipes_development -c "SELECT count(*) FROM recipes; SELECT count(*) FROM steps; SELECT count(*) FROM ingredients; SELECT count(*) FROM cross_references; SELECT count(*) FROM nutrition_entries;"
```

Counts should be identical after both runs.

**Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: add database seeds from Markdown recipes and nutrition YAML"
```

---

### Task 11: Verify the dual path

**Files:** None (verification only)

**Step 1: Verify static build still works**

```bash
bin/generate
```

Expected: Parses all recipes, generates HTML in `output/web/`, no errors. Same output as before any of these changes.

**Step 2: Run the test suite**

```bash
rake test
```

Expected: All existing tests pass. No regressions.

**Step 3: Run the linter**

```bash
rake lint
```

Expected: No new lint violations from the code we've added.

**Step 4: Verify database path works end-to-end**

```bash
rake db:reset
```

Then verify with a quick Ruby script:

```bash
ruby -r bundler/setup -r yaml -r erb -r ./app/models -e "
  config = YAML.safe_load(ERB.new(File.read('config/database.yml')).result, permitted_classes: [], aliases: true)
  ActiveRecord::Base.establish_connection(config['development'])

  puts \"Recipes: #{RecipeRecord.full_recipes.count}\"
  puts \"Quick Bites: #{RecipeRecord.quick_bites.count}\"
  puts \"Steps: #{StepRecord.count}\"
  puts \"Ingredients: #{IngredientRecord.count}\"
  puts \"Cross-references: #{CrossReferenceRecord.count}\"
  puts \"Nutrition entries: #{NutritionEntryRecord.count}\"
  puts
  r = RecipeRecord.full_recipes.first
  puts \"First recipe: #{r.title} (#{r.category})\"
  puts \"  Steps: #{r.step_records.count}\"
  puts \"  Ingredients: #{r.ingredient_records.count}\"
  puts \"  Cross-refs: #{r.cross_reference_records.count}\"
"
```

Expected: Non-zero counts for all tables, recipe details load correctly.

**Step 5: Verify cross-references resolve**

```bash
ruby -r bundler/setup -r yaml -r erb -r ./app/models -e "
  config = YAML.safe_load(ERB.new(File.read('config/database.yml')).result, permitted_classes: [], aliases: true)
  ActiveRecord::Base.establish_connection(config['development'])

  xref = CrossReferenceRecord.first
  if xref
    puts \"Cross-ref: #{xref.recipe_record.title} -> #{xref.target_recipe.title} (x#{xref.multiplier})\"
  else
    puts 'No cross-references found (may be expected if no recipes use @[...] syntax)'
  end
"
```

**Step 6: Final commit (if any lint/test fixes were needed)**

```bash
git add -A && git commit -m "chore: fix lint/test issues from database layer"
```

Only if changes were needed. Skip if everything passed clean.

---

## Notes for the implementer

- **RuboCop rules:** `frozen_string_literal: true` on every file. Max line length 120. Rescued exceptions named `error`. See `.rubocop.yml`.
- **Ruby conventions:** Use Enumerable methods, not `each` + accumulators. Guard clauses. No explicit `return` at end of methods. See CLAUDE.md.
- **The `is_a?` check in seeds:** The seed script uses `case item when Ingredient` / `when CrossReference` to distinguish ingredient list items. This is `===` matching (class match), which is idiomatic in `case` statements — it's different from the `is_a?` anti-pattern called out in CLAUDE.md. The domain classes `Step#ingredients` and `Step#cross_references` use `.grep(Ingredient)` which is the same pattern.
- **PostgreSQL must be running** for all database tasks. Start with `sudo service postgresql start` if needed.
- **Static build is independent.** `bin/generate` and `rake test` never touch the database. The database is only used by `rake db:*` tasks.
- **`db/schema.rb` is generated** by `rake db:migrate` and should be in `.gitignore`.

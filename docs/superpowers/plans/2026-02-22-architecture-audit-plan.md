# Architecture Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the data model so the database is the complete source of truth for rendering (no parser at render time), adopt `acts_as_tenant` for multi-tenancy enforcement, replace dev-only auth with OmniAuth-compatible session infrastructure, and prepare for Docker deployment.

**Architecture:** Parse-on-save replaces the render-time parser bridge. `MarkdownImporter` stores everything (cross-reference multipliers, processed instructions, nutrition). Controllers load from AR only. `acts_as_tenant` enforces kitchen scoping automatically. Database-backed sessions with `Authentication` concern replace manual `session[:user_id]`.

**Tech Stack:** Rails 8.1, PostgreSQL, acts_as_tenant, OmniAuth, ActiveJob (synchronous), Minitest

---

## Milestone 1: Data Foundation

Goal: Add the new models and columns. Get `acts_as_tenant` working. Update `MarkdownImporter` to store cross-references fully. Extract `NutritionEntry` from the YAML blob. All existing tests must keep passing.

### Task 1: Add `acts_as_tenant` gem

**Files:**
- Modify: `Gemfile:12`
- Create: `config/initializers/acts_as_tenant.rb`

**Step 1: Add gem to Gemfile**

After `gem 'redcarpet'` (line 12), add:

```ruby
gem 'acts_as_tenant'
```

**Step 2: Bundle install**

Run: `bundle install`
Expected: Success, gem installed.

**Step 3: Create initializer**

Create `config/initializers/acts_as_tenant.rb`:

```ruby
# frozen_string_literal: true

ActsAsTenant.configure do |config|
  config.require_tenant = true
end
```

**Step 4: Run existing tests**

Run: `rake test`
Expected: Failures — `acts_as_tenant` now requires a tenant to be set for tenanted models, but we haven't configured any models yet. Tests that query tenanted models without setting a tenant will fail. This is expected; we fix it in subsequent tasks.

**Step 5: Commit**

```bash
git add Gemfile Gemfile.lock config/initializers/acts_as_tenant.rb
git commit -m "chore: add acts_as_tenant gem with require_tenant config"
```

---

### Task 2: Apply `acts_as_tenant` to existing models

**Files:**
- Modify: `app/models/recipe.rb:5`
- Modify: `app/models/category.rb:4`
- Modify: `app/models/site_document.rb:4`
- Modify: `app/models/membership.rb:4`
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/landing_controller.rb`
- Modify: `test/test_helper.rb`

**Step 1: Write a test that verifies tenant scoping works**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'acts_as_tenant scopes recipes to current kitchen' do
  k1 = Kitchen.create!(name: 'K1', slug: 'k1')
  k2 = Kitchen.create!(name: 'K2', slug: 'k2')
  cat1 = k1.categories.create!(name: 'Cat', slug: 'cat')
  cat2 = k2.categories.create!(name: 'Cat', slug: 'cat')
  k1.recipes.create!(title: 'R1', slug: 'r1', markdown_source: '# R1', category: cat1)
  k2.recipes.create!(title: 'R2', slug: 'r2', markdown_source: '# R2', category: cat2)

  ActsAsTenant.with_tenant(k1) do
    assert_equal ['R1'], Recipe.pluck(:title)
  end

  ActsAsTenant.with_tenant(k2) do
    assert_equal ['R2'], Recipe.pluck(:title)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_acts_as_tenant_scopes_recipes_to_current_kitchen`
Expected: FAIL — `acts_as_tenant` not yet applied to Recipe model.

**Step 3: Apply `acts_as_tenant` to models**

In `app/models/recipe.rb`, replace `belongs_to :kitchen` (line 5) with `acts_as_tenant :kitchen`:

```ruby
class Recipe < ApplicationRecord
  belongs_to :category
  acts_as_tenant :kitchen
```

In `app/models/category.rb`, replace `belongs_to :kitchen` (line 4) with `acts_as_tenant :kitchen`:

```ruby
class Category < ApplicationRecord
  acts_as_tenant :kitchen
```

In `app/models/site_document.rb`, replace `belongs_to :kitchen` (line 4) with `acts_as_tenant :kitchen`:

```ruby
class SiteDocument < ApplicationRecord
  acts_as_tenant :kitchen
```

In `app/models/membership.rb`, replace `belongs_to :kitchen` (line 4) with `acts_as_tenant :kitchen`:

```ruby
class Membership < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :user
```

Note: `acts_as_tenant` adds `belongs_to :kitchen` automatically, so we remove the explicit declaration.

**Step 4: Configure tenant in ApplicationController**

Replace the current `current_kitchen` method in `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  set_current_tenant_through_filter
  before_action :set_kitchen_from_path

  helper_method :current_user, :current_kitchen, :logged_in?

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]

    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_kitchen = ActsAsTenant.current_tenant

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_membership
    head :unauthorized unless logged_in? && current_kitchen&.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
```

**Step 5: Fix LandingController**

`LandingController` loads `Kitchen.all` — no tenant context. Add skip:

```ruby
class LandingController < ApplicationController
  skip_before_action :set_kitchen_from_path

  def show
    @kitchens = ActsAsTenant.without_tenant { Kitchen.all }
  end
end
```

**Step 6: Fix test helper**

Tests need a tenant set. Update `test/test_helper.rb` to set tenant after creating kitchen:

```ruby
module ActionDispatch
  class IntegrationTest
    private

    def create_kitchen_and_user
      @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
      @user = User.create!(name: 'Test User', email: 'test@example.com')
      ActsAsTenant.current_tenant = @kitchen
      Membership.create!(kitchen: @kitchen, user: @user)
    end

    def log_in
      get dev_login_path(id: @user.id)
    end

    def kitchen_slug
      @kitchen.slug
    end
  end
end
```

Also ensure model tests set tenant. Any model test that creates tenanted records directly needs `ActsAsTenant.current_tenant = kitchen` before creation, or must use `ActsAsTenant.with_tenant(kitchen) { ... }`.

**Step 7: Run all tests**

Run: `rake test`
Expected: Fix any remaining failures. Common issues:
- Model tests that create Recipe/Category without setting tenant → wrap in `ActsAsTenant.with_tenant`
- Service tests (MarkdownImporter, CrossReferenceUpdater) that create records → set tenant
- Controller tests should work because `create_kitchen_and_user` sets the tenant

Iterate until all tests pass.

**Step 8: Run lint**

Run: `rake lint`
Expected: PASS. Fix any RuboCop issues.

**Step 9: Commit**

```bash
git add -A
git commit -m "feat: apply acts_as_tenant to Recipe, Category, SiteDocument, Membership

Configures path-based tenant resolution in ApplicationController.
LandingController skips tenant filter (shows all kitchens).
Test helper sets tenant after creating kitchen."
```

---

### Task 3: Create `CrossReference` model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_cross_references.rb`
- Create: `app/models/cross_reference.rb`
- Modify: `app/models/step.rb`
- Create: `test/models/cross_reference_test.rb`

**Step 1: Write the test**

Create `test/models/cross_reference_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class CrossReferenceTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.create!(name: 'Cat', slug: 'cat')
    @source = Recipe.create!(title: 'Pizza', slug: 'pizza', markdown_source: '# Pizza', category: @category)
    @target = Recipe.create!(title: 'Dough', slug: 'dough', markdown_source: '# Dough', category: @category)
    @step = @source.steps.create!(title: 'Make pizza', instructions: 'Stretch the dough.', position: 0)
  end

  test 'belongs to step and target recipe' do
    ref = @step.cross_references.create!(
      target_recipe: @target,
      multiplier: 2.0,
      prep_note: 'Let rest',
      position: 0
    )

    assert_equal @step, ref.step
    assert_equal @target, ref.target_recipe
    assert_in_delta 2.0, ref.multiplier
    assert_equal 'Let rest', ref.prep_note
  end

  test 'defaults multiplier to 1.0' do
    ref = @step.cross_references.create!(target_recipe: @target, position: 0)

    assert_in_delta 1.0, ref.multiplier
  end

  test 'requires target_recipe' do
    ref = @step.cross_references.new(position: 0)

    refute ref.valid?
    assert ref.errors[:target_recipe].any?
  end

  test 'requires position' do
    ref = @step.cross_references.new(target_recipe: @target)

    refute ref.valid?
    assert ref.errors[:position].any?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/cross_reference_test.rb`
Expected: FAIL — model and table don't exist.

**Step 3: Create migration**

Run: `rails generate migration CreateCrossReferences`

Edit the generated migration:

```ruby
class CreateCrossReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :cross_references do |t|
      t.references :step, null: false, foreign_key: true
      t.references :kitchen, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.decimal :multiplier, precision: 8, scale: 2, default: 1.0, null: false
      t.string :prep_note
      t.integer :position, null: false

      t.timestamps
    end

    add_index :cross_references, [:step_id, :position], unique: true
  end
end
```

**Step 4: Create model**

Create `app/models/cross_reference.rb`:

```ruby
# frozen_string_literal: true

class CrossReference < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :step, inverse_of: :cross_references
  belongs_to :target_recipe, class_name: 'Recipe'

  validates :position, presence: true
  validates :position, uniqueness: { scope: :step_id }

  delegate :slug, to: :target_recipe, prefix: :target
  delegate :title, to: :target_recipe, prefix: :target
end
```

**Step 5: Add association to Step**

In `app/models/step.rb`, add:

```ruby
class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps

  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step
  has_many :cross_references, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  validates :title, presence: true
  validates :position, presence: true

  def ingredient_list_items
    (ingredients + cross_references).sort_by(&:position)
  end
end
```

**Step 6: Run migration and tests**

Run: `rails db:migrate && ruby -Itest test/models/cross_reference_test.rb`
Expected: PASS

**Step 7: Run full test suite**

Run: `rake test`
Expected: PASS (new model doesn't affect existing tests).

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: add CrossReference model for storing cross-ref rendering data

Captures multiplier, prep_note, and position — data previously
discarded by MarkdownImporter. Step#ingredient_list_items merges
ingredients and cross-references by position for interleaved rendering."
```

---

### Task 4: Add `kitchen_id` to `recipe_dependencies`, `nutrition_data` to `recipes`, `processed_instructions` to `steps`

**Files:**
- Create: `db/migrate/TIMESTAMP_add_architecture_audit_columns.rb`
- Modify: `app/models/recipe_dependency.rb`
- Modify: `app/models/recipe.rb`

**Step 1: Write tests for new columns**

Add to `test/models/kitchen_test.rb`:

```ruby
test 'recipe dependencies have kitchen_id' do
  k1 = Kitchen.create!(name: 'K1', slug: 'k1')
  ActsAsTenant.with_tenant(k1) do
    cat = Category.create!(name: 'C', slug: 'c')
    r1 = Recipe.create!(title: 'R1', slug: 'r1', markdown_source: '# R1', category: cat)
    r2 = Recipe.create!(title: 'R2', slug: 'r2', markdown_source: '# R2', category: cat)
    dep = r1.outbound_dependencies.create!(target_recipe: r2)

    assert_equal k1.id, dep.kitchen_id
  end
end

test 'recipe stores nutrition_data as JSON' do
  k1 = Kitchen.create!(name: 'K1', slug: 'k1')
  ActsAsTenant.with_tenant(k1) do
    cat = Category.create!(name: 'C', slug: 'c')
    recipe = Recipe.create!(title: 'R', slug: 'r', markdown_source: '# R', category: cat)
    recipe.update!(nutrition_data: { 'calories' => 100, 'fat' => 5 })
    recipe.reload

    assert_equal 100, recipe.nutrition_data['calories']
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/kitchen_test.rb -n test_recipe_dependencies_have_kitchen_id`
Expected: FAIL — column doesn't exist.

**Step 3: Create migration**

Run: `rails generate migration AddArchitectureAuditColumns`

Edit:

```ruby
class AddArchitectureAuditColumns < ActiveRecord::Migration[8.1]
  def change
    # Cross-reference rendering data stored in cross_references table (Task 3).
    # RecipeDependency gets kitchen_id for acts_as_tenant defense-in-depth.
    add_reference :recipe_dependencies, :kitchen, null: true, foreign_key: true

    # Pre-computed nutrition stored on recipe after parse-on-save.
    add_column :recipes, :nutrition_data, :jsonb

    # Instructions with scalable number spans already applied.
    add_column :steps, :processed_instructions, :text

    # Backfill kitchen_id on existing dependencies from source recipe.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE recipe_dependencies
          SET kitchen_id = recipes.kitchen_id
          FROM recipes
          WHERE recipe_dependencies.source_recipe_id = recipes.id
        SQL

        change_column_null :recipe_dependencies, :kitchen_id, false
      end
    end
  end
end
```

**Step 4: Update RecipeDependency model**

Replace `app/models/recipe_dependency.rb`:

```ruby
# frozen_string_literal: true

class RecipeDependency < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :source_recipe, class_name: 'Recipe', inverse_of: :outbound_dependencies
  belongs_to :target_recipe, class_name: 'Recipe', inverse_of: :inbound_dependencies

  validates :target_recipe_id, uniqueness: { scope: [:kitchen_id, :source_recipe_id] }
end
```

**Step 5: Add `has_many :recipe_dependencies` to Kitchen**

In `app/models/kitchen.rb`, add after line 9:

```ruby
has_many :recipe_dependencies, dependent: :destroy
```

**Step 6: Run migration and tests**

Run: `rails db:migrate && rake test`
Expected: PASS

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add kitchen_id to recipe_dependencies, nutrition_data to recipes, processed_instructions to steps

Defense-in-depth: recipe_dependencies now scoped by acts_as_tenant.
nutrition_data jsonb column stores pre-computed nutrition facts.
processed_instructions stores instructions with scalable spans applied."
```

---

### Task 5: Create `NutritionEntry` model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_nutrition_entries.rb`
- Create: `app/models/nutrition_entry.rb`
- Create: `test/models/nutrition_entry_test.rb`

**Step 1: Write the test**

Create `test/models/nutrition_entry_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class NutritionEntryTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    ActsAsTenant.current_tenant = @kitchen
  end

  test 'stores nutrient data for an ingredient' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30.0,
      calories: 110.0,
      fat: 0.0,
      protein: 4.0
    )

    entry.reload
    assert_equal 'Flour (all-purpose)', entry.ingredient_name
    assert_in_delta 110.0, entry.calories
  end

  test 'enforces unique ingredient_name per kitchen' do
    NutritionEntry.create!(ingredient_name: 'Salt', basis_grams: 6.0)

    duplicate = NutritionEntry.new(ingredient_name: 'Salt', basis_grams: 6.0)
    refute duplicate.valid?
  end

  test 'stores density data' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Flour',
      basis_grams: 30.0,
      density_grams: 30.0,
      density_volume: 0.25,
      density_unit: 'cup'
    )

    entry.reload
    assert_equal 'cup', entry.density_unit
    assert_in_delta 0.25, entry.density_volume
  end

  test 'stores portions as JSON' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Butter',
      basis_grams: 14.0,
      portions: { 'stick' => 113.0, '~unitless' => 14.0 }
    )

    entry.reload
    assert_in_delta 113.0, entry.portions['stick']
  end

  test 'stores sources as JSON array' do
    entry = NutritionEntry.create!(
      ingredient_name: 'Salt',
      basis_grams: 6.0,
      sources: [{ 'type' => 'usda', 'fdc_id' => 173530 }]
    )

    entry.reload
    assert_equal 'usda', entry.sources.first['type']
  end

  test 'requires ingredient_name and basis_grams' do
    entry = NutritionEntry.new
    refute entry.valid?
    assert entry.errors[:ingredient_name].any?
    assert entry.errors[:basis_grams].any?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/nutrition_entry_test.rb`
Expected: FAIL — model and table don't exist.

**Step 3: Create migration**

Run: `rails generate migration CreateNutritionEntries`

Edit:

```ruby
class CreateNutritionEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :nutrition_entries do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :ingredient_name, null: false
      t.decimal :basis_grams, null: false
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
      t.jsonb :portions, default: {}
      t.jsonb :sources, default: []

      t.timestamps
    end

    add_index :nutrition_entries, [:kitchen_id, :ingredient_name], unique: true
  end
end
```

**Step 4: Create model**

Create `app/models/nutrition_entry.rb`:

```ruby
# frozen_string_literal: true

class NutritionEntry < ApplicationRecord
  acts_as_tenant :kitchen

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, presence: true, numericality: { greater_than: 0 }
end
```

**Step 5: Add association to Kitchen**

In `app/models/kitchen.rb`, add:

```ruby
has_many :nutrition_entries, dependent: :destroy
```

**Step 6: Run migration and tests**

Run: `rails db:migrate && ruby -Itest test/models/nutrition_entry_test.rb`
Expected: PASS

**Step 7: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: add NutritionEntry model replacing nutrition_data SiteDocument

One row per ingredient with 11 FDA nutrients, density data,
named portions (jsonb), and USDA source provenance (jsonb).
Kitchen-scoped via acts_as_tenant."
```

---

### Task 6: Update `MarkdownImporter` to store cross-references

**Files:**
- Modify: `app/services/markdown_importer.rb`
- Modify: `test/services/markdown_importer_test.rb`

**Step 1: Write tests for cross-reference storage**

Add to `test/services/markdown_importer_test.rb`:

```ruby
test 'imports cross-references with multiplier and prep_note' do
  ActsAsTenant.with_tenant(@kitchen) do
    MarkdownImporter.import("# Dough\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nMix it.", kitchen: @kitchen)

    markdown = "# Pizza\n\nCategory: Bread\n\n## Assemble\n\n- @[Dough], 2: Let rest.\n- Cheese, 1 cup\n\nAssemble it."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    step = recipe.steps.first
    assert_equal 1, step.cross_references.size

    ref = step.cross_references.first
    assert_equal 'Dough', ref.target_title
    assert_in_delta 2.0, ref.multiplier
    assert_equal 'Let rest.', ref.prep_note
  end
end

test 'cross-references and ingredients share position sequence' do
  ActsAsTenant.with_tenant(@kitchen) do
    MarkdownImporter.import("# Sauce\n\nCategory: Bread\n\n## Mix\n\n- Tomato, 1 can\n\nMix.", kitchen: @kitchen)

    markdown = "# Pizza\n\nCategory: Bread\n\n## Build\n\n- Dough, 1 ball\n- @[Sauce]\n- Cheese, 2 cups\n\nBuild it."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    step = recipe.steps.first
    items = step.ingredient_list_items

    assert_equal 3, items.size
    assert_equal 'Dough', items[0].name
    assert_kind_of CrossReference, items[1]
    assert_equal 'Cheese', items[2].name
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n test_imports_cross_references_with_multiplier_and_prep_note`
Expected: FAIL — importer doesn't create CrossReference records yet.

**Step 3: Update MarkdownImporter**

Replace the `import_ingredients` and `rebuild_dependencies` methods in `app/services/markdown_importer.rb`:

```ruby
def replace_steps(recipe)
  recipe.steps.destroy_all

  parsed[:steps].each_with_index do |step_data, index|
    step = recipe.steps.create!(
      title: step_data[:tldr],
      instructions: step_data[:instructions],
      position: index
    )

    import_step_items(step, step_data[:ingredients])
  end
end

def import_step_items(step, ingredient_data_list)
  ingredient_data_list.each_with_index do |data, index|
    if data[:cross_reference]
      import_cross_reference(step, data, index)
    else
      import_ingredient(step, data, index)
    end
  end
end

def import_ingredient(step, data, position)
  qty, unit = split_quantity(data[:quantity])

  step.ingredients.create!(
    name: data[:name],
    quantity: qty,
    unit: unit,
    prep_note: data[:prep_note],
    position: position
  )
end

def import_cross_reference(step, data, position)
  target_slug = FamilyRecipes.slugify(data[:target_title])
  target = kitchen.recipes.find_by(slug: target_slug)
  return unless target

  step.cross_references.create!(
    target_recipe: target,
    multiplier: data[:multiplier] || 1.0,
    prep_note: data[:prep_note],
    position: position
  )
end
```

Keep `rebuild_dependencies` as-is — it still serves the graph-query purpose (which recipes reference which, independent of step position).

**Step 4: Run tests**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: PASS

**Step 5: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: store cross-references with multiplier, prep_note, position

MarkdownImporter now creates CrossReference records alongside
Ingredients, sharing a position sequence for interleaved rendering.
RecipeDependency still maintained for graph queries."
```

---

### Task 7: Update seeds to create `NutritionEntry` rows

**Files:**
- Modify: `db/seeds.rb`
- Modify: `app/models/kitchen.rb` (if not already done)

**Step 1: Update `db/seeds.rb`**

Replace the `nutrition_data` SiteDocument seeding block with NutritionEntry creation. Keep the SiteDocument for backward compatibility during migration, but add NutritionEntry rows.

Add after the existing seed logic:

```ruby
# Seed NutritionEntry rows from nutrition-data.yaml
nutrition_path = Rails.root.join('db/seeds/resources/nutrition-data.yaml')
if File.exist?(nutrition_path)
  nutrition_data = YAML.safe_load_file(nutrition_path, permitted_classes: [], permitted_symbols: [], aliases: false)
  nutrition_data.each do |name, entry|
    nutrients = entry['nutrients']
    next unless nutrients.is_a?(Hash) && nutrients['basis_grams'].is_a?(Numeric)

    density = entry['density'] || {}
    NutritionEntry.find_or_initialize_by(kitchen: kitchen, ingredient_name: name).tap do |ne|
      ne.assign_attributes(
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
        density_grams: density['grams'],
        density_volume: density['volume'],
        density_unit: density['unit'],
        portions: entry['portions'] || {},
        sources: entry['sources'] || []
      )
      ne.save!
    end
  end
  puts "  Seeded #{NutritionEntry.where(kitchen: kitchen).count} nutrition entries"
end
```

**Step 2: Test the seed**

Run: `rails db:seed`
Expected: Success. Output includes "Seeded N nutrition entries".

**Step 3: Verify in console**

Run: `rails runner "puts NutritionEntry.count"`
Expected: A number matching the YAML entry count.

**Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: seed NutritionEntry rows from nutrition-data.yaml

Idempotent: find_or_initialize_by prevents duplicates on re-seed.
Runs alongside existing SiteDocument seeding for backward compat."
```

---

### Task 8: Consolidate SiteDocument fallback pattern

**Files:**
- Modify: `app/models/site_document.rb`
- Modify: `app/controllers/homepage_controller.rb`
- Modify: `app/controllers/recipes_controller.rb`
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `app/controllers/groceries_controller.rb`

**Step 1: Add class method to SiteDocument**

In `app/models/site_document.rb`:

```ruby
# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  acts_as_tenant :kitchen

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :content, presence: true

  def self.content_for(name, fallback_path: nil)
    find_by(name: name)&.content || (fallback_path && File.exist?(fallback_path) && File.read(fallback_path))
  end
end
```

**Step 2: Update controllers to use `SiteDocument.content_for`**

Update each controller's fallback methods to use the consolidated pattern. For example, in `RecipesController#load_nutrition_data`:

```ruby
def load_nutrition_data
  content = SiteDocument.content_for('nutrition_data',
    fallback_path: Rails.root.join('db/seeds/resources/nutrition-data.yaml'))
  return unless content

  YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
end
```

Apply the same pattern to `homepage_controller.rb` (`load_site_config`), `ingredients_controller.rb` (`load_grocery_aisles`), and `groceries_controller.rb` (`load_grocery_aisles`, `load_quick_bites_by_subsection`).

**Step 3: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 4: Run lint**

Run: `rake lint`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: consolidate SiteDocument fallback into content_for class method

Replaces four separate load methods with SiteDocument.content_for(name, fallback_path:).
Controllers still own parsing (YAML, markdown) but fallback logic is DRY."
```

---

## Milestone 2: Eliminate Parser at Render Time

Goal: Pre-process instructions on save. Pre-compute nutrition on save. Update views to render from AR data only. Delete render-time parser code from controllers.

### Task 9: Process instructions on save

**Files:**
- Modify: `app/services/markdown_importer.rb`
- Modify: `test/services/markdown_importer_test.rb`

**Step 1: Write the test**

Add to `test/services/markdown_importer_test.rb`:

```ruby
test 'stores processed_instructions with scalable number spans' do
  ActsAsTenant.with_tenant(@kitchen) do
    markdown = "# Bread\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n\nCombine 3* cups of water."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    step = recipe.steps.first
    assert_includes step.processed_instructions, 'data-base-value="3"'
    assert_includes step.processed_instructions, 'scalable'
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/markdown_importer_test.rb -n test_stores_processed_instructions_with_scalable_number_spans`
Expected: FAIL — processed_instructions is nil.

**Step 3: Update MarkdownImporter**

In `replace_steps`, after creating the step, process instructions:

```ruby
def replace_steps(recipe)
  recipe.steps.destroy_all

  parsed[:steps].each_with_index do |step_data, index|
    step = recipe.steps.create!(
      title: step_data[:tldr],
      instructions: step_data[:instructions],
      processed_instructions: process_instructions(step_data[:instructions]),
      position: index
    )

    import_step_items(step, step_data[:ingredients])
  end
end

def process_instructions(text)
  return if text.blank?

  ScalableNumberPreprocessor.process_instructions(text)
end
```

**Step 4: Run tests**

Run: `ruby -Itest test/services/markdown_importer_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: pre-process scalable number spans on save

MarkdownImporter now runs ScalableNumberPreprocessor on step
instructions at import time, storing result in processed_instructions."
```

---

### Task 10: Compute and store nutrition on save

**Files:**
- Create: `app/jobs/recipe_nutrition_job.rb`
- Create: `app/jobs/cascade_nutrition_job.rb`
- Create: `test/jobs/recipe_nutrition_job_test.rb`
- Modify: `app/services/markdown_importer.rb`

**Step 1: Write the test**

Create `test/jobs/recipe_nutrition_job_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipeNutritionJobTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    ActsAsTenant.current_tenant = @kitchen
    @category = Category.create!(name: 'Cat', slug: 'cat')

    NutritionEntry.create!(
      ingredient_name: 'Flour',
      basis_grams: 30.0,
      calories: 110.0,
      fat: 0.5,
      protein: 3.0
    )
  end

  test 'computes and stores nutrition_data on recipe' do
    markdown = "# Bread\n\nCategory: Cat\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
    recipe = MarkdownImporter.import(markdown, kitchen: @kitchen)

    RecipeNutritionJob.perform_now(recipe)
    recipe.reload

    assert recipe.nutrition_data.present?
    assert recipe.nutrition_data['totals']['calories'].positive?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: FAIL — job class doesn't exist.

**Step 3: Create job classes**

Create `app/jobs/recipe_nutrition_job.rb`:

```ruby
# frozen_string_literal: true

class RecipeNutritionJob < ApplicationJob
  def perform(recipe)
    ActsAsTenant.with_tenant(recipe.kitchen) do
      nutrition_data = build_nutrition_lookup
      return unless nutrition_data.any?

      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
      result = calculator.calculate(parsed_recipe(recipe), alias_map, recipe_map)

      recipe.update_column(:nutrition_data, serialize_result(result))
    end
  end

  private

  def build_nutrition_lookup
    NutritionEntry.all.to_h do |entry|
      nutrients = {
        'basis_grams' => entry.basis_grams.to_f,
        'calories' => entry.calories&.to_f || 0,
        'fat' => entry.fat&.to_f || 0,
        'saturated_fat' => entry.saturated_fat&.to_f || 0,
        'trans_fat' => entry.trans_fat&.to_f || 0,
        'cholesterol' => entry.cholesterol&.to_f || 0,
        'sodium' => entry.sodium&.to_f || 0,
        'carbs' => entry.carbs&.to_f || 0,
        'fiber' => entry.fiber&.to_f || 0,
        'total_sugars' => entry.total_sugars&.to_f || 0,
        'added_sugars' => entry.added_sugars&.to_f || 0,
        'protein' => entry.protein&.to_f || 0
      }

      data = { 'nutrients' => nutrients }

      if entry.density_grams && entry.density_volume && entry.density_unit
        data['density'] = {
          'grams' => entry.density_grams.to_f,
          'volume' => entry.density_volume.to_f,
          'unit' => entry.density_unit
        }
      end

      data['portions'] = entry.portions if entry.portions.present?

      [entry.ingredient_name, data]
    end
  end

  def parsed_recipe(recipe)
    FamilyRecipes::Recipe.new(
      markdown_source: recipe.markdown_source,
      id: recipe.slug,
      category: recipe.category.name
    )
  end

  def alias_map
    @alias_map ||= begin
      doc_content = SiteDocument.content_for('grocery_aisles',
        fallback_path: Rails.root.join('db/seeds/resources/grocery-info.yaml'))
      return {} unless doc_content

      aisles = FamilyRecipes.parse_grocery_aisles_markdown(doc_content)
      FamilyRecipes.build_alias_map(aisles)
    rescue StandardError
      {}
    end
  end

  def omit_set
    @omit_set ||= begin
      doc_content = SiteDocument.content_for('grocery_aisles',
        fallback_path: Rails.root.join('db/seeds/resources/grocery-info.yaml'))
      return Set.new unless doc_content

      aisles = FamilyRecipes.parse_grocery_aisles_markdown(doc_content)
      omit_key = aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
      return Set.new unless omit_key

      aisles[omit_key].to_set { |item| item[:name].downcase }
    rescue StandardError
      Set.new
    end
  end

  def recipe_map
    @recipe_map ||= Recipe.includes(:category).to_h do |r|
      [r.slug, parsed_recipe(r)]
    end
  end

  def serialize_result(result)
    {
      'totals' => result.totals.transform_values(&:to_f),
      'serving_count' => result.serving_count,
      'per_serving' => result.per_serving&.transform_values(&:to_f),
      'per_unit' => result.per_unit&.transform_values(&:to_f),
      'makes_quantity' => result.makes_quantity,
      'makes_unit_singular' => result.makes_unit_singular,
      'makes_unit_plural' => result.makes_unit_plural,
      'units_per_serving' => result.units_per_serving,
      'missing_ingredients' => result.missing_ingredients,
      'partial_ingredients' => result.partial_ingredients
    }
  end
end
```

Create `app/jobs/cascade_nutrition_job.rb`:

```ruby
# frozen_string_literal: true

class CascadeNutritionJob < ApplicationJob
  def perform(recipe)
    ActsAsTenant.with_tenant(recipe.kitchen) do
      recipe.referencing_recipes.find_each do |dependent|
        RecipeNutritionJob.perform_now(dependent)
      end
    end
  end
end
```

**Step 4: Wire into MarkdownImporter**

At the end of the `import` method in `app/services/markdown_importer.rb`, after `rebuild_dependencies`, add:

```ruby
def import
  ActiveRecord::Base.transaction do
    recipe = find_or_initialize_recipe
    update_recipe_attributes(recipe)
    recipe.save!
    replace_steps(recipe)
    rebuild_dependencies(recipe)
    recipe
  end.tap do |recipe|
    RecipeNutritionJob.perform_now(recipe)
    CascadeNutritionJob.perform_now(recipe)
  end
end
```

Note: Jobs run OUTSIDE the transaction so they see committed data.

**Step 5: Run tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: PASS

Run: `rake test`
Expected: PASS (existing tests unaffected — nutrition is now computed on save but existing code paths still work).

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: compute and store nutrition on save via ActiveJob

RecipeNutritionJob calculates nutrition from NutritionEntry rows
and stores the result as jsonb on the recipe. CascadeNutritionJob
re-computes nutrition for all recipes that reference the saved one.
Both run synchronously with perform_now; switch to Solid Queue later."
```

---

### Task 11: Update views to render from AR data only

**Files:**
- Modify: `app/views/recipes/show.html.erb`
- Modify: `app/views/recipes/_step.html.erb`
- Modify: `app/views/recipes/_nutrition_table.html.erb`
- Modify: `app/helpers/recipes_helper.rb`
- Modify: `app/controllers/recipes_controller.rb`

**Step 1: Update RecipesController#show**

Replace the `show` action and delete the render-time parser methods:

```ruby
def show
  @recipe = current_kitchen.recipes
    .includes(steps: [:ingredients, :cross_references])
    .find_by!(slug: params[:slug])
  @nutrition = @recipe.nutrition_data
rescue ActiveRecord::RecordNotFound
  head :not_found
end
```

Delete these private methods (they are no longer called):
- `parse_recipe` (lines 72–78)
- `calculate_nutrition` (lines 80–86)
- `recipe_map` (lines 124–133)

Keep `load_nutrition_data`, `load_grocery_aisles`, `alias_map`, `omit_set`, `build_omit_set` — they're still used by the groceries-related code and will be used by `RecipeNutritionJob`.

Actually, on reflection, `recipe_map`, `alias_map`, `omit_set`, `load_nutrition_data`, and `load_grocery_aisles` in RecipesController are ONLY used by `calculate_nutrition` and thus by the old render path. They can ALL be deleted from the controller. The job has its own versions.

Delete: `parse_recipe`, `calculate_nutrition`, `load_nutrition_data`, `grocery_aisles`, `load_grocery_aisles`, `alias_map`, `omit_set`, `build_omit_set`, `recipe_map`.

**Step 2: Update recipe show view**

Replace `app/views/recipes/show.html.erb` lines 29–34 (the meta line with yield formatting):

The yields now need pre-formatting. Since `ScalableNumberPreprocessor` runs on save for instructions but NOT for the meta line (makes/serves are stored as structured data, not markdown), the view should format them. Keep `format_yield_line` in the helper — it's cheap and the data comes from AR columns.

Replace lines 38–40 (the step loop) to iterate AR steps:

```erb
<% @recipe.steps.each do |step| %>
  <%= render 'step', step: step %>
<% end %>
```

Replace lines 48–50 (nutrition check) to use the JSON data:

```erb
<%- if @nutrition && @nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
  <%= render 'nutrition_table', nutrition: @nutrition %>
<%- end -%>
```

**Step 3: Update step partial**

Replace `app/views/recipes/_step.html.erb`:

```erb
<section>
  <h2><%= step.title %></h2>
  <div>
    <%- unless step.ingredient_list_items.empty? -%>
    <div class="ingredients">
      <ul>
        <%- step.ingredient_list_items.each do |item| -%>
        <%- if item.is_a?(CrossReference) -%>
        <li class="cross-reference"><b><%= link_to item.target_title, recipe_path(item.target_slug) %></b><% if item.multiplier != 1.0 %>, <span class="quantity"><%= item.multiplier == item.multiplier.to_i ? item.multiplier.to_i : item.multiplier %></span><% end %>
        <%- if item.prep_note -%>
          <small><%= item.prep_note %></small>
        <%- end -%>
        </li>
        <%- else -%>
        <li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2)}").html_safe if item.quantity_unit %><% end %>>
          <b><%= item.name %></b><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>
        <%- if item.prep_note -%>
          <small><%= item.prep_note %></small>
        <%- end -%>
        </li>
        <%- end -%>
        <%- end -%>
      </ul>
    </div>
    <%- end -%>

    <%- if step.processed_instructions.present? -%>
    <div class="instructions">
      <%= render_markdown(step.processed_instructions) %>
    </div>
    <%- elsif step.instructions.present? -%>
    <div class="instructions">
      <%= scalable_instructions(step.instructions) %>
    </div>
    <%- end -%>
  </div>
</section>
```

Note: Falls back to `scalable_instructions(step.instructions)` if `processed_instructions` is nil (for recipes that haven't been re-imported yet). This ensures a smooth migration — old data still renders.

**Step 4: Update nutrition table partial**

Replace `app/views/recipes/_nutrition_table.html.erb` to read from the JSON hash instead of the `NutritionCalculator::Result` Data.define object. The JSON keys are strings, not symbols:

```erb
<aside class="nutrition-facts">
  <h2>Nutrition Facts</h2>
  <%
    has_per_unit = nutrition['per_unit'] && nutrition['makes_quantity']&.to_f&.positive?
    has_per_serving = nutrition['per_serving'] && nutrition['serving_count']

    columns = []

    if has_per_unit
      columns << ["Per #{nutrition['makes_unit_singular']&.capitalize}", nutrition['per_unit'], false]
      if has_per_serving && nutrition['units_per_serving']
        ups = nutrition['units_per_serving']
        formatted_ups = FamilyRecipes::VulgarFractions.format(ups)
        singular = FamilyRecipes::VulgarFractions.singular_noun?(ups)
        ups_unit = singular ? nutrition['makes_unit_singular'] : nutrition['makes_unit_plural']
        columns << ["Per Serving<br>(#{formatted_ups} #{ups_unit})".html_safe, nutrition['per_serving'], false]
      end
      columns << ['Total', nutrition['totals'], true]
    elsif has_per_serving
      columns << ['Per Serving', nutrition['per_serving'], false]
      columns << ['Total', nutrition['totals'], true]
    else
      columns << ['Total', nutrition['totals'], true]
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
        ['Calories', 'calories', '', 0],
        ['Total Fat', 'fat', 'g', 0],
        ['Sat. Fat', 'saturated_fat', 'g', 1],
        ['Trans Fat', 'trans_fat', 'g', 1],
        ['Cholesterol', 'cholesterol', 'mg', 0],
        ['Sodium', 'sodium', 'mg', 0],
        ['Total Carbs', 'carbs', 'g', 0],
        ['Fiber', 'fiber', 'g', 1],
        ['Total Sugars', 'total_sugars', 'g', 1],
        ['Added Sugars', 'added_sugars', 'g', 2],
        ['Protein', 'protein', 'g', 0],
      ].each do |label, key, unit_label, indent| -%>
      <tr<%= %( class="indent-#{indent}").html_safe if indent > 0 %>>
        <td><%= label %></td>
        <%- columns.each do |_, values, is_scalable| -%>
        <td<%= %( data-nutrient="#{key}" data-base-value="#{values[key].to_f.round(1)}").html_safe if is_scalable %>><%= values[key].to_f.round %><%= unit_label %></td>
        <%- end -%>
      </tr>
      <%- end -%>
    </tbody>
  </table>
  <%
    missing = (nutrition['missing_ingredients'] || []) + (nutrition['partial_ingredients'] || [])
  %>
  <%- if missing.any? -%>
  <p class="nutrition-note">*Approximate. Data unavailable for: <%= missing.uniq.join(', ') %>.</p>
  <%- end -%>
</aside>
```

**Step 5: Run full test suite**

Run: `rake test`
Expected: Some controller tests may need updates — they assert on `@parsed_recipe` behavior that no longer exists. Update assertions to match the new AR-based rendering. The HTML output should be identical.

**Step 6: Run lint**

Run: `rake lint`
Expected: PASS

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: eliminate parser at render time

RecipesController#show loads from AR only — no parser, no recipe_map rebuild.
Views render from Step#ingredient_list_items (AR ingredients + cross-references
merged by position) and Step#processed_instructions (pre-processed on save).
Nutrition table reads from Recipe#nutrition_data (pre-computed jsonb).
Falls back to render-time processing for recipes not yet re-imported."
```

---

### Task 12: Re-import all recipes to populate new columns

**Step 1: Create a rake task or run re-import**

Run in Rails console or as a one-off script:

```bash
rails runner "
  Kitchen.find_each do |kitchen|
    ActsAsTenant.with_tenant(kitchen) do
      kitchen.recipes.find_each do |recipe|
        MarkdownImporter.import(recipe.markdown_source, kitchen: kitchen)
      end
    end
  end
  puts 'Done. All recipes re-imported.'
"
```

This re-processes all recipes through the updated `MarkdownImporter`, populating `processed_instructions`, `CrossReference` records, and `nutrition_data`.

**Step 2: Verify**

Run: `rails runner "puts Step.where.not(processed_instructions: nil).count"`
Expected: Non-zero (all steps with instructions have processed versions).

Run: `rails runner "puts CrossReference.count"`
Expected: Non-zero if any recipes have `@[...]` references.

Run: `rails runner "puts Recipe.where.not(nutrition_data: nil).count"`
Expected: Non-zero if NutritionEntry data exists.

**Step 3: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 4: Commit**

```bash
git commit --allow-empty -m "chore: re-import all recipes to populate new columns

Ran MarkdownImporter.import on all existing recipes to populate
processed_instructions, CrossReference records, and nutrition_data."
```

---

## Milestone 3: Authentication

Goal: Replace dev-only auth with OmniAuth-compatible infrastructure. Database-backed sessions, `Current` model, `Authentication` concern, `ConnectedService` model. OmniAuth `:developer` strategy for dev/test.

### Task 13: Create `Session` and `Current` models

**Files:**
- Create: `db/migrate/TIMESTAMP_create_sessions.rb`
- Create: `app/models/session.rb`
- Create: `app/models/current.rb`
- Modify: `app/models/user.rb`

**Step 1: Write the test**

Create `test/models/session_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class SessionTest < ActiveSupport::TestCase
  test 'belongs to user' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    session = user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    assert_equal user, session.user
  end

  test 'Current.user delegates through session' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    session = user.sessions.create!(ip_address: '127.0.0.1', user_agent: 'Minitest')

    Current.session = session
    assert_equal user, Current.user
  ensure
    Current.reset
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/session_test.rb`
Expected: FAIL — models don't exist.

**Step 3: Create migration**

Run: `rails generate migration CreateSessions`

Edit:

```ruby
class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
```

**Step 4: Create models**

Create `app/models/session.rb`:

```ruby
# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user
end
```

Create `app/models/current.rb`:

```ruby
# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session

  delegate :user, to: :session, allow_nil: true
end
```

Add to `app/models/user.rb`:

```ruby
has_many :sessions, dependent: :destroy
```

**Step 5: Run migration and tests**

Run: `rails db:migrate && ruby -Itest test/models/session_test.rb`
Expected: PASS

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Session model and Current for database-backed auth

Session stores user_id, ip_address, user_agent per login.
Current provides per-request thread-local session/user access."
```

---

### Task 14: Create `ConnectedService` model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_connected_services.rb`
- Create: `app/models/connected_service.rb`
- Create: `test/models/connected_service_test.rb`
- Modify: `app/models/user.rb`

**Step 1: Write the test**

Create `test/models/connected_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class ConnectedServiceTest < ActiveSupport::TestCase
  test 'links a provider identity to a user' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    service = user.connected_services.create!(provider: 'developer', uid: 'test@example.com')

    assert_equal 'developer', service.provider
    assert_equal user, service.user
  end

  test 'enforces unique provider + uid' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    user.connected_services.create!(provider: 'google', uid: '123')

    duplicate = ConnectedService.new(user: user, provider: 'google', uid: '123')
    refute duplicate.valid?
  end

  test 'allows same uid across different providers' do
    user = User.create!(name: 'Test', email: 'test@example.com')
    user.connected_services.create!(provider: 'google', uid: '123')

    different_provider = user.connected_services.new(provider: 'github', uid: '123')
    assert different_provider.valid?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/connected_service_test.rb`
Expected: FAIL

**Step 3: Create migration**

```ruby
class CreateConnectedServices < ActiveRecord::Migration[8.1]
  def change
    create_table :connected_services do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :uid, null: false

      t.timestamps
    end

    add_index :connected_services, [:provider, :uid], unique: true
  end
end
```

**Step 4: Create model**

Create `app/models/connected_service.rb`:

```ruby
# frozen_string_literal: true

class ConnectedService < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
```

Add to `app/models/user.rb`:

```ruby
has_many :connected_services, dependent: :destroy
```

**Step 5: Make email required on User**

In `app/models/user.rb`, change:

```ruby
validates :email, presence: true, uniqueness: true
```

Create migration to change the partial index to a full NOT NULL + unique:

```ruby
class MakeUserEmailRequired < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :email
    change_column_null :users, :email, false
    add_index :users, :email, unique: true
  end
end
```

**Step 6: Run migrations and tests**

Run: `rails db:migrate && ruby -Itest test/models/connected_service_test.rb`
Expected: PASS

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ConnectedService model for OAuth identity storage

Separate table (provider + uid + user_id) supports multiple OAuth
providers per user. Email now required on User for OAuth flows."
```

---

### Task 15: Create `Authentication` concern and OmniAuth setup

**Files:**
- Create: `app/controllers/concerns/authentication.rb`
- Create: `app/controllers/omniauth_callbacks_controller.rb`
- Create: `config/initializers/omniauth.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `config/routes.rb`
- Modify: `Gemfile`
- Delete: `app/controllers/dev_sessions_controller.rb`
- Modify: `test/test_helper.rb`
- Modify: `test/controllers/auth_test.rb`

This is a large task. The key steps:

**Step 1: Add OmniAuth gems to Gemfile**

```ruby
gem 'omniauth'
gem 'omniauth-rails_csrf_protection'
```

Run: `bundle install`

**Step 2: Create OmniAuth initializer**

Create `config/initializers/omniauth.rb`:

```ruby
# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :developer if Rails.env.development? || Rails.env.test?
  # Future: provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
end
```

**Step 3: Create Authentication concern**

Create `app/controllers/concerns/authentication.rb`:

```ruby
# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id])
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to '/auth/developer'
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip
    ).tap do |new_session|
      Current.session = new_session
      cookies.signed.permanent[:session_id] = {
        value: new_session.id, httponly: true, same_site: :lax
      }
    end
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(:session_id)
    Current.reset
  end

  def current_user = Current.user
end
```

**Step 4: Create OmniauthCallbacksController**

Create `app/controllers/omniauth_callbacks_controller.rb`:

```ruby
# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access only: %i[create failure]
  skip_before_action :set_kitchen_from_path

  def create
    auth = request.env['omniauth.auth']
    service = ConnectedService.find_by(provider: auth.provider, uid: auth.uid)

    if service
      start_new_session_for(service.user)
    else
      user = User.find_by(email: auth.info.email) || User.create!(
        name: auth.info.name,
        email: auth.info.email
      )
      user.connected_services.find_or_create_by!(provider: auth.provider, uid: auth.uid)
      start_new_session_for(user)
    end

    redirect_to after_authentication_url
  end

  def failure
    redirect_to root_path
  end
end
```

**Step 5: Update ApplicationController**

Replace `app/controllers/application_controller.rb`:

```ruby
# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern
  allow_unauthenticated_access

  set_current_tenant_through_filter
  before_action :set_kitchen_from_path

  helper_method :current_kitchen, :logged_in?

  private

  def set_kitchen_from_path
    return unless params[:kitchen_slug]

    set_current_tenant(Kitchen.find_by!(slug: params[:kitchen_slug]))
  end

  def current_kitchen = ActsAsTenant.current_tenant

  def logged_in? = authenticated?

  def require_membership
    head :unauthorized unless logged_in? && current_kitchen&.member?(current_user)
  end

  def default_url_options
    { kitchen_slug: current_kitchen&.slug }.compact
  end
end
```

Note: `allow_unauthenticated_access` at the ApplicationController level makes all pages public by default (matching current behavior — read-only access for everyone). Write endpoints still use `require_membership`.

**Step 6: Update routes**

Replace `config/routes.rb`:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  root 'landing#show'

  scope 'kitchens/:kitchen_slug' do
    get '/', to: 'homepage#show', as: :kitchen_root
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'ingredients', to: 'ingredients#index', as: :ingredients
    get 'groceries', to: 'groceries#show', as: :groceries
    patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
    patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
  end

  get 'auth/:provider/callback', to: 'omniauth_callbacks#create', as: :omniauth_callback
  get 'auth/failure', to: 'omniauth_callbacks#failure'
  delete 'logout', to: 'omniauth_callbacks#destroy', as: :logout

  if Rails.env.development? || Rails.env.test?
    get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login
    get 'dev/logout', to: 'dev_sessions#destroy', as: :dev_logout
  end
end
```

Note: Keep `DevSessionsController` for test convenience — `log_in` helper still uses it. Also renamed `index` to `ingredients`.

**Step 7: Update test helper**

Replace `test/test_helper.rb`:

```ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'minitest/autorun'

# Stub OmniAuth for tests
OmniAuth.config.test_mode = true

module ActionDispatch
  class IntegrationTest
    private

    def create_kitchen_and_user
      @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
      @user = User.create!(name: 'Test User', email: 'test@example.com')
      ActsAsTenant.current_tenant = @kitchen
      Membership.create!(kitchen: @kitchen, user: @user)
    end

    def log_in(user = @user)
      get dev_login_path(id: user.id)
    end

    def kitchen_slug
      @kitchen.slug
    end
  end
end
```

**Step 8: Run full test suite**

Run: `rake test`
Expected: Fix any failures. Common issues:
- Route helper changes (`ingredients_path` instead of old name)
- Auth test assertions may need updates

Iterate until all tests pass.

**Step 9: Run lint**

Run: `rake lint`
Expected: PASS

**Step 10: Commit**

```bash
git add -A
git commit -m "feat: add OmniAuth auth infrastructure with database-backed sessions

Authentication concern provides start_new_session_for, terminate_session,
resume_session via signed cookie. OmniAuth :developer strategy for dev/test.
ConnectedService links OAuth identities to users.
DevSessionsController kept for test convenience."
```

---

## Milestone 4: Polish and Prep

### Task 16: Add health check, `.env.example`, PWA manifest

**Step 1: Add health check route**

In `config/routes.rb`, add before the root:

```ruby
get 'up', to: 'rails/health#show', as: :rails_health_check
```

**Step 2: Create `.env.example`**

Create `.env.example`:

```bash
# Database
DATABASE_HOST=localhost
DATABASE_USERNAME=
DATABASE_PASSWORD=

# Server
PORT=3030
BINDING=0.0.0.0
RAILS_MAX_THREADS=3
WEB_CONCURRENCY=1

# Rails
SECRET_KEY_BASE=
RAILS_LOG_LEVEL=info

# OAuth (Phase 2 — not yet needed)
# GOOGLE_CLIENT_ID=
# GOOGLE_CLIENT_SECRET=

# Nutrition data (optional — for USDA API lookups)
# USDA_API_KEY=
```

**Step 3: Add PWA manifest stub**

Create `public/manifest.json`:

```json
{
  "name": "Family Recipes",
  "short_name": "Recipes",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#c0392b",
  "icons": []
}
```

Add manifest link to `app/views/layouts/application.html.erb` `<head>`:

```erb
<link rel="manifest" href="/manifest.json">
```

**Step 4: Document Solid Queue upgrade path**

Add to CLAUDE.md under a new section:

```markdown
### Background Jobs

Save-time operations (nutrition calculation, cross-reference cascades) run synchronously
via `perform_now`. When this becomes too slow, add `solid_queue` gem and switch to
`perform_later`. Solid Queue runs inside Puma via `plugin :solid_queue` — no separate
process needed. See `app/jobs/` for the job classes.
```

**Step 5: Run full test suite**

Run: `rake test`
Expected: PASS

**Step 6: Run lint**

Run: `rake lint`
Expected: PASS

**Step 7: Commit**

```bash
git add -A
git commit -m "chore: add health check, .env.example, PWA manifest stub

/up endpoint for Docker health checks. .env.example documents all
environment variables. PWA manifest makes app installable on mobile.
CLAUDE.md updated with Solid Queue upgrade path."
```

---

## Post-Implementation Verification

After all milestones are complete:

1. **Run full test suite:** `rake`
2. **Reset and re-seed:** `rails db:drop db:create db:migrate db:seed`
3. **Start dev server:** `bin/dev`
4. **Verify recipe pages render correctly** — check a recipe with cross-references, nutrition data, and scalable numbers
5. **Verify groceries page** — check quick bites, aisle editing, recipe selector
6. **Verify auth flow** — visit `/auth/developer`, log in, verify edit buttons appear
7. **Verify landing page** — should list kitchens without auth
8. **Run lint:** `rake lint`

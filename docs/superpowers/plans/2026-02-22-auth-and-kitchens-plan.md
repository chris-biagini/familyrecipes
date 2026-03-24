# Auth & Kitchens Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Kitchen tenancy, User/Membership auth, kitchen-scoped URLs, and dev-only login so the app can distinguish logged-in members from anonymous visitors.

**Architecture:** Kitchen is the tenant. Routes scoped under `/kitchens/:kitchen_slug`. ApplicationController provides `current_user` (from session), `current_kitchen` (from URL slug), and `require_membership` (before_action guard). Dev-only route sets session. Views conditionally show edit UI to kitchen members.

**Tech Stack:** Rails 8, PostgreSQL, Minitest, cookie-based sessions.

**Design doc:** `docs/plans/2026-02-22-auth-and-kitchens-design.md`

---

### Task 1: Database Migrations

Create three new tables and add `kitchen_id` FK to three existing tables. Replace globally-unique indexes with kitchen-scoped composite indexes.

**Files:**
- Create: `db/migrate/TIMESTAMP_create_kitchens.rb`
- Create: `db/migrate/TIMESTAMP_create_users.rb`
- Create: `db/migrate/TIMESTAMP_create_memberships.rb`
- Create: `db/migrate/TIMESTAMP_add_kitchen_id_to_existing_tables.rb`

**Step 1: Generate migrations**

```bash
bin/rails generate migration CreateKitchens name:string slug:string
bin/rails generate migration CreateUsers name:string email:string
bin/rails generate migration CreateMemberships kitchen:references user:references role:string
bin/rails generate migration AddKitchenIdToExistingTables
```

**Step 2: Edit the kitchens migration**

```ruby
class CreateKitchens < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchens do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :kitchens, :slug, unique: true
  end
end
```

**Step 3: Edit the users migration**

```ruby
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email

      t.timestamps
    end

    add_index :users, :email, unique: true, where: 'email IS NOT NULL'
  end
end
```

Note: partial unique index — email is nullable (future OAuth users may not have one), but when present must be unique.

**Step 4: Edit the memberships migration**

```ruby
class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'member'

      t.timestamps
    end

    add_index :memberships, %i[kitchen_id user_id], unique: true
  end
end
```

**Step 5: Edit the kitchen_id FK migration**

This migration adds `kitchen_id` to categories, recipes, and site_documents. It also replaces the globally-unique slug/name indexes with kitchen-scoped composite indexes.

```ruby
class AddKitchenIdToExistingTables < ActiveRecord::Migration[8.1]
  def change
    add_reference :categories, :kitchen, null: false, foreign_key: true # rubocop:disable Rails/NotNullColumn
    add_reference :recipes, :kitchen, null: false, foreign_key: true # rubocop:disable Rails/NotNullColumn
    add_reference :site_documents, :kitchen, null: false, foreign_key: true # rubocop:disable Rails/NotNullColumn

    # Replace globally-unique indexes with kitchen-scoped composite indexes
    remove_index :categories, :slug
    add_index :categories, %i[kitchen_id slug], unique: true

    remove_index :recipes, :slug
    add_index :recipes, %i[kitchen_id slug], unique: true

    remove_index :site_documents, :name
    add_index :site_documents, %i[kitchen_id name], unique: true
  end
end
```

**Important:** The NOT NULL `kitchen_id` columns mean this migration will fail if existing data lacks a kitchen. The seeds must run on a clean database (after `db:drop db:create`), OR we handle data migration. Since this is a development branch with no production data, `db:drop db:create db:migrate db:seed` is the path.

**Step 6: Run migrations**

```bash
bin/rails db:drop db:create db:migrate
```

Expected: migrations run cleanly (no seed data yet, so NOT NULL is fine on empty tables).

**Step 7: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "db: add kitchens, users, memberships tables and kitchen_id FKs"
```

---

### Task 2: New Models — Kitchen, User, Membership

**Files:**
- Create: `app/models/kitchen.rb`
- Create: `app/models/user.rb`
- Create: `app/models/membership.rb`
- Create: `test/models/kitchen_test.rb`
- Create: `test/models/user_test.rb`
- Create: `test/models/membership_test.rb`

**Step 1: Write Kitchen model tests**

```ruby
# test/models/kitchen_test.rb
# frozen_string_literal: true

require 'test_helper'

class KitchenTest < ActiveSupport::TestCase
  setup do
    Kitchen.destroy_all
  end

  test 'validates name presence' do
    kitchen = Kitchen.new(slug: 'test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:name], "can't be blank"
  end

  test 'validates slug presence' do
    kitchen = Kitchen.new(name: 'Test')

    assert_not kitchen.valid?
    assert_includes kitchen.errors[:slug], "can't be blank"
  end

  test 'validates slug uniqueness' do
    Kitchen.create!(name: 'First', slug: 'first')
    duplicate = Kitchen.new(name: 'Other', slug: 'first')

    assert_not duplicate.valid?
  end

  test 'member? returns true for kitchen members' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    user = User.create!(name: 'Alice')
    Membership.create!(kitchen: kitchen, user: user)

    assert kitchen.member?(user)
  end

  test 'member? returns false for non-members' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    user = User.create!(name: 'Alice')

    assert_not kitchen.member?(user)
  end

  test 'member? returns false for nil user' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')

    assert_not kitchen.member?(nil)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/models/kitchen_test.rb
```

Expected: NameError — `Kitchen` model not defined (or validation failures).

**Step 3: Write Kitchen model**

```ruby
# app/models/kitchen.rb
# frozen_string_literal: true

class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :site_documents, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
  end
end
```

**Step 4: Write User model tests**

```ruby
# test/models/user_test.rb
# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  setup do
    User.destroy_all
  end

  test 'validates name presence' do
    user = User.new(email: 'test@example.com')

    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test 'allows nil email' do
    user = User.new(name: 'Alice')

    assert user.valid?
  end

  test 'validates email uniqueness when present' do
    User.create!(name: 'Alice', email: 'alice@example.com')
    duplicate = User.new(name: 'Bob', email: 'alice@example.com')

    assert_not duplicate.valid?
  end

  test 'allows multiple nil emails' do
    User.create!(name: 'Alice')
    bob = User.new(name: 'Bob')

    assert bob.valid?
  end

  test 'has kitchens through memberships' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    user = User.create!(name: 'Alice')
    Membership.create!(kitchen: kitchen, user: user)

    assert_includes user.kitchens, kitchen
  end
end
```

**Step 5: Write User model**

```ruby
# app/models/user.rb
# frozen_string_literal: true

class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :kitchens, through: :memberships

  validates :name, presence: true
  validates :email, uniqueness: true, allow_nil: true
end
```

**Step 6: Write Membership model tests**

```ruby
# test/models/membership_test.rb
# frozen_string_literal: true

require 'test_helper'

class MembershipTest < ActiveSupport::TestCase
  test 'validates uniqueness of user per kitchen' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    user = User.create!(name: 'Alice')
    Membership.create!(kitchen: kitchen, user: user)

    duplicate = Membership.new(kitchen: kitchen, user: user)

    assert_not duplicate.valid?
  end

  test 'defaults role to member' do
    kitchen = Kitchen.create!(name: 'Test', slug: 'test')
    user = User.create!(name: 'Alice')
    membership = Membership.create!(kitchen: kitchen, user: user)

    assert_equal 'member', membership.role
  end
end
```

**Step 7: Write Membership model**

```ruby
# app/models/membership.rb
# frozen_string_literal: true

class Membership < ApplicationRecord
  belongs_to :kitchen
  belongs_to :user

  validates :user_id, uniqueness: { scope: :kitchen_id }
end
```

**Step 8: Run all model tests**

```bash
bin/rails test test/models/
```

Expected: All pass.

**Step 9: Commit**

```bash
git add app/models/kitchen.rb app/models/user.rb app/models/membership.rb test/models/
git commit -m "feat: add Kitchen, User, Membership models with tests"
```

---

### Task 3: Update Existing Models — Kitchen Associations

Add `belongs_to :kitchen` to Category, Recipe, and SiteDocument. Scope uniqueness validations to kitchen.

**Files:**
- Modify: `app/models/category.rb`
- Modify: `app/models/recipe.rb`
- Modify: `app/models/site_document.rb`

**Step 1: Update Category model**

In `app/models/category.rb`, add `belongs_to :kitchen` and scope slug uniqueness:

```ruby
# frozen_string_literal: true

class Category < ApplicationRecord
  belongs_to :kitchen

  has_many :recipes, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }

  scope :ordered, -> { order(:position, :name) }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(name)
end
```

Changes: added `belongs_to :kitchen`, scoped both `name` and `slug` uniqueness to `kitchen_id`.

**Step 2: Update Recipe model**

In `app/models/recipe.rb`, add `belongs_to :kitchen` and scope slug uniqueness:

Add `belongs_to :kitchen` after the existing `belongs_to :category` (line 4). Change the slug validation from `validates :slug, presence: true, uniqueness: true` to `validates :slug, presence: true, uniqueness: { scope: :kitchen_id }`.

**Step 3: Update SiteDocument model**

In `app/models/site_document.rb`, add `belongs_to :kitchen` and scope name uniqueness:

```ruby
# frozen_string_literal: true

class SiteDocument < ApplicationRecord
  belongs_to :kitchen

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :content, presence: true
end
```

**Step 4: Run existing model tests to see what breaks**

```bash
bin/rails test test/models/ test/services/
```

Expected: Tests that create Categories/Recipes/SiteDocuments without a kitchen will fail. This is expected — we'll fix these in Task 9 (test updates).

**Step 5: Commit**

```bash
git add app/models/category.rb app/models/recipe.rb app/models/site_document.rb
git commit -m "feat: add kitchen associations to Category, Recipe, SiteDocument"
```

---

### Task 4: Update MarkdownImporter + CrossReferenceUpdater

MarkdownImporter needs a `kitchen:` keyword argument. CrossReferenceUpdater passes the referencing recipe's kitchen.

**Files:**
- Modify: `app/services/markdown_importer.rb`
- Modify: `app/services/cross_reference_updater.rb`

**Step 1: Update MarkdownImporter**

The changes:
- `self.import` and `initialize` gain `kitchen:` keyword parameter
- `update_recipe_attributes` assigns `kitchen: @kitchen`
- `find_or_create_category` scopes to `@kitchen.categories`

```ruby
# frozen_string_literal: true

class MarkdownImporter
  def self.import(markdown_source, kitchen:)
    new(markdown_source, kitchen: kitchen).import
  end

  def initialize(markdown_source, kitchen:)
    @markdown_source = markdown_source
    @kitchen = kitchen
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
    tokens = LineClassifier.classify(markdown_source)
    RecipeBuilder.new(tokens).build
  end

  def find_or_initialize_recipe
    slug = FamilyRecipes.slugify(parsed[:title])
    @kitchen.recipes.find_or_initialize_by(slug: slug)
  end

  def update_recipe_attributes(recipe)
    category = find_or_create_category(parsed[:front_matter][:category])
    makes_qty, makes_unit = parse_makes(parsed[:front_matter][:makes])

    recipe.assign_attributes(
      title: parsed[:title],
      description: parsed[:description],
      category: category,
      kitchen: @kitchen,
      makes_quantity: makes_qty,
      makes_unit_noun: makes_unit,
      serves: parsed[:front_matter][:serves]&.to_i,
      footer: parsed[:footer],
      markdown_source: markdown_source
    )
  end

  def find_or_create_category(name)
    slug = FamilyRecipes.slugify(name)
    @kitchen.categories.find_or_create_by!(slug: slug) do |cat|
      cat.name = name
      cat.position = @kitchen.categories.maximum(:position).to_i + 1
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
      next if data[:cross_reference]

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

**Step 2: Update CrossReferenceUpdater**

In `app/services/cross_reference_updater.rb`, pass `kitchen:` to `MarkdownImporter.import`:

Change line 37 from:
```ruby
MarkdownImporter.import(updated_source)
```
to:
```ruby
MarkdownImporter.import(updated_source, kitchen: ref_recipe.kitchen)
```

**Step 3: Commit**

```bash
git add app/services/markdown_importer.rb app/services/cross_reference_updater.rb
git commit -m "feat: add kitchen parameter to MarkdownImporter and CrossReferenceUpdater"
```

---

### Task 5: Update Seeds

Create kitchen, user, and membership. Pass kitchen to all MarkdownImporter calls.

**Files:**
- Modify: `db/seeds.rb`

**Step 1: Rewrite seeds.rb**

```ruby
# frozen_string_literal: true

# Create kitchen and user
kitchen = Kitchen.find_or_create_by!(slug: 'biagini-family') do |k|
  k.name = 'Biagini Family'
end

user = User.find_or_create_by!(email: 'chris@example.com') do |u|
  u.name = 'Chris'
end

Membership.find_or_create_by!(kitchen: kitchen, user: user)

puts "Kitchen: #{kitchen.name} (#{kitchen.slug})"
puts "User: #{user.name} (#{user.email})"

# Import recipes
recipes_dir = Rails.root.join('recipes')
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

  existing = Recipe.find_by(slug: slug)
  if existing&.edited_at?
    puts "  [skipped] #{existing.title} (web-edited)"
    next
  end

  recipe = MarkdownImporter.import(markdown, kitchen: kitchen)
  puts "  #{recipe.title} (#{recipe.category.name})"
end

puts "Done! #{Recipe.count} recipes, #{Category.count} categories."

# Seed Quick Bites document
quick_bites_path = recipes_dir.join('Quick Bites.md')
if File.exist?(quick_bites_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'quick_bites') do |doc|
    doc.content = File.read(quick_bites_path)
  end
  puts 'Quick Bites document loaded.'
end

# Seed Grocery Aisles document (convert YAML to markdown)
grocery_yaml_path = Rails.root.join('resources/grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  SiteDocument.find_or_create_by!(kitchen: kitchen, name: 'grocery_aisles') do |doc|
    raw = YAML.safe_load_file(grocery_yaml_path, permitted_classes: [], permitted_symbols: [], aliases: false)
    doc.content = raw.map { |aisle, items|
      heading = "## #{aisle.tr('_', ' ')}"
      item_lines = items.map { |item|
        name = item.respond_to?(:fetch) ? item.fetch('name') : item
        "- #{name}"
      }
      [heading, *item_lines, ''].join("\n")
    }.join("\n")
  end
  puts 'Grocery Aisles document loaded.'
end
```

**Step 2: Run fresh database setup**

```bash
bin/rails db:drop db:create db:migrate db:seed
```

Expected: All migrations run, kitchen + user + membership created, all recipes imported with kitchen_id, site documents created with kitchen_id.

**Step 3: Verify in console**

```bash
bin/rails runner "puts Kitchen.count; puts User.count; puts Recipe.count; puts Category.pluck(:kitchen_id).uniq"
```

Expected: 1 kitchen, 1 user, N recipes, all categories have same kitchen_id.

**Step 4: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: update seeds with kitchen, user, and membership creation"
```

---

### Task 6: Routes + Auth Infrastructure

Rewrite routes under `/kitchens/:kitchen_slug` scope. Add auth helpers to ApplicationController. Create DevSessionsController and LandingController.

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/dev_sessions_controller.rb`
- Create: `app/controllers/landing_controller.rb`
- Create: `app/views/landing/show.html.erb`

**Step 1: Rewrite routes.rb**

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  root 'landing#show'

  scope 'kitchens/:kitchen_slug' do
    get '/', to: 'homepage#show', as: :kitchen_root
    resources :recipes, only: %i[show create update destroy], param: :slug
    get 'index', to: 'ingredients#index', as: :ingredients
    get 'groceries', to: 'groceries#show', as: :groceries
    patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
    patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
  end

  # Dev-only login (not loaded in production)
  if Rails.env.development? || Rails.env.test?
    get 'dev/login/:id', to: 'dev_sessions#create', as: :dev_login
    get 'dev/logout', to: 'dev_sessions#destroy', as: :dev_logout
  end
end
```

Note: dev routes are also available in test environment so we can test the login helper.

**Step 2: Rewrite ApplicationController**

```ruby
# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :current_user, :current_kitchen, :logged_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_kitchen
    return @current_kitchen if defined?(@current_kitchen)

    @current_kitchen = Kitchen.find_by!(slug: params[:kitchen_slug]) if params[:kitchen_slug]
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

Note: `current_kitchen` uses `defined?(@current_kitchen)` guard to avoid re-querying after a nil result (e.g., on the landing page where there's no kitchen_slug). It only queries if `params[:kitchen_slug]` is present.

**Step 3: Create DevSessionsController**

```ruby
# app/controllers/dev_sessions_controller.rb
# frozen_string_literal: true

class DevSessionsController < ApplicationController
  def create
    user = User.find(params[:id])
    session[:user_id] = user.id
    redirect_to kitchen_root_path(kitchen_slug: user.kitchens.first.slug)
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
```

**Step 4: Create LandingController**

```ruby
# app/controllers/landing_controller.rb
# frozen_string_literal: true

class LandingController < ApplicationController
  def show
    @kitchens = Kitchen.all
  end
end
```

**Step 5: Create landing page view**

```erb
<%# app/views/landing/show.html.erb %>
<% content_for(:title) { 'Family Recipes' } %>

<article class="landing">
  <header>
    <h1>Family Recipes</h1>
    <p>A place for your family's recipes.</p>
  </header>

  <% if @kitchens.any? %>
  <nav class="kitchen-list">
    <ul>
      <% @kitchens.each do |kitchen| %>
      <li><%= link_to kitchen.name, kitchen_root_path(kitchen_slug: kitchen.slug) %></li>
      <% end %>
    </ul>
  </nav>
  <% end %>
</article>
```

**Step 6: Verify routes compile**

```bash
bin/rails routes
```

Expected: routes list shows `/kitchens/:kitchen_slug/recipes/:slug`, `kitchen_root`, `dev_login`, `dev_logout`, etc.

**Step 7: Commit**

```bash
git add config/routes.rb app/controllers/application_controller.rb app/controllers/dev_sessions_controller.rb app/controllers/landing_controller.rb app/views/landing/
git commit -m "feat: kitchen-scoped routes, auth helpers, dev login, landing page"
```

---

### Task 7: Update Controllers — Scoping + Auth

Add `before_action :require_membership` to write endpoints. Scope queries to `current_kitchen`. Update redirect paths.

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Modify: `app/controllers/groceries_controller.rb`
- Modify: `app/controllers/homepage_controller.rb`
- Modify: `app/controllers/ingredients_controller.rb`

**Step 1: Update RecipesController**

Key changes:
- Add `before_action :require_membership, only: %i[create update destroy]`
- Scope `Recipe` queries to `current_kitchen.recipes`
- Pass `kitchen: current_kitchen` to `MarkdownImporter.import`
- Change `root_path` in destroy redirect to `kitchen_root_path`
- Scope `recipe_map` to current kitchen
- Scope category cleanup to current kitchen

```ruby
# frozen_string_literal: true

class RecipesController < ApplicationController
  before_action :require_membership, only: %i[create update destroy]

  def show
    @recipe = current_kitchen.recipes.includes(steps: :ingredients).find_by!(slug: params[:slug])
    @parsed_recipe = parse_recipe
    @nutrition = calculate_nutrition
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def create
    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)
    recipe.update!(edited_at: Time.current)

    render json: { redirect_url: recipe_path(recipe.slug) }
  end

  def update
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    errors = MarkdownValidator.validate(params[:markdown_source])
    return render json: { errors: errors }, status: :unprocessable_entity if errors.any?

    old_title = @recipe.title
    recipe = MarkdownImporter.import(params[:markdown_source], kitchen: current_kitchen)

    updated_references = if title_changed?(old_title, recipe.title)
                           CrossReferenceUpdater.rename_references(old_title: old_title, new_title: recipe.title)
                         else
                           []
                         end

    @recipe.destroy! if recipe.slug != @recipe.slug
    recipe.update!(edited_at: Time.current)
    current_kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: recipe_path(recipe.slug) }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def destroy
    @recipe = current_kitchen.recipes.find_by!(slug: params[:slug])

    updated_references = CrossReferenceUpdater.strip_references(@recipe)
    @recipe.destroy!
    current_kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all

    response_json = { redirect_url: kitchen_root_path }
    response_json[:updated_references] = updated_references if updated_references.any?
    render json: response_json
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def title_changed?(old_title, new_title)
    old_title != new_title
  end

  def parse_recipe
    FamilyRecipes::Recipe.new(
      markdown_source: @recipe.markdown_source,
      id: @recipe.slug,
      category: @recipe.category.name
    )
  end

  def calculate_nutrition
    nutrition_data = load_nutrition_data
    return unless nutrition_data

    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
    calculator.calculate(@parsed_recipe, alias_map, recipe_map)
  end

  def load_nutrition_data
    path = Rails.root.join('resources/nutrition-data.yaml')
    return unless File.exist?(path)

    YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def grocery_aisles
    @grocery_aisles ||= load_grocery_aisles
  end

  def load_grocery_aisles
    doc = current_kitchen.site_documents.find_by(name: 'grocery_aisles')
    return FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml')) unless doc

    FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
  end

  def alias_map
    @alias_map ||= FamilyRecipes.build_alias_map(grocery_aisles)
  end

  def omit_set
    @omit_set ||= build_omit_set
  end

  def build_omit_set
    omit_key = grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    grocery_aisles[omit_key].to_set { |item| item[:name].downcase }
  end

  def recipe_map
    @recipe_map ||= current_kitchen.recipes.includes(:category).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end
end
```

**Step 2: Update GroceriesController**

Key changes:
- Add `before_action :require_membership, only: %i[update_quick_bites update_grocery_aisles]`
- Scope all queries to `current_kitchen`

```ruby
# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership, only: %i[update_quick_bites update_grocery_aisles]

  def show
    @categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    @grocery_aisles = load_grocery_aisles
    @alias_map = FamilyRecipes.build_alias_map(@grocery_aisles)
    @omit_set = build_omit_set
    @recipe_map = build_recipe_map
    @unit_plurals = collect_unit_plurals
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = quick_bites_document&.content || ''
    @grocery_aisles_content = grocery_aisles_document&.content || ''
  end

  def update_quick_bites
    content = params[:content].to_s
    return render json: { errors: ['Content cannot be blank.'] }, status: :unprocessable_entity if content.blank?

    doc = current_kitchen.site_documents.find_or_initialize_by(name: 'quick_bites')
    doc.content = content
    doc.save!

    render json: { status: 'ok' }
  end

  def update_grocery_aisles
    content = params[:content].to_s
    errors = validate_grocery_aisles(content)
    return render json: { errors: }, status: :unprocessable_entity if errors.any?

    doc = current_kitchen.site_documents.find_or_initialize_by(name: 'grocery_aisles')
    doc.content = content
    doc.save!

    render json: { status: 'ok' }
  end

  private

  def load_grocery_aisles
    doc = grocery_aisles_document
    return fallback_grocery_aisles unless doc

    FamilyRecipes.parse_grocery_aisles_markdown(doc.content)
  end

  def fallback_grocery_aisles
    yaml_path = Rails.root.join('resources/grocery-info.yaml')
    return {} unless File.exist?(yaml_path)

    FamilyRecipes.parse_grocery_info(yaml_path)
  end

  def build_omit_set
    omit_key = @grocery_aisles.keys.find { |k| k.downcase.tr('_', ' ') == 'omit from list' }
    return Set.new unless omit_key

    @grocery_aisles[omit_key].to_set { |item| item[:name].downcase }
  end

  def build_recipe_map
    current_kitchen.recipes.includes(:category).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end

  def collect_unit_plurals
    @recipe_map.values
               .flat_map { |r| r.all_ingredients_with_quantities(@alias_map, @recipe_map) }
               .flat_map { |_, amounts| amounts.compact.filter_map(&:unit) }
               .uniq
               .to_h { |u| [u, FamilyRecipes::Inflector.unit_display(u, 2)] }
  end

  def load_quick_bites_by_subsection
    doc = quick_bites_document
    return {} unless doc

    FamilyRecipes.parse_quick_bites_content(doc.content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def quick_bites_document
    @quick_bites_document ||= current_kitchen.site_documents.find_by(name: 'quick_bites')
  end

  def grocery_aisles_document
    @grocery_aisles_document ||= current_kitchen.site_documents.find_by(name: 'grocery_aisles')
  end

  def validate_grocery_aisles(content)
    return ['Content cannot be blank.'] if content.blank?

    parsed = FamilyRecipes.parse_grocery_aisles_markdown(content)
    validations = {
      'Must have at least one aisle (## Aisle Name).' => parsed.empty?
    }

    validations.select { |_msg, failed| failed }.keys
  end
end
```

**Step 3: Update HomepageController**

Scope categories to `current_kitchen`:

```ruby
# frozen_string_literal: true

class HomepageController < ApplicationController
  def show
    @site_config = load_site_config
    @categories = categories_with_recipes
  end

  private

  def load_site_config = YAML.safe_load_file(Rails.root.join('resources/site-config.yaml'))

  def categories_with_recipes
    current_kitchen.categories.ordered.includes(:recipes).reject { |cat| cat.recipes.empty? }
  end
end
```

**Step 4: Update IngredientsController**

Scope queries to `current_kitchen`:

```ruby
# frozen_string_literal: true

class IngredientsController < ApplicationController
  def index
    @ingredients_with_recipes = build_ingredient_index
  end

  private

  def build_ingredient_index
    alias_map = load_alias_map
    index = recipes_by_ingredient(alias_map)
    index.sort_by { |name, _| name.downcase }
  end

  def recipes_by_ingredient(alias_map)
    current_kitchen.recipes.includes(steps: :ingredients).each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        canonical = alias_map[ingredient.name.downcase] || ingredient.name
        index[canonical] << recipe unless index[canonical].include?(recipe)
      end
    end
  end

  def load_alias_map
    grocery_aisles = FamilyRecipes.parse_grocery_info(Rails.root.join('resources/grocery-info.yaml'))
    FamilyRecipes.build_alias_map(grocery_aisles)
  end
end
```

**Step 5: Commit**

```bash
git add app/controllers/
git commit -m "feat: scope controllers to current_kitchen, add require_membership guards"
```

---

### Task 8: Update Views

Update nav links to use kitchen-scoped helpers. Wrap edit buttons in membership checks. Update the landing page nav.

**Files:**
- Modify: `app/views/shared/_nav.html.erb`
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/views/recipes/show.html.erb`
- Modify: `app/views/groceries/show.html.erb`
- Modify: `app/views/ingredients/index.html.erb`
- Modify: `app/views/recipes/_editor_dialog.html.erb`
- Modify: `app/views/layouts/application.html.erb`

**Step 1: Update nav partial**

The nav links need to be kitchen-scoped when inside a kitchen, and absent when on the landing page.

```erb
<%# app/views/shared/_nav.html.erb %>
  <nav>
    <div>
      <% if current_kitchen %>
        <%= link_to 'Home', kitchen_root_path, class: 'home', title: 'Home (Table of Contents)' %>
        <%= link_to 'Index', ingredients_path, class: 'index', title: 'Index of ingredients' %>
        <%= link_to 'Groceries', groceries_path, class: 'groceries', title: 'Printable grocery list' %>
      <% else %>
        <%= link_to 'Home', root_path, class: 'home', title: 'Home' %>
      <% end %>
    </div>
    <%= yield :extra_nav if content_for?(:extra_nav) %>
  </nav>
```

**Step 2: Update homepage view**

Wrap the "+ New" button in a membership check. Update the recipe-meta category link to use `kitchen_root_path` anchor.

In `app/views/homepage/show.html.erb`, change lines 3-7 (extra_nav):

```erb
<% content_for(:extra_nav) do %>
  <% if current_kitchen.member?(current_user) %>
    <div>
      <button type="button" id="new-recipe-button" class="btn">+ New</button>
    </div>
  <% end %>
<% end %>
```

Also wrap the editor dialog render (lines 44-47) in the same check:

```erb
<% if current_kitchen.member?(current_user) %>
  <%= render 'recipes/editor_dialog',
             mode: :create,
             content: "# Recipe Title\n\nOptional description.\n\nCategory: \nMakes: \nServes: \n\n## Step Name (short summary)\n\n- Ingredient, quantity: prep note\n\nInstructions here.\n\n---\n\nOptional notes or source.",
             action_url: recipes_path %>
<% end %>
```

**Step 3: Update recipe show view**

Wrap the edit button and editor dialog in membership check. The scale button stays visible to everyone.

In `app/views/recipes/show.html.erb`, change lines 7-12 (extra_nav):

```erb
<% content_for(:extra_nav) do %>
    <div>
      <% if current_kitchen.member?(current_user) %>
        <button type="button" id="edit-button" class="btn">Edit</button>
      <% end %>
      <button type="button" id="scale-button" class="btn">Scale</button>
    </div>
<% end %>
```

Wrap the editor dialog render (lines 51-55) in membership check:

```erb
<% if current_kitchen.member?(current_user) %>
  <%= render 'editor_dialog',
             mode: :edit,
             content: @recipe.markdown_source,
             action_url: recipe_path(@recipe.slug),
             recipe: @recipe %>
<% end %>
```

Update the recipe-meta category link (line 28) from `root_path` to `kitchen_root_path`:

```erb
<%= link_to @recipe.category.name, kitchen_root_path(anchor: @recipe.category.slug) %>
```

**Step 4: Update groceries view**

Wrap edit buttons in membership check. In `app/views/groceries/show.html.erb`, change lines 18-23 (extra_nav):

```erb
<% content_for(:extra_nav) do %>
  <% if current_kitchen.member?(current_user) %>
    <div>
      <button type="button" id="edit-quick-bites-button" class="btn">Edit Quick Bites</button>
      <button type="button" id="edit-aisles-button" class="btn">Edit Aisles</button>
    </div>
  <% end %>
<% end %>
```

Wrap editor dialogs (lines 130-164) in membership check:

```erb
<% if current_kitchen.member?(current_user) %>
  <dialog class="editor-dialog" ...> ... </dialog>
  <dialog class="editor-dialog" ...> ... </dialog>
<% end %>
```

**Step 5: No changes needed for ingredients index view or editor dialog partial**

The ingredients view already uses `recipe_path(recipe.slug)` which will auto-fill `kitchen_slug` via `default_url_options`. The editor dialog partial doesn't reference any paths directly — its `action_url` is passed in from the parent view.

**Step 6: Verify route helpers render correctly**

```bash
bin/rails runner "app = ActionDispatch::Integration::Session.new(Rails.application); puts app.kitchen_root_path(kitchen_slug: 'biagini-family')"
```

Expected: `/kitchens/biagini-family`

**Step 7: Commit**

```bash
git add app/views/
git commit -m "feat: kitchen-scoped nav links, conditional edit buttons for members"
```

---

### Task 9: Update All Tests

This is the largest task. Every integration test needs a kitchen + kitchen_slug in URLs. Write tests need a logged-in session. Add new auth-specific tests.

**Files:**
- Modify: `test/test_helper.rb`
- Modify: `test/controllers/recipes_controller_test.rb`
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `test/controllers/homepage_controller_test.rb`
- Modify: `test/controllers/ingredients_controller_test.rb`
- Modify: `test/services/markdown_importer_test.rb`
- Modify: `test/services/cross_reference_updater_test.rb`
- Create: `test/controllers/dev_sessions_controller_test.rb`
- Create: `test/controllers/landing_controller_test.rb`
- Create: `test/controllers/auth_test.rb`

**Step 1: Update test_helper.rb with auth helpers**

```ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative '../config/environment'
require 'rails/test_help'
require 'minitest/autorun'

class ActionDispatch::IntegrationTest
  private

  def create_kitchen_and_user
    @kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
    @user = User.create!(name: 'Test User', email: 'test@example.com')
    Membership.create!(kitchen: @kitchen, user: @user)
  end

  def log_in
    get dev_login_path(id: @user.id)
  end

  def kitchen_slug
    @kitchen.slug
  end
end
```

**Step 2: Update MarkdownImporterTest**

Every `MarkdownImporter.import(markdown)` call needs `kitchen:`. Add kitchen creation to setup:

In `test/services/markdown_importer_test.rb`, change setup (lines 34-37):

```ruby
setup do
  Recipe.destroy_all
  Category.destroy_all
  @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
end
```

Change every `MarkdownImporter.import(...)` call to `MarkdownImporter.import(..., kitchen: @kitchen)`. This affects lines: 40, 103, 106, 115, 119, 139, 178, 179, 199, 205, 228, 248, 279, 280. It's a mechanical find-and-replace:
- `MarkdownImporter.import(BASIC_RECIPE)` → `MarkdownImporter.import(BASIC_RECIPE, kitchen: @kitchen)`
- `MarkdownImporter.import(markdown_with_xref)` → `MarkdownImporter.import(markdown_with_xref, kitchen: @kitchen)`
- etc.

Also update the `split_quantity` test (line 205) constructor:

```ruby
importer = MarkdownImporter.new("# Dummy\n\nCategory: Test\n\n## Step\n\n- Salt\n\nText.", kitchen: @kitchen)
```

**Step 3: Update CrossReferenceUpdaterTest**

Add kitchen creation to setup and pass `kitchen:` to all import calls. The test file at `test/services/cross_reference_updater_test.rb` needs the same treatment as MarkdownImporterTest.

**Step 4: Update RecipesControllerTest**

Major changes:
- Add `create_kitchen_and_user` and `log_in` to setup
- Add `kitchen_slug` to all path helpers
- Add `log_in` before write operations
- Update `root_path` assertion in destroy test to `kitchen_root_path`
- Pass `kitchen:` to MarkdownImporter calls in setup

Replace setup block:

```ruby
setup do
  create_kitchen_and_user
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia
    ...existing markdown...
  MD
end
```

Path helper changes (all instances):
- `recipe_path('focaccia')` → `recipe_path('focaccia', kitchen_slug: kitchen_slug)`
- `recipes_path` → `recipes_path(kitchen_slug: kitchen_slug)`
- `root_path` → `kitchen_root_path(kitchen_slug: kitchen_slug)` (in destroy redirect assertion)

Add `log_in` before every `patch`, `post`, `delete` call:

```ruby
test 'update saves valid markdown and returns redirect URL' do
  log_in
  patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
        params: { markdown_source: updated_markdown },
        as: :json
  ...
end
```

Read tests (GET) do NOT need `log_in` — they remain publicly accessible.

**Step 5: Update GroceriesControllerTest**

Same pattern:
- Add `create_kitchen_and_user` to setup (or inline per test since some tests create their own data)
- Add `kitchen_slug` to path helpers
- Add `log_in` before PATCH calls
- Pass `kitchen:` to MarkdownImporter calls

For tests that create data inline (most of them), add kitchen creation at the start:

```ruby
test 'renders the groceries page with recipe checkboxes' do
  create_kitchen_and_user
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    ...
  MD

  get groceries_path(kitchen_slug: kitchen_slug)
  ...
end
```

For tests that reference `SiteDocument`, associate with kitchen:

```ruby
SiteDocument.create!(name: 'quick_bites', content: ..., kitchen: @kitchen)
```

**Step 6: Update HomepageControllerTest**

Same pattern:
- `create_kitchen_and_user` in each test (or a shared setup)
- `get kitchen_root_path(kitchen_slug: kitchen_slug)` instead of `get root_path`
- `recipe_path('focaccia', kitchen_slug: kitchen_slug)` in assertions
- `Category.create!(..., kitchen: @kitchen)` for all category creations
- `MarkdownImporter.import(..., kitchen: @kitchen)` for all imports

**Step 7: Update IngredientsControllerTest**

Same pattern:
- `create_kitchen_and_user`
- `get ingredients_path(kitchen_slug: kitchen_slug)`
- `Category.create!(..., kitchen: @kitchen)`
- `MarkdownImporter.import(..., kitchen: @kitchen)`
- `recipe_path('focaccia', kitchen_slug: kitchen_slug)` in assertions

**Step 8: Create DevSessionsControllerTest**

```ruby
# test/controllers/dev_sessions_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class DevSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
  end

  test 'login sets session and redirects to kitchen' do
    get dev_login_path(id: @user.id)

    assert_redirected_to kitchen_root_path(kitchen_slug: @kitchen.slug)
  end

  test 'logout clears session and redirects to landing' do
    log_in

    get dev_logout_path

    assert_redirected_to root_path
  end
end
```

**Step 9: Create LandingControllerTest**

```ruby
# test/controllers/landing_controller_test.rb
# frozen_string_literal: true

require 'test_helper'

class LandingControllerTest < ActionDispatch::IntegrationTest
  test 'renders landing page' do
    get root_path

    assert_response :success
    assert_select 'h1', 'Family Recipes'
  end

  test 'lists kitchens' do
    Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')

    get root_path

    assert_response :success
    assert_select 'a', 'Test Kitchen'
  end
end
```

**Step 10: Create auth integration tests**

```ruby
# test/controllers/auth_test.rb
# frozen_string_literal: true

require 'test_helper'

class AuthTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups

      Mix well.
    MD
  end

  test 'unauthenticated POST to recipes returns 401' do
    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: "# New\n\nCategory: Bread\n\n## Step (do)\n\n- Flour\n\nMix." },
         as: :json

    assert_response :unauthorized
  end

  test 'unauthenticated PATCH to recipes returns 401' do
    patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
          params: { markdown_source: "# Focaccia\n\nCategory: Bread\n\n## Step (do)\n\n- Flour\n\nMix." },
          as: :json

    assert_response :unauthorized
  end

  test 'unauthenticated DELETE to recipes returns 401' do
    delete recipe_path('focaccia', kitchen_slug: kitchen_slug), as: :json

    assert_response :unauthorized
  end

  test 'unauthenticated PATCH to quick_bites returns 401' do
    patch groceries_quick_bites_path(kitchen_slug: kitchen_slug),
          params: { content: '## Snacks' },
          as: :json

    assert_response :unauthorized
  end

  test 'unauthenticated PATCH to grocery_aisles returns 401' do
    patch groceries_grocery_aisles_path(kitchen_slug: kitchen_slug),
          params: { content: "## Produce\n- Apples" },
          as: :json

    assert_response :unauthorized
  end

  test 'non-member cannot write to a kitchen' do
    outsider = User.create!(name: 'Outsider')
    get dev_login_path(id: outsider.id)

    post recipes_path(kitchen_slug: kitchen_slug),
         params: { markdown_source: "# New\n\nCategory: Bread\n\n## Step (do)\n\n- Flour\n\nMix." },
         as: :json

    assert_response :unauthorized
  end

  test 'recipe page hides edit button for non-members' do
    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-button', count: 0
  end

  test 'recipe page shows edit button for members' do
    log_in

    get recipe_path('focaccia', kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-button', count: 1
  end

  test 'homepage hides new button for non-members' do
    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#new-recipe-button', count: 0
  end

  test 'homepage shows new button for members' do
    log_in

    get kitchen_root_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#new-recipe-button', count: 1
  end

  test 'groceries page hides edit buttons for non-members' do
    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-quick-bites-button', count: 0
    assert_select '#edit-aisles-button', count: 0
  end

  test 'groceries page shows edit buttons for members' do
    log_in

    get groceries_path(kitchen_slug: kitchen_slug)

    assert_response :success
    assert_select '#edit-quick-bites-button', count: 1
    assert_select '#edit-aisles-button', count: 1
  end
end
```

**Step 11: Run full test suite**

```bash
rake test
```

Expected: All tests pass. Fix any failures.

**Step 12: Run lint**

```bash
rake lint
```

Expected: No new violations. Fix any.

**Step 13: Commit**

```bash
git add test/
git commit -m "test: update all tests for kitchen scoping and auth"
```

---

### Task 10: Final Verification

**Step 1: Run full default rake (lint + test)**

```bash
rake
```

Expected: Clean pass.

**Step 2: Start dev server and manually verify**

```bash
bin/dev
```

Check in browser:
- `http://localhost:3030/` → landing page with kitchen link
- Click kitchen link → `/kitchens/biagini-family` homepage
- No edit buttons visible (not logged in)
- Visit `http://localhost:3030/dev/login/1` → redirects to kitchen homepage
- Edit buttons now visible
- Click a recipe → edit/scale buttons, edit button visible
- Groceries page → edit buttons visible
- Visit `http://localhost:3030/dev/logout` → back to landing page
- Edit buttons gone

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "feat: auth and kitchens — complete implementation"
```

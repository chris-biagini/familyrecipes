# Recipe Tagging Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a kitchen-scoped tagging system to recipes with faceted search filtering, editor integration, recipe detail display, and tag management.

**Architecture:** Tags are a normalized join table (`tags` + `recipe_tags`) with kitchen-scoped uniqueness. The search overlay gains pill-based filtering (client-side). The recipe editor gains a side panel with tag input and autocomplete. A management dialog reuses the ordered list editor in a new "no ordering" mode.

**Tech Stack:** Rails 8, SQLite, Stimulus, Turbo Streams, Minitest

**Spec:** `docs/plans/2026-03-13-recipe-tagging-design.md`

---

## Chunk 1: Data Layer (Models, Migration, Write Services)

### Task 1: Migration and Models

**Files:**
- Create: `db/migrate/004_create_tags.rb`
- Create: `app/models/tag.rb`
- Create: `app/models/recipe_tag.rb`
- Modify: `app/models/recipe.rb:18-20` (add tag associations)
- Modify: `app/models/kitchen.rb` (add `has_many :tags`)
- Create: `test/models/tag_test.rb`
- Create: `test/models/recipe_tag_test.rb`

- [ ] **Step 1: Write Tag model tests**

Create `test/models/tag_test.rb`:

```ruby
require 'test_helper'

class TagTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
  end

  test 'valid with letters-only name' do
    tag = Tag.new(name: 'vegan')
    assert tag.valid?
  end

  test 'valid with hyphenated name' do
    tag = Tag.new(name: 'gluten-free')
    assert tag.valid?
  end

  test 'downcases name on save' do
    tag = Tag.create!(name: 'Vegan')
    assert_equal 'vegan', tag.name
  end

  test 'rejects names with spaces' do
    tag = Tag.new(name: 'two words')
    assert_not tag.valid?
    assert_includes tag.errors[:name], 'only allows letters and hyphens'
  end

  test 'rejects names with numbers' do
    tag = Tag.new(name: 'tag123')
    assert_not tag.valid?
  end

  test 'rejects names with underscores' do
    tag = Tag.new(name: 'under_score')
    assert_not tag.valid?
  end

  test 'rejects blank name' do
    tag = Tag.new(name: '')
    assert_not tag.valid?
  end

  test 'enforces kitchen-scoped uniqueness' do
    Tag.create!(name: 'vegan')
    duplicate = Tag.new(name: 'vegan')
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  test 'same name allowed in different kitchens' do
    Tag.create!(name: 'vegan')

    other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    ActsAsTenant.with_tenant(other_kitchen) do
      tag = Tag.new(name: 'vegan')
      assert tag.valid?
    end
  end

  test 'cleanup_orphans removes tags with no recipes' do
    used = Tag.create!(name: 'used')
    orphan = Tag.create!(name: 'orphan')
    setup_test_category
    recipe = Recipe.create!(title: 'Test', slug: 'test',
                            markdown_source: '# Test', category: @category)
    RecipeTag.create!(recipe: recipe, tag: used)

    Tag.cleanup_orphans(@kitchen)

    assert Tag.exists?(used.id)
    assert_not Tag.exists?(orphan.id)
  end

  test 'destroying tag cascades to recipe_tags' do
    tag = Tag.create!(name: 'doomed')
    setup_test_category
    recipe = Recipe.create!(title: 'Test', slug: 'test',
                            markdown_source: '# Test', category: @category)
    RecipeTag.create!(recipe: recipe, tag: tag)

    assert_difference 'RecipeTag.count', -1 do
      tag.destroy
    end
  end
end
```

- [ ] **Step 2: Write RecipeTag model tests**

Create `test/models/recipe_tag_test.rb`:

```ruby
require 'test_helper'

class RecipeTagTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category
    @recipe = Recipe.create!(title: 'Test', slug: 'test',
                             markdown_source: '# Test', category: @category)
    @tag = Tag.create!(name: 'vegan')
  end

  test 'valid with recipe and tag' do
    rt = RecipeTag.new(recipe: @recipe, tag: @tag)
    assert rt.valid?
  end

  test 'prevents duplicate recipe-tag pairs' do
    RecipeTag.create!(recipe: @recipe, tag: @tag)
    duplicate = RecipeTag.new(recipe: @recipe, tag: @tag)
    assert_not duplicate.valid?
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/models/tag_test.rb && ruby -Itest test/models/recipe_tag_test.rb`
Expected: FAIL — models and table don't exist yet

- [ ] **Step 4: Write the migration**

Create `db/migrate/004_create_tags.rb`:

```ruby
class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    add_index :tags, %i[kitchen_id name], unique: true

    create_table :recipe_tags do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
    end

    add_index :recipe_tags, %i[recipe_id tag_id], unique: true
  end
end
```

- [ ] **Step 5: Write the Tag model**

Create `app/models/tag.rb`:

```ruby
# Kitchen-scoped label for cross-cutting recipe classification.
# Tags are single-word (letters and hyphens only), stored lowercase.
# Managed via TagWriteService for bulk operations; created inline
# by RecipeWriteService during recipe saves.
#
# Collaborators:
# - RecipeTag: join model linking tags to recipes
# - RecipeWriteService: creates tags on recipe save, calls cleanup_orphans
# - TagWriteService: bulk rename/delete from management dialog
# - SearchDataHelper: includes tags in search JSON for pill recognition
class Tag < ApplicationRecord
  acts_as_tenant :kitchen

  has_many :recipe_tags, dependent: :destroy
  has_many :recipes, through: :recipe_tags

  validates :name, presence: true,
                   uniqueness: { scope: :kitchen_id, case_sensitive: false },
                   format: { with: /\A[a-zA-Z-]+\z/,
                             message: 'only allows letters and hyphens' }

  before_validation :downcase_name

  def self.cleanup_orphans(kitchen)
    kitchen.tags.where.missing(:recipe_tags).destroy_all
  end

  private

  def downcase_name
    self.name = name.downcase if name.present?
  end
end
```

- [ ] **Step 6: Write the RecipeTag model**

Create `app/models/recipe_tag.rb`:

```ruby
# Join model linking recipes to tags. No business logic — just
# enforces the unique constraint preventing duplicate assignments.
#
# Collaborators:
# - Recipe: parent recipe
# - Tag: parent tag
class RecipeTag < ApplicationRecord
  belongs_to :recipe
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :recipe_id }
end
```

- [ ] **Step 7: Add tag associations to Recipe and Kitchen models**

Modify `app/models/kitchen.rb`. Add alongside existing `has_many` declarations:

```ruby
has_many :tags, dependent: :destroy
```

Modify `app/models/recipe.rb`. After the existing `has_many :inbound_cross_references` block (around line 24), add:

```ruby
has_many :recipe_tags, dependent: :destroy
has_many :tags, through: :recipe_tags
```

Update the `with_full_tree` scope (around line 35) to include tags:

```ruby
scope :with_full_tree, lambda {
  includes(:category, :tags,
           steps: [:ingredients,
                   { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }])
}
```

- [ ] **Step 8: Run migration and tests**

Run: `rails db:migrate && ruby -Itest test/models/tag_test.rb && ruby -Itest test/models/recipe_tag_test.rb`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add db/migrate/004_create_tags.rb app/models/tag.rb app/models/recipe_tag.rb \
  app/models/recipe.rb app/models/kitchen.rb \
  test/models/tag_test.rb test/models/recipe_tag_test.rb db/schema.rb
git commit -m "feat: add Tag and RecipeTag models with migration"
```

---

### Task 2: RecipeWriteService Tag Handling

**Files:**
- Modify: `app/services/recipe_write_service.rb`
- Create: `test/services/recipe_write_service_tags_test.rb`

- [ ] **Step 1: Write failing tests for tag sync**

Create `test/services/recipe_write_service_tags_test.rb`:

```ruby
require 'test_helper'

class RecipeWriteServiceTagsTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category
    @markdown = "# Tagged Recipe\n\n## Step\n\n- Flour, 1 cup\n\nMix."
  end

  test 'create with tags creates tag records and associations' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[vegan quick]
    )

    assert_equal 2, result.recipe.tags.size
    assert_equal %w[quick vegan], result.recipe.tags.map(&:name).sort
  end

  test 'create without tags works as before' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name
    )

    assert_equal 0, result.recipe.tags.size
  end

  test 'create finds existing tags instead of duplicating' do
    Tag.create!(name: 'vegan')

    assert_no_difference 'Tag.count' do
      RecipeWriteService.create(
        markdown: @markdown, kitchen: @kitchen,
        category_name: @category.name, tags: %w[vegan]
      )
    end
  end

  test 'update syncs tags — adds new, removes absent' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[vegan quick]
    )

    RecipeWriteService.update(
      slug: result.recipe.slug, markdown: @markdown,
      kitchen: @kitchen, category_name: @category.name,
      tags: %w[vegan weeknight]
    )

    result.recipe.reload
    assert_equal %w[vegan weeknight], result.recipe.tags.map(&:name).sort
  end

  test 'update with empty tags removes all tags' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[vegan quick]
    )

    RecipeWriteService.update(
      slug: result.recipe.slug, markdown: @markdown,
      kitchen: @kitchen, category_name: @category.name,
      tags: []
    )

    result.recipe.reload
    assert_empty result.recipe.tags
  end

  test 'update without tags param leaves tags unchanged' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[vegan]
    )

    RecipeWriteService.update(
      slug: result.recipe.slug, markdown: @markdown,
      kitchen: @kitchen, category_name: @category.name
    )

    result.recipe.reload
    assert_equal ['vegan'], result.recipe.tags.map(&:name)
  end

  test 'removing tags cleans up orphaned tag records' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[orphan-me]
    )

    RecipeWriteService.update(
      slug: result.recipe.slug, markdown: @markdown,
      kitchen: @kitchen, category_name: @category.name,
      tags: []
    )

    assert_not Tag.exists?(name: 'orphan-me')
  end

  test 'tags are downcased on save' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[Vegan QUICK]
    )

    assert_equal %w[quick vegan], result.recipe.tags.map(&:name).sort
  end

  test 'destroy removes recipe_tags but orphan cleanup handles tag records' do
    result = RecipeWriteService.create(
      markdown: @markdown, kitchen: @kitchen,
      category_name: @category.name, tags: %w[doomed]
    )

    RecipeWriteService.destroy(slug: result.recipe.slug, kitchen: @kitchen)

    assert_not Tag.exists?(name: 'doomed')
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/recipe_write_service_tags_test.rb`
Expected: FAIL — `tags` parameter not accepted yet

- [ ] **Step 3: Add tag sync to RecipeWriteService**

Modify `app/services/recipe_write_service.rb`:

RecipeWriteService uses class methods that delegate to instance methods.
Add `tags: nil` to both layers, pass it through, and call `sync_tags` in the
instance methods. Add `Tag.cleanup_orphans` to `finalize`.

**Class methods** (around lines 17 and 21) — add `tags: nil` and pass through:
```ruby
def self.create(markdown:, kitchen:, category_name:, tags: nil)
  new(kitchen:).create(markdown:, category_name:, tags:)
end

def self.update(slug:, markdown:, kitchen:, category_name:, tags: nil)
  new(kitchen:).update(slug:, markdown:, category_name:, tags:)
end
```

**Instance methods** (around lines 33 and 40) — add `tags: nil` and call sync:
```ruby
def create(markdown:, category_name:, tags: nil)
  # ... existing body ...
  sync_tags(recipe, tags) if tags
  finalize
  # ...
end

def update(slug:, markdown:, category_name:, tags: nil)
  # ... existing body ...
  sync_tags(recipe, tags) if tags
  finalize
  # ...
end
```

In `finalize` (around line 95), add before `kitchen.broadcast_update`:
```ruby
Tag.cleanup_orphans(kitchen)
```

Add private instance method (uses the `kitchen` attr_reader, not `recipe.kitchen`):
```ruby
def sync_tags(recipe, tag_names)
  desired = tag_names.map { |n| kitchen.tags.find_or_create_by!(name: n.downcase) }
  recipe.tags = desired
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/recipe_write_service_tags_test.rb`
Expected: All PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `rake test`
Expected: All existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add app/services/recipe_write_service.rb test/services/recipe_write_service_tags_test.rb
git commit -m "feat: add tag sync to RecipeWriteService"
```

---

### Task 3: TagWriteService

**Files:**
- Create: `app/services/tag_write_service.rb`
- Create: `test/services/tag_write_service_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/services/tag_write_service_test.rb`:

```ruby
require 'test_helper'

class TagWriteServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    Tag.where(kitchen: @kitchen).destroy_all
    @vegan = Tag.create!(name: 'vegan')
    @quick = Tag.create!(name: 'quick')
  end

  test 'rename updates tag name' do
    result = TagWriteService.update(
      kitchen: @kitchen,
      renames: { 'vegan' => 'plant-based' },
      deletes: []
    )

    assert result.success
    @vegan.reload
    assert_equal 'plant-based', @vegan.name
  end

  test 'rename rejects duplicate name' do
    result = TagWriteService.update(
      kitchen: @kitchen,
      renames: { 'vegan' => 'quick' },
      deletes: []
    )

    assert_not result.success
    assert result.errors.any? { |e| e.include?('quick') }
  end

  test 'delete removes tag and associations' do
    setup_test_category
    recipe = Recipe.create!(title: 'Test', slug: 'test',
                            markdown_source: '# Test', category: @category)
    RecipeTag.create!(recipe: recipe, tag: @vegan)

    result = TagWriteService.update(
      kitchen: @kitchen,
      renames: {},
      deletes: ['vegan']
    )

    assert result.success
    assert_not Tag.exists?(@vegan.id)
    assert_empty recipe.reload.tags
  end

  test 'rename and delete in same changeset' do
    result = TagWriteService.update(
      kitchen: @kitchen,
      renames: { 'quick' => 'fast' },
      deletes: ['vegan']
    )

    assert result.success
    assert_not Tag.exists?(@vegan.id)
    assert_equal 'fast', @quick.reload.name
  end

  test 'empty changeset succeeds' do
    result = TagWriteService.update(
      kitchen: @kitchen,
      renames: {},
      deletes: []
    )

    assert result.success
  end

  test 'rename downcases new name' do
    TagWriteService.update(
      kitchen: @kitchen,
      renames: { 'vegan' => 'PLANT-BASED' },
      deletes: []
    )

    assert_equal 'plant-based', @vegan.reload.name
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/tag_write_service_test.rb`
Expected: FAIL — service doesn't exist

- [ ] **Step 3: Implement TagWriteService**

Create `app/services/tag_write_service.rb`:

```ruby
# Handles bulk tag management operations (rename, delete) from the
# tag management dialog. Follows the same changeset pattern as
# CategoryWriteService — a single call processes all mutations.
#
# Collaborators:
# - Tag: the model being mutated
# - TagsController: thin controller that delegates here
# - Kitchen#broadcast_update: notifies clients after changes
class TagWriteService
  Result = Data.define(:success, :errors)

  def self.update(kitchen:, renames:, deletes:)
    errors = validate_renames(kitchen, renames)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      apply_renames(kitchen, renames)
      apply_deletes(kitchen, deletes)
    end

    kitchen.broadcast_update
    Result.new(success: true, errors: [])
  end

  def self.validate_renames(kitchen, renames)
    errors = []
    existing = kitchen.tags.pluck(:name)
    renames.each do |old_name, new_name|
      normalized = new_name.downcase
      if normalized != old_name && existing.include?(normalized)
        errors << "Tag '#{new_name}' already exists"
      end
    end
    errors
  end
  private_class_method :validate_renames

  def self.apply_renames(kitchen, renames)
    renames.each do |old_name, new_name|
      tag = kitchen.tags.find_by!(name: old_name)
      tag.update!(name: new_name.downcase)
    end
  end
  private_class_method :apply_renames

  def self.apply_deletes(kitchen, deletes)
    kitchen.tags.where(name: deletes).destroy_all if deletes.any?
  end
  private_class_method :apply_deletes
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/tag_write_service_test.rb`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/tag_write_service.rb test/services/tag_write_service_test.rb
git commit -m "feat: add TagWriteService for bulk tag management"
```

---

### Task 4: TagsController and Routes

**Files:**
- Create: `app/controllers/tags_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/tags_controller_test.rb`

- [ ] **Step 1: Write failing controller tests**

Create `test/controllers/tags_controller_test.rb`:

```ruby
require 'test_helper'

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    @vegan = Tag.create!(name: 'vegan', kitchen: @kitchen)
    @quick = Tag.create!(name: 'quick', kitchen: @kitchen)
  end

  test 'tags_content returns tag names as JSON' do
    get tags_content_path(kitchen_slug: kitchen_slug), as: :json

    assert_response :success
    body = response.parsed_body
    assert_includes body['items'], 'vegan'
    assert_includes body['items'], 'quick'
  end

  test 'update_tags renames and deletes' do
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: { 'vegan' => 'plant-based' }, deletes: ['quick'] },
          as: :json

    assert_response :success
    assert_equal 'plant-based', @vegan.reload.name
    assert_not Tag.exists?(@quick.id)
  end

  test 'update_tags returns errors on duplicate rename' do
    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: { 'vegan' => 'quick' }, deletes: [] },
          as: :json

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert body['errors'].any?
  end

  test 'requires membership for update' do
    other_user = User.create!(name: 'Other', email: 'other@example.com')
    get dev_login_path(id: other_user.id)

    patch tags_update_path(kitchen_slug: kitchen_slug),
          params: { renames: {}, deletes: [] },
          as: :json

    assert_response :forbidden
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/tags_controller_test.rb`
Expected: FAIL — controller and routes don't exist

- [ ] **Step 3: Add routes**

Modify `config/routes.rb`. Add near the existing `categories` routes (around line 39):

```ruby
patch 'tags/update', to: 'tags#update_tags', as: :tags_update
get 'tags/content', to: 'tags#content', as: :tags_content
```

- [ ] **Step 4: Implement TagsController**

Create `app/controllers/tags_controller.rb`:

```ruby
# Thin controller for the tag management dialog. Provides content
# loading (list of tag names) and bulk update (renames + deletes).
# Delegates all business logic to TagWriteService.
#
# Collaborators:
# - TagWriteService: handles rename/delete changeset
# - Tag: queried for content listing
class TagsController < ApplicationController
  before_action :require_membership, only: :update_tags

  def content
    items = current_kitchen.tags.order(:name).pluck(:name)
    render json: { items: }
  end

  def update_tags
    result = TagWriteService.update(
      kitchen: current_kitchen,
      renames: params.fetch(:renames, {}).to_unsafe_h,
      deletes: params.fetch(:deletes, [])
    )

    if result.success
      render json: { success: true }
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/tags_controller_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/tags_controller.rb config/routes.rb \
  test/controllers/tags_controller_test.rb
git commit -m "feat: add TagsController with routes for tag management"
```

---

### Task 5: Wire tags param through RecipesController

**Files:**
- Modify: `app/controllers/recipes_controller.rb`
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'create with tags assigns tags to the recipe' do
  markdown = "# Tag Test\n\n## Step\n\n- Flour, 1 cup\n\nMix."
  post recipes_path(kitchen_slug: kitchen_slug),
       params: { markdown_source: markdown, category: @category.name,
                 tags: %w[vegan quick] },
       as: :json

  assert_response :success
  recipe = Recipe.find_by!(slug: 'tag-test')
  assert_equal %w[quick vegan], recipe.tags.map(&:name).sort
end

test 'update with tags syncs tags' do
  post recipes_path(kitchen_slug: kitchen_slug),
       params: { markdown_source: @focaccia_markdown, category: @category.name,
                 tags: %w[vegan] },
       as: :json

  patch recipe_path('focaccia', kitchen_slug: kitchen_slug),
        params: { markdown_source: @focaccia_markdown, category: @category.name,
                  tags: %w[quick weeknight] },
        as: :json

  assert_response :success
  recipe = Recipe.find_by!(slug: 'focaccia')
  assert_equal %w[quick weeknight], recipe.tags.map(&:name).sort
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /tags/`
Expected: FAIL — tags param not forwarded

- [ ] **Step 3: Wire tags param in RecipesController**

Modify `app/controllers/recipes_controller.rb`. In the `create` action (around line 34), add `tags:` param:

```ruby
result = RecipeWriteService.create(
  markdown: params[:markdown_source], kitchen: current_kitchen,
  category_name: params[:category], tags: params[:tags]
)
```

In the `update` action (around line 45), add `tags:` param:

```ruby
result = RecipeWriteService.update(
  slug: params[:slug], markdown: params[:markdown_source],
  kitchen: current_kitchen, category_name: params[:category],
  tags: params[:tags]
)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /tags/`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All tests pass, no regressions

- [ ] **Step 6: Commit**

```bash
git add app/controllers/recipes_controller.rb test/controllers/recipes_controller_test.rb
git commit -m "feat: wire tags param through RecipesController to write service"
```

---

## Chunk 2: Search Overlay (Data, Filtering, Pill UI)

### Task 6: SearchDataHelper Tag Integration

**Files:**
- Modify: `app/helpers/search_data_helper.rb`
- Modify: `test/helpers/search_data_helper_test.rb` (or create if absent)

- [ ] **Step 1: Write failing test**

Check if `test/helpers/search_data_helper_test.rb` exists. If not, create it. Add tests:

```ruby
require 'test_helper'

class SearchDataHelperTest < ActiveSupport::TestCase
  include SearchDataHelper

  setup do
    setup_test_kitchen
    setup_test_category
    @recipe = Recipe.create!(title: 'Miso Soup', slug: 'miso-soup',
                             markdown_source: "# Miso Soup\n\n## Step\n\n- Dashi, 4 cups\n\nHeat.",
                             category: @category)
    Tag.create!(name: 'vegan').tap { |t| RecipeTag.create!(recipe: @recipe, tag: t) }
    Tag.create!(name: 'quick').tap { |t| RecipeTag.create!(recipe: @recipe, tag: t) }
    Tag.create!(name: 'unused')
  end

  # Stub current_kitchen for the helper
  def current_kitchen
    @kitchen
  end

  test 'search data includes all_tags with all kitchen tags' do
    data = JSON.parse(search_data_json)
    assert_equal %w[quick unused vegan], data['all_tags'].sort
  end

  test 'search data includes all_categories' do
    data = JSON.parse(search_data_json)
    assert_includes data['all_categories'], @category.name
  end

  test 'search data includes tags per recipe' do
    data = JSON.parse(search_data_json)
    recipe_data = data['recipes'].find { |r| r['slug'] == 'miso-soup' }
    assert_equal %w[quick vegan], recipe_data['tags'].sort
  end

  test 'search data recipes key is an array' do
    data = JSON.parse(search_data_json)
    assert_kind_of Array, data['recipes']
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: FAIL — current format returns flat array, no `all_tags`

- [ ] **Step 3: Update SearchDataHelper**

Modify `app/helpers/search_data_helper.rb`:

Change `search_data_json` to return the new structure. The recipes query needs to `includes(:tags)`. Add `all_tags` and `all_categories` to the top-level object. Add `tags` to each recipe entry.

```ruby
def search_data_json
  recipes = current_kitchen.recipes.includes(:category, :ingredients, :tags).alphabetical
  {
    all_tags: current_kitchen.tags.order(:name).pluck(:name),
    all_categories: current_kitchen.categories.ordered.pluck(:name),
    recipes: recipes.map { |r| search_entry_for(r) }
  }.to_json
end

def search_entry_for(recipe)
  {
    title: recipe.title,
    slug: recipe.slug,
    description: recipe.description.to_s,
    category: recipe.category.name,
    tags: recipe.tags.map(&:name).sort,
    ingredients: recipe.ingredients.map(&:name).uniq
  }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/helpers/search_data_helper_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/helpers/search_data_helper.rb test/helpers/search_data_helper_test.rb
git commit -m "feat: expand search data JSON with tags and categories"
```

---

### Task 7: Search Overlay Controller — Data Parsing and Pill Filtering

**Files:**
- Modify: `app/javascript/controllers/search_overlay_controller.js`
- Modify: `app/views/shared/_search_overlay.html.erb`
- Modify: `app/assets/stylesheets/style.css`

This task updates the search overlay to parse the new JSON structure, replace the plain `<input>` with a pill-capable wrapper, implement pill recognition and filtering, and add pill styles.

- [ ] **Step 1: Update search overlay view for pill-capable input**

Modify `app/views/shared/_search_overlay.html.erb`. Replace the existing search `<input>` with a wrapper div containing the input. Add targets for the wrapper and pill container:

```erb
<div class="search-input-wrapper" data-search-overlay-target="inputWrapper">
  <span class="search-icon">&#x2315;</span>
  <div class="search-pill-area" data-search-overlay-target="pillArea"></div>
  <input type="text" class="search-input" placeholder="Search recipes..."
         data-search-overlay-target="input"
         data-action="input->search-overlay#search keydown->search-overlay#keydown"
         autocomplete="off" spellcheck="false">
</div>
```

- [ ] **Step 2: Add pill CSS to style.css**

Add to `app/assets/stylesheets/style.css` after the existing search overlay styles:

```css
/* Search & editor tag pills */
.search-input-wrapper {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.3rem;
  padding: 0.75rem 1rem;
}

.search-pill-area {
  display: contents;
}

.tag-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  padding: 0.15rem 0.55rem;
  border-radius: 99px;
  font-size: 0.75rem;
  font-weight: 500;
  white-space: nowrap;
  cursor: default;
}

.tag-pill--tag {
  background: var(--tag-bg, #e8e3db);
  color: var(--tag-text, #4a4540);
}

.tag-pill--category {
  background: var(--cat-bg, #dde7d8);
  color: var(--cat-text, #3a4a35);
}

.tag-pill__remove {
  font-size: 0.6rem;
  opacity: 0.5;
  cursor: pointer;
  line-height: 1;
  border: none;
  background: none;
  color: inherit;
  padding: 0;
}

.tag-pill__remove:hover {
  opacity: 1;
}

.search-input--hinted {
  text-decoration: underline;
  text-decoration-color: var(--text-light);
  text-underline-offset: 0.2em;
}
```

Add CSS custom properties to `:root` (light mode) and the dark mode media query:

Light mode:
```css
--tag-bg: #e8e3db;
--tag-text: #4a4540;
--cat-bg: #dde7d8;
--cat-text: #3a4a35;
```

Dark mode:
```css
--tag-bg: #3a3530;
--tag-text: #c8c0b5;
--cat-bg: #2e3a2b;
--cat-text: #a8c8a0;
```

- [ ] **Step 3: Update search_overlay_controller.js**

Modify `app/javascript/controllers/search_overlay_controller.js`:

Update targets to include `pillArea` and `inputWrapper`:
```javascript
static targets = ["dialog", "input", "results", "data", "pillArea", "inputWrapper"]
```

Update data parsing in `connect()` to use the new structure:
```javascript
const data = this.hasDataTarget
  ? JSON.parse(this.dataTarget.textContent || "{}")
  : {}
this.recipes = data.recipes || []
this.allTags = new Set((data.all_tags || []).map(t => t.toLowerCase()))
this.allCategories = new Set((data.all_categories || []).map(c => c.toLowerCase()))
this.activePills = []
```

Add pill management methods:
```javascript
checkForPillConversion() {
  const value = this.inputTarget.value
  const word = value.trimEnd()
  if (!word || value.slice(-1) !== " ") return

  const lower = word.toLowerCase()
  const type = this.allTags.has(lower) ? "tag" : this.allCategories.has(lower) ? "category" : null
  if (!type) return

  this.addPill(word, type)
  this.inputTarget.value = ""
}
```

```javascript
addPill(text, type) {
  const lower = text.toLowerCase()
  if (this.activePills.some(p => p.text === lower)) return

  this.activePills.push({ text: lower, type })
  this.renderPills()
  this.performSearch()
}
```

```javascript
removePill(index) {
  this.activePills.splice(index, 1)
  this.renderPills()
  this.performSearch()
}
```

```javascript
renderPills() {
  this.pillAreaTarget.replaceChildren()
  this.activePills.forEach((pill, i) => {
    const el = document.createElement("span")
    el.className = `tag-pill tag-pill--${pill.type}`
    el.textContent = pill.text

    const btn = document.createElement("button")
    btn.className = "tag-pill__remove"
    btn.textContent = "\u00d7"
    btn.type = "button"
    btn.addEventListener("click", (e) => {
      e.stopPropagation()
      this.removePill(i)
    })
    el.appendChild(btn)
    this.pillAreaTarget.appendChild(el)
  })
}
```

```javascript
updateHint() {
  const word = this.inputTarget.value.toLowerCase().trim()
  const matches = word && (this.allTags.has(word) || this.allCategories.has(word))
  this.inputTarget.classList.toggle("search-input--hinted", matches)
}
```

Update the `search()` method to call `checkForPillConversion()`, `updateHint()`, and `performSearch()`:
```javascript
search() {
  this.checkForPillConversion()
  this.updateHint()
  this.performSearch()
}
```

Add `performSearch()` that applies pill filters before text matching:
```javascript
performSearch() {
  const query = this.inputTarget.value.toLowerCase().trim()
  if (!query && this.activePills.length === 0) {
    this.resultsTarget.replaceChildren()
    return
  }

  let candidates = this.recipes
  for (const pill of this.activePills) {
    candidates = candidates.filter(r => this.matchesPill(r, pill))
  }

  const results = query ? this.rankResults(query, candidates) : candidates
  this.renderResults(results)
}
```

```javascript
matchesPill(recipe, pill) {
  const text = pill.text
  if (pill.type === "tag") {
    return recipe.tags?.some(t => t.toLowerCase() === text) ||
      this.textContains(recipe, text)
  }
  if (pill.type === "category") {
    return recipe.category.toLowerCase() === text ||
      this.textContains(recipe, text)
  }
  return false
}

textContains(recipe, text) {
  return recipe.title.toLowerCase().includes(text) ||
    recipe.description.toLowerCase().includes(text) ||
    recipe.ingredients.some(i => i.toLowerCase().includes(text))
}
```

Update `rankResults` to accept a `candidates` parameter and update the tier
cutoff from `< 4` to `< 5` (tags are now tier 3, ingredients tier 4):
```javascript
rankResults(query, candidates = this.recipes) {
  const scored = []
  for (const recipe of candidates) {
    const tier = this.matchTier(recipe, query)
    if (tier < 5) scored.push({ recipe, tier })
  }
  scored.sort((a, b) => {
    if (a.tier !== b.tier) return a.tier - b.tier
    return a.recipe.title.localeCompare(b.recipe.title)
  })
  return scored.map(s => s.recipe)
}
```

Handle backspace-to-dissolve in the `keydown` handler:
```javascript
// Inside keydown handler, add at the top:
if (event.key === "Backspace" && this.inputTarget.value === "" && this.activePills.length > 0) {
  const last = this.activePills.pop()
  this.inputTarget.value = last.text
  this.renderPills()
  event.preventDefault()
  return
}
```

Update `matchTier` to include tags as a ranking tier (between category and ingredients):
```javascript
matchTier(recipe, query) {
  if (recipe.title.toLowerCase().includes(query)) return 0
  if (recipe.description.toLowerCase().includes(query)) return 1
  if (recipe.category.toLowerCase().includes(query)) return 2
  if (recipe.tags?.some(t => t.toLowerCase().includes(query))) return 3
  if (recipe.ingredients.some(i => i.toLowerCase().includes(query))) return 4
  return 5
}
```

Clear pills on dialog close:
```javascript
// In the close/reset method:
this.activePills = []
this.renderPills()
```

- [ ] **Step 4: Test manually in browser**

Run: `bin/dev`

1. Open search overlay (press `/`)
2. Verify existing search still works (text matching across tiers)
3. If any tags exist, type a tag name + space → should convert to pill
4. Verify backspace dissolves pill back to text
5. Verify × button removes pill
6. Verify pill filtering: pill + text narrows results correctly

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js \
  app/views/shared/_search_overlay.html.erb \
  app/assets/stylesheets/style.css
git commit -m "feat: add pill-based tag and category filtering to search overlay"
```

---

## Chunk 3: Editor Side Panel and Tag Input

### Task 8: Editor Layout — Side Panel and Responsive Drawer

**Files:**
- Modify: `app/views/recipes/show.html.erb:33-58` (edit editor dialog)
- Modify: `app/views/homepage/show.html.erb:78-101` (new recipe dialog)
- Modify: `app/assets/stylesheets/style.css` (editor side panel + responsive)
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

- [ ] **Step 1: Restructure the editor dialog views**

In both `recipes/show.html.erb` (edit dialog, around line 33) and `homepage/show.html.erb` (new recipe dialog, around line 78), replace the textarea + category-row block with a side-panel layout.

The pattern for both dialogs:

```erb
<div class="editor-body-split">
  <textarea class="editor-textarea" data-editor-target="textarea"
            data-recipe-editor-target="textarea" spellcheck="false"
            placeholder="Loading..."></textarea>
  <div class="editor-side-panel">
    <div class="side-section">
      <label for="...-category">Category</label>
      <select id="...-category" class="category-select"
              data-recipe-editor-target="categorySelect">
        <!-- category options -->
      </select>
      <input type="text" class="category-new-input" placeholder="New category name"
             data-recipe-editor-target="categoryInput" hidden maxlength="50">
    </div>
    <div class="side-section" data-controller="tag-input"
         data-tag-input-tags-value='<%= (local_assigns[:recipe] ? recipe.tags.pluck(:name) : []).to_json %>'
         data-tag-input-all-tags-value='<%= current_kitchen.tags.left_joins(:recipe_tags).group(:id).order(:name).pluck(:name, Arel.sql("COUNT(recipe_tags.id)")).to_json %>'>
      <label>Tags</label>
      <div class="tag-pills-editor" data-tag-input-target="pills"></div>
      <div class="tag-autocomplete-wrapper">
        <input type="text" class="tag-text-input" placeholder="Add tag..."
               data-tag-input-target="input"
               data-action="input->tag-input#onInput keydown->tag-input#onKeydown"
               maxlength="30">
        <div class="tag-autocomplete" data-tag-input-target="dropdown" hidden></div>
      </div>
    </div>
  </div>
</div>
<!-- Mobile toggle (replaces desktop side panel on narrow screens) -->
<div class="editor-mobile-meta" data-action="click->recipe-editor#toggleMobilePanel">
  <span class="editor-mobile-meta__chevron">&#x25BC;</span>
  <span>Category &amp; Tags</span>
  <div class="editor-mobile-meta__preview" data-recipe-editor-target="mobilePillPreview"></div>
</div>
```

Remove the old `editor-category-row` div entirely.

- [ ] **Step 2: Add side panel and responsive CSS**

Add to `app/assets/stylesheets/style.css`:

```css
/* Editor side panel — desktop */
.editor-body-split {
  display: flex;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.editor-side-panel {
  width: 200px;
  flex-shrink: 0;
  border-left: 1px solid var(--rule);
  background: var(--surface-alt);
  padding: 0.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  overflow-y: auto;
}

.side-section label {
  font-weight: 600;
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--text-soft);
  display: block;
  margin-bottom: 0.35rem;
}

/* Mobile toggle */
.editor-mobile-meta {
  display: none;
  align-items: center;
  gap: 0.4rem;
  padding: 0.5rem 0.75rem;
  border-top: 1px solid var(--rule);
  cursor: pointer;
  font-size: 0.72rem;
  font-weight: 500;
  color: var(--text-soft);
  background: var(--surface-alt);
  user-select: none;
}

.editor-mobile-meta__chevron {
  font-size: 0.55rem;
  transition: transform 200ms;
  color: var(--text-light);
}

.editor-mobile-meta--open .editor-mobile-meta__chevron {
  transform: rotate(180deg);
}

.editor-mobile-meta__preview {
  display: flex;
  gap: 0.2rem;
  margin-left: auto;
}

/* Responsive: hide side panel, show mobile toggle on narrow screens */
@media (max-width: 640px) {
  .editor-dialog { width: min(95vw, 50rem); }

  .editor-body-split {
    flex-direction: column;
  }

  .editor-side-panel {
    width: 100%;
    border-left: none;
    border-top: 1px solid var(--rule-faint);
    display: none;
  }

  .editor-side-panel--mobile-open {
    display: flex;
  }

  .editor-mobile-meta {
    display: flex;
  }
}

/* Desktop: widen editor dialog for side panel */
@media (min-width: 641px) {
  .editor-dialog:has(.editor-body-split) {
    width: min(90vw, 56rem);
  }
}

/* Tag input in side panel */
.tag-pills-editor {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
  margin-bottom: 0.3rem;
}

.tag-text-input {
  width: 100%;
  border: 1px solid var(--rule);
  border-radius: 3px;
  padding: 0.25rem 0.4rem;
  font-size: 0.78rem;
  font-family: inherit;
  background: var(--ground);
  color: var(--text);
}

.tag-text-input::placeholder { color: var(--text-light); }

.tag-autocomplete-wrapper {
  position: relative;
}

.tag-autocomplete {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: var(--ground);
  border: 1px solid var(--rule);
  border-radius: 4px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  max-height: 150px;
  overflow-y: auto;
  z-index: 10;
  font-size: 0.75rem;
}

.tag-autocomplete__item {
  padding: 0.35rem 0.5rem;
  cursor: pointer;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.tag-autocomplete__item:hover,
.tag-autocomplete__item--highlighted {
  background: rgba(179, 58, 58, 0.06);
}

.tag-autocomplete__count {
  font-size: 0.65rem;
  color: var(--text-light);
}
```

- [ ] **Step 3: Update recipe_editor_controller for mobile toggle**

Add `mobilePillPreview` to targets. Add `toggleMobilePanel` method:

```javascript
toggleMobilePanel(event) {
  const toggle = event.currentTarget
  const panel = this.element.querySelector(".editor-side-panel")
  toggle.classList.toggle("editor-mobile-meta--open")
  panel.classList.toggle("editor-side-panel--mobile-open")
}
```

- [ ] **Step 4: Widen the editor dialog**

Update the `.editor-dialog` max-width. The `@media (min-width: 641px)` rule with `:has(.editor-body-split)` handles this (added in Step 2 CSS).

- [ ] **Step 5: Test manually in browser**

1. Open recipe editor — verify side panel shows on desktop with Category and Tags sections
2. Resize to mobile width — verify side panel hides, toggle bar appears
3. Click toggle — verify panel expands/collapses
4. Verify textarea still gets full height

- [ ] **Step 6: Commit**

```bash
git add app/views/recipes/show.html.erb app/views/homepage/show.html.erb \
  app/assets/stylesheets/style.css app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: add editor side panel layout with responsive mobile drawer"
```

---

### Task 9: Tag Input Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/tag_input_controller.js`
- Modify: `config/importmap.rb` (if manual pin needed — check if `pin_all_from` covers controllers)

- [ ] **Step 1: Create tag_input_controller.js**

Create `app/javascript/controllers/tag_input_controller.js`:

```javascript
// Manages the tag input field in the recipe editor side panel.
// Renders existing tags as pills, provides autocomplete from the
// kitchen's tag list, and exposes getters for recipe_editor_controller
// to read during editor:collect and editor:modified events.
//
// Collaborators:
// - recipe_editor_controller: reads tags/modified getters during editor events
// - editor_controller: dispatches editor:reset which triggers tag restoration
// - SearchDataHelper: provides allTags data via embedded JSON attribute
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pills", "input", "dropdown"]
  static values = {
    tags: { type: Array, default: [] },
    allTags: { type: Array, default: [] }  // [[name, count], ...]
  }

  connect() {
    this.currentTags = [...this.tagsValue]
    this.originalTags = [...this.tagsValue]
    this.highlightedIndex = -1
    this.tagCounts = new Map(this.allTagsValue.map(([name, count]) => [name, count]))
    this.tagNames = this.allTagsValue.map(([name]) => name)
    this.renderPills()

    this.handleReset = () => { this.reset() }
    this.element.closest("[data-controller~='editor']")
      ?.addEventListener("editor:reset", this.handleReset)
  }

  disconnect() {
    this.element.closest("[data-controller~='editor']")
      ?.removeEventListener("editor:reset", this.handleReset)
  }

  get tags() {
    return [...this.currentTags]
  }

  get modified() {
    return JSON.stringify(this.currentTags.sort()) !== JSON.stringify(this.originalTags.sort())
  }

  reset() {
    this.currentTags = [...this.originalTags]
    this.renderPills()
    this.inputTarget.value = ""
    this.hideDropdown()
  }

  onInput() {
    const value = this.inputTarget.value.toLowerCase().replace(/[^a-z-]/g, "")
    if (value !== this.inputTarget.value) {
      this.inputTarget.value = value
    }
    this.showAutocomplete(value)
  }

  onKeydown(event) {
    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      if (this.highlightedIndex >= 0) {
        this.selectHighlighted()
      } else {
        this.addCurrentInput()
      }
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveHighlight(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveHighlight(-1)
    } else if (event.key === "Escape") {
      this.hideDropdown()
    } else if (event.key === "Backspace" && this.inputTarget.value === "") {
      this.currentTags.pop()
      this.renderPills()
    }
  }

  addCurrentInput() {
    const name = this.inputTarget.value.trim().toLowerCase()
    if (name && /^[a-z-]+$/.test(name) && !this.currentTags.includes(name)) {
      this.currentTags.push(name)
      this.renderPills()
    }
    this.inputTarget.value = ""
    this.hideDropdown()
  }

  addTag(name) {
    const lower = name.toLowerCase()
    if (!this.currentTags.includes(lower)) {
      this.currentTags.push(lower)
      this.renderPills()
    }
    this.inputTarget.value = ""
    this.hideDropdown()
    this.inputTarget.focus()
  }

  removeTag(index) {
    this.currentTags.splice(index, 1)
    this.renderPills()
  }

  renderPills() {
    this.pillsTarget.replaceChildren()
    this.currentTags.forEach((name, i) => {
      const pill = document.createElement("span")
      pill.className = "tag-pill tag-pill--tag"
      pill.textContent = name

      const btn = document.createElement("button")
      btn.className = "tag-pill__remove"
      btn.textContent = "\u00d7"
      btn.type = "button"
      btn.addEventListener("click", () => this.removeTag(i))

      pill.appendChild(btn)
      this.pillsTarget.appendChild(pill)
    })
  }

  showAutocomplete(query) {
    if (!query) {
      this.hideDropdown()
      return
    }

    const matches = this.tagNames
      .filter(t => t.startsWith(query) && !this.currentTags.includes(t))
      .slice(0, 8)

    if (matches.length === 0) {
      this.hideDropdown()
      return
    }

    this.highlightedIndex = 0
    this.dropdownTarget.replaceChildren()

    matches.forEach((tag, i) => {
      const item = document.createElement("div")
      item.className = "tag-autocomplete__item"
      if (i === 0) item.classList.add("tag-autocomplete__item--highlighted")

      const nameSpan = document.createElement("span")
      nameSpan.textContent = tag
      item.appendChild(nameSpan)

      const count = this.tagCounts.get(tag) || 0
      if (count > 0) {
        const countSpan = document.createElement("span")
        countSpan.className = "tag-autocomplete__count"
        countSpan.textContent = `${count} recipe${count === 1 ? "" : "s"}`
        item.appendChild(countSpan)
      }

      item.addEventListener("click", () => this.addTag(tag))
      this.dropdownTarget.appendChild(item)
    })

    this.dropdownTarget.hidden = false
    this.currentMatches = matches
  }

  hideDropdown() {
    this.dropdownTarget.hidden = true
    this.highlightedIndex = -1
    this.currentMatches = []
  }

  moveHighlight(direction) {
    if (!this.currentMatches?.length) return
    const items = this.dropdownTarget.querySelectorAll(".tag-autocomplete__item")
    if (this.highlightedIndex >= 0) {
      items[this.highlightedIndex]?.classList.remove("tag-autocomplete__item--highlighted")
    }
    this.highlightedIndex = Math.max(0, Math.min(this.currentMatches.length - 1,
      this.highlightedIndex + direction))
    items[this.highlightedIndex]?.classList.add("tag-autocomplete__item--highlighted")
  }

  selectHighlighted() {
    if (this.highlightedIndex >= 0 && this.currentMatches?.[this.highlightedIndex]) {
      this.addTag(this.currentMatches[this.highlightedIndex])
    }
  }
}
```

- [ ] **Step 2: Verify controller auto-registers**

Check that `config/importmap.rb` has `pin_all_from "app/javascript/controllers"` — if so, the new controller is auto-registered. No manual pin needed.

- [ ] **Step 3: Test manually in browser**

1. Open recipe editor
2. Type in tag field — verify character restriction (letters + hyphens only)
3. Type partial tag name — autocomplete dropdown appears
4. Arrow down/up, Enter to select — pill appears
5. Type new tag + Enter — pill appears
6. Click × on pill — tag removed
7. Backspace on empty input — last pill removed
8. Click Cancel — tags reset to original

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/tag_input_controller.js
git commit -m "feat: add tag_input_controller with autocomplete and pill management"
```

---

### Task 10: Wire Tag Input into Editor Lifecycle

**Files:**
- Modify: `app/javascript/controllers/recipe_editor_controller.js`

- [ ] **Step 1: Update recipe_editor_controller to gather tags on collect**

Modify `handleCollect` (around line 119) to also read tags from the `tag_input_controller`:

```javascript
handleCollect(event) {
  event.detail.handled = true
  const tagController = this.element.querySelector("[data-controller~='tag-input']")
    ?.__stimulusController
    || this.application.getControllerForElementAndIdentifier(
      this.element.querySelector("[data-controller~='tag-input']"), "tag-input"
    )

  event.detail.data = {
    markdown_source: this.hasTextareaTarget ? this.textareaTarget.value : null,
    category: this.selectedCategory(),
    tags: tagController?.tags || []
  }
}
```

- [ ] **Step 2: Update handleModified to check tag changes**

Modify `handleModified` (around line 127) to also check tag controller:

```javascript
handleModified(event) {
  if (this.selectedCategory() !== this.originalCategory) {
    event.detail.modified = true
  }
  const tagController = this.application.getControllerForElementAndIdentifier(
    this.element.querySelector("[data-controller~='tag-input']"), "tag-input"
  )
  if (tagController?.modified) {
    event.detail.modified = true
  }
}
```

- [ ] **Step 3: Extract tag controller lookup to a shared method**

Refactor both methods to use a single `tagController` getter:

```javascript
get tagController() {
  const el = this.element.querySelector("[data-controller~='tag-input']")
  return el ? this.application.getControllerForElementAndIdentifier(el, "tag-input") : null
}
```

Then use `this.tagController?.tags` and `this.tagController?.modified` in the handlers.

- [ ] **Step 4: Test manually**

1. Open editor, add a tag, click Cancel — should get unsaved changes warning
2. Open editor, add a tag, click Save — verify tags param is sent (check Network tab)
3. Reload page, open editor — verify saved tags appear as pills

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/recipe_editor_controller.js
git commit -m "feat: wire tag_input_controller into editor collect and modified events"
```

---

## Chunk 4: Recipe Detail, Tag Management, Polish

### Task 11: Recipe Detail Page — Tag Display

**Files:**
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Modify: `app/assets/stylesheets/style.css`
- Modify: `app/javascript/controllers/recipe_state_controller.js` (add searchTag action)
- Modify: `app/javascript/controllers/search_overlay_controller.js` (add openWithTag method)
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write failing test**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'show page displays tags as pills' do
  tag = Tag.create!(name: 'vegan', kitchen: @kitchen)
  RecipeTag.create!(recipe: @recipe, tag: tag)

  get recipe_path(@recipe.slug, kitchen_slug: kitchen_slug)

  assert_response :success
  assert_select '.recipe-tag-pill', 'vegan'
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /tags.*pills/`
Expected: FAIL — no `.recipe-tag-pill` element

- [ ] **Step 3: Add tag pills to recipe-meta line**

Modify `app/views/recipes/_recipe_content.html.erb`. After the serves/makes metadata (around line 15, after the closing `<p>` of `.recipe-meta`), add:

```erb
<% if recipe.tags.any? %>
  <p class="recipe-tags">
    <% recipe.tags.sort_by(&:name).each do |tag| %>
      <button type="button" class="recipe-tag-pill tag-pill tag-pill--tag"
              data-action="click->recipe-state#searchTag"
              data-tag="<%= tag.name %>"><%= tag.name %></button>
    <% end %>
  </p>
<% end %>
```

- [ ] **Step 4: Add recipe tag pill CSS**

Add to `app/assets/stylesheets/style.css`:

```css
.recipe-tags {
  margin-top: 0.25rem;
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
}

.recipe-tag-pill {
  border: none;
  cursor: pointer;
  font-size: 0.68rem;
  letter-spacing: 0.05em;
}

.recipe-tag-pill:hover {
  opacity: 0.8;
}
```

- [ ] **Step 5: Add click-to-search behavior**

Add `searchTag` action to `app/javascript/controllers/recipe_state_controller.js`:

```javascript
searchTag(event) {
  const tag = event.currentTarget.dataset.tag
  const searchDialog = document.querySelector("[data-controller='search-overlay']")
  if (!searchDialog) return

  const overlay = this.application.getControllerForElementAndIdentifier(searchDialog, "search-overlay")
  if (overlay) {
    overlay.openWithTag(tag)
  }
}
```

Add `openWithTag` method to `search_overlay_controller.js`:

```javascript
openWithTag(tagName) {
  this.open()
  this.addPill(tagName, "tag")
  this.inputTarget.value = ""
  this.performSearch()
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /tags.*pills/`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb \
  app/assets/stylesheets/style.css \
  app/javascript/controllers/recipe_state_controller.js \
  app/javascript/controllers/search_overlay_controller.js \
  test/controllers/recipes_controller_test.rb
git commit -m "feat: display clickable tag pills on recipe detail page"
```

---

### Task 12: Tag Management Dialog

**Files:**
- Modify: `app/views/homepage/show.html.erb`
- Modify: `app/javascript/utilities/ordered_list_editor_utils.js`
- Modify: `app/javascript/controllers/ordered_list_editor_controller.js`

- [ ] **Step 1: Add "no ordering" mode to ordered_list_editor_utils.js**

Modify `buildControls` (around line 206) to accept an `orderable` parameter:

```javascript
export function buildControls(item, index, liveItems, callbacks, orderable = true) {
```

Wrap the up/down button creation in `if (orderable)`:

```javascript
if (orderable) {
  // existing up/down button creation code
}
// delete button always present
```

Modify `buildRowElement` (around line 56) to pass the orderable flag:

```javascript
export function buildRowElement(item, index, liveItems, callbacks, orderable = true) {
  // ...
  row.appendChild(buildControls(item, index, liveItems, callbacks, orderable))
  return row
}
```

Modify `renderRows` (around line 68) to accept and pass orderable:

```javascript
export function renderRows(container, items, callbacks, orderable = true) {
  // ...
  const rows = items.map((item, index) =>
    buildRowElement(item, index, liveItems, callbacks, orderable)
  )
  // ...
}
```

- [ ] **Step 2: Add orderable value to ordered_list_editor_controller.js**

Add to static values (around line 25):

```javascript
orderable: { type: Boolean, default: true }
```

Pass `this.orderableValue` through the render call chain. Update the `render` method:

```javascript
render() {
  renderRows(this.listTarget, this.items, this.rowCallbacks(), this.orderableValue)
}
```

- [ ] **Step 3: Add "Edit Tags" button and dialog to homepage**

Modify `app/views/homepage/show.html.erb`. After the "Edit Categories" button (around line 13), add:

```erb
<button type="button" id="edit-tags-button" class="edit-toggle">
  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
       fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
       stroke-linejoin="round">
    <path d="M12 2H2v10l9.29 9.29a1 1 0 0 0 1.42 0l6.58-6.58a1 1 0 0 0 0-1.42L12 2Z"/>
    <path d="M7 7h.01"/>
  </svg>
  Edit Tags
</button>
```

After the existing category editor dialog, add:

```erb
<%= render layout: 'shared/editor_dialog',
    locals: { title: 'Edit Tags',
              id: 'tag-order-editor',
              dialog_data: { extra_controllers: 'ordered-list-editor',
                             editor_on_success: 'close',
                             'ordered-list-editor-load-url': tags_content_path,
                             'ordered-list-editor-save-url': tags_update_path,
                             'ordered-list-editor-load-key': 'items',
                             'ordered-list-editor-open-selector': '#edit-tags-button',
                             'ordered-list-editor-orderable': false } } do %>
  <div class="editor-body ordered-list-editor-body">
    <div class="aisle-list" data-ordered-list-editor-target="list"></div>
    <div class="aisle-errors" data-ordered-list-editor-target="errors"></div>
  </div>
<% end %>
```

- [ ] **Step 4: Test manually**

1. Navigate to homepage
2. Click "Edit Tags" — dialog opens
3. Verify tags listed alphabetically with no up/down arrows
4. Click tag name → rename inline
5. Click × → mark for deletion
6. Click Save → verify renames/deletes applied
7. Verify "Edit Categories" dialog still works with ordering arrows

- [ ] **Step 5: Commit**

```bash
git add app/views/homepage/show.html.erb \
  app/javascript/utilities/ordered_list_editor_utils.js \
  app/javascript/controllers/ordered_list_editor_controller.js
git commit -m "feat: add tag management dialog with no-ordering mode"
```

---

### Task 13: Final Integration Tests and Polish

**Files:**
- Modify: `test/controllers/recipes_controller_test.rb`

- [ ] **Step 1: Write integration tests for the full flow**

Add to `test/controllers/recipes_controller_test.rb`:

```ruby
test 'full tag lifecycle: create, update, display, remove' do
  # Create with tags
  markdown = "# Tag Lifecycle\n\n## Step\n\n- Flour, 1 cup\n\nMix."
  post recipes_path(kitchen_slug: kitchen_slug),
       params: { markdown_source: markdown, category: @category.name,
                 tags: %w[vegan quick] },
       as: :json
  assert_response :success

  # Verify display
  get recipe_path('tag-lifecycle', kitchen_slug: kitchen_slug)
  assert_response :success
  assert_select '.recipe-tag-pill', count: 2

  # Update: remove one, add another
  patch recipe_path('tag-lifecycle', kitchen_slug: kitchen_slug),
        params: { markdown_source: markdown, category: @category.name,
                  tags: %w[vegan weeknight] },
        as: :json
  assert_response :success

  recipe = Recipe.find_by!(slug: 'tag-lifecycle')
  assert_equal %w[vegan weeknight], recipe.tags.map(&:name).sort
  assert_not Tag.exists?(name: 'quick')
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /lifecycle/`
Expected: PASS

- [ ] **Step 3: Run full test suite**

Run: `rake`
Expected: All tests pass, zero RuboCop offenses

- [ ] **Step 4: Update html_safe_allowlist if needed**

Run: `rake lint:html_safe`
If new `.html_safe` calls were introduced (only `search_data_json` should have one already in the allowlist), update `config/html_safe_allowlist.yml` with correct line numbers.

- [ ] **Step 5: Commit**

```bash
git add test/controllers/recipes_controller_test.rb \
  config/html_safe_allowlist.yml
git commit -m "test: add full-lifecycle integration tests for tagging"
```

---

### Task 14: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add tag-related architecture notes to CLAUDE.md**

In the Architecture section, add a brief note about tags:

```
**Tags.** Kitchen-scoped labels for cross-cutting recipe classification.
`Tag` + `RecipeTag` join table. `RecipeWriteService` handles tag sync on
recipe save; `TagWriteService` handles bulk rename/delete from the management
dialog. Tags are single-word (`[a-zA-Z-]`), stored lowercase. Orphan cleanup
via `Tag.cleanup_orphans(kitchen)`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add tagging architecture notes to CLAUDE.md"
```

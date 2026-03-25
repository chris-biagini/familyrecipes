# Normalize Quick Bites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Normalize Quick Bites from a raw text blob into proper AR models with stable integer PKs, reusing the existing `categories` table for unified menu display.

**Architecture:** Two new tables (`quick_bites`, `quick_bite_ingredients`) with FK to existing `categories`. QuickBite AR model provides duck-type interface (`ingredients_with_quantities`, `all_ingredient_names`) so consumers like ShoppingListBuilder work unchanged. The parser value object (`FamilyRecipes::QuickBite`) is retained for editor plaintext mode; storage moves entirely to AR.

**Tech Stack:** Rails 8, SQLite, Minitest, acts_as_tenant

**Spec:** `docs/superpowers/specs/2026-03-24-normalize-quick-bites-design.md`

---

### Task 1: Migration — Create Tables and Migrate Data

**Files:**
- Create: `db/migrate/015_normalize_quick_bites.rb`

This migration creates both tables, migrates existing data from
`Kitchen#quick_bites_content`, rewrites `meal_plan_selections` QB rows from
slug IDs to integer PKs, and drops the `quick_bites_content` column.

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class NormalizeQuickBites < ActiveRecord::Migration[8.0]
  def up
    create_table :quick_bites do |t|
      t.integer :kitchen_id, null: false
      t.integer :category_id, null: false
      t.string :title, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :quick_bites, %i[kitchen_id category_id]
    add_index :quick_bites, %i[kitchen_id title], unique: true

    create_table :quick_bite_ingredients do |t|
      t.integer :quick_bite_id, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
    end

    add_index :quick_bite_ingredients, :quick_bite_id

    migrate_data
    remove_column :kitchens, :quick_bites_content, :text
  end

  def down
    add_column :kitchens, :quick_bites_content, :text
    reverse_data
    drop_table :quick_bite_ingredients
    drop_table :quick_bites
  end

  private

  def migrate_data
    kitchens_with_qb = execute("SELECT id, quick_bites_content FROM kitchens WHERE quick_bites_content IS NOT NULL AND quick_bites_content != ''")

    kitchens_with_qb.each do |row|
      kitchen_id = row['id']
      content = row['quick_bites_content']
      migrate_kitchen(kitchen_id, content)
    end
  end

  # Inline parser — no application code dependencies per project conventions.
  # Format: "## Subcategory\n- Title: Ing1, Ing2\n- SelfRef\n"
  def migrate_kitchen(kitchen_id, content)
    now = Time.current.iso8601
    current_subcategory = nil
    position = 0

    content.each_line do |line|
      line = line.strip
      if line.start_with?('## ')
        current_subcategory = line.delete_prefix('## ').strip
      elsif line.start_with?('- ') && current_subcategory
        text = line.delete_prefix('- ').strip
        title, rest = text.split(':', 2).map(&:strip)
        rest = nil if rest&.empty?
        ingredients = rest ? rest.split(',').map(&:strip).reject(&:empty?) : [title]
        slug_id = slugify(title)

        category_id = find_or_create_category(kitchen_id, current_subcategory, now)
        qb_id = insert_quick_bite(kitchen_id, category_id, title, position, now)
        insert_ingredients(qb_id, ingredients)
        rewrite_selection(kitchen_id, slug_id, qb_id)
        position += 1
      end
    end
  end

  # Minimal slugify — matches FamilyRecipes.slugify behavior for ASCII titles.
  # Uses NFKD normalization, lowercase, spaces to dashes, strip non-alnum.
  def slugify(text)
    text.unicode_normalize(:nfkd)
        .encode('ASCII', replace: '')
        .downcase
        .gsub(/\s+/, '-')
        .gsub(/[^a-z0-9-]/, '')
        .gsub(/-{2,}/, '-')
        .sub(/^-|-$/, '')
  end

  def find_or_create_category(kitchen_id, name, now)
    slug = slugify(name)
    existing = execute("SELECT id FROM categories WHERE kitchen_id = #{kitchen_id} AND slug = #{quote(slug)} LIMIT 1").first
    return existing['id'] if existing

    max_pos = execute("SELECT MAX(position) AS mp FROM categories WHERE kitchen_id = #{kitchen_id}").first['mp'].to_i
    execute(<<~SQL)
      INSERT INTO categories (kitchen_id, name, slug, position, created_at, updated_at)
      VALUES (#{kitchen_id}, #{quote(name)}, #{quote(slug)}, #{max_pos + 1}, #{quote(now)}, #{quote(now)})
    SQL
    execute("SELECT last_insert_rowid() AS id").first['id']
  end

  def insert_quick_bite(kitchen_id, category_id, title, position, now)
    execute(<<~SQL)
      INSERT INTO quick_bites (kitchen_id, category_id, title, position, created_at, updated_at)
      VALUES (#{kitchen_id}, #{category_id}, #{quote(title)}, #{position}, #{quote(now)}, #{quote(now)})
    SQL
    execute("SELECT last_insert_rowid() AS id").first['id']
  end

  def insert_ingredients(qb_id, ingredients)
    ingredients.each_with_index do |name, idx|
      execute(<<~SQL)
        INSERT INTO quick_bite_ingredients (quick_bite_id, name, position)
        VALUES (#{qb_id}, #{quote(name)}, #{idx})
      SQL
    end
  end

  def rewrite_selection(kitchen_id, old_slug_id, new_int_id)
    execute(<<~SQL)
      UPDATE meal_plan_selections
      SET selectable_id = #{quote(new_int_id.to_s)}
      WHERE kitchen_id = #{kitchen_id}
        AND selectable_type = 'QuickBite'
        AND selectable_id = #{quote(old_slug_id)}
    SQL
  end

  def reverse_data
    execute("SELECT DISTINCT kitchen_id FROM quick_bites").each do |row|
      kitchen_id = row['kitchen_id']
      reverse_kitchen(kitchen_id)
    end
  end

  def reverse_kitchen(kitchen_id)
    qbs = execute(<<~SQL)
      SELECT qb.id, qb.title, qb.position, c.name AS category_name
      FROM quick_bites qb
      JOIN categories c ON c.id = qb.category_id
      WHERE qb.kitchen_id = #{kitchen_id}
      ORDER BY c.position, qb.position
    SQL

    lines = []
    current_category = nil
    qbs.each do |qb|
      if qb['category_name'] != current_category
        lines << '' if current_category
        lines << "## #{qb['category_name']}"
        current_category = qb['category_name']
      end

      ingredients = execute("SELECT name FROM quick_bite_ingredients WHERE quick_bite_id = #{qb['id']} ORDER BY position").map { |r| r['name'] }
      line = if ingredients == [qb['title']]
               "- #{qb['title']}"
             else
               "- #{qb['title']}: #{ingredients.join(', ')}"
             end
      lines << line

      # Rewrite selection back to slug
      slug = slugify(qb['title'])
      execute(<<~SQL)
        UPDATE meal_plan_selections
        SET selectable_id = #{quote(slug)}
        WHERE kitchen_id = #{kitchen_id}
          AND selectable_type = 'QuickBite'
          AND selectable_id = #{quote(qb['id'].to_s)}
      SQL
    end

    content = lines.join("\n").strip
    content = nil if content.empty?
    execute("UPDATE kitchens SET quick_bites_content = #{content ? quote(content) : 'NULL'} WHERE id = #{kitchen_id}")
  end
end
```

- [ ] **Step 2: Run migration**

```bash
rails db:migrate
```

Expected: Tables created, data migrated, `quick_bites_content` dropped.

- [ ] **Step 3: Verify migration**

```bash
rails runner "ActsAsTenant.without_tenant { puts QuickBite.count; puts QuickBiteIngredient.count; puts MealPlanSelection.quick_bites.pluck(:selectable_id) }"
```

Expected: QuickBite and QuickBiteIngredient rows exist matching seed data.
Selection IDs are now integer strings.

- [ ] **Step 4: Test rollback**

```bash
rails db:rollback STEP=1 && rails db:migrate
```

Expected: Clean round-trip — rollback restores `quick_bites_content`, re-migrate produces same result.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/015_normalize_quick_bites.rb db/schema.rb
git commit -m "Add migration: normalize quick_bites into AR tables (#286)"
```

---

### Task 2: AR Models — QuickBite and QuickBiteIngredient

**Files:**
- Create: `app/models/quick_bite.rb`
- Create: `app/models/quick_bite_ingredient.rb`
- Modify: `app/models/category.rb` — add `has_many :quick_bites`
- Modify: `app/models/kitchen.rb` — add `has_many :quick_bites`, remove parsed_quick_bites methods
- Create: `test/models/quick_bite_test.rb`
- Create: `test/models/quick_bite_ingredient_test.rb`

- [ ] **Step 1: Write QuickBite model test**

```ruby
# test/models/quick_bite_test.rb
# frozen_string_literal: true

require 'test_helper'

class QuickBiteTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    @category = Category.find_or_create_for(@kitchen, 'Snacks')
  end

  # --- validations ---

  test 'requires title' do
    qb = QuickBite.new(category: @category, position: 0)

    assert_not qb.valid?
    assert_includes qb.errors[:title], "can't be blank"
  end

  test 'requires category' do
    qb = QuickBite.new(title: 'Test', position: 0)

    assert_not qb.valid?
    assert_includes qb.errors[:category], 'must exist'
  end

  test 'enforces unique title within kitchen' do
    QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    dup = QuickBite.new(title: 'PB&J', category: @category, position: 1)

    assert_not dup.valid?
  end

  # --- duck-type interface ---

  test 'ingredients_with_quantities returns name-nil pairs' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 1)

    expected = [['Bread', [nil]], ['Peanut Butter', [nil]]]

    assert_equal expected, qb.ingredients_with_quantities
  end

  test 'all_ingredient_names returns unique names' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 1)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 2)

    assert_equal %w[Bread Peanut\ Butter], qb.all_ingredient_names
  end

  test 'all_ingredient_names preserves position order' do
    qb = QuickBite.create!(title: 'PB&J', category: @category, position: 0)
    qb.quick_bite_ingredients.create!(name: 'Peanut Butter', position: 0)
    qb.quick_bite_ingredients.create!(name: 'Bread', position: 1)

    assert_equal ['Peanut Butter', 'Bread'], qb.all_ingredient_names
  end

  # --- scoping ---

  test 'scoped to kitchen via acts_as_tenant' do
    QuickBite.create!(title: 'Tacos', category: @category, position: 0)

    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    ActsAsTenant.current_tenant = other_kitchen

    assert_empty QuickBite.all
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
ruby -Itest test/models/quick_bite_test.rb
```

Expected: `NameError: uninitialized constant QuickBite`

- [ ] **Step 3: Write QuickBite model**

```ruby
# app/models/quick_bite.rb
# frozen_string_literal: true

# A lightweight grocery bundle — a title plus a flat ingredient list, without
# the step/instruction structure of a full Recipe. Lives within a Category
# alongside recipes on the menu page. Responds to the same duck-type interface
# as Recipe (#ingredients_with_quantities, #all_ingredient_names) so
# ShoppingListBuilder and RecipeAvailabilityCalculator can treat both uniformly.
#
# - Category (parent grouping, shared with Recipe)
# - QuickBiteIngredient (child ingredient names, ordered by position)
# - Kitchen (tenant owner)
# - MealPlanSelection (references by stringified integer PK)
class QuickBite < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :category
  has_many :quick_bite_ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :quick_bite

  validates :title, presence: true, uniqueness: { scope: :kitchen_id }
  validates :position, presence: true

  scope :ordered, -> { order(:position) }

  def all_ingredient_names
    quick_bite_ingredients.map(&:name).uniq
  end

  def ingredients_with_quantities
    all_ingredient_names.map { |name| [name, [nil]] }
  end
end
```

- [ ] **Step 4: Write QuickBiteIngredient model**

```ruby
# app/models/quick_bite_ingredient.rb
# frozen_string_literal: true

# A single ingredient name within a QuickBite. Stores only a name and position
# — no quantities, units, or catalog FK. Names resolve through
# IngredientResolver at query time, same as recipe ingredients.
#
# - QuickBite (parent)
class QuickBiteIngredient < ApplicationRecord
  belongs_to :quick_bite, inverse_of: :quick_bite_ingredients

  validates :name, presence: true
  validates :position, presence: true
end
```

- [ ] **Step 5: Run QuickBite tests**

```bash
ruby -Itest test/models/quick_bite_test.rb
```

Expected: All pass.

- [ ] **Step 6: Update Category model**

In `app/models/category.rb`, add `has_many :quick_bites` and update
`cleanup_orphans` to preserve categories that have Quick Bites:

```ruby
# After: has_many :recipes, dependent: :destroy
has_many :quick_bites, dependent: :destroy

# Replace cleanup_orphans:
def self.cleanup_orphans(kitchen)
  kitchen.categories.where.missing(:recipes).where.missing(:quick_bites).destroy_all
end
```

Update the header comment to mention QuickBite as a collaborator.

Update `scope :with_recipes` to also include quick_bites — or add a parallel
scope. The menu page will need categories that have either recipes or QBs:

```ruby
scope :with_recipes, -> { where.associated(:recipes).distinct }
scope :with_content, -> { left_joins(:recipes, :quick_bites).where('recipes.id IS NOT NULL OR quick_bites.id IS NOT NULL').distinct }
```

- [ ] **Step 7: Test that cleanup_orphans preserves QB-only categories**

Add to `test/models/category_test.rb`:

```ruby
test 'cleanup_orphans preserves categories that have only quick bites' do
  cat = Category.create!(name: 'Snacks', slug: 'snacks')
  QuickBite.create!(title: 'Goldfish', category: cat, position: 0)

  Category.cleanup_orphans(@kitchen)

  assert Category.exists?(id: cat.id), 'QB-only category should not be destroyed'
end
```

- [ ] **Step 8: Update Kitchen model**

In `app/models/kitchen.rb`:

Add association:
```ruby
has_many :quick_bites, dependent: :destroy
```

Remove these methods and the callback:
- `parsed_quick_bites`
- `quick_bites_by_subsection`
- `clear_parsed_quick_bites_cache`
- `after_save :clear_parsed_quick_bites_cache, if: :saved_change_to_quick_bites_content?`

Update header comment to mention `quick_bites` instead of `quick_bites_content`.

Update `reconcile_meal_plan_tables`:
```ruby
def self.reconcile_meal_plan_tables(kitchen)
  resolver = IngredientCatalog.resolver_for(kitchen)
  visible = ShoppingListBuilder.visible_names_for(kitchen:, resolver:)
  OnHandEntry.reconcile!(kitchen:, visible_names: visible, resolver:)
  CustomGroceryItem.where(kitchen_id: kitchen.id).stale(cutoff: Date.current - CustomGroceryItem::RETENTION).delete_all
  CookHistoryEntry.prune!(kitchen:)
  valid_slugs = kitchen.recipes.pluck(:slug)
  valid_qb_ids = kitchen.quick_bites.pluck(:id).map(&:to_s) # strings for selectable_id column
  MealPlanSelection.prune_stale!(kitchen:, valid_recipe_slugs: valid_slugs, valid_qb_ids:)
  # Note: quick_bite_ids_for returns integers (for consumer use); prune_stale!
  # expects strings (matching the selectable_id column type). Both are correct.
end
```

- [ ] **Step 9: Run full test suite**

```bash
rake test
```

Expected: Some failures in tests that reference `quick_bites_content` or
`parsed_quick_bites` — these will be fixed in subsequent tasks. Model tests
should pass.

- [ ] **Step 10: Commit**

```bash
git add app/models/quick_bite.rb app/models/quick_bite_ingredient.rb app/models/category.rb app/models/kitchen.rb test/models/quick_bite_test.rb test/models/category_test.rb
git commit -m "Add QuickBite and QuickBiteIngredient AR models (#286)"
```

---

### Task 3: Update MealPlanSelection for Integer QB IDs

**Files:**
- Modify: `app/models/meal_plan_selection.rb` — `quick_bite_ids_for` returns integers
- Modify: `test/models/meal_plan_selection_test.rb`

- [ ] **Step 1: Write test for integer QB ID coercion**

Add to `test/models/meal_plan_selection_test.rb`:

```ruby
test 'quick_bite_ids_for returns integer IDs' do
  MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: '42')
  MealPlanSelection.create!(selectable_type: 'QuickBite', selectable_id: '7')

  ids = MealPlanSelection.quick_bite_ids_for(@kitchen)

  assert_equal [42, 7].to_set, ids.to_set
  assert_kind_of Integer, ids.first
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
ruby -Itest test/models/meal_plan_selection_test.rb -n test_quick_bite_ids_for_returns_integer_IDs
```

Expected: FAIL — returns `["42", "7"]` (strings).

- [ ] **Step 3: Update `quick_bite_ids_for` to coerce to integers**

In `app/models/meal_plan_selection.rb`:

```ruby
def self.quick_bite_ids_for(kitchen)
  ActsAsTenant.with_tenant(kitchen) { quick_bites.pluck(:selectable_id).map(&:to_i) }
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
ruby -Itest test/models/meal_plan_selection_test.rb
```

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/meal_plan_selection.rb test/models/meal_plan_selection_test.rb
git commit -m "Coerce QB selection IDs to integers (#286)"
```

---

### Task 4: Update QuickBitesSerializer for AR Models

**Files:**
- Modify: `lib/familyrecipes/quick_bites_serializer.rb` — add `from_records` method
- Create: `test/lib/quick_bites_serializer_test.rb` (or add to existing)

The serializer needs a new `from_records` method that builds the same IR hash
from AR models (grouped by category) instead of parsed value objects.

- [ ] **Step 1: Write test for AR-backed IR generation**

```ruby
# test/lib/quick_bites_serializer_test.rb (add to existing or create)
test 'from_records produces same IR structure as to_ir' do
  category = Category.find_or_create_for(@kitchen, 'Snacks')
  qb1 = QuickBite.create!(title: 'Hummus with Pretzels', category:, position: 0)
  qb1.quick_bite_ingredients.create!([
    { name: 'Hummus', position: 0 },
    { name: 'Pretzels', position: 1 }
  ])
  qb2 = QuickBite.create!(title: 'Goldfish', category:, position: 1)
  qb2.quick_bite_ingredients.create!(name: 'Goldfish', position: 0)

  ir = FamilyRecipes::QuickBitesSerializer.from_records(@kitchen)

  assert_equal 1, ir[:categories].size
  cat = ir[:categories].first
  assert_equal 'Snacks', cat[:name]
  assert_equal 2, cat[:items].size
  assert_equal({ name: 'Hummus with Pretzels', ingredients: %w[Hummus Pretzels] }, cat[:items].first)
  assert_equal({ name: 'Goldfish', ingredients: %w[Goldfish] }, cat[:items].last)
end

test 'from_records round-trips through serialize' do
  category = Category.find_or_create_for(@kitchen, 'Snacks')
  qb = QuickBite.create!(title: 'PB&J', category:, position: 0)
  qb.quick_bite_ingredients.create!([
    { name: 'Bread', position: 0 },
    { name: 'Peanut Butter', position: 1 },
    { name: 'Jelly', position: 2 }
  ])

  ir = FamilyRecipes::QuickBitesSerializer.from_records(@kitchen)
  plaintext = FamilyRecipes::QuickBitesSerializer.serialize(ir)

  assert_includes plaintext, '## Snacks'
  assert_includes plaintext, '- PB&J: Bread, Peanut Butter, Jelly'
end
```

- [ ] **Step 2: Run to verify failure**

```bash
ruby -Itest test/lib/quick_bites_serializer_test.rb
```

Expected: `NoMethodError: undefined method 'from_records'`

- [ ] **Step 3: Implement `from_records`**

In `lib/familyrecipes/quick_bites_serializer.rb`, append at the end of the
module body (after the existing methods, so `module_function` applies):

```ruby
def from_records(kitchen)
  grouped = kitchen.quick_bites.includes(:category, :quick_bite_ingredients)
                   .order('categories.position, quick_bites.position')
                   .group_by(&:category)

  categories = grouped.map do |category, qbs|
    {
      name: category.name,
      items: qbs.map { |qb| { name: qb.title, ingredients: qb.quick_bite_ingredients.sort_by(&:position).map(&:name) } }
    }
  end

  { categories: }
end
```

Update header comment to mention the new AR-backed path.

- [ ] **Step 4: Run tests**

```bash
ruby -Itest test/lib/quick_bites_serializer_test.rb
```

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes/quick_bites_serializer.rb test/lib/quick_bites_serializer_test.rb
git commit -m "Add AR-backed from_records to QuickBitesSerializer (#286)"
```

---

### Task 5: Update QuickBitesWriteService

**Files:**
- Modify: `app/services/quick_bites_write_service.rb`
- Modify: `test/services/quick_bites_write_service_test.rb`

Both entry points (`update` and `update_from_structure`) now persist to AR
models instead of the text blob. The plaintext path parses first, converts to
IR, then uses the same AR save logic as the structure path.

- [ ] **Step 1: Write tests for AR-backed write service**

```ruby
# Add to test/services/quick_bites_write_service_test.rb

test 'update_from_structure creates QuickBite records' do
  setup_test_category(name: 'Snacks')
  structure = {
    categories: [
      { name: 'Snacks', items: [
        { name: 'PB&J', ingredients: %w[Bread Peanut\ Butter Jelly] },
        { name: 'Goldfish', ingredients: %w[Goldfish] }
      ] }
    ]
  }

  QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

  assert_equal 2, @kitchen.quick_bites.count
  pbj = @kitchen.quick_bites.find_by(title: 'PB&J')
  assert_equal %w[Bread Peanut\ Butter Jelly], pbj.quick_bite_ingredients.order(:position).pluck(:name)
  assert_equal 'Snacks', pbj.category.name
end

test 'update_from_structure replaces all existing QBs' do
  cat = Category.find_or_create_for(@kitchen, 'Snacks')
  QuickBite.create!(title: 'Old Item', category: cat, position: 0)

  structure = {
    categories: [
      { name: 'Snacks', items: [
        { name: 'New Item', ingredients: %w[Chips] }
      ] }
    ]
  }

  QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

  assert_equal ['New Item'], @kitchen.quick_bites.pluck(:title)
end

test 'update with plaintext creates AR records' do
  content = "## Snacks\n- Hummus with Pretzels: Hummus, Pretzels\n- Goldfish\n"

  result = QuickBitesWriteService.update(kitchen: @kitchen, content:)

  assert_equal 2, @kitchen.quick_bites.count
  assert_empty result.warnings
end

test 'update with nil content clears all QBs' do
  cat = Category.find_or_create_for(@kitchen, 'Snacks')
  QuickBite.create!(title: 'Test', category: cat, position: 0)

  QuickBitesWriteService.update(kitchen: @kitchen, content: nil)

  assert_equal 0, @kitchen.quick_bites.count
end

test 'update_from_structure creates category if it does not exist' do
  structure = {
    categories: [
      { name: 'New Category', items: [
        { name: 'Test', ingredients: %w[Stuff] }
      ] }
    ]
  }

  QuickBitesWriteService.update_from_structure(kitchen: @kitchen, structure:)

  assert @kitchen.categories.exists?(name: 'New Category')
end
```

- [ ] **Step 2: Run to verify failures**

```bash
ruby -Itest test/services/quick_bites_write_service_test.rb
```

Expected: Failures — current implementation writes to `quick_bites_content`.

- [ ] **Step 3: Rewrite QuickBitesWriteService**

```ruby
# app/services/quick_bites_write_service.rb
# frozen_string_literal: true

# Orchestrates quick bites updates. Dual entry: `update` accepts raw plaintext
# (parses to IR then saves via AR); `update_from_structure` accepts an IR hash
# and persists directly to QuickBite/QuickBiteIngredient records. Replaces all
# existing QBs on each save (full replacement, not incremental diff).
#
# - FamilyRecipes.parse_quick_bites_content: plaintext → value objects (editor path)
# - FamilyRecipes::QuickBitesSerializer: value objects → IR (editor path)
# - Category.find_or_create_for: category resolution
# - Kitchen.finalize_writes: centralized post-write pipeline
class QuickBitesWriteService
  Result = Data.define(:warnings)

  def self.update(kitchen:, content:)
    new(kitchen:).update(content:)
  end

  def self.update_from_structure(kitchen:, structure:)
    new(kitchen:).update_from_structure(structure:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(content:)
    stored = content.to_s.presence
    return clear_all if stored.nil?

    result = FamilyRecipes.parse_quick_bites_content(stored)
    ir = FamilyRecipes::QuickBitesSerializer.to_ir(result.quick_bites)
    persist_structure(ir)
    finalize
    Result.new(warnings: result.warnings)
  end

  def update_from_structure(structure:)
    persist_structure(structure)
    finalize
    Result.new(warnings: [])
  end

  private

  attr_reader :kitchen

  def clear_all
    kitchen.quick_bites.destroy_all
    finalize
    Result.new(warnings: [])
  end

  def persist_structure(ir)
    kitchen.quick_bites.destroy_all
    position = 0

    ir[:categories].each do |cat_data|
      category = Category.find_or_create_for(kitchen, cat_data[:name])

      cat_data[:items].each do |item|
        qb = kitchen.quick_bites.create!(
          title: item[:name],
          category:,
          position:
        )
        item[:ingredients].each_with_index do |name, idx|
          qb.quick_bite_ingredients.create!(name:, position: idx)
        end
        position += 1
      end
    end
  end

  def finalize
    Kitchen.finalize_writes(kitchen)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
ruby -Itest test/services/quick_bites_write_service_test.rb
```

Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/quick_bites_write_service.rb test/services/quick_bites_write_service_test.rb
git commit -m "Rewrite QuickBitesWriteService for AR persistence (#286)"
```

---

### Task 6: Update Consumer Services

**Files:**
- Modify: `app/services/shopping_list_builder.rb`
- Modify: `app/services/recipe_availability_calculator.rb`
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `app/helpers/search_data_helper.rb`

- [ ] **Step 1: Update ShoppingListBuilder**

Replace `selected_quick_bites` method in `app/services/shopping_list_builder.rb`:

```ruby
# Was:
#   def selected_quick_bites
#     ids = MealPlanSelection.quick_bite_ids_for(@kitchen)
#     return [] if ids.empty?
#     @kitchen.parsed_quick_bites.select { |qb| ids.include?(qb.id) }
#   end

def selected_quick_bites
  ids = MealPlanSelection.quick_bite_ids_for(@kitchen)
  return [] if ids.empty?

  @kitchen.quick_bites.where(id: ids).includes(:quick_bite_ingredients)
end
```

Update header comment to remove FamilyRecipes::QuickBite reference.

- [ ] **Step 2: Update RecipeAvailabilityCalculator**

Replace `quick_bites` method in `app/services/recipe_availability_calculator.rb`:

```ruby
# Was:
#   def quick_bites
#     @kitchen.parsed_quick_bites
#   end

def quick_bites
  @kitchen.quick_bites.includes(:quick_bite_ingredients)
end
```

Update header comment.

- [ ] **Step 3: Update IngredientRowBuilder**

Replace `merge_quick_bite_sources` in `app/services/ingredient_row_builder.rb`:

```ruby
def merge_quick_bite_sources(index, seen)
  kitchen.quick_bites.includes(:quick_bite_ingredients).each do |qb|
    source = QuickBiteSource.new(title: qb.title)
    qb.all_ingredient_names.each do |raw_name|
      name = canonical_ingredient_name(raw_name)
      qb_key = "qb:#{qb.id}"
      index[name] << source if seen[name].add?(qb_key)
    end
  end

  index
end
```

Update header comment to mention QuickBite (AR model) instead of FamilyRecipes::QuickBite.

- [ ] **Step 4: Update SearchDataHelper**

In `app/helpers/search_data_helper.rb`, update `ingredient_corpus` to include
QB ingredient names:

```ruby
def ingredient_corpus(recipes)
  names = recipes.flat_map { |r| r.ingredients.map(&:name) }
  names.concat(OnHandEntry.where(kitchen_id: current_kitchen.id).pluck(:ingredient_name))
  names.concat(QuickBiteIngredient.joins(:quick_bite).where(quick_bites: { kitchen_id: current_kitchen.id }).pluck(:name))
  names.uniq.sort
end
```

- [ ] **Step 5: Run test suite**

```bash
rake test
```

Expected: Most tests pass. Remaining failures likely in menu controller and
integration tests that set up `quick_bites_content` directly.

- [ ] **Step 6: Commit**

```bash
git add app/services/shopping_list_builder.rb app/services/recipe_availability_calculator.rb app/services/ingredient_row_builder.rb app/helpers/search_data_helper.rb
git commit -m "Update consumer services for AR-backed QuickBites (#286)"
```

---

### Task 7: Update MenuController and Editor Endpoints

**Files:**
- Modify: `app/controllers/menu_controller.rb`
- Modify: `test/controllers/menu_controller_test.rb`

- [ ] **Step 1: Update MenuController#show**

Replace `@quick_bites_by_subsection` with per-category QB loading:

```ruby
def show
  @categories = recipe_selector_categories
  @selected_recipes = selected_ids_for('Recipe')
  @selected_quick_bites = selected_ids_for('QuickBite').map(&:to_i).to_set
  @availability = compute_availability
  @cook_weights = CookHistoryWeighter.call(CookHistoryEntry.where(kitchen_id: current_kitchen.id).recent)
end
```

Note: `@selected_quick_bites` is now a Set of integers. The
`selected_ids_for` helper plucks strings, so coerce to integers.

- [ ] **Step 2: Update editor endpoints**

Replace `quick_bites_content` and `quickbites_editor_frame`:

```ruby
def quick_bites_content
  ir = FamilyRecipes::QuickBitesSerializer.from_records(current_kitchen)
  content = FamilyRecipes::QuickBitesSerializer.serialize(ir)
  render json: { content:, structure: ir }
end

def quickbites_editor_frame
  ir = FamilyRecipes::QuickBitesSerializer.from_records(current_kitchen)
  content = FamilyRecipes::QuickBitesSerializer.serialize(ir)

  render partial: 'menu/quickbites_editor_frame', locals: {
    content:, structure: ir
  }, layout: false
end
```

The `parse_quick_bites` and `serialize_quick_bites` endpoints remain unchanged
— they're used for mode-switching within the editor session and work on
plaintext/IR without touching storage.

- [ ] **Step 3: Update `recipe_selector_categories` to eager-load QBs**

```ruby
def recipe_selector_categories
  current_kitchen.categories.ordered.includes(
    quick_bites: :quick_bite_ingredients,
    recipes: { steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }] }
  )
end
```

- [ ] **Step 4: Update tests**

In `test/controllers/menu_controller_test.rb`, replace any
`@kitchen.update!(quick_bites_content: ...)` setup with AR model creation:

```ruby
# Helper for tests:
def create_quick_bite(title, category_name:, ingredients:)
  cat = Category.find_or_create_for(@kitchen, category_name)
  qb = QuickBite.create!(title:, category: cat, position: QuickBite.where(kitchen_id: @kitchen.id).count)
  ingredients.each_with_index do |name, idx|
    qb.quick_bite_ingredients.create!(name:, position: idx)
  end
  qb
end
```

- [ ] **Step 5: Run tests**

```bash
ruby -Itest test/controllers/menu_controller_test.rb
```

Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/menu_controller.rb test/controllers/menu_controller_test.rb
git commit -m "Update MenuController for AR-backed QuickBites (#286)"
```

---

**Note on MealPlanWriteService:** No code changes needed. `apply_select`
receives `slug` from controller params as a string (`"42"`) and passes it to
`MealPlanSelection.toggle` which stores it in the string `selectable_id`
column. The integer coercion in `quick_bite_ids_for` happens only on the read
path. The JS sends `cb.dataset.slug` which Task 8 changes to render the
integer PK via `data-slug="<%= item.id %>"`.

---

### Task 8: Update Menu Views for Unified Category Display

**Files:**
- Modify: `app/views/menu/_recipe_selector.html.erb`
- Modify: `app/views/menu/show.html.erb`

The menu page now renders Quick Bites within each category (after recipes)
instead of in a separate "QuickBites" section. The availability lookup keys
change from string slugs to integer PKs.

- [ ] **Step 1: Update `_recipe_selector.html.erb`**

Replace the entire template. Key changes:
- Remove the separate `quick_bites_by_subsection` block at the bottom
- Add a QB subsection within each category's `<div class="category">`
- Use `category.quick_bites.ordered` to get QBs per category
- Availability keyed by `qb.id` (integer)
- Selected check uses `selected_quick_bites.include?(qb.id)` (integer Set)
- `data-slug` attribute uses `qb.id` (integer) for selection toggle

The locals signature changes:
```erb
<%# locals: (categories:, selected_recipes: Set.new, selected_quick_bites: Set.new, availability: {}) %>
```

Remove `quick_bites_by_subsection` from locals since QBs now come through
categories.

Within each category div, after the recipes `</ul>`, add:

```erb
<%- qbs = category.quick_bites.sort_by(&:position) -%>
<%- if qbs.any? -%>
<ul class="quick-bites-list" data-type="quick_bite">
  <%- qbs.each do |item| -%>
    <li class="recipe-selector-item quick-bite-item">
      <input class="custom-checkbox" type="checkbox"
             id="qb-<%= item.id %>-checkbox"
             data-slug="<%= item.id %>"
             data-title="<%= h item.title %>"
             <%= 'checked' if selected_quick_bites.include?(item.id) %>>
      <label for="qb-<%= item.id %>-checkbox"><%= item.title %></label>
      <%# Availability badge — same markup as recipes %>
      <% info = availability[item.id] %>
      <% if info %>
        <% have_count = info[:ingredients].size - info[:missing] %>
        <% total = info[:ingredients].size %>
        <% fraction = total.positive? ? have_count.to_f / total : 0 %>
        <% opacity_step = (fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round %>
        <% if total == 1 %>
          <span class="availability-single<%= have_count == 1 ? ' on-hand' : ' not-on-hand' %> opacity-<%= opacity_step %>"><svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><% if have_count == 1 %><circle cx="5" cy="5" r="4.5" fill="currentColor"/><% else %><circle cx="5" cy="5" r="3.5" fill="none" stroke="currentColor" stroke-width="1.5"/><% end %></svg></span>
        <% else %>
          <details class="collapse-header<%= ' all-on-hand' if info[:missing].zero? %> opacity-<%= opacity_step %>">
            <summary aria-label="Have <%= have_count %> of <%= total %><%= info[:missing_names].any? ? '; missing: ' + info[:missing_names].join(', ') : '' %>"><%= have_count %>/<%= total %></summary>
          </details>
        <% end %>
      <% end %>
      <% if info && info[:ingredients].size > 1 %>
        <div class="collapse-body">
          <div class="collapse-inner">
            <% have = info[:ingredients] - info[:missing_names] %>
            <% if have.any? %><div class="availability-have"><strong>Have</strong><span><%= have.join(', ') %></span></div><% end %>
            <% if info[:missing_names].any? %><div class="availability-need"><strong>Missing</strong><span><%= info[:missing_names].join(', ') %></span></div><% end %>
          </div>
        </div>
      <% end %>
    </li>
  <%- end -%>
</ul>
<%- end -%>
```

Also update the category loop to show categories that have *either* recipes or
QBs:

```erb
<%- categories.each do |category| -%>
<%- next if category.recipes.empty? && category.quick_bites.empty? -%>
```

- [ ] **Step 2: Update `show.html.erb`**

Update the render call to remove `quick_bites_by_subsection`:

```erb
<%= render 'menu/recipe_selector', categories: @categories, selected_recipes: @selected_recipes, selected_quick_bites: @selected_quick_bites, availability: @availability %>
```

- [ ] **Step 3: Add CSS for QB items within categories**

In `app/assets/stylesheets/menu.css`, add a subtle visual distinction for
Quick Bite items within categories (e.g., slightly smaller text or a different
left-border treatment) so they're visually diminutive but still part of the
category flow.

```css
.quick-bites-list {
  list-style: none;
  padding: 0;
  margin: 0.25rem 0 0;
  border-top: 1px solid var(--rule-faint);
  padding-top: 0.25rem;
}

.quick-bite-item {
  font-size: 0.9em;
}
```

- [ ] **Step 4: Run integration tests**

```bash
ruby -Itest test/integration/menu_integration_test.rb
```

Expected: Failures in tests referencing old QB section structure. Fix test
assertions to match new per-category layout.

- [ ] **Step 5: Commit**

```bash
git add app/views/menu/_recipe_selector.html.erb app/views/menu/show.html.erb app/assets/stylesheets/menu.css
git commit -m "Render Quick Bites within categories on menu page (#286)"
```

---

### Task 9: Update Export/Import Services

**Files:**
- Modify: `app/services/export_service.rb`
- Modify: `app/services/import_service.rb`
- Modify: `test/services/export_service_test.rb`
- Modify: `test/services/import_service_test.rb`

- [ ] **Step 1: Update ExportService**

Replace `add_quick_bites` in `app/services/export_service.rb`:

```ruby
def add_quick_bites(zos)
  return if @kitchen.quick_bites.none?

  ir = FamilyRecipes::QuickBitesSerializer.from_records(@kitchen)
  content = FamilyRecipes::QuickBitesSerializer.serialize(ir)
  zos.put_next_entry('quick-bites.txt')
  zos.write(content)
end
```

Update header comment to remove `Kitchen: quick_bites_content` reference.

- [ ] **Step 2: Verify ImportService still works**

`ImportService#import_quick_bites` already calls
`QuickBitesWriteService.update(kitchen:, content:)`, which now parses
plaintext and saves to AR. This should work without changes. Verify with
existing import tests.

- [ ] **Step 3: Run export/import tests**

```bash
ruby -Itest test/services/export_service_test.rb
ruby -Itest test/services/import_service_test.rb
```

Expected: Export tests may fail if they assert on `quick_bites_content`.
Import tests should pass since the write service interface is unchanged.

- [ ] **Step 4: Fix any failing tests**

Update test setup to create AR records instead of setting `quick_bites_content`.

- [ ] **Step 5: Commit**

```bash
git add app/services/export_service.rb app/services/import_service.rb test/services/export_service_test.rb test/services/import_service_test.rb
git commit -m "Update export/import for AR-backed QuickBites (#286)"
```

---

### Task 10: Update Seeds

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Update QB seed loading**

Replace the direct column assignment with write service call:

```ruby
# Was:
#   kitchen.update!(quick_bites_content: File.read(quick_bites_path))

# Now:
QuickBitesWriteService.update(kitchen: kitchen, content: File.read(quick_bites_path))
puts 'Quick Bites content loaded.'
```

- [ ] **Step 2: Verify seeds**

```bash
rails db:drop db:create db:migrate db:seed
```

Expected: Seeds load without errors. Quick Bites appear as AR records.

- [ ] **Step 3: Commit**

```bash
git add db/seeds.rb
git commit -m "Update seeds to use QuickBitesWriteService (#286)"
```

---

### Task 11: Fix Remaining Test Failures and Cleanup

**Files:**
- Modify: Various test files that reference `quick_bites_content` or `parsed_quick_bites`
- Modify: `test/test_helper.rb` — add `create_quick_bite` helper
- Remove: Dead code references

- [ ] **Step 1: Add test helper for creating Quick Bites**

In `test/test_helper.rb`, add to `ActiveSupport::TestCase`:

```ruby
def create_quick_bite(title, category_name: 'Snacks', ingredients: [title])
  cat = Category.find_or_create_for(@kitchen, category_name)
  qb = QuickBite.create!(title:, category: cat, position: QuickBite.where(kitchen_id: @kitchen.id).count)
  ingredients.each_with_index do |name, idx|
    qb.quick_bite_ingredients.create!(name:, position: idx)
  end
  qb
end
```

- [ ] **Step 2: Run full test suite, fix all failures**

```bash
rake test
```

For each failing test, replace `quick_bites_content` setup with
`create_quick_bite` calls. Replace `parsed_quick_bites` assertions with AR
queries.

- [ ] **Step 3: Run lint**

```bash
bundle exec rubocop
```

Fix any offenses.

- [ ] **Step 4: Update `html_safe_allowlist.yml` if line numbers shifted**

```bash
rake lint:html_safe
```

- [ ] **Step 5: Commit**

Stage all modified test files and any remaining source changes by name:

```bash
git add test/ app/ lib/ config/
git commit -m "Fix remaining test failures and cleanup (#286)"
```

---

### Task 12: Update CLAUDE.md and Architectural Comments

**Files:**
- Modify: `CLAUDE.md` — update Architecture section
- Verify: All new/modified files have proper header comments

- [ ] **Step 1: Update CLAUDE.md**

In the Architecture section:
- Remove references to `Kitchen#quick_bites_content` and `parse_quick_bites_content`
- Add `QuickBite` and `QuickBiteIngredient` to the AR models list
- Update the "Two namespaces" section if `FamilyRecipes::QuickBite` parser
  is still referenced
- Update the routing/MealPlan section to note QB selections use integer PKs
- Note that `Category` now has both `has_many :recipes` and `has_many :quick_bites`

- [ ] **Step 2: Verify all header comments are current**

Check that modified files have updated header comments:
- `quick_bites_write_service.rb` ✓ (rewritten in Task 5)
- `shopping_list_builder.rb` — remove FamilyRecipes::QuickBite reference
- `recipe_availability_calculator.rb` — update collaborators
- `ingredient_row_builder.rb` — update collaborators
- `category.rb` — add QuickBite collaborator
- `kitchen.rb` — update to mention `quick_bites` association

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md and comments for QB normalization (#286)"
```

---

### Task 13: Final Verification

- [ ] **Step 1: Run full test suite**

```bash
rake test
```

Expected: All tests pass, 0 failures.

- [ ] **Step 2: Run lint**

```bash
bundle exec rubocop
```

Expected: 0 offenses.

- [ ] **Step 3: Run `html_safe` audit**

```bash
rake lint:html_safe
```

Expected: Clean.

- [ ] **Step 4: Test fresh database setup**

```bash
rails db:drop db:create db:migrate db:seed
```

Expected: Clean setup with QB data in AR tables.

- [ ] **Step 5: Manual smoke test**

```bash
bin/dev
```

Verify:
- Menu page loads with QBs displayed within categories
- QB selection/deselection works (checkbox toggle)
- QB editor opens, saves in both plaintext and graphical modes
- Groceries page shows selected QB ingredients
- Ingredients page lists QB ingredient sources
- Export/import round-trip preserves QB data

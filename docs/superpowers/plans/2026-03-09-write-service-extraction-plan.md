# Write Service Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract aisle and category mutation logic from controllers into dedicated write services, consolidating aisle ownership and matching the project's existing service conventions.

**Architecture:** Two new services — `AisleWriteService` and `CategoryWriteService` — each with a `Result = Data.define(:success, :errors)` return type. Controllers become thin param-parsers that delegate to the service and handle the response. `CatalogWriteService` delegates aisle sync to `AisleWriteService` instead of owning it inline.

**Tech Stack:** Rails 8, Minitest, SQLite

---

### Task 1: Create AisleWriteService with update_order

**Files:**
- Create: `app/services/aisle_write_service.rb`
- Create: `test/services/aisle_write_service_test.rb`
- Modify: `app/controllers/groceries_controller.rb:40-58` (update_aisle_order action)
- Modify: `app/controllers/groceries_controller.rb:67-87` (remove cascade methods + build_aisle_order_text)

**Step 1: Write the failing tests**

Create `test/services/aisle_write_service_test.rb`. These tests cover the same behavior currently tested through controller integration tests in `test/controllers/groceries_controller_test.rb`, but at the service layer:

```ruby
# frozen_string_literal: true

require 'test_helper'

class AisleWriteServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen: @kitchen).delete_all
  end

  # --- update_order: validation ---

  test 'update_order returns errors for too many aisles' do
    order = (1..51).map { |i| "Aisle #{i}" }.join("\n")

    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: order, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('Too many') })
  end

  test 'update_order returns errors for aisle name too long' do
    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: 'a' * 51, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('too long') })
  end

  test 'update_order returns errors for case-insensitive duplicates' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Produce\nproduce", renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('more than once') })
  end

  # --- update_order: saves and normalizes ---

  test 'update_order saves normalized aisle_order' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Produce\n  Baking\nProduce\n\nFrozen", renames: {}, deletes: []
    )

    assert result.success
    assert_equal "Produce\nBaking\nFrozen", @kitchen.reload.aisle_order
  end

  test 'update_order clears aisle_order when empty' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    result = AisleWriteService.update_order(kitchen: @kitchen, aisle_order: '', renames: {}, deletes: [])

    assert result.success
    assert_nil @kitchen.reload.aisle_order
  end

  # --- update_order: cascade renames ---

  test 'update_order cascades renames to catalog entries' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: "Fruits\nDairy",
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_order cascades renames case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: cascade deletes ---

  test 'update_order clears aisle from catalog entries on delete' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Milk', aisle: 'Dairy')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Dairy',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_equal 'Dairy', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Milk').aisle
  end

  test 'update_order cascades deletes case-insensitively' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: '',
      renames: {}, deletes: ['Produce']
    )

    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: renames + deletes together ---

  test 'update_order handles renames and deletes in one call' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Bread', aisle: 'Bakery')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: ['Bakery']
    )

    assert_equal 'Fruits', IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Apples').aisle
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'Bread').aisle
  end

  # --- update_order: tenant isolation ---

  test 'update_order does not affect other kitchens' do
    other_kitchen = nil
    with_multi_kitchen do
      other_kitchen = Kitchen.create!(name: 'Other', slug: 'other')
    end
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Apples', aisle: 'Produce')
    IngredientCatalog.create!(kitchen: other_kitchen, ingredient_name: 'Apples', aisle: 'Produce')

    AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Fruits',
      renames: { 'Produce' => 'Fruits' }, deletes: []
    )

    assert_equal 'Produce', IngredientCatalog.find_by(kitchen: other_kitchen, ingredient_name: 'Apples').aisle
  end

  # --- update_order: ignores nil/non-hash renames and non-array deletes ---

  test 'update_order tolerates nil renames and deletes' do
    result = AisleWriteService.update_order(
      kitchen: @kitchen, aisle_order: 'Produce', renames: nil, deletes: nil
    )

    assert result.success
    assert_equal 'Produce', @kitchen.reload.aisle_order
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: `NameError: uninitialized constant AisleWriteService`

**Step 3: Write AisleWriteService**

Create `app/services/aisle_write_service.rb`:

```ruby
# frozen_string_literal: true

# Placeholder header comment — will be written in Task 4.
class AisleWriteService
  Result = Data.define(:success, :errors)

  def self.update_order(kitchen:, aisle_order:, renames:, deletes:)
    new(kitchen:).update_order(aisle_order:, renames:, deletes:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update_order(aisle_order:, renames:, deletes:)
    kitchen.aisle_order = aisle_order.to_s
    kitchen.normalize_aisle_order!

    errors = validate_order
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      cascade_renames(renames)
      cascade_deletes(deletes)
      kitchen.save!
    end

    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_order
    items = kitchen.parsed_aisle_order
    errors = []
    errors << "Too many items (maximum #{Kitchen::MAX_AISLES})." if items.size > Kitchen::MAX_AISLES

    long = items.select { |name| name.size > Kitchen::MAX_AISLE_NAME_LENGTH }
    long.each { |name| errors << "\"#{name}\" is too long (maximum #{Kitchen::MAX_AISLE_NAME_LENGTH} characters)." }

    dupes = items.group_by(&:downcase).select { |_, v| v.size > 1 }.values.map(&:first)
    dupes.each { |name| errors << "\"#{name}\" appears more than once (case-insensitive)." }
    errors
  end

  def cascade_renames(renames)
    return unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', old_name)
             .update_all(aisle: new_name) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def cascade_deletes(deletes)
    return unless deletes.is_a?(Array)

    deletes.each do |name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', name)
             .update_all(aisle: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
```

**Step 4: Run service tests to verify they pass**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: All pass

**Step 5: Wire up GroceriesController**

Replace the `update_aisle_order` action and remove the cascade private methods. The controller becomes:

```ruby
def update_aisle_order
  result = AisleWriteService.update_order(
    kitchen: current_kitchen,
    aisle_order: params[:aisle_order].to_s,
    renames: params[:renames],
    deletes: params[:deletes]
  )
  return render(json: { errors: result.errors }, status: :unprocessable_content) if result.errors.any?

  current_kitchen.broadcast_update
  render json: { status: 'ok' }
end
```

Remove these private methods from `GroceriesController`:
- `cascade_aisle_renames` (lines 67-73)
- `cascade_aisle_deletes` (lines 76-83)
- `build_aisle_order_text` (lines 85-87)

Update `aisle_order_content` to inline the `all_aisles` call:

```ruby
def aisle_order_content
  render json: { aisle_order: current_kitchen.all_aisles.join("\n") }
end
```

Remove `include OrderedListEditor` from `GroceriesController` — it's no longer needed here.

**Step 6: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All pass (same behavior, different code path)

**Step 7: Commit**

```bash
git add app/services/aisle_write_service.rb test/services/aisle_write_service_test.rb \
  app/controllers/groceries_controller.rb
git commit -m "feat: extract AisleWriteService from GroceriesController"
```

---

### Task 2: Move aisle sync from CatalogWriteService to AisleWriteService

**Files:**
- Modify: `app/services/aisle_write_service.rb`
- Modify: `app/services/catalog_write_service.rb:70-76` (sync_aisle_to_kitchen) and `105-119` (sync_all_aisles)
- Modify: `test/services/aisle_write_service_test.rb`

**Step 1: Write failing tests for sync methods**

Add to `test/services/aisle_write_service_test.rb`:

```ruby
# --- sync_new_aisle ---

test 'sync_new_aisle appends aisle to kitchen aisle_order' do
  @kitchen.update!(aisle_order: 'Produce')

  AisleWriteService.sync_new_aisle(kitchen: @kitchen, aisle: 'Baking')

  assert_includes @kitchen.reload.parsed_aisle_order, 'Baking'
end

test 'sync_new_aisle skips omit aisle' do
  @kitchen.update!(aisle_order: 'Produce')

  AisleWriteService.sync_new_aisle(kitchen: @kitchen, aisle: 'omit')

  assert_not_includes @kitchen.reload.parsed_aisle_order, 'omit'
end

test 'sync_new_aisle does not duplicate existing aisle' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  AisleWriteService.sync_new_aisle(kitchen: @kitchen, aisle: 'Baking')

  assert_equal 1, @kitchen.reload.parsed_aisle_order.count('Baking')
end

test 'sync_new_aisle skips case-duplicate aisle' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  AisleWriteService.sync_new_aisle(kitchen: @kitchen, aisle: 'baking')

  assert_equal %w[Produce Baking], @kitchen.reload.parsed_aisle_order
end

# --- sync_new_aisles (bulk) ---

test 'sync_new_aisles appends multiple new aisles in one pass' do
  @kitchen.update!(aisle_order: 'Produce')

  AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: %w[Baking Dairy])

  order = @kitchen.reload.parsed_aisle_order

  assert_includes order, 'Baking'
  assert_includes order, 'Dairy'
  assert_includes order, 'Produce'
end

test 'sync_new_aisles skips omit and duplicates' do
  @kitchen.update!(aisle_order: "Produce\nBaking")

  AisleWriteService.sync_new_aisles(kitchen: @kitchen, aisles: %w[Baking omit Dairy])

  order = @kitchen.reload.parsed_aisle_order

  assert_equal 1, order.count('Baking')
  assert_not_includes order, 'omit'
  assert_includes order, 'Dairy'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: `NoMethodError: undefined method 'sync_new_aisle'`

**Step 3: Add sync methods to AisleWriteService**

Add class methods and implementation:

```ruby
def self.sync_new_aisle(kitchen:, aisle:)
  new(kitchen:).sync_new_aisle(aisle:)
end

def self.sync_new_aisles(kitchen:, aisles:)
  new(kitchen:).sync_new_aisles(aisles:)
end

def sync_new_aisle(aisle:)
  return if aisle == 'omit'
  return if kitchen.parsed_aisle_order.any? { |a| a.casecmp?(aisle) }

  existing = kitchen.aisle_order.to_s
  kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
end

def sync_new_aisles(aisles:)
  new_aisles = aisles.reject { |a| a == 'omit' }.uniq
  return if new_aisles.empty?

  existing = kitchen.parsed_aisle_order.to_set(&:downcase)
  additions = new_aisles.reject { |a| existing.include?(a.downcase) }
  return if additions.empty?

  combined = [kitchen.aisle_order.to_s, *additions].reject(&:empty?).join("\n")
  kitchen.reload.update!(aisle_order: combined)
end
```

**Step 4: Run service tests to verify they pass**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: All pass

**Step 5: Update CatalogWriteService to delegate**

In `app/services/catalog_write_service.rb`:

Replace `sync_aisle_to_kitchen(entry.aisle)` (line 42) with:
```ruby
AisleWriteService.sync_new_aisle(kitchen:, aisle: entry.aisle)
```

Replace `sync_all_aisles(entries_hash)` (line 61) with:
```ruby
sync_bulk_aisles(entries_hash)
```

Replace the `sync_all_aisles` private method (lines 105-119) with:
```ruby
def sync_bulk_aisles(entries_hash)
  aisles = entries_hash.values.filter_map { |e| e['aisle'] }
  AisleWriteService.sync_new_aisles(kitchen:, aisles:)
end
```

Remove the `sync_aisle_to_kitchen` private method entirely (lines 70-76).

**Step 6: Run CatalogWriteService tests to verify nothing broke**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All pass — the aisle sync behavior is identical, just delegated

**Step 7: Commit**

```bash
git add app/services/aisle_write_service.rb test/services/aisle_write_service_test.rb \
  app/services/catalog_write_service.rb
git commit -m "refactor: consolidate aisle sync into AisleWriteService"
```

---

### Task 3: Create CategoryWriteService with update_order

**Files:**
- Create: `app/services/category_write_service.rb`
- Create: `test/services/category_write_service_test.rb`
- Modify: `app/controllers/categories_controller.rb:25-38` (update_order action) and `42-78` (remove cascade methods)

**Step 1: Write the failing tests**

Create `test/services/category_write_service_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class CategoryWriteServiceTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    Category.destroy_all
    @bread = Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
    @dessert = Category.create!(name: 'Dessert', slug: 'dessert', position: 1, kitchen: @kitchen)
  end

  # --- validation ---

  test 'update_order returns errors for too many categories' do
    names = (1..51).map { |i| "Cat #{i}" }

    result = CategoryWriteService.update_order(kitchen: @kitchen, names:, renames: {}, deletes: [])

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('Too many') })
  end

  test 'update_order returns errors for name too long' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['a' * 51], renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('too long') })
  end

  test 'update_order returns errors for case-insensitive duplicates' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread bread Dessert], renames: {}, deletes: []
    )

    assert_not result.success
    assert(result.errors.any? { |e| e.include?('more than once') })
  end

  # --- renames ---

  test 'update_order renames a category' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Artisan Bread', 'Dessert'],
      renames: { 'Bread' => 'Artisan Bread' }, deletes: []
    )

    @bread.reload

    assert_equal 'Artisan Bread', @bread.name
    assert_equal 'artisan-bread', @bread.slug
  end

  test 'update_order renames with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Artisan Bread', 'Dessert'],
      renames: { 'bread' => 'Artisan Bread' }, deletes: []
    )

    assert_equal 'Artisan Bread', @bread.reload.name
  end

  test 'update_order handles case-only rename' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[bread Dessert],
      renames: { 'Bread' => 'bread' }, deletes: []
    )

    assert_equal 'bread', @bread.reload.name
  end

  # --- deletes ---

  test 'update_order deletes category and reassigns recipes to Miscellaneous' do
    MarkdownImporter.import("# Rolls\n\n## Mix (do it)\n\n- Flour, 1 cup\n\nMix.",
                            kitchen: @kitchen, category: @bread)

    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Dessert'],
      renames: {}, deletes: ['Bread']
    )

    assert_nil Category.find_by(name: 'Bread')
    assert_equal 'Miscellaneous', Recipe.find_by!(slug: 'rolls').category.name
  end

  test 'update_order deletes with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: ['Dessert'],
      renames: {}, deletes: ['bread']
    )

    assert_nil Category.find_by(slug: 'bread')
  end

  # --- reordering ---

  test 'update_order reorders categories by position' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Dessert Bread],
      renames: {}, deletes: []
    )

    assert_equal 0, @dessert.reload.position
    assert_equal 1, @bread.reload.position
  end

  test 'update_order reorders with case mismatch' do
    CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[dessert bread],
      renames: {}, deletes: []
    )

    assert_equal 0, @dessert.reload.position
    assert_equal 1, @bread.reload.position
  end

  # --- success result ---

  test 'update_order returns success on valid input' do
    result = CategoryWriteService.update_order(
      kitchen: @kitchen, names: %w[Bread Dessert],
      renames: {}, deletes: []
    )

    assert result.success
    assert_empty result.errors
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/category_write_service_test.rb`
Expected: `NameError: uninitialized constant CategoryWriteService`

**Step 3: Write CategoryWriteService**

Create `app/services/category_write_service.rb`:

```ruby
# frozen_string_literal: true

# Placeholder header comment — will be written in Task 4.
class CategoryWriteService
  Result = Data.define(:success, :errors)

  MAX_CATEGORIES = 50
  MAX_NAME_LENGTH = 50

  def self.update_order(kitchen:, names:, renames:, deletes:)
    new(kitchen:).update_order(names:, renames:, deletes:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update_order(names:, renames:, deletes:)
    errors = validate_order(names)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      cascade_renames(renames)
      cascade_deletes(deletes)
      update_positions(names)
    end

    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_order(names)
    errors = []
    errors << "Too many items (maximum #{MAX_CATEGORIES})." if names.size > MAX_CATEGORIES

    long = names.select { |name| name.size > MAX_NAME_LENGTH }
    long.each { |name| errors << "\"#{name}\" is too long (maximum #{MAX_NAME_LENGTH} characters)." }

    dupes = names.group_by(&:downcase).select { |_, v| v.size > 1 }.values.map(&:first)
    dupes.each { |name| errors << "\"#{name}\" appears more than once (case-insensitive)." }
    errors
  end

  def cascade_renames(renames)
    return unless renames.is_a?(Hash) || renames.is_a?(ActionController::Parameters)

    renames.each_pair do |old_name, new_name|
      category = kitchen.categories.find_by!(slug: FamilyRecipes.slugify(old_name))
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def cascade_deletes(deletes)
    deletes = Array(deletes)
    return if deletes.empty?

    misc = find_or_create_miscellaneous

    deletes.each do |name|
      category = kitchen.categories.find_by(slug: FamilyRecipes.slugify(name))
      next unless category

      category.recipes.update_all(category_id: misc.id) # rubocop:disable Rails/SkipsModelValidations
      category.destroy!
    end
  end

  def find_or_create_miscellaneous
    slug = FamilyRecipes.slugify('Miscellaneous')
    kitchen.categories.find_or_create_by!(slug:) do |cat|
      cat.name = 'Miscellaneous'
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def update_positions(names)
    names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name))
             .update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
```

**Step 4: Run service tests to verify they pass**

Run: `ruby -Itest test/services/category_write_service_test.rb`
Expected: All pass

**Step 5: Wire up CategoriesController**

Replace the `update_order` action and remove all private methods except `order_content`'s helper. The controller becomes:

```ruby
# frozen_string_literal: true

# Placeholder header comment — will be written in Task 4.
class CategoriesController < ApplicationController
  before_action :require_membership, only: [:update_order]

  def order_content
    categories = current_kitchen.categories.ordered
    render json: {
      categories: categories.map { |c| { name: c.name, position: c.position, recipe_count: c.recipes.size } }
    }
  end

  def update_order
    result = CategoryWriteService.update_order(
      kitchen: current_kitchen,
      names: Array(params[:category_order]),
      renames: params[:renames],
      deletes: params[:deletes]
    )
    return render(json: { errors: result.errors }, status: :unprocessable_content) unless result.success

    current_kitchen.broadcast_update
    render json: { status: 'ok' }
  end
end
```

Remove `include OrderedListEditor` — no longer needed here.

**Step 6: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/categories_controller_test.rb`
Expected: All pass

**Step 7: Commit**

```bash
git add app/services/category_write_service.rb test/services/category_write_service_test.rb \
  app/controllers/categories_controller.rb
git commit -m "feat: extract CategoryWriteService from CategoriesController"
```

---

### Task 4: Update architectural comments and CLAUDE.md

**Files:**
- Modify: `app/services/aisle_write_service.rb` (header comment)
- Modify: `app/services/category_write_service.rb` (header comment)
- Modify: `app/controllers/groceries_controller.rb` (header comment)
- Modify: `app/controllers/categories_controller.rb` (header comment)
- Modify: `app/services/catalog_write_service.rb` (header comment — mention AisleWriteService delegation)
- Modify: `CLAUDE.md`

**Step 1: Write header comments**

`AisleWriteService`:
```ruby
# Orchestrates all aisle mutations: reorder, rename, delete (with cascade to
# IngredientCatalog rows), and new-aisle sync. Single owner of Kitchen#aisle_order
# writes — CatalogWriteService delegates here for aisle sync after catalog saves.
#
# - Kitchen#aisle_order: newline-delimited string of user-ordered aisle names
# - IngredientCatalog: cascade target for rename/delete operations
# - CatalogWriteService: calls sync_new_aisle / sync_new_aisles after catalog writes
```

`CategoryWriteService`:
```ruby
# Orchestrates category ordering, renaming, and deletion. Cascade deletes reassign
# orphaned recipes to Miscellaneous. Called by CategoriesController for the Edit
# Categories dialog changeset.
#
# - Category: AR model with position column for homepage ordering
# - Kitchen#broadcast_update: page-refresh morph (called by controller, not service)
```

Update `GroceriesController` header to mention `AisleWriteService` instead of describing inline cascade logic.

Update `CategoriesController` header to mention `CategoryWriteService`.

Update `CatalogWriteService` header collaborator list to include `AisleWriteService`.

**Step 2: Update CLAUDE.md Architecture section**

In the "Write path" paragraph, add after the `CatalogWriteService` sentence:

```
`AisleWriteService` orchestrates all `Kitchen#aisle_order` mutations — reorder, rename/delete cascades to catalog rows, and new-aisle sync (called by `CatalogWriteService` after catalog saves).
`CategoryWriteService` orchestrates category ordering, renaming, and deletion cascades.
```

**Step 3: Check if OrderedListEditor concern is still used**

After removing it from both `GroceriesController` and `CategoriesController`, check if any other file includes it. If not, delete `app/controllers/concerns/ordered_list_editor.rb` and `test/controllers/concerns/ordered_list_editor_test.rb` (if one exists).

Run: `grep -r 'OrderedListEditor' app/ test/`

If no remaining references, delete the files.

**Step 4: Run full test suite**

Run: `rake test`
Expected: All pass, no regressions

**Step 5: Run linter**

Run: `bundle exec rubocop`
Expected: No new offenses

**Step 6: Commit**

```bash
git add -A
git commit -m "docs: update architectural comments for write service extraction"
```

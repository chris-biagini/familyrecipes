# ListWriteService Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify AisleWriteService, CategoryWriteService, and TagWriteService under a shared template method base class.

**Architecture:** Extract `ListWriteService` with a skeleton (validate → transaction → finalize) and four hooks (`validate_changeset`, `apply_renames`, `apply_deletes`, `apply_ordering`). Each existing service becomes a thin subclass. `OrderedListValidation` concern is absorbed and deleted.

**Tech Stack:** Ruby/Rails, Minitest, ActiveRecord transactions

**Spec:** `docs/plans/2026-03-19-list-write-service-unification-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/services/list_write_service.rb` | Create | Base class: skeleton, Result type, input normalization, shared validation helpers |
| `test/services/list_write_service_test.rb` | Create | Skeleton tests using minimal test subclass |
| `app/services/aisle_write_service.rb` | Rewrite | Subclass: aisle cascade + sync_new_aisles |
| `test/services/aisle_write_service_test.rb` | Modify | Rename `update_order` → `update` at call sites |
| `app/controllers/groceries_controller.rb` | Modify (line 43) | Rename `update_order` → `update` |
| `app/services/category_write_service.rb` | Rewrite | Subclass: category cascade + position updates |
| `test/services/category_write_service_test.rb` | Modify | Rename `update_order` → `update` at call sites |
| `app/controllers/categories_controller.rb` | Modify (line 19) | Rename `update_order` → `update` |
| `app/services/tag_write_service.rb` | Rewrite | Subclass: tag cascade (no ordering) |
| `app/services/concerns/ordered_list_validation.rb` | Delete | Absorbed into ListWriteService |
| `CLAUDE.md` | Modify | Note base class in Architecture section |

---

### Task 1: Create ListWriteService base class

**Files:**
- Create: `app/services/list_write_service.rb`
- Create: `test/services/list_write_service_test.rb`

- [ ] **Step 1: Write the base class test file**

```ruby
# frozen_string_literal: true

require 'test_helper'
require 'turbo/broadcastable/test_helper'

class ListWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  class TestListService < ListWriteService
    attr_reader :hook_calls

    private

    def validate_changeset(renames:, deletes:, fail_validation: false, **)
      @hook_calls = [[:validate_changeset, { renames:, deletes: }]]
      fail_validation ? ['Forced validation error'] : []
    end

    def apply_renames(renames)
      (@hook_calls ||= []) << [:apply_renames, renames]
    end

    def apply_deletes(deletes)
      (@hook_calls ||= []) << [:apply_deletes, deletes]
    end

    def apply_ordering(**params)
      (@hook_calls ||= []) << [:apply_ordering, params]
    end
  end

  setup do
    setup_test_kitchen
  end

  test 'calls hooks in order within a transaction on success' do
    service = TestListService.new(kitchen: @kitchen)
    result = service.update(renames: { 'a' => 'b' }, deletes: ['c'])

    assert result.success
    assert_empty result.errors
    hooks = service.hook_calls.map(&:first)

    assert_equal %i[validate_changeset apply_renames apply_deletes apply_ordering], hooks
  end

  test 'short-circuits on validation errors without transaction or finalize' do
    assert_no_turbo_stream_broadcasts [@kitchen, :updates] do
      service = TestListService.new(kitchen: @kitchen)
      result = service.update(renames: {}, deletes: [], fail_validation: true)

      assert_not result.success
      assert_equal ['Forced validation error'], result.errors
      assert_equal 1, service.hook_calls.size
    end
  end

  test 'normalizes nil renames to empty hash' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: nil, deletes: [])

    assert_equal({}, service.hook_calls.first[1][:renames])
  end

  test 'normalizes nil deletes to empty array' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: {}, deletes: nil)

    assert_equal [], service.hook_calls.first[1][:deletes]
  end

  test 'class-level update delegates to instance' do
    result = TestListService.update(kitchen: @kitchen, renames: {}, deletes: [])

    assert result.success
  end

  test 'passes extra keyword arguments through to hooks' do
    service = TestListService.new(kitchen: @kitchen)
    service.update(renames: {}, deletes: [], fail_validation: false)

    last_hook = service.hook_calls.last

    assert_equal :apply_ordering, last_hook[0]
  end

  test 'finalize_writes broadcasts on success' do
    assert_turbo_stream_broadcasts [@kitchen, :updates] do
      TestListService.update(kitchen: @kitchen, renames: {}, deletes: [])
    end
  end

  # --- shared validation helpers ---

  test 'validate_order flags too many items' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[a b c], max_items: 2, max_name_length: 50)

    assert(errors.any? { |e| e.include?('Too many') })
  end

  test 'validate_order flags names exceeding max length' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, ['a' * 51], max_items: 100, max_name_length: 50)

    assert(errors.any? { |e| e.include?('too long') })
  end

  test 'validate_order flags case-insensitive duplicates' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo foo], max_items: 100, max_name_length: 50)

    assert(errors.any? { |e| e.include?('more than once') })
  end

  test 'validate_order with exact_dupes false ignores exact duplicates' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo Foo], max_items: 100, max_name_length: 50, exact_dupes: false)

    assert_empty errors
  end

  test 'validate_order with exact_dupes false flags mixed-case variants' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_order, %w[Foo foo], max_items: 100, max_name_length: 50, exact_dupes: false)

    assert(errors.any? { |e| e.include?('more than once') })
  end

  test 'validate_renames_length flags names exceeding max' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_renames_length, { 'old' => 'a' * 51 }, 50)

    assert(errors.any? { |e| e.include?('exceeds maximum length') })
  end

  test 'validate_renames_length passes names within limit' do
    service = TestListService.new(kitchen: @kitchen)
    errors = service.send(:validate_renames_length, { 'old' => 'a' * 50 }, 50)

    assert_empty errors
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby -Itest test/services/list_write_service_test.rb`
Expected: FAIL — `ListWriteService` not defined

- [ ] **Step 3: Write the ListWriteService base class**

```ruby
# frozen_string_literal: true

# Template method base class for list management services (aisles, categories,
# tags). Provides the shared skeleton: validate → transaction(renames, deletes,
# ordering) → finalize. Subclasses override hooks for their specific cascade
# behavior. Input normalization (coercing renames/deletes to clean Ruby types)
# happens once here so subclasses never need defensive type guards.
#
# - Kitchen.finalize_writes: centralized post-write finalization
# - AisleWriteService, CategoryWriteService, TagWriteService: subclasses
class ListWriteService
  Result = Data.define(:success, :errors)

  def self.update(kitchen:, renames: {}, deletes: [], **params)
    new(kitchen:).update(renames:, deletes:, **params)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def update(renames: {}, deletes: [], **params)
    renames = normalize_renames(renames)
    deletes = Array(deletes)

    errors = validate_changeset(renames:, deletes:, **params)
    return Result.new(success: false, errors:) if errors.any?

    ActiveRecord::Base.transaction do
      apply_renames(renames)
      apply_deletes(deletes)
      apply_ordering(**params)
    end

    Kitchen.finalize_writes(kitchen)
    Result.new(success: true, errors: [])
  end

  private

  attr_reader :kitchen

  def validate_changeset(renames:, deletes:, **) = []
  def apply_renames(renames) = nil
  def apply_deletes(deletes) = nil
  def apply_ordering(**) = nil

  def normalize_renames(renames)
    case renames
    when Hash then renames
    when ActionController::Parameters then renames.to_unsafe_h
    else {}
    end
  end

  def validate_order(items, max_items:, max_name_length:, exact_dupes: true)
    errors = []
    errors << "Too many items (maximum #{max_items})." if items.size > max_items

    long = items.select { |name| name.size > max_name_length }
    errors.concat(long.map { |name| "\"#{name}\" is too long (maximum #{max_name_length} characters)." })

    dupes = items.group_by(&:downcase)
                 .select { |_, v| exact_dupes ? v.size > 1 : v.uniq.size > 1 }
                 .values.map(&:first)
    errors.concat(dupes.map { |name| "\"#{name}\" appears more than once (case-insensitive)." })
    errors
  end

  def validate_renames_length(renames, max_length)
    renames.values
           .select { |name| name.size > max_length }
           .map { |name| "\"#{name}\" exceeds maximum length of #{max_length} characters." }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/list_write_service_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/list_write_service.rb test/services/list_write_service_test.rb
git commit -m "Add ListWriteService base class with template method skeleton"
```

---

### Task 2: Migrate AisleWriteService to subclass

**Files:**
- Rewrite: `app/services/aisle_write_service.rb`
- Modify: `test/services/aisle_write_service_test.rb` — rename `update_order` → `update` (21 occurrences)
- Modify: `app/controllers/groceries_controller.rb:43` — rename `update_order` → `update`

- [ ] **Step 1: Rewrite AisleWriteService as a ListWriteService subclass**

```ruby
# frozen_string_literal: true

# Orchestrates all aisle mutations: reorder, rename, delete (with cascade to
# IngredientCatalog rows), and new-aisle sync. Extends ListWriteService for
# the shared validate → transaction → finalize skeleton.
#
# - Kitchen#aisle_order: newline-delimited string of user-ordered aisle names
# - IngredientCatalog: cascade target for rename/delete operations
# - CatalogWriteService: calls sync_new_aisles after catalog writes
# - ListWriteService: template method base class
class AisleWriteService < ListWriteService
  def self.sync_new_aisles(kitchen:, aisles:)
    new(kitchen:).sync_new_aisles(aisles:)
  end

  def sync_new_aisles(aisles:)
    return if aisles.empty?

    kitchen.reload
    current = kitchen.aisle_order.to_s.split("\n").reject(&:empty?)
    current.concat(aisles)
    kitchen.update!(aisle_order: current.uniq(&:downcase).join("\n"))
  end

  private

  # Exact duplicates are silently normalized away; only flag mixed-case variants
  def validate_changeset(renames:, aisle_order:, **)
    kitchen.aisle_order = aisle_order.to_s

    validate_order(kitchen.parsed_aisle_order,
                   max_items: Kitchen::MAX_AISLES,
                   max_name_length: Kitchen::MAX_AISLE_NAME_LENGTH,
                   exact_dupes: false) +
      validate_renames_length(renames, Kitchen::MAX_AISLE_NAME_LENGTH)
  end

  def apply_renames(renames)
    renames.each_pair do |old_name, new_name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', old_name)
             .update_all(aisle: new_name) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def apply_deletes(deletes)
    deletes.each do |name|
      kitchen.ingredient_catalog.where('LOWER(aisle) = LOWER(?)', name)
             .update_all(aisle: nil) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def apply_ordering(aisle_order:, **)
    kitchen.normalize_aisle_order!
    kitchen.save!
  end
end
```

- [ ] **Step 2: Update test file — rename `update_order` → `update`**

In `test/services/aisle_write_service_test.rb`:
1. Replace all `AisleWriteService.update_order(` with
   `AisleWriteService.update(` (15 method-call occurrences).
2. Rename `update_order` in test names and section comments to `update`
   (e.g., `test 'update_order returns errors...'` → `test 'update returns
   errors...'`, `# --- update_order: validation ---` → `# --- update:
   validation ---`).

- [ ] **Step 3: Update controller call site**

In `app/controllers/groceries_controller.rb:43`, change:
```ruby
    result = AisleWriteService.update_order(
```
to:
```ruby
    result = AisleWriteService.update(
```

- [ ] **Step 4: Run aisle tests to verify they pass**

Run: `ruby -Itest test/services/aisle_write_service_test.rb`
Expected: All 20 tests PASS

- [ ] **Step 5: Run groceries controller tests**

Run: `ruby -Itest test/controllers/groceries_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/aisle_write_service.rb test/services/aisle_write_service_test.rb app/controllers/groceries_controller.rb
git commit -m "Migrate AisleWriteService to ListWriteService subclass"
```

---

### Task 3: Migrate CategoryWriteService to subclass

**Files:**
- Rewrite: `app/services/category_write_service.rb`
- Modify: `test/services/category_write_service_test.rb` — rename `update_order` → `update` (10 occurrences)
- Modify: `app/controllers/categories_controller.rb:19` — rename `update_order` → `update`

- [ ] **Step 1: Rewrite CategoryWriteService as a ListWriteService subclass**

```ruby
# frozen_string_literal: true

# Orchestrates category ordering, renaming, and deletion. Cascade deletes
# reassign orphaned recipes to Miscellaneous. Extends ListWriteService for
# the shared validate → transaction → finalize skeleton.
#
# - Category: AR model with position column for homepage ordering
# - ListWriteService: template method base class
class CategoryWriteService < ListWriteService
  MAX_ITEMS = 50
  MAX_NAME_LENGTH = 50

  private

  def validate_changeset(renames:, names:, **)
    validate_order(names, max_items: MAX_ITEMS, max_name_length: MAX_NAME_LENGTH) +
      validate_renames_length(renames, MAX_NAME_LENGTH)
  end

  def apply_renames(renames)
    renames.each_pair do |old_name, new_name|
      category = kitchen.categories.find_by!(slug: FamilyRecipes.slugify(old_name))
      category.update!(name: new_name, slug: FamilyRecipes.slugify(new_name))
    end
  end

  def apply_deletes(deletes)
    return if deletes.empty?

    misc = Category.miscellaneous(kitchen)

    deletes.each do |name|
      category = kitchen.categories.find_by(slug: FamilyRecipes.slugify(name))
      next unless category

      category.recipes.update_all(category_id: misc.id) # rubocop:disable Rails/SkipsModelValidations
      category.destroy!
    end
  end

  def apply_ordering(names:, **)
    names.each_with_index do |name, index|
      kitchen.categories.where(slug: FamilyRecipes.slugify(name))
             .update_all(position: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
```

- [ ] **Step 2: Update test file — rename `update_order` → `update`**

In `test/services/category_write_service_test.rb`:
1. Replace all `CategoryWriteService.update_order(` with
   `CategoryWriteService.update(` (14 method-call occurrences).
2. Rename `update_order` in test names and section comments to `update`
   (e.g., `test 'update_order renames a category'` → `test 'update renames
   a category'`, `# --- validation ---` comments are already generic).

- [ ] **Step 3: Update controller call site**

In `app/controllers/categories_controller.rb:19`, change:
```ruby
    result = CategoryWriteService.update_order(
```
to:
```ruby
    result = CategoryWriteService.update(
```

- [ ] **Step 4: Run category tests to verify they pass**

Run: `ruby -Itest test/services/category_write_service_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Run categories controller tests**

Run: `ruby -Itest test/controllers/categories_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add app/services/category_write_service.rb test/services/category_write_service_test.rb app/controllers/categories_controller.rb
git commit -m "Migrate CategoryWriteService to ListWriteService subclass"
```

---

### Task 4: Migrate TagWriteService to subclass

**Files:**
- Rewrite: `app/services/tag_write_service.rb`

No test or controller changes needed — TagWriteService already uses `.update`
as its entry point. The structural change is converting from class methods to
instance methods via the base class constructor.

- [ ] **Step 1: Rewrite TagWriteService as a ListWriteService subclass**

```ruby
# frozen_string_literal: true

# Handles bulk tag management operations (rename, delete) from the tag
# management dialog. Extends ListWriteService for the shared validate →
# transaction → finalize skeleton. No ordering — tags sort alphabetically.
#
# - Tag: the model being mutated
# - TagsController: thin controller that delegates here
# - ListWriteService: template method base class
class TagWriteService < ListWriteService
  private

  def validate_changeset(renames:, **)
    existing = kitchen.tags.pluck(:name)
    renames.filter_map do |old_name, new_name|
      normalized = new_name.downcase
      "Tag '#{new_name}' already exists" if normalized != old_name && existing.include?(normalized)
    end
  end

  def apply_renames(renames)
    renames.each do |old_name, new_name|
      tag = kitchen.tags.find_by!(name: old_name)
      tag.update!(name: new_name.downcase)
    end
  end

  def apply_deletes(deletes)
    kitchen.tags.where(name: deletes).destroy_all if deletes.any?
  end
end
```

- [ ] **Step 2: Run tag tests to verify they pass**

Run: `ruby -Itest test/services/tag_write_service_test.rb`
Expected: All 6 tests PASS

- [ ] **Step 3: Run tags controller tests**

Run: `ruby -Itest test/controllers/tags_controller_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/tag_write_service.rb
git commit -m "Migrate TagWriteService to ListWriteService subclass"
```

---

### Task 5: Delete OrderedListValidation and update documentation

**Files:**
- Delete: `app/services/concerns/ordered_list_validation.rb`
- Modify: `CLAUDE.md` — note ListWriteService in Architecture section

- [ ] **Step 1: Delete the OrderedListValidation concern**

```bash
git rm app/services/concerns/ordered_list_validation.rb
```

No other file references it after Tasks 2–4 removed the `include` lines.

- [ ] **Step 2: Update CLAUDE.md Architecture section**

In the `**Write path.**` paragraph of CLAUDE.md, after the write services
bullet list, add:

```
- `ListWriteService` is the template method base class for
  `AisleWriteService`, `CategoryWriteService`, and `TagWriteService`.
  Subclasses override `validate_changeset`, `apply_renames`,
  `apply_deletes`, and `apply_ordering` hooks.
```

- [ ] **Step 3: Run full test suite**

Run: `rake test`
Expected: All tests PASS, 0 failures, 0 errors

- [ ] **Step 4: Run lint**

Run: `bundle exec rubocop`
Expected: 0 offenses

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Delete OrderedListValidation concern (absorbed into ListWriteService) and update docs"
```

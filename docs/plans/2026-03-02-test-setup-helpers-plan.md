# Test Setup Helpers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate kitchen/tenant/category/catalog boilerplate duplicated across 20+ test files by extracting shared helpers into `ActiveSupport::TestCase` (closes #154).

**Architecture:** Add `setup_test_kitchen`, `setup_test_category`, and `create_catalog_entry` to `ActiveSupport::TestCase` in `test_helper.rb`. Move `create_kitchen_and_user` from `ActionDispatch::IntegrationTest` to `ActiveSupport::TestCase` (calling `setup_test_kitchen` internally). Keep `log_in` and `kitchen_slug` in `ActionDispatch::IntegrationTest` since they use integration test methods.

**Tech Stack:** Ruby, Minitest, Rails test infrastructure

---

### Task 1: Add shared helpers to test_helper.rb

**Files:**
- Modify: `test/test_helper.rb`

**Step 1: Add helpers to ActiveSupport::TestCase and refactor create_kitchen_and_user**

Replace the current `ActionDispatch::IntegrationTest` monkey-patch with two blocks:

```ruby
class ActiveSupport::TestCase
  private

  def setup_test_kitchen
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
  end

  def setup_test_category(name: 'Test', slug: nil)
    slug ||= FamilyRecipes.slugify(name)
    @category = Category.find_or_create_by!(name:, slug:)
  end

  def create_catalog_entry(name, aisle: nil, basis_grams: nil, **nutrient_attrs)
    IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: name) do |e|
      e.aisle = aisle
      e.basis_grams = basis_grams
      nutrient_attrs.each { |attr, val| e.public_send(:"#{attr}=", val) }
    end
  end

  def create_kitchen_and_user
    setup_test_kitchen
    @user = User.create!(name: 'Test User', email: 'test@example.com')
    Membership.create!(kitchen: @kitchen, user: @user)
  end
end

module ActionDispatch
  class IntegrationTest
    private

    def log_in
      get dev_login_path(id: @user.id)
    end

    def kitchen_slug
      @kitchen.slug
    end
  end
end
```

**Step 2: Update the header comment**

Update the file header to reflect all four helpers and their locations.

**Step 3: Run tests to verify nothing breaks**

Run: `rake test`
Expected: All tests pass (helpers added, nothing removed yet).

**Step 4: Commit**

```
git commit -m "refactor: add shared test setup helpers to ActiveSupport::TestCase"
```

---

### Task 2: Update model tests to use shared helpers

**Files (10):**
- Modify: `test/models/recipe_model_test.rb`
- Modify: `test/models/step_test.rb`
- Modify: `test/models/ingredient_test.rb`
- Modify: `test/models/cross_reference_test.rb`
- Modify: `test/models/recipe_aggregation_test.rb`
- Modify: `test/models/category_test.rb`
- Modify: `test/models/meal_plan_test.rb`
- Modify: `test/models/membership_test.rb`
- Modify: `test/models/ingredient_catalog_test.rb`
- Modify: `test/models/kitchen_aisle_order_test.rb`

**Step 1: Replace setup boilerplate in each file**

Replacements by pattern:

**Kitchen + tenant + category** (recipe_model_test, step_test, ingredient_test, recipe_aggregation_test):
```ruby
# Before:
setup do
  @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
  ActsAsTenant.current_tenant = @kitchen
  @category = Category.find_or_create_by!(name: 'Test', slug: 'test')
end

# After:
setup do
  setup_test_kitchen
  setup_test_category
end
```

For recipe_aggregation_test, the category name is 'Bread':
```ruby
setup do
  setup_test_kitchen
  setup_test_category(name: 'Bread')
end
```

**cross_reference_test.rb** — 4 setup blocks, all start with kitchen + tenant + Category 'Bread':
```ruby
# Replace the first 3 lines of each setup block with:
setup_test_kitchen
setup_test_category(name: 'Bread')
```

**Kitchen + tenant only** (category_test, meal_plan_test, membership_test):
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen

# After:
setup_test_kitchen
```
Keep any extra lines (e.g., `MealPlan.where(kitchen: @kitchen).delete_all`).

**ingredient_catalog_test** — uses kitchen without tenant:
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all

# After:
setup_test_kitchen
IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all
```

**kitchen_aisle_order_test** — uses different kitchen name/slug:
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test', slug: 'test')

# After:
setup_test_kitchen
```

**Step 2: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 3: Commit**

```
git commit -m "refactor: use shared setup helpers in model tests"
```

---

### Task 3: Update service tests to use shared helpers

**Files (6):**
- Modify: `test/services/shopping_list_builder_test.rb`
- Modify: `test/services/recipe_availability_calculator_test.rb`
- Modify: `test/services/cross_reference_updater_test.rb`
- Modify: `test/services/markdown_importer_test.rb`
- Modify: `test/services/recipe_write_service_test.rb`
- Modify: `test/services/recipe_broadcaster_test.rb`

**Step 1: Replace setup boilerplate in each file**

**Kitchen + tenant only** (markdown_importer_test, recipe_write_service_test):
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen

# After:
setup_test_kitchen
```
Keep extra lines like `Recipe.destroy_all; Category.destroy_all`.

**Kitchen + tenant + category** (cross_reference_updater_test):
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen
Category.find_or_create_by!(slug: 'bread', kitchen: @kitchen) do |cat|
  cat.name = 'Bread'
  cat.position = 0
end

# After:
setup_test_kitchen
setup_test_category(name: 'Bread')
```
Note: this test sets `position: 0` on the category. Check if this matters — if so, set it after `setup_test_category`.

**Kitchen + tenant + category + catalog** (shopping_list_builder_test, recipe_availability_calculator_test):
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen
Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
  p.basis_grams = 30
  p.aisle = 'Baking'
end

# After:
setup_test_kitchen
setup_test_category(name: 'Bread')

create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
```

**recipe_broadcaster_test** — kitchen + tenant + user:
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen
@user = User.find_or_create_by!(email: 'test@example.com') { |u| u.name = 'Test' }
Membership.find_or_create_by!(kitchen: @kitchen, user: @user)

# After:
create_kitchen_and_user
```

**Step 2: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 3: Commit**

```
git commit -m "refactor: use shared setup helpers in service tests"
```

---

### Task 4: Update helper, job, channel, and controller tests

**Files (5):**
- Modify: `test/helpers/recipes_helper_test.rb`
- Modify: `test/helpers/ingredients_helper_test.rb`
- Modify: `test/jobs/recipe_nutrition_job_test.rb`
- Modify: `test/channels/meal_plan_channel_test.rb`
- Modify: `test/controllers/header_auth_test.rb`

**Step 1: Replace setup boilerplate**

**Helper tests** (recipes_helper_test, ingredients_helper_test):
```ruby
# Before:
@kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen

# After:
setup_test_kitchen
```

**recipe_nutrition_job_test**:
```ruby
# Before:
@kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen
Recipe.destroy_all
Category.destroy_all
IngredientCatalog.destroy_all

IngredientCatalog.create!(
  ingredient_name: 'Flour',
  basis_grams: 30.0,
  calories: 110.0,
  fat: 0.5,
  protein: 3.0
)

# After:
setup_test_kitchen
Recipe.destroy_all
Category.destroy_all
IngredientCatalog.destroy_all

create_catalog_entry('Flour', basis_grams: 30.0, calories: 110.0, fat: 0.5, protein: 3.0)
```

**meal_plan_channel_test**:
```ruby
# Before:
@kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
@user = User.create!(name: 'Member', email: 'member@example.com')
ActsAsTenant.with_tenant(@kitchen) do
  Membership.create!(kitchen: @kitchen, user: @user)
end

# After:
setup_test_kitchen
@user = User.create!(name: 'Member', email: 'member@example.com')
Membership.create!(kitchen: @kitchen, user: @user)
```

**header_auth_test**:
```ruby
# Before:
@kitchen = Kitchen.create!(name: 'Test Kitchen', slug: 'test-kitchen')
ActsAsTenant.current_tenant = @kitchen

# After:
setup_test_kitchen
```

**Step 2: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 3: Commit**

```
git commit -m "refactor: use shared setup helpers in helper, job, channel, and controller tests"
```

---

### Task 5: Final verification and lint

**Step 1: Run full suite with lint**

Run: `rake`
Expected: All tests pass, no RuboCop offenses.

**Step 2: Squash into single commit, push**

Squash all task commits into one referencing #154, then push.

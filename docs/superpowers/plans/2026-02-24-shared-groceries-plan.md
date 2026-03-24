# Shared Groceries Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Transform the groceries page into a live shared inventory with server-backed state, real-time sync via ActionCable, and per-ingredient aisle storage.

**Architecture:** Rename NutritionEntry → IngredientProfile with aisle column. New GroceryList model stores shared state as jsonb. ActionCable broadcasts version bumps; clients fetch state via JSON endpoint. Offline support via local storage write buffer. Server computes the aisle-organized shopping list.

**Tech Stack:** Rails 8, ActionCable (Solid Cable adapter on PostgreSQL), PostgreSQL jsonb, vanilla JS

---

### Task 1: Rename NutritionEntry to IngredientProfile (migration)

**Files:**
- Create: `db/migrate/TIMESTAMP_rename_nutrition_entries_to_ingredient_profiles.rb`
- Create: `db/migrate/TIMESTAMP_add_aisle_to_ingredient_profiles.rb`
- Modify: `app/models/nutrition_entry.rb` → rename to `app/models/ingredient_profile.rb`
- Test: `test/models/nutrition_entry_test.rb` → rename to `test/models/ingredient_profile_test.rb`

**Step 1: Generate the rename migration**

```ruby
# db/migrate/TIMESTAMP_rename_nutrition_entries_to_ingredient_profiles.rb
class RenameNutritionEntriesToIngredientProfiles < ActiveRecord::Migration[8.1]
  def change
    rename_table :nutrition_entries, :ingredient_profiles
  end
end
```

**Step 2: Generate the aisle + nullable basis_grams migration**

```ruby
# db/migrate/TIMESTAMP_add_aisle_to_ingredient_profiles.rb
class AddAisleToIngredientProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ingredient_profiles, :aisle, :string
    change_column_null :ingredient_profiles, :basis_grams, true
  end
end
```

**Step 3: Run migrations**

Run: `rails db:migrate`
Expected: both migrations apply cleanly, `db/schema.rb` updated.

**Step 4: Rename the model file**

Move `app/models/nutrition_entry.rb` → `app/models/ingredient_profile.rb`. Update class name:

```ruby
# app/models/ingredient_profile.rb
class IngredientProfile < ApplicationRecord
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

Key change: `basis_grams` validation switches from `presence: true` to `allow_nil: true` with `numericality` only when present. This supports aisle-only rows.

**Step 5: Rename and update the test file**

Move `test/models/nutrition_entry_test.rb` → `test/models/ingredient_profile_test.rb`. Replace all `NutritionEntry` references with `IngredientProfile`. Update the class name to `IngredientProfileTest`. Update the `basis_grams` validation test — it should now allow nil (for aisle-only rows) but still reject 0 or negative when present.

Add a test for aisle-only rows:

```ruby
test 'allows aisle-only rows without basis_grams' do
  entry = IngredientProfile.new(ingredient_name: 'Egg yolk', aisle: 'Refrigerated')

  assert_predicate entry, :valid?
end

test 'stores aisle data' do
  entry = IngredientProfile.create!(ingredient_name: 'Flour', basis_grams: 30, aisle: 'Baking')
  entry.reload

  assert_equal 'Baking', entry.aisle
end
```

**Step 6: Run tests to verify rename**

Run: `ruby -Itest test/models/ingredient_profile_test.rb`
Expected: all tests pass

**Step 7: Commit**

```bash
git add -A && git commit -m "refactor: rename NutritionEntry to IngredientProfile, add aisle column"
```

---

### Task 2: Update all NutritionEntry references across codebase

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb` (update model references)
- Modify: `app/controllers/ingredients_controller.rb:7` (update lookup call)
- Modify: `app/jobs/recipe_nutrition_job.rb:20` (update lookup call)
- Modify: `app/jobs/cascade_nutrition_job.rb` (if any references)
- Modify: `db/seeds.rb:99` (update `NutritionEntry` → `IngredientProfile`)
- Modify: `lib/familyrecipes/nutrition_entry_helpers.rb` (keep filename but this module name stays — it's under FamilyRecipes namespace, no collision)
- Modify: `test/controllers/nutrition_entries_controller_test.rb` (update model refs)
- Modify: `test/controllers/ingredients_controller_test.rb` (update model refs)
- Modify: `test/jobs/recipe_nutrition_job_test.rb` (update model refs)
- Modify: `app/views/ingredients/index.html.erb` (if any direct model refs)

**Step 1: Update NutritionEntriesController**

In `app/controllers/nutrition_entries_controller.rb`, replace all `NutritionEntry` with `IngredientProfile`:
- Line 10: `IngredientProfile.find_or_initialize_by(...)`
- Line 22: `IngredientProfile.find_by!(...)`

**Step 2: Update IngredientsController**

In `app/controllers/ingredients_controller.rb`, line 7:
```ruby
@nutrition_lookup = IngredientProfile.lookup_for(current_kitchen)
```

**Step 3: Update RecipeNutritionJob**

In `app/jobs/recipe_nutrition_job.rb`, line 20:
```ruby
IngredientProfile.lookup_for(kitchen).transform_values do |entry|
```

**Step 4: Update db/seeds.rb**

Lines 99-121: Replace all `NutritionEntry` with `IngredientProfile`. Line 122:
```ruby
puts "Seeded #{IngredientProfile.global.count} ingredient profiles."
```

**Step 5: Update all test files**

Replace `NutritionEntry` with `IngredientProfile` in:
- `test/controllers/nutrition_entries_controller_test.rb`
- `test/controllers/ingredients_controller_test.rb` (lines 169, 171, 191)
- `test/jobs/recipe_nutrition_job_test.rb` (lines 11-19, 45, 77-84)

**Step 6: Run full test suite**

Run: `rake test`
Expected: all tests pass with the renamed model

**Step 7: Commit**

```bash
git add -A && git commit -m "refactor: update all NutritionEntry references to IngredientProfile"
```

---

### Task 3: Populate aisle data from grocery-info.yaml

**Files:**
- Modify: `db/seeds.rb` (add aisle population from grocery YAML)
- Test: manual — run `rails db:seed` and verify

**Step 1: Add aisle seeding to db/seeds.rb**

After the existing nutrition seeding block (around line 123), add:

```ruby
# Populate aisle data on IngredientProfile rows from grocery-info.yaml
grocery_yaml_path = resources_dir.join('grocery-info.yaml')
if File.exist?(grocery_yaml_path)
  grocery_data = FamilyRecipes.parse_grocery_info(grocery_yaml_path)
  aisle_count = 0

  grocery_data.each do |aisle, items|
    # Normalize "Omit_From_List" to "omit"
    aisle_value = aisle.downcase.tr('_', ' ') == 'omit from list' ? 'omit' : aisle

    items.each do |item|
      profile = IngredientProfile.find_or_initialize_by(kitchen_id: nil, ingredient_name: item[:name])
      profile.aisle = aisle_value
      profile.save!
      aisle_count += 1
    end
  end

  puts "Populated aisle data on #{aisle_count} ingredient profiles."
end
```

**Step 2: Run seed**

Run: `rails db:seed`
Expected: "Populated aisle data on N ingredient profiles." printed. Profiles with nutrition data now also have aisle; aisle-only profiles created for ingredients without nutrition data.

**Step 3: Verify in console**

Run: `rails runner "puts IngredientProfile.where.not(aisle: nil).count"`
Expected: count matches number of items in grocery-info.yaml

**Step 4: Commit**

```bash
git add db/seeds.rb && git commit -m "feat: seed aisle data onto IngredientProfile rows from grocery YAML"
```

---

### Task 4: Remove alias map, grocery YAML parsing, and aisle SiteDocument

**Files:**
- Modify: `lib/familyrecipes.rb` (remove `parse_grocery_info`, `parse_grocery_aisles_markdown`, `build_alias_map`, `build_known_ingredients`)
- Modify: `app/controllers/groceries_controller.rb` (remove alias_map, grocery_aisles loading, aisle-related methods)
- Modify: `app/controllers/ingredients_controller.rb` (remove alias_map usage)
- Modify: `app/jobs/recipe_nutrition_job.rb` (remove grocery_aisles/alias_map loading)
- Modify: `lib/familyrecipes/nutrition_calculator.rb:52` (remove alias_map parameter)
- Modify: `lib/familyrecipes/build_validator.rb` (remove alias_map/known_ingredients params)
- Modify: `lib/familyrecipes/recipe.rb` (update `all_ingredients_with_quantities` to drop alias_map)
- Modify: `lib/familyrecipes/ingredient.rb` (remove `normalized_name` if it uses alias_map)
- Modify: `lib/familyrecipes/cross_reference.rb` (update if alias_map passed through)
- Remove: `test/familyrecipes_test.rb` tests for `build_alias_map`, `build_known_ingredients`, `parse_grocery_info`, `parse_grocery_aisles_markdown`
- Modify: `test/controllers/groceries_controller_test.rb` (remove alias-related and aisle-editor tests)
- Modify: Various test files that pass alias_map

**Step 1: Remove module-level methods from `lib/familyrecipes.rb`**

Remove methods: `parse_grocery_info` (lines 31-43), `parse_grocery_aisles_markdown` (lines 47-61), `build_alias_map` (lines 64-82), `build_known_ingredients` (lines 85-92).

**Step 2: Update NutritionCalculator**

In `lib/familyrecipes/nutrition_calculator.rb`, line 52: change `calculate(recipe, alias_map, recipe_map)` to `calculate(recipe, recipe_map)`. Update `sum_totals` similarly. In `sum_totals`, line 77: change `recipe.all_ingredients_with_quantities(alias_map, recipe_map)` to `recipe.all_ingredients_with_quantities(recipe_map)`.

**Step 3: Update Recipe class**

In `lib/familyrecipes/recipe.rb`, update `all_ingredients_with_quantities` and `own_ingredients_with_quantities` to remove `alias_map` parameter. `normalized_name` on Ingredient should just use the ingredient's name directly (no alias lookup).

**Step 4: Update Ingredient and CrossReference classes**

Remove any `normalized_name(alias_map)` method or update it to just return the name. Update CrossReference's `expanded_ingredients` to drop alias_map parameter.

**Step 5: Update RecipeNutritionJob**

In `app/jobs/recipe_nutrition_job.rb`:
- Remove `grocery_aisles`, `load_grocery_aisles`, `alias_map` methods (lines 50-66)
- Update `omit_set` to query from IngredientProfile: `IngredientProfile.where(aisle: 'omit').pluck(:ingredient_name).to_set(&:downcase)`
- Update `perform` line 12: `calculator.calculate(parsed_recipe(recipe), recipe_map(recipe.kitchen))`

**Step 6: Update IngredientsController**

In `app/controllers/ingredients_controller.rb`:
- Remove `load_alias_map` and `load_grocery_aisles` methods
- Remove `@alias_map` from `index`
- In `recipes_by_ingredient`, use ingredient name directly instead of `@alias_map[ingredient.name.downcase] || ingredient.name`

**Step 7: Update GroceriesController**

Remove from `show`:
- `@grocery_aisles`, `@alias_map`, `@omit_set`, `@recipe_map`, `@unit_plurals`, `@grocery_aisles_content`
- Remove `update_grocery_aisles` action entirely
- Remove private methods: `load_grocery_aisles`, `build_omit_set`, `build_recipe_map`, `collect_unit_plurals`, `grocery_aisles_document`, `validate_grocery_aisles`

Keep: `show` (will be rebuilt in later tasks), `update_quick_bites`, `load_quick_bites_by_subsection`, `quick_bites_document`

**Step 8: Update BuildValidator**

Remove `alias_map` and `known_ingredients` parameters. Update `validate_ingredients` to check against `IngredientProfile` instead of `known_ingredients` set. Update `validate_nutrition` to use recipe ingredients without alias_map.

**Step 9: Remove routes**

In `config/routes.rb`, remove line 14:
```ruby
patch 'groceries/grocery_aisles', to: 'groceries#update_grocery_aisles', as: :groceries_grocery_aisles
```

**Step 10: Update tests**

- Remove `test_build_alias_map`, `test_build_alias_map_without_aliases`, `test_build_known_ingredients`, `test_parse_grocery_info_returns_aisles`, `test_parse_grocery_aisles_markdown_*` from `test/familyrecipes_test.rb`
- Remove `test 'update_grocery_aisles *'` tests from `test/controllers/groceries_controller_test.rb`
- Update `test/nutrition_calculator_test.rb` to remove alias_map from `calculate` calls
- Update `test/build_validator_test.rb` to remove alias_map/known_ingredients params
- Update any other tests passing alias_map

**Step 11: Run full test suite**

Run: `rake test`
Expected: all tests pass

**Step 12: Commit**

```bash
git add -A && git commit -m "refactor: remove alias map, grocery YAML parsing, and aisle SiteDocument"
```

---

### Task 5: Create GroceryList model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_grocery_lists.rb`
- Create: `app/models/grocery_list.rb`
- Test: `test/models/grocery_list_test.rb`

**Step 1: Write the test**

```ruby
# test/models/grocery_list_test.rb
class GroceryListTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    GroceryList.where(kitchen: @kitchen).delete_all
  end

  test 'belongs to kitchen' do
    list = GroceryList.create!(kitchen: @kitchen)

    assert_equal @kitchen, list.kitchen
  end

  test 'enforces one list per kitchen' do
    GroceryList.create!(kitchen: @kitchen)
    duplicate = GroceryList.new(kitchen: @kitchen)

    refute_predicate duplicate, :valid?
  end

  test 'defaults to version 0 and empty state' do
    list = GroceryList.create!(kitchen: @kitchen)

    assert_equal 0, list.version
    assert_equal({}, list.state)
  end

  test 'for_kitchen finds or creates' do
    list = GroceryList.for_kitchen(@kitchen)

    assert_predicate list, :persisted?
    assert_equal @kitchen, list.kitchen

    assert_equal list, GroceryList.for_kitchen(@kitchen)
  end

  test 'apply_action adds recipe to selected_recipes' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)

    assert_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action removes recipe from selected_recipes' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: false)

    refute_includes list.state['selected_recipes'], 'pizza-dough'
  end

  test 'apply_action checks off item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)

    assert_includes list.state['checked_off'], 'milk'
  end

  test 'apply_action adds custom item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    assert_includes list.state['custom_items'], 'birthday candles'
  end

  test 'apply_action removes custom item' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')
    list.apply_action('custom_items', item: 'birthday candles', action: 'remove')

    refute_includes list.state['custom_items'], 'birthday candles'
  end

  test 'clear resets state and bumps version' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'pizza-dough', selected: true)
    old_version = list.version

    list.clear!

    assert_equal({}, list.state)
    assert_operator list.version, :>, old_version
  end

  test 'apply_action bumps version' do
    list = GroceryList.for_kitchen(@kitchen)
    old_version = list.version

    list.apply_action('check', item: 'milk', checked: true)

    assert_operator list.version, :>, old_version
  end

  test 'operations are idempotent' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('check', item: 'milk', checked: true)
    version_after_first = list.version

    list.apply_action('check', item: 'milk', checked: true)

    assert_equal version_after_first, list.version
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/grocery_list_test.rb`
Expected: FAIL — `GroceryList` not defined

**Step 3: Generate migration**

```ruby
# db/migrate/TIMESTAMP_create_grocery_lists.rb
class CreateGroceryLists < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_lists do |t|
      t.references :kitchen, null: false, foreign_key: true, index: { unique: true }
      t.integer :version, null: false, default: 0
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
  end
end
```

**Step 4: Write the model**

```ruby
# app/models/grocery_list.rb
# frozen_string_literal: true

class GroceryList < ApplicationRecord
  belongs_to :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_KEYS = %w[selected_recipes selected_quick_bites custom_items checked_off].freeze

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  end

  def apply_action(action_type, **params)
    ensure_state_keys

    case action_type
    when 'select' then apply_select(**params)
    when 'check' then apply_check(**params)
    when 'custom_items' then apply_custom_items(**params)
    end
  end

  def clear!
    self.state = {}
    increment(:version)
    save!
  end

  private

  def ensure_state_keys
    STATE_KEYS.each { |key| state[key] ||= [] }
  end

  def apply_select(type:, slug:, selected:, **)
    key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
    toggle_array(key, slug, selected)
  end

  def apply_check(item:, checked:, **)
    toggle_array('checked_off', item, checked)
  end

  def apply_custom_items(item:, action:, **)
    toggle_array('custom_items', item, action == 'add')
  end

  def toggle_array(key, value, add)
    list = state[key]
    already_present = list.include?(value)

    if add && !already_present
      list << value
      bump_and_save!
    elsif !add && already_present
      list.delete(value)
      bump_and_save!
    end
  end

  def bump_and_save!
    increment(:version)
    save!
  end
end
```

**Step 5: Run migration and tests**

Run: `rails db:migrate && ruby -Itest test/models/grocery_list_test.rb`
Expected: all tests pass

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add GroceryList model with jsonb state and version counter"
```

---

### Task 6: Set up ActionCable with Solid Cable

**Files:**
- Modify: `Gemfile` (add `solid_cable`)
- Create: `config/cable.yml`
- Create: `db/migrate/TIMESTAMP_create_solid_cable_tables.rb` (via generator)
- Create: `app/channels/application_cable/connection.rb`
- Create: `app/channels/application_cable/channel.rb`
- Create: `app/channels/grocery_list_channel.rb`
- Test: `test/channels/grocery_list_channel_test.rb`

**Step 1: Add solid_cable to Gemfile**

Add to Gemfile (after `gem 'acts_as_tenant'`):
```ruby
gem 'solid_cable'
```

Run: `bundle install`

**Step 2: Install Solid Cable**

Run: `bin/rails solid_cable:install`

This generates the migration and cable.yml config. Edit `config/cable.yml` to ensure:

```yaml
development:
  adapter: solid_cable
  polling_interval: 0.1.seconds

test:
  adapter: test

production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
```

Run: `rails db:migrate`

**Step 3: Create ActionCable connection**

```ruby
# app/channels/application_cable/connection.rb
# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
  end
end
```

```ruby
# app/channels/application_cable/channel.rb
# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
```

**Step 4: Create GroceryListChannel**

```ruby
# app/channels/grocery_list_channel.rb
# frozen_string_literal: true

class GroceryListChannel < ApplicationCable::Channel
  def subscribed
    kitchen = Kitchen.find_by(slug: params[:kitchen_slug])
    reject unless kitchen

    stream_for kitchen
  end

  def self.broadcast_version(kitchen, version)
    broadcast_to(kitchen, version: version)
  end
end
```

**Step 5: Write channel test**

```ruby
# test/channels/grocery_list_channel_test.rb
# frozen_string_literal: true

require 'test_helper'
require 'action_cable/testing/canned_answers'

class GroceryListChannelTest < ActionCable::Channel::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
  end

  test 'subscribes to kitchen grocery list' do
    subscribe kitchen_slug: @kitchen.slug

    assert subscription.confirmed?
  end

  test 'rejects subscription for unknown kitchen' do
    subscribe kitchen_slug: 'nonexistent'

    assert subscription.rejected?
  end

  test 'broadcasts version to kitchen' do
    assert_broadcast_on(
      GroceryListChannel.broadcasting_for(@kitchen),
      version: 42
    ) do
      GroceryListChannel.broadcast_version(@kitchen, 42)
    end
  end
end
```

**Step 6: Run channel tests**

Run: `ruby -Itest test/channels/grocery_list_channel_test.rb`
Expected: all tests pass

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: set up ActionCable with Solid Cable and GroceryListChannel"
```

---

### Task 7: Build the grocery list API endpoints

**Files:**
- Modify: `config/routes.rb` (add new grocery routes)
- Modify: `app/controllers/groceries_controller.rb` (add state/select/check/custom_items/clear actions)
- Create: `app/services/shopping_list_builder.rb`
- Test: `test/controllers/groceries_controller_test.rb` (add API tests)
- Test: `test/services/shopping_list_builder_test.rb`

**Step 1: Add routes**

In `config/routes.rb`, replace the existing grocery routes (keeping `quick_bites` PATCH) with:

```ruby
get 'groceries', to: 'groceries#show', as: :groceries
get 'groceries/state', to: 'groceries#state', as: :groceries_state
patch 'groceries/select', to: 'groceries#select', as: :groceries_select
patch 'groceries/check', to: 'groceries#check', as: :groceries_check
patch 'groceries/custom_items', to: 'groceries#update_custom_items', as: :groceries_custom_items
delete 'groceries/clear', to: 'groceries#clear', as: :groceries_clear
patch 'groceries/quick_bites', to: 'groceries#update_quick_bites', as: :groceries_quick_bites
```

**Step 2: Write ShoppingListBuilder service**

```ruby
# app/services/shopping_list_builder.rb
# frozen_string_literal: true

class ShoppingListBuilder
  def initialize(kitchen:, grocery_list:)
    @kitchen = kitchen
    @grocery_list = grocery_list
    @profiles = IngredientProfile.lookup_for(kitchen)
  end

  def build
    ingredients = aggregate_recipe_ingredients.merge(aggregate_quick_bite_ingredients) { |_, a, b| merge_amounts(a, b) }
    organized = organize_by_aisle(ingredients)
    add_custom_items(organized)
    organized
  end

  private

  def selected_recipes
    slugs = @grocery_list.state.fetch('selected_recipes', [])
    @kitchen.recipes.includes(:category, steps: :ingredients).where(slug: slugs)
  end

  def selected_quick_bites
    slugs = @grocery_list.state.fetch('selected_quick_bites', [])
    return [] if slugs.empty?

    doc = @kitchen.site_documents.find_by(name: 'quick_bites')
    return [] unless doc

    all_bites = FamilyRecipes.parse_quick_bites_content(doc.content)
    all_bites.select { |qb| slugs.include?(qb.id) }
  end

  def aggregate_recipe_ingredients
    recipe_map = build_recipe_map
    selected_recipes.each_with_object({}) do |recipe, merged|
      parsed = recipe_map[recipe.slug]
      next unless parsed

      parsed.all_ingredients_with_quantities(recipe_map).each do |name, amounts|
        merged[name] = merged.key?(name) ? merge_amounts(merged[name], amounts) : amounts
      end
    end
  end

  def aggregate_quick_bite_ingredients
    selected_quick_bites.each_with_object({}) do |qb, merged|
      qb.ingredients_with_quantities.each do |name, amounts|
        merged[name] = merged.key?(name) ? merge_amounts(merged[name], amounts) : amounts
      end
    end
  end

  def build_recipe_map
    @kitchen.recipes.includes(:category, steps: :ingredients).to_h do |r|
      parsed = FamilyRecipes::Recipe.new(
        markdown_source: r.markdown_source,
        id: r.slug,
        category: r.category.name
      )
      [r.slug, parsed]
    end
  end

  def merge_amounts(existing, incoming)
    IngredientAggregator.merge_amount_lists(existing, incoming)
  end

  def organize_by_aisle(ingredients)
    result = Hash.new { |h, k| h[k] = [] }

    ingredients.each do |name, amounts|
      profile = @profiles[name]
      aisle = profile&.aisle

      next if aisle == 'omit'

      target_aisle = aisle || 'Miscellaneous'
      result[target_aisle] << { name: name, amounts: serialize_amounts(amounts) }
    end

    result.sort_by { |aisle, _| aisle == 'Miscellaneous' ? 'zzz' : aisle }.to_h
  end

  def add_custom_items(organized)
    custom = @grocery_list.state.fetch('custom_items', [])
    return if custom.empty?

    organized['Miscellaneous'] ||= []
    custom.each { |item| organized['Miscellaneous'] << { name: item, amounts: [] } }
  end

  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value, q.unit] }
  end
end
```

Note: `IngredientAggregator.merge_amount_lists` may need to be added — check if it exists or if the merge logic needs to be extracted from `Recipe#all_ingredients_with_quantities`.

**Step 3: Write ShoppingListBuilder test**

```ruby
# test/services/shopping_list_builder_test.rb
# frozen_string_literal: true

require 'test_helper'

class ShoppingListBuilderTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen
    Category.find_or_create_by!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)

      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    IngredientProfile.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
      p.basis_grams = 30
      p.aisle = 'Baking'
    end
    IngredientProfile.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Salt') do |p|
      p.basis_grams = 6
      p.aisle = 'Spices'
    end
  end

  test 'builds shopping list organized by aisle' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    assert result.key?('Baking'), "Expected 'Baking' aisle"
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    assert flour, 'Expected Flour in Baking aisle'
  end

  test 'puts unmapped ingredients in Miscellaneous' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    # Remove Salt's aisle
    IngredientProfile.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: nil)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    assert result.key?('Miscellaneous')
    salt = result['Miscellaneous'].find { |i| i[:name] == 'Salt' }

    assert salt, 'Expected Salt in Miscellaneous'
  end

  test 'omits ingredients with aisle omit' do
    IngredientProfile.find_by(ingredient_name: 'Salt', kitchen_id: nil)&.update!(aisle: 'omit')

    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
    all_names = result.values.flatten.map { |i| i[:name] }

    refute_includes all_names, 'Salt'
  end

  test 'includes custom items in Miscellaneous' do
    list = GroceryList.for_kitchen(@kitchen)
    list.apply_action('custom_items', item: 'birthday candles', action: 'add')

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
    custom = result['Miscellaneous'].find { |i| i[:name] == 'birthday candles' }

    assert custom
    assert_empty custom[:amounts]
  end

  test 'empty list returns empty hash' do
    list = GroceryList.for_kitchen(@kitchen)

    result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build

    assert_empty result
  end
end
```

**Step 4: Update GroceriesController with new actions**

```ruby
# app/controllers/groceries_controller.rb
# frozen_string_literal: true

class GroceriesController < ApplicationController
  before_action :require_membership, only: %i[select check update_custom_items clear update_quick_bites]

  def show
    @categories = current_kitchen.categories.ordered.includes(recipes: { steps: :ingredients })
    @quick_bites_by_subsection = load_quick_bites_by_subsection
    @quick_bites_content = quick_bites_document&.content || ''
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

    doc = current_kitchen.site_documents.find_or_initialize_by(name: 'quick_bites')
    doc.content = content
    doc.save!

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
    doc = quick_bites_document
    return {} unless doc

    FamilyRecipes.parse_quick_bites_content(doc.content)
                 .group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def quick_bites_document
    @quick_bites_document ||= current_kitchen.site_documents.find_by(name: 'quick_bites')
  end
end
```

**Step 5: Write controller tests for API endpoints**

Add to `test/controllers/groceries_controller_test.rb`:

```ruby
test 'state returns version and empty state for new list' do
  get groceries_state_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
  json = JSON.parse(response.body)

  assert_equal 0, json['version']
  assert_equal({}, json['shopping_list'])
end

test 'select adds recipe and returns version' do
  log_in
  patch groceries_select_path(kitchen_slug: kitchen_slug),
        params: { type: 'recipe', slug: 'focaccia', selected: true },
        as: :json

  assert_response :success
  json = JSON.parse(response.body)

  assert_operator json['version'], :>, 0
end

test 'select requires membership' do
  patch groceries_select_path(kitchen_slug: kitchen_slug),
        params: { type: 'recipe', slug: 'focaccia', selected: true },
        as: :json

  assert_response :unauthorized
end

test 'check marks item as checked' do
  log_in
  patch groceries_check_path(kitchen_slug: kitchen_slug),
        params: { item: 'flour', checked: true },
        as: :json

  assert_response :success
end

test 'custom_items adds item' do
  log_in
  patch groceries_custom_items_path(kitchen_slug: kitchen_slug),
        params: { item: 'birthday candles', action_type: 'add' },
        as: :json

  assert_response :success
end

test 'clear resets the list' do
  log_in
  delete groceries_clear_path(kitchen_slug: kitchen_slug), as: :json

  assert_response :success
  json = JSON.parse(response.body)

  assert json.key?('version')
end

test 'state includes shopping_list when recipes selected' do
  Category.create!(name: 'Bread', slug: 'bread', position: 0, kitchen: @kitchen)
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Focaccia

    Category: Bread

    ## Mix (combine)

    - Flour, 3 cups

    Mix well.
  MD

  IngredientProfile.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Flour') do |p|
    p.basis_grams = 30
    p.aisle = 'Baking'
  end

  log_in
  patch groceries_select_path(kitchen_slug: kitchen_slug),
        params: { type: 'recipe', slug: 'focaccia', selected: true },
        as: :json

  get groceries_state_path(kitchen_slug: kitchen_slug), as: :json

  json = JSON.parse(response.body)

  assert json['shopping_list'].key?('Baking')
end
```

**Step 6: Run tests**

Run: `rake test`
Expected: all tests pass

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: grocery list API with state, select, check, custom items, clear"
```

---

### Task 8: Rewrite groceries view for server-driven state

**Files:**
- Modify: `app/views/groceries/show.html.erb` (remove share section, data-ingredients, aisle editor; add ActionCable JS)
- Delete: `app/assets/javascripts/qrcodegen.js`

**Step 1: Rewrite the view**

Remove:
- `window.UNIT_PLURALS` script block
- `qrcodegen.js` include
- `data-ingredients` attributes on all checkboxes (recipe and quick bite)
- `@alias_map`/`@omit_set` filtering in recipe/quick-bite rendering
- Share section (lines 89-98)
- Aisle-based shopping list HTML (lines 100-129) — this will be rendered by JS from the server JSON
- Aisles editor dialog (lines 151-167)
- "Edit Aisles" button

Add:
- `actioncable.js` script include
- New `groceries.js` script (will be rewritten in next task)
- `data-slug` attributes on checkboxes (instead of data-ingredients)
- A `<div id="shopping-list"></div>` container for JS-rendered content
- Data attributes for kitchen slug and state URL on a container element

Keep:
- Recipe selector structure (categories, checkboxes, labels, recipe links) — but without `data-ingredients`
- Quick Bites section — but without `data-ingredients`
- Custom items section (input + list)
- Quick Bites editor dialog
- CSS/JS includes for notify, wake-lock, recipe-editor
- noscript message
- Print-friendly structure

**Step 2: Delete qrcodegen.js**

```bash
rm app/assets/javascripts/qrcodegen.js
```

**Step 3: Verify page renders**

Run: `bin/dev` (in background)
Navigate to groceries page, verify it loads without errors.

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: rewrite groceries view for server-driven state, remove QR/share section"
```

---

### Task 9: Rewrite groceries JavaScript

**Files:**
- Rewrite: `app/assets/javascripts/groceries.js`

This is the largest single task. The new JS needs to:

1. **On load:** Fetch `GET /groceries/state` and render from server state (or from local cache if offline)
2. **On checkbox change:** Send PATCH to server, apply optimistically, update local cache
3. **ActionCable subscription:** Listen for version broadcasts, fetch state if version > local
4. **Heartbeat:** Poll `GET /groceries/state` every 30 seconds
5. **Offline queue:** Buffer failed writes in `pending` array in local storage
6. **Shopping list rendering:** Build aisle sections from server-provided `shopping_list` JSON
7. **Notifications:** Show "List updated" toast via `Notify` when remote changes arrive
8. **Aisle collapse/expand:** Local-only, persisted in local storage

**Key architecture:**

```javascript
var GrocerySync = {
  version: 0,
  state: {},
  pending: [],
  storageKey: 'grocery-sync',
  // ... init, subscribe, heartbeat, fetchState, sendAction, flushPending
};

var GroceryUI = {
  // ... renderCheckboxes, renderShoppingList, renderCustomItems, animateAisle
};
```

Remove:
- All URL encoding/decoding (`encodeState`, `decodeState`, base-26 encoding)
- `parseStateFromUrl`, URL parameter handling
- QR code generation
- Share button/clipboard logic
- `buildRecipeIndex`, `buildAisleIndex`
- `aggregateQuantities` (server does this now)
- `updateGroceryList` (server does this now)
- `saveState`/`loadFromStorage` (replaced by sync module)

Keep (adapted):
- `animateCollapse`/`animateExpand` — aisle collapse animation
- Check-off interaction with strikethrough
- Custom item chip rendering
- Item count display
- Wake lock integration

**Step 1: Write the new groceries.js**

The file will be substantial (~400 lines). Key sections:

- `GrocerySync` module: ActionCable subscription, heartbeat timer, state fetch, action dispatch, pending queue, local storage cache
- `GroceryUI` module: render shopping list from JSON, manage checkbox states, custom items, aisle animation, item count, notifications
- Event listeners: checkbox changes, custom item add/remove, clear button
- Initialization: load from cache, fetch from server, subscribe to channel

**Step 2: Verify in browser**

Test scenarios:
- Select a recipe → shopping list appears
- Unselect → items disappear
- Check off item → strikethrough
- Add custom item → appears in Miscellaneous
- Open in two tabs → changes sync between them

**Step 3: Commit**

```bash
git add app/assets/javascripts/groceries.js && git commit -m "feat: rewrite groceries JS for server-driven state with ActionCable sync"
```

---

### Task 10: Update groceries CSS

**Files:**
- Modify: `app/assets/stylesheets/groceries.css`

**Step 1: Remove styles for deleted elements**

Remove:
- `#share-section`, `#qr-container`, `#share-url-row`, `#share-url`, `#share-action`, `#share-feedback` styles
- Any styles tied to the old static aisle list structure if the new structure differs

Add/update:
- Styles for dynamically-rendered aisle sections (the structure is the same `<details class="aisle">` pattern, just rendered by JS instead of ERB)
- Connection status indicator (optional — small dot showing online/offline)

Keep:
- Recipe selector grid, checkbox styling, Quick Bites subsections
- Custom items chip list
- Aisle collapse/expand animation
- Check-off strikethrough
- Item count
- Print styles (adapted for new structure)

**Step 2: Verify print styles still work**

Print preview the page, verify recipe selector and shopping list render cleanly.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/groceries.css && git commit -m "feat: update groceries CSS, remove share section styles"
```

---

### Task 11: Update tests for new groceries architecture

**Files:**
- Modify: `test/controllers/groceries_controller_test.rb`
- Modify: `test/integration/end_to_end_test.rb` (if grocery_aisles referenced)

**Step 1: Remove obsolete tests**

Remove from `test/controllers/groceries_controller_test.rb`:
- `test 'renders share section'` (lines 62-68)
- `test 'renders UNIT_PLURALS script'` (lines 70-75)
- `test 'recipe checkboxes include ingredient data as JSON'` (lines 202-229)
- `test 'renders aisle sections from grocery data'` (lines 38-45) — aisles are now rendered by JS
- `test 'does not render Omit_From_List aisle'` (lines 47-52) — same
- All `update_grocery_aisles` tests (lines 172-200)

**Step 2: Update remaining tests**

Update `test 'renders the groceries page with recipe checkboxes'` — assert `data-slug` instead of `data-ingredients`.

Add new tests for the state endpoint and API (from Task 7).

**Step 3: Run full test suite**

Run: `rake test`
Expected: all tests pass

**Step 4: Commit**

```bash
git add -A && git commit -m "test: update groceries tests for server-driven architecture"
```

---

### Task 12: Update CLAUDE.md and clean up

**Files:**
- Modify: `CLAUDE.md` (update model names, routes, architecture docs)
- Remove: `db/seeds/resources/grocery-info.yaml` (no longer needed at runtime; keep for historical reference or delete)
- Verify: no remaining references to `NutritionEntry`, `alias_map`, `grocery_aisles` SiteDocument

**Step 1: Search for stale references**

```bash
grep -r 'NutritionEntry' app/ lib/ test/ config/ db/seeds.rb bin/nutrition
grep -r 'alias_map' app/ lib/ test/
grep -r 'grocery_aisles' app/ lib/ test/ config/
grep -r 'parse_grocery_info' app/ lib/ test/
grep -r 'build_alias_map' app/ lib/ test/
```

Fix any remaining references found.

**Step 2: Update CLAUDE.md**

- Replace all `NutritionEntry` references with `IngredientProfile`
- Add `GroceryList` to the models section
- Add `ShoppingListBuilder` to services section
- Add `GroceryListChannel` to architecture
- Update routes section with new grocery API endpoints
- Remove alias_map references
- Update assets section (remove qrcodegen.js, note ActionCable JS)
- Note Solid Cable in deployment section

**Step 3: Run full test suite one final time**

Run: `rake`
Expected: lint + all tests pass

**Step 4: Commit**

```bash
git add -A && git commit -m "docs: update CLAUDE.md for IngredientProfile rename and shared groceries architecture"
```

# CatalogWriteService Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract post-save orchestration from NutritionEntriesController into CatalogWriteService, and replace the IngredientRows concern with an IngredientRowBuilder service class.

**Architecture:** Two new service classes replace a fat controller and a misplaced concern. CatalogWriteService mirrors RecipeWriteService's pattern (persistence + post-write pipeline). IngredientRowBuilder replaces the IngredientRows concern with explicit constructor args, eliminating the implicit `current_kitchen` dependency.

**Tech Stack:** Rails 8, Minitest, Turbo Streams, ActiveSupport::TestCase

---

### Task 1: Create IngredientRowBuilder — failing tests

**Files:**
- Create: `test/services/ingredient_row_builder_test.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class IngredientRowBuilderTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  test 'rows returns sorted ingredient rows from recipes' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups
      - Salt, 1 tsp

      Mix well.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    assert_equal 2, rows.size
    assert_equal 'Flour', rows.first[:name]
    assert_equal 'Salt', rows.last[:name]
    assert_equal 'missing', rows.first[:status]
  end

  test 'rows reflects catalog entry status' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110)

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups

      Mix.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    rows = builder.rows

    assert_equal 1, rows.size
    assert_equal 'incomplete', rows.first[:status]
    assert rows.first[:has_nutrition]
  end

  test 'summary counts statuses' do
    IngredientCatalog.create!(ingredient_name: 'Salt', basis_grams: 6, calories: 0,
                              density_grams: 6, density_volume: 1, density_unit: 'tsp')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups
      - Salt, 1 tsp

      Mix.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    summary = builder.summary

    assert_equal 2, summary[:total]
    assert_equal 1, summary[:complete]
    assert_equal 1, summary[:missing_nutrition]
  end

  test 'next_needing_attention finds next incomplete ingredient' do
    IngredientCatalog.create!(ingredient_name: 'Flour', basis_grams: 30, calories: 110,
                              density_grams: 30, density_volume: 0.25, density_unit: 'cup')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups
      - Salt, 1 tsp

      Mix.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)

    assert_equal 'Salt', builder.next_needing_attention(after: 'Flour')
  end

  test 'accepts precomputed lookup to avoid redundant query' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups

      Mix.
    MD

    lookup = IngredientCatalog.lookup_for(@kitchen)
    builder = IngredientRowBuilder.new(kitchen: @kitchen, lookup: lookup)
    rows = builder.rows

    assert_equal 1, rows.size
  end

  test 'accepts explicit recipes scope' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Focaccia

      Category: Bread

      ## Mix (combine)
      - Flour, 3 cups
      - Salt, 1 tsp

      Mix.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Bagels

      Category: Bread

      ## Mix (combine)
      - Flour, 4 cups
      - Sugar, 1 tbsp

      Mix.
    MD

    one_recipe = @kitchen.recipes.where(slug: 'focaccia').includes(steps: :ingredients)
    builder = IngredientRowBuilder.new(kitchen: @kitchen, recipes: one_recipe)
    rows = builder.rows

    names = rows.map { |r| r[:name] }

    assert_includes names, 'Flour'
    assert_includes names, 'Salt'
    refute_includes names, 'Sugar'
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: NameError — `uninitialized constant IngredientRowBuilder`

---

### Task 2: Create IngredientRowBuilder — implementation

**Files:**
- Create: `app/services/ingredient_row_builder.rb`

**Step 1: Write the implementation**

```ruby
# frozen_string_literal: true

# Builds ingredient table row data from recipes and the IngredientCatalog.
# Canonicalizes ingredient names through catalog lookup and Inflector variants.
# Pure data transform — takes kitchen, recipes, and lookup as explicit inputs.
#
# - IngredientCatalog: overlay model for nutrition/aisle metadata
# - FamilyRecipes::Inflector: variant matching for ingredient name normalization
# - IngredientsController, NutritionEntriesController, RecipeBroadcaster: consumers
class IngredientRowBuilder
  def initialize(kitchen:, recipes: nil, lookup: nil)
    @kitchen = kitchen
    @recipes = recipes || kitchen.recipes.includes(steps: :ingredients)
    @lookup  = lookup || IngredientCatalog.lookup_for(kitchen)
  end

  def rows
    index = recipes_by_ingredient
    index.sort_by { |name, _| name.downcase }.map { |name, recipes| ingredient_row(name, recipes) }
  end

  def summary
    all = rows
    { total: all.size,
      complete: all.count { |r| r[:status] == 'complete' },
      missing_nutrition: all.count { |r| !r[:has_nutrition] },
      missing_density: all.count { |r| r[:has_nutrition] && !r[:has_density] } }
  end

  def next_needing_attention(after:)
    sorted = recipes_by_ingredient.keys.sort_by(&:downcase)
    idx = sorted.index { |name| name.casecmp(after).zero? }
    return unless idx

    sorted[(idx + 1)..].find { |name| row_status(lookup[name]) != 'complete' }
  end

  private

  attr_reader :kitchen, :recipes, :lookup

  def ingredient_row(name, recipes)
    entry = lookup[name]
    { name:, entry:, recipe_count: recipes.size, recipes:,
      has_nutrition: entry&.basis_grams.present?,
      has_density: entry&.density_grams.present?,
      aisle: entry&.aisle,
      source: entry_source(entry),
      status: row_status(entry) }
  end

  def entry_source(entry)
    return 'missing' unless entry

    entry.custom? ? 'custom' : 'global'
  end

  def row_status(entry)
    return 'missing' if entry&.basis_grams.blank?
    return 'incomplete' if entry.density_grams.blank?

    'complete'
  end

  def recipes_by_ingredient
    @recipes_by_ingredient ||= build_recipes_by_ingredient
  end

  def build_recipes_by_ingredient
    seen = Hash.new { |h, k| h[k] = Set.new }

    recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
      recipe.ingredients.each do |ingredient|
        name = canonical_ingredient_name(ingredient.name, index)
        index[name] << recipe if seen[name].add?(recipe.id)
      end
    end
  end

  def canonical_ingredient_name(name, index)
    entry = lookup[name]
    return entry.ingredient_name if entry

    FamilyRecipes::Inflector.ingredient_variants(name).find { |v| index.key?(v) } || name
  end
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: All 6 tests pass

**Step 3: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "feat: extract IngredientRowBuilder from IngredientRows concern"
```

---

### Task 3: Migrate IngredientsController to IngredientRowBuilder

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`
- Test: `test/controllers/ingredients_controller_test.rb` (existing, no changes needed)

**Step 1: Update the controller**

Remove `include IngredientRows`. Replace with `IngredientRowBuilder` instantiation. The controller currently calls `build_ingredient_rows(catalog_lookup)`, `build_summary(rows)`, and `next_needing_attention(after:, lookup:)` — all provided by the builder.

```ruby
# frozen_string_literal: true

# Ingredients management page — member-only. Displays a searchable, filterable
# table of all ingredients across recipes with their nutrition/density status
# and aisle assignments. The edit action renders the nutrition editor form as a
# partial for the dialog. Uses IngredientRowBuilder for row-building logic
# shared with NutritionEntriesController and RecipeBroadcaster.
class IngredientsController < ApplicationController
  before_action :require_membership
  before_action :prevent_html_caching, only: :index

  def index
    @ingredient_rows = row_builder.rows
    @summary = row_builder.summary
    @available_aisles = current_kitchen.all_aisles
    @next_needing_attention = first_needing_attention
  end

  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles
    recipes = recipes_for_ingredient(ingredient_name)

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles,
                     next_name: row_builder.next_needing_attention(after: ingredient_name),
                     recipes: }
  end

  private

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def recipes_for_ingredient(name)
    raw_names = matching_raw_names(name)
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where(ingredients: { name: raw_names })
                   .distinct
  end

  def matching_raw_names(canonical_name)
    catalog_lookup.filter_map { |raw, entry| raw if entry.ingredient_name == canonical_name }
                  .push(canonical_name)
                  .uniq
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    [name, catalog_lookup[name]]
  end

  def catalog_lookup
    @catalog_lookup ||= IngredientCatalog.lookup_for(current_kitchen)
  end

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen, lookup: catalog_lookup)
  end

  def decoded_ingredient_name
    params[:ingredient_name]
  end
end
```

**Step 2: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All tests pass

**Step 3: Commit**

```bash
git add app/controllers/ingredients_controller.rb
git commit -m "refactor: migrate IngredientsController to IngredientRowBuilder"
```

---

### Task 4: Migrate RecipeBroadcaster to IngredientRowBuilder

**Files:**
- Modify: `app/services/recipe_broadcaster.rb`
- Test: `test/services/recipe_broadcaster_test.rb` (existing, no changes needed)

**Step 1: Update the broadcaster**

Remove `include IngredientRows`. Update `broadcast_ingredients` to use `IngredientRowBuilder`. The broadcaster already has `kitchen` and `catalog_lookup` available, and passes `recipes` explicitly.

In `recipe_broadcaster.rb`, change:

1. Remove line 12: `include IngredientRows`
2. Replace `broadcast_ingredients` method body:

```ruby
def broadcast_ingredients(recipes, catalog_lookup:)
  builder = IngredientRowBuilder.new(kitchen:, recipes:, lookup: catalog_lookup)

  Turbo::StreamsChannel.broadcast_replace_to(
    kitchen, 'recipes',
    target: 'ingredients-summary',
    partial: 'ingredients/summary_bar',
    locals: { summary: builder.summary }
  )
  Turbo::StreamsChannel.broadcast_replace_to(
    kitchen, 'recipes',
    target: 'ingredients-table',
    partial: 'ingredients/table',
    locals: { ingredient_rows: builder.rows }
  )
end
```

3. Update header comment: replace "IngredientRows concern" reference with "IngredientRowBuilder".

**Step 2: Run existing broadcaster tests**

Run: `ruby -Itest test/services/recipe_broadcaster_test.rb`
Expected: All tests pass

**Step 3: Commit**

```bash
git add app/services/recipe_broadcaster.rb
git commit -m "refactor: migrate RecipeBroadcaster to IngredientRowBuilder"
```

---

### Task 5: Create CatalogWriteService — failing tests

**Files:**
- Create: `test/services/catalog_write_service_test.rb`

**Step 1: Write the failing tests**

```ruby
# frozen_string_literal: true

require 'test_helper'

class CatalogWriteServiceTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen_id: [@kitchen.id, nil]).delete_all
  end

  VALID_PARAMS = {
    nutrients: { basis_grams: 30, calories: 110, fat: 0.5, saturated_fat: 0,
                 trans_fat: 0, cholesterol: 0, sodium: 5, carbs: 23,
                 fiber: 1, total_sugars: 0, added_sugars: 0, protein: 3 },
    density: { volume: 0.25, unit: 'cup', grams: 30 },
    portions: {}, aisle: 'Baking', aliases: nil
  }.freeze

  test 'upsert creates kitchen-scoped entry and returns persisted result' do
    result = CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour', params: VALID_PARAMS)

    assert_instance_of CatalogWriteService::Result, result
    assert result.persisted
    assert_equal 'flour', result.entry.ingredient_name
    assert_predicate result.entry, :custom?
    assert_in_delta 30.0, result.entry.basis_grams
  end

  test 'upsert updates existing entry' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour', basis_grams: 100, calories: 364)

    result = CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour', params: VALID_PARAMS)

    assert result.persisted
    assert_in_delta 30.0, result.entry.basis_grams
  end

  test 'upsert returns non-persisted result on validation failure' do
    bad_params = { nutrients: { basis_grams: 0, calories: 110 }, density: {}, portions: {}, aisle: nil, aliases: nil }

    result = CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour', params: bad_params)

    refute result.persisted
    assert result.entry.errors.any?
  end

  test 'upsert syncs new aisle to kitchen aisle_order' do
    CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour',
                               params: VALID_PARAMS.merge(aisle: 'Deli'))

    assert_includes @kitchen.reload.parsed_aisle_order, 'Deli'
  end

  test 'upsert does not sync omit aisle to kitchen' do
    CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour',
                               params: VALID_PARAMS.merge(aisle: 'omit'))

    refute_includes @kitchen.reload.parsed_aisle_order.to_a, 'omit'
  end

  test 'upsert does not duplicate existing aisle' do
    @kitchen.update!(aisle_order: "Produce\nBaking")

    CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour', params: VALID_PARAMS)

    assert_equal "Produce\nBaking", @kitchen.reload.aisle_order
  end

  test 'upsert recalculates affected recipes when nutrition present' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Test Bread

      Category: Bread
      Serves: 4

      ## Mix (combine)
      - Flour, 3 cups

      Mix well.
    MD

    recipe = @kitchen.recipes.find_by!(slug: 'test-bread')

    assert_nil recipe.nutrition_data

    CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'Flour', params: VALID_PARAMS)
    nutrition = recipe.reload.nutrition_data

    assert_not_nil nutrition
    assert_predicate nutrition.dig('per_serving', 'calories'), :positive?
  end

  test 'upsert broadcasts meal plan refresh when aisle present' do
    assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
      CatalogWriteService.upsert(kitchen: @kitchen, ingredient_name: 'flour', params: VALID_PARAMS)
    end
  end

  test 'destroy deletes kitchen entry' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour', basis_grams: 30, calories: 110)

    result = CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')

    assert result.persisted
    assert_nil IngredientCatalog.find_by(kitchen: @kitchen, ingredient_name: 'flour')
  end

  test 'destroy recalculates affected recipes' do
    IngredientCatalog.create!(kitchen_id: nil, ingredient_name: 'Flour',
                              basis_grams: 100, calories: 364)
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Flour',
                              basis_grams: 30, calories: 110,
                              density_grams: 30.0, density_volume: 0.25, density_unit: 'cup')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Test Bread

      Category: Bread
      Serves: 4

      ## Mix (combine)
      - Flour, 3 cups

      Mix.
    MD

    recipe = @kitchen.recipes.find_by!(slug: 'test-bread')
    RecipeNutritionJob.perform_now(recipe)

    assert_predicate recipe.reload.nutrition_data.dig('per_serving', 'calories'), :positive?

    CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'Flour')
    nutrition = recipe.reload.nutrition_data

    assert_not_nil nutrition
    assert_includes nutrition['partial_ingredients'], 'Flour'
  end

  test 'destroy broadcasts meal plan refresh' do
    IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'flour', basis_grams: 30, calories: 110)

    assert_turbo_stream_broadcasts [@kitchen, :meal_plan_updates] do
      CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'flour')
    end
  end

  test 'destroy raises RecordNotFound for missing entry' do
    assert_raises(ActiveRecord::RecordNotFound) do
      CatalogWriteService.destroy(kitchen: @kitchen, ingredient_name: 'nonexistent')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: NameError — `uninitialized constant CatalogWriteService`

---

### Task 6: Create CatalogWriteService — implementation

**Files:**
- Create: `app/services/catalog_write_service.rb`

**Step 1: Write the implementation**

```ruby
# frozen_string_literal: true

# Orchestrates IngredientCatalog create/update/destroy. Owns the full post-write
# pipeline: persist the entry, sync new aisles to the kitchen's aisle_order,
# recalculate nutrition for affected recipes, and broadcast a meal-plan refresh
# signal for cross-device sync. Mirrors RecipeWriteService's pattern.
#
# - IngredientCatalog: the overlay model being persisted
# - RecipeNutritionJob: synchronous nutrition recalculation per affected recipe
# - Kitchen: aisle_order sync target
# - Turbo::StreamsChannel: meal-plan refresh broadcast
class CatalogWriteService
  Result = Data.define(:entry, :persisted)

  WEB_SOURCE = [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }].freeze

  def self.upsert(kitchen:, ingredient_name:, params:)
    new(kitchen:).upsert(ingredient_name:, params:)
  end

  def self.destroy(kitchen:, ingredient_name:)
    new(kitchen:).destroy(ingredient_name:)
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def upsert(ingredient_name:, params:)
    entry = IngredientCatalog.find_or_initialize_by(kitchen:, ingredient_name:)
    entry.assign_from_params(**params, sources: WEB_SOURCE)
    return Result.new(entry:, persisted: false) unless entry.save

    post_write(entry.aisle, ingredient_name, has_nutrition: entry.basis_grams.present?)
    Result.new(entry:, persisted: true)
  end

  def destroy(ingredient_name:)
    entry = IngredientCatalog.find_by!(kitchen:, ingredient_name:)
    entry.destroy!
    post_write(nil, ingredient_name, has_nutrition: true)
    Result.new(entry:, persisted: true)
  end

  private

  attr_reader :kitchen

  def post_write(aisle, ingredient_name, has_nutrition:)
    sync_aisle_to_kitchen(aisle) if aisle && aisle != 'omit'
    recalculate_affected_recipes(ingredient_name) if has_nutrition
    broadcast_meal_plan_refresh
  end

  def sync_aisle_to_kitchen(aisle)
    return if kitchen.parsed_aisle_order.include?(aisle)

    existing = kitchen.aisle_order.to_s
    kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
  end

  def recalculate_affected_recipes(ingredient_name)
    canonical = ingredient_name.downcase
    kitchen.recipes
           .joins(steps: :ingredients)
           .where('LOWER(ingredients.name) = ?', canonical)
           .distinct
           .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end

  def broadcast_meal_plan_refresh
    Turbo::StreamsChannel.broadcast_refresh_to(kitchen, :meal_plan_updates)
  end
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/catalog_write_service_test.rb`
Expected: All 12 tests pass

**Step 3: Commit**

```bash
git add app/services/catalog_write_service.rb test/services/catalog_write_service_test.rb
git commit -m "feat: extract CatalogWriteService from NutritionEntriesController"
```

---

### Task 7: Slim NutritionEntriesController

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`
- Test: `test/controllers/nutrition_entries_controller_test.rb` (existing, no changes needed)

**Step 1: Rewrite the controller**

```ruby
# frozen_string_literal: true

# JSON/Turbo Stream API for creating, updating, and deleting kitchen-scoped
# IngredientCatalog entries from the web nutrition editor. Delegates persistence
# and post-write orchestration to CatalogWriteService; handles only param
# parsing and response rendering. Uses IngredientRowBuilder for Turbo Stream
# ingredient table updates.
#
# - CatalogWriteService: persistence + post-write pipeline (aisle sync, nutrition recalc, broadcast)
# - IngredientRowBuilder: ingredient table row data for Turbo Stream responses
class NutritionEntriesController < ApplicationController
  before_action :require_membership

  def upsert
    result = CatalogWriteService.upsert(
      kitchen: current_kitchen,
      ingredient_name:,
      params: catalog_params
    )
    return render_errors(result.entry) unless result.persisted

    respond_to do |format|
      format.turbo_stream { render_turbo_stream_update }
      format.json { render_json_response }
    end
  end

  def destroy
    CatalogWriteService.destroy(kitchen: current_kitchen, ingredient_name:)
    render json: { status: 'ok' }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def ingredient_name
    params[:ingredient_name]
  end

  def catalog_params
    { nutrients: permitted_nutrients, density: permitted_density,
      portions: permitted_portions, aisle: params[:aisle]&.strip.presence,
      aliases: permitted_aliases }
  end

  def permitted_nutrients
    return {} unless params[:nutrients]

    params[:nutrients].permit(:basis_grams, *IngredientCatalog::NUTRIENT_COLUMNS).to_h.symbolize_keys
  end

  def permitted_density
    return {} unless params[:density]

    params[:density].permit(:volume, :unit, :grams).to_h.symbolize_keys
  end

  def permitted_portions
    return {} unless params[:portions]

    params[:portions].permit!.to_h.select { |k, v| k.size <= 50 && v.to_s.match?(/\A[\d.]+\z/) }
  end

  def permitted_aliases
    return unless params.key?(:aliases)

    Array(params[:aliases]).map { |a| a.to_s.strip }.compact_blank.uniq.first(20)
  end

  def render_errors(entry)
    render json: { errors: entry.errors.full_messages }, status: :unprocessable_content
  end

  def render_json_response
    response_body = { status: 'ok' }
    if params[:save_and_next]
      response_body[:next_ingredient] = row_builder.next_needing_attention(after: ingredient_name)
    end
    render json: response_body
  end

  def render_turbo_stream_update
    builder = row_builder
    all_rows = builder.rows
    @updated_row = all_rows.find { |r| r[:name].casecmp(ingredient_name).zero? }
    @summary = builder.summary
    @next_ingredient = builder.next_needing_attention(after: ingredient_name) if params[:save_and_next]

    render :upsert
  end

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen)
  end
end
```

**Step 2: Run existing controller tests to verify nothing broke**

Run: `ruby -Itest test/controllers/nutrition_entries_controller_test.rb`
Expected: All tests pass

**Step 3: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb
git commit -m "refactor: slim NutritionEntriesController — delegate to CatalogWriteService"
```

---

### Task 8: Delete IngredientRows concern

**Files:**
- Delete: `app/controllers/concerns/ingredient_rows.rb`

**Step 1: Delete the file**

```bash
git rm app/controllers/concerns/ingredient_rows.rb
```

**Step 2: Run the full test suite to verify no remaining references**

Run: `rake test`
Expected: All tests pass — no file references the deleted concern

**Step 3: Commit**

```bash
git commit -m "chore: remove IngredientRows concern — replaced by IngredientRowBuilder"
```

---

### Task 9: Update header comments and html_safe allowlist

**Files:**
- Modify: `app/services/recipe_broadcaster.rb` (header comment — if not already updated in Task 4)
- Modify: `app/controllers/ingredients_controller.rb` (header comment — if not already updated in Task 3)
- Verify: `config/html_safe_allowlist.yml` — check if any line numbers shifted

**Step 1: Verify header comments are accurate**

Read each modified file's header comment. Ensure:
- `RecipeBroadcaster` references `IngredientRowBuilder`, not `IngredientRows`
- `IngredientsController` references `IngredientRowBuilder`, not the concern
- `NutritionEntriesController` references `CatalogWriteService` and `IngredientRowBuilder`

**Step 2: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: Pass. If line numbers shifted in any file with `.html_safe` calls, update `config/html_safe_allowlist.yml`.

**Step 3: Run full suite + lint**

Run: `rake`
Expected: All tests pass, 0 RuboCop offenses

**Step 4: Commit any remaining updates**

```bash
git add -A
git commit -m "docs: update header comments for CatalogWriteService extraction"
```

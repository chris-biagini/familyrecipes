# IngredientResolver Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Unify divergent canonical-name resolution into a single `IngredientResolver` class, eliminating ad-hoc fallback logic in ShoppingListBuilder, RecipeAvailabilityCalculator, and IngredientRowBuilder.

**Architecture:** A new `IngredientResolver` wraps the existing `IngredientCatalog.lookup_for` hash with a three-step resolution cascade (exact → case-insensitive → uncataloged variant collapsing). A factory method `IngredientCatalog.resolver_for(kitchen)` constructs it. Callers switch from raw hash access to `resolver.resolve(name)`.

**Tech Stack:** Ruby, Rails 8, Minitest, IngredientCatalog (AR model), FamilyRecipes::Inflector

---

### Task 0: Create feature branch

**Step 1: Create and switch to branch**

```bash
git checkout -b ingredient-resolver
```

**Step 2: Verify clean state**

```bash
git status
```

Expected: clean working tree on `ingredient-resolver` branch.

---

### Task 1: Write failing tests for IngredientResolver

**Files:**
- Create: `test/services/ingredient_resolver_test.rb`

This is a pure unit test file — hand-built lookup hashes, no database. We use lightweight structs to simulate `IngredientCatalog` AR objects.

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require 'test_helper'

class IngredientResolverTest < ActiveSupport::TestCase
  FakeEntry = Struct.new(:ingredient_name, :aisle, :aliases, keyword_init: true) do
    def basis_grams = nil
    def density_grams = nil
  end

  setup do
    @eggs = FakeEntry.new(ingredient_name: 'Eggs', aisle: 'Refrigerated', aliases: [])
    @flour = FakeEntry.new(ingredient_name: 'Flour', aisle: 'Baking', aliases: ['AP flour'])
    @parmesan = FakeEntry.new(ingredient_name: 'Parmesan', aisle: 'Dairy', aliases: ['parmesan cheese'])

    # Simulate what IngredientCatalog.lookup_for produces:
    # canonical names + inflector variants + alias variants
    @lookup = {
      'Eggs' => @eggs, 'Egg' => @eggs,
      'Flour' => @flour, 'AP flour' => @flour, 'ap flour' => @flour, 'AP Flour' => @flour,
      'Parmesan' => @parmesan, 'parmesan cheese' => @parmesan, 'Parmesan Cheese' => @parmesan
    }
  end

  # --- resolve: exact match ---

  test 'resolves exact catalog match' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('Eggs')
  end

  test 'resolves inflector variant to canonical name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('Egg')
  end

  test 'resolves alias to canonical name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Flour', resolver.resolve('AP flour')
  end

  # --- resolve: case-insensitive fallback ---

  test 'resolves case-insensitive match when exact misses' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Eggs', resolver.resolve('eggs')
    assert_equal 'Eggs', resolver.resolve('EGGS')
    assert_equal 'Flour', resolver.resolve('flour')
  end

  test 'resolves alias case-insensitively' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Parmesan', resolver.resolve('PARMESAN CHEESE')
  end

  # --- resolve: uncataloged names ---

  test 'returns raw name for uncataloged ingredient' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Seltzer', resolver.resolve('Seltzer')
  end

  test 'collapses uncataloged names case-insensitively to first-seen' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Seltzer', resolver.resolve('Seltzer')
    assert_equal 'Seltzer', resolver.resolve('seltzer')
    assert_equal 'Seltzer', resolver.resolve('SELTZER')
  end

  test 'collapses uncataloged inflector variants to first-seen' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Onion', resolver.resolve('Onion')
    assert_equal 'Onion', resolver.resolve('Onions')
  end

  test 'collapses uncataloged inflector variants when plural seen first' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal 'Onions', resolver.resolve('Onions')
    assert_equal 'Onions', resolver.resolve('Onion')
  end

  # --- resolve: never nil ---

  test 'never returns nil' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal '', resolver.resolve('')
    assert_equal 'Unknown', resolver.resolve('Unknown')
  end

  # --- catalog_entry ---

  test 'catalog_entry returns AR object for cataloged name' do
    resolver = IngredientResolver.new(@lookup)

    assert_equal @eggs, resolver.catalog_entry('Eggs')
    assert_equal @eggs, resolver.catalog_entry('Egg')
    assert_equal @eggs, resolver.catalog_entry('eggs')
  end

  test 'catalog_entry returns nil for uncataloged name' do
    resolver = IngredientResolver.new(@lookup)

    assert_nil resolver.catalog_entry('Seltzer')
  end

  # --- cataloged? ---

  test 'cataloged? returns true for known ingredients' do
    resolver = IngredientResolver.new(@lookup)

    assert resolver.cataloged?('Eggs')
    assert resolver.cataloged?('eggs')
    assert resolver.cataloged?('Egg')
  end

  test 'cataloged? returns false for unknown ingredients' do
    resolver = IngredientResolver.new(@lookup)

    assert_not resolver.cataloged?('Seltzer')
  end

  # --- all_keys_for ---

  test 'all_keys_for returns all lookup keys mapping to canonical name' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Eggs')

    assert_includes keys, 'Eggs'
    assert_includes keys, 'Egg'
    assert_equal 2, keys.size
  end

  test 'all_keys_for includes the canonical name even if not a lookup key' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Flour')

    assert_includes keys, 'Flour'
    assert_includes keys, 'AP flour'
    assert_includes keys, 'ap flour'
    assert_includes keys, 'AP Flour'
  end

  test 'all_keys_for returns array with just the name for uncataloged ingredients' do
    resolver = IngredientResolver.new(@lookup)
    keys = resolver.all_keys_for('Seltzer')

    assert_equal ['Seltzer'], keys
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
ruby -Itest test/services/ingredient_resolver_test.rb
```

Expected: `NameError: uninitialized constant IngredientResolver`

---

### Task 2: Implement IngredientResolver

**Files:**
- Create: `app/services/ingredient_resolver.rb`

**Step 1: Write the implementation**

```ruby
# frozen_string_literal: true

# Single source of truth for resolving ingredient names to their canonical form.
# Wraps an IngredientCatalog lookup hash with a three-step cascade: exact match,
# case-insensitive fallback, and uncataloged variant collapsing via Inflector.
# Stateful within a request — accumulates uncataloged names so that differently-
# cased or inflected forms of the same unknown ingredient collapse to one canonical
# name across all services sharing this resolver.
#
# Collaborators:
# - IngredientCatalog.resolver_for(kitchen) — factory entry point
# - ShoppingListBuilder, RecipeAvailabilityCalculator, IngredientRowBuilder — consumers
# - FamilyRecipes::Inflector — variant generation for uncataloged fallback
class IngredientResolver
  attr_reader :lookup

  def initialize(lookup)
    @lookup = lookup
    @ci_lookup = lookup.each_with_object({}) { |(k, v), h| h[k.downcase] ||= v }
    @uncataloged = {}
  end

  def resolve(name)
    entry = find_entry(name)
    return entry.ingredient_name if entry

    resolve_uncataloged(name)
  end

  def catalog_entry(name)
    find_entry(name)
  end

  def cataloged?(name)
    find_entry(name).present?
  end

  def all_keys_for(canonical_name)
    keys = @lookup.filter_map { |raw, entry| raw if entry.ingredient_name == canonical_name }
    keys.push(canonical_name) unless keys.include?(canonical_name)
    keys
  end

  private

  def find_entry(name)
    @lookup[name] || @ci_lookup[name.downcase]
  end

  def resolve_uncataloged(name)
    return name if name.blank?

    downcased = name.downcase
    return @uncataloged[downcased] if @uncataloged.key?(downcased)

    existing = find_variant_match(name)
    return existing if existing

    @uncataloged[downcased] = name
  end

  def find_variant_match(name)
    FamilyRecipes::Inflector.ingredient_variants(name).each do |variant|
      canonical = @uncataloged[variant.downcase]
      return register_alias(name, canonical) if canonical
    end
    nil
  end

  def register_alias(name, canonical)
    @uncataloged[name.downcase] = canonical
    canonical
  end
end
```

**Step 2: Run tests to verify they pass**

```bash
ruby -Itest test/services/ingredient_resolver_test.rb
```

Expected: All tests pass.

**Step 3: Run full test suite to ensure no regressions**

```bash
rake test
```

Expected: All existing tests still pass.

**Step 4: Commit**

```bash
git add app/services/ingredient_resolver.rb test/services/ingredient_resolver_test.rb
git commit -m "feat: add IngredientResolver with unified name resolution

Three-step cascade: exact → case-insensitive → uncataloged variant
collapsing. Wraps existing lookup_for hash without modifying it."
```

---

### Task 3: Add factory method to IngredientCatalog

**Files:**
- Modify: `app/models/ingredient_catalog.rb`
- Test: `test/services/ingredient_resolver_test.rb` (add integration test)

**Step 1: Write the failing test**

Add to the bottom of `test/services/ingredient_resolver_test.rb`:

```ruby
  # --- factory ---

  test 'IngredientCatalog.resolver_for returns an IngredientResolver' do
    setup_test_kitchen
    resolver = IngredientCatalog.resolver_for(@kitchen)

    assert_instance_of IngredientResolver, resolver
    assert_kind_of Hash, resolver.lookup
  end
```

**Step 2: Run test to verify it fails**

```bash
ruby -Itest test/services/ingredient_resolver_test.rb -n test_IngredientCatalog.resolver_for_returns_an_IngredientResolver
```

Expected: `NoMethodError: undefined method 'resolver_for'`

**Step 3: Add the factory method**

In `app/models/ingredient_catalog.rb`, add after the `lookup_for` method (after line 57):

```ruby
  def self.resolver_for(kitchen)
    IngredientResolver.new(lookup_for(kitchen))
  end
```

**Step 4: Run test to verify it passes**

```bash
ruby -Itest test/services/ingredient_resolver_test.rb -n test_IngredientCatalog.resolver_for_returns_an_IngredientResolver
```

Expected: PASS

**Step 5: Commit**

```bash
git add app/models/ingredient_catalog.rb test/services/ingredient_resolver_test.rb
git commit -m "feat: add IngredientCatalog.resolver_for factory method"
```

---

### Task 4: Migrate ShoppingListBuilder to IngredientResolver

**Files:**
- Modify: `app/services/shopping_list_builder.rb`
- Modify: `test/services/shopping_list_builder_test.rb`

This is the most complex migration — ShoppingListBuilder has the most ad-hoc resolution logic to remove.

**Step 1: Update the constructor and remove ad-hoc resolution**

Replace ShoppingListBuilder's constructor and private resolution methods. The key changes:
- `catalog_lookup:` keyword becomes `resolver:`
- Remove `@profiles`, `@profiles_ci`, `@uncataloged_names`
- `canonical_name` delegates to `@resolver.resolve`
- `organize_by_aisle` uses `@resolver.catalog_entry` for aisle/omit lookups

```ruby
# In initialize: replace catalog_lookup parameter and internal state
def initialize(kitchen:, meal_plan:, resolver: nil)
  @kitchen = kitchen
  @meal_plan = meal_plan
  @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
end
```

Replace `canonical_name`:

```ruby
def canonical_name(name)
  @resolver.resolve(name)
end
```

Replace `organize_by_aisle` to use resolver for entry lookups:

```ruby
def organize_by_aisle(ingredients)
  visible = ingredients.reject { |name, _| @resolver.catalog_entry(name)&.aisle == 'omit' }
  grouped = visible.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(name, entry), result|
    target_aisle = @resolver.catalog_entry(name)&.aisle || 'Miscellaneous'
    result[target_aisle] << { name: name, amounts: serialize_amounts(entry[:amounts]), sources: entry[:sources] }
  end

  sort_aisles(grouped)
end
```

**Step 2: Run existing tests — they should all pass without test changes**

```bash
ruby -Itest test/services/shopping_list_builder_test.rb
```

Expected: All 18 tests pass. The constructor accepts `resolver:` with a fallback to `IngredientCatalog.resolver_for`, so existing tests that don't pass either keyword still work.

**Step 3: Commit**

```bash
git add app/services/shopping_list_builder.rb
git commit -m "refactor: migrate ShoppingListBuilder to IngredientResolver

Remove @profiles, @profiles_ci, @uncataloged_names and ad-hoc
canonical_name. Delegate to resolver.resolve and resolver.catalog_entry."
```

---

### Task 5: Migrate RecipeAvailabilityCalculator to IngredientResolver

**Files:**
- Modify: `app/services/recipe_availability_calculator.rb`
- Modify: `test/services/recipe_availability_calculator_test.rb`

**Step 1: Update the service**

Replace `catalog_lookup:` with `resolver:`, remove `@profiles` and `canonical_name`, use resolver for omit set:

```ruby
def initialize(kitchen:, checked_off:, resolver: nil)
  @kitchen = kitchen
  @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
  @checked_off = Set.new(checked_off.map { |name| @resolver.resolve(name) })
  @omitted = build_omit_set
end
```

Replace `canonical_name`:

```ruby
def canonical_name(name)
  @resolver.resolve(name)
end
```

Replace `build_omit_set`:

```ruby
def build_omit_set
  seen = Set.new
  @resolver.lookup.each_value.with_object(Set.new) do |entry, set|
    next unless entry.aisle == 'omit'
    set.add(entry.ingredient_name) if seen.add?(entry.ingredient_name)
  end
end
```

**Step 2: Run existing tests**

```bash
ruby -Itest test/services/recipe_availability_calculator_test.rb
```

Expected: All 8 tests pass.

**Step 3: Add a test for the CI resolution bug this whole effort fixes**

Append to `test/services/recipe_availability_calculator_test.rb`:

```ruby
  test 'resolves checked-off names case-insensitively' do
    result = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen,
      checked_off: %w[flour salt]
    ).call

    assert_equal 0, result['focaccia'][:missing],
                 'Checking off "flour" (lowercase) should satisfy "Flour" (capitalized)'
  end
```

**Step 4: Run new test**

```bash
ruby -Itest test/services/recipe_availability_calculator_test.rb -n test_resolves_checked-off_names_case-insensitively
```

Expected: PASS (the resolver's CI fallback handles this).

**Step 5: Commit**

```bash
git add app/services/recipe_availability_calculator.rb test/services/recipe_availability_calculator_test.rb
git commit -m "refactor: migrate RecipeAvailabilityCalculator to IngredientResolver

Gains case-insensitive resolution and uncataloged variant collapsing
that were previously missing. Fixes availability dot desync."
```

---

### Task 6: Migrate IngredientRowBuilder to IngredientResolver

**Files:**
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `test/services/ingredient_row_builder_test.rb`

**Step 1: Update the service**

Replace `lookup:` with `resolver:`, remove the runtime Inflector fallback:

Constructor:

```ruby
def initialize(kitchen:, recipes: nil, resolver: nil)
  @kitchen = kitchen
  @recipes = recipes || kitchen.recipes.includes(steps: :ingredients)
  @resolver = resolver || IngredientCatalog.resolver_for(kitchen)
end
```

Expose lookup via resolver for callers that need raw hash access:

```ruby
attr_reader :kitchen, :recipes

def lookup
  @resolver.lookup
end
```

Replace `canonical_ingredient_name` — the `index` parameter is no longer needed:

```ruby
def canonical_ingredient_name(name)
  @resolver.resolve(name)
end
```

Update `compute_recipes_by_ingredient` to drop the `index` argument:

```ruby
def compute_recipes_by_ingredient
  seen = Hash.new { |h, k| h[k] = Set.new }

  recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
    recipe.ingredients.each do |ingredient|
      name = canonical_ingredient_name(ingredient.name)
      index[name] << recipe if seen[name].add?(recipe.id)
    end
  end
end
```

Update `ingredient_row` to use resolver for entry lookups:

```ruby
def ingredient_row(name, recs)
  entry = @resolver.catalog_entry(name)
  { name:, entry:, recipe_count: recs.size, recipes: recs,
    has_nutrition: entry&.basis_grams.present?,
    has_density: entry&.density_grams.present?,
    aisle: entry&.aisle,
    source: entry_source(entry),
    status: row_status(entry) }
end
```

Update `next_needing_attention` to use resolver for status check:

```ruby
def next_needing_attention(after:)
  sorted = recipes_by_ingredient.keys.sort_by(&:downcase)
  idx = sorted.index { |name| name.casecmp(after).zero? }
  return unless idx

  sorted[(idx + 1)..].find { |name| row_status(@resolver.catalog_entry(name)) != 'complete' }
end
```

**Step 2: Update the "precomputed lookup" test**

The test `accepts precomputed lookup to avoid redundant query` passes `lookup:` — update it to pass `resolver:`:

```ruby
  test 'accepts precomputed resolver to avoid redundant query' do
    create_catalog_entry('Flour', basis_grams: 30, aisle: 'Baking')
    resolver = IngredientCatalog.resolver_for(@kitchen)

    builder = IngredientRowBuilder.new(kitchen: @kitchen, resolver:)
    rows = builder.rows

    flour = rows.find { |r| r[:name] == 'Flour' }

    assert_equal 'Baking', flour[:aisle]
    assert_equal 'global', flour[:source]
  end
```

**Step 3: Run all IngredientRowBuilder tests**

```bash
ruby -Itest test/services/ingredient_row_builder_test.rb
```

Expected: All tests pass.

**Step 4: Commit**

```bash
git add app/services/ingredient_row_builder.rb test/services/ingredient_row_builder_test.rb
git commit -m "refactor: migrate IngredientRowBuilder to IngredientResolver

Remove runtime Inflector fallback and peer-index scanning. The
resolver's cascade handles variant collapsing for all cases."
```

---

### Task 7: Migrate IngredientsController

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`

**Step 1: Update the controller**

Replace `catalog_lookup` with `resolver`, update `row_builder` and `matching_raw_names`:

```ruby
  private

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen, resolver:)
  end

  def resolver
    @resolver ||= IngredientCatalog.resolver_for(current_kitchen)
  end

  def first_needing_attention
    row = @ingredient_rows.find { |r| r[:status] != 'complete' }
    row&.fetch(:name)
  end

  def recipes_for_ingredient(name)
    raw_names = resolver.all_keys_for(name)
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where(ingredients: { name: raw_names })
                   .distinct
  end

  def load_ingredient_data
    name = decoded_ingredient_name
    [name, resolver.catalog_entry(name)]
  end

  def decoded_ingredient_name
    params[:ingredient_name]
  end
```

Remove the `catalog_lookup` and `matching_raw_names` methods entirely.

**Step 2: Run controller tests**

```bash
ruby -Itest test/controllers/ingredients_controller_test.rb
```

Expected: All tests pass.

**Step 3: Commit**

```bash
git add app/controllers/ingredients_controller.rb
git commit -m "refactor: migrate IngredientsController to IngredientResolver

Replace catalog_lookup hash and matching_raw_names with resolver.
Uses resolver.all_keys_for for reverse lookup."
```

---

### Task 8: Migrate NutritionEntriesController

**Files:**
- Modify: `app/controllers/nutrition_entries_controller.rb`

**Step 1: Update the controller**

Replace the `row_builder` method to pass a resolver:

```ruby
  def resolver
    @resolver ||= IngredientCatalog.resolver_for(current_kitchen)
  end

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen, resolver:)
  end
```

**Step 2: Run controller tests**

```bash
ruby -Itest test/controllers/nutrition_entries_controller_test.rb
```

Expected: All tests pass.

**Step 3: Commit**

```bash
git add app/controllers/nutrition_entries_controller.rb
git commit -m "refactor: migrate NutritionEntriesController to IngredientResolver

Fixes the inconsistency where this controller constructed
IngredientRowBuilder without passing a lookup."
```

---

### Task 9: Migrate RecipeBroadcaster

**Files:**
- Modify: `app/services/recipe_broadcaster.rb`

**Step 1: Update broadcast_ingredients**

Replace the `catalog_lookup` usage with a resolver:

In the `broadcast` method, change:

```ruby
catalog_lookup = IngredientCatalog.lookup_for(kitchen)
```

to:

```ruby
resolver = IngredientCatalog.resolver_for(kitchen)
```

And update the call:

```ruby
broadcast_ingredients(categories.flat_map(&:recipes), resolver:)
```

Update `broadcast_ingredients`:

```ruby
def broadcast_ingredients(recipes, resolver:)
  builder = IngredientRowBuilder.new(kitchen:, recipes:, resolver:)

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

**Step 2: Run broadcaster tests**

```bash
ruby -Itest test/services/recipe_broadcaster_test.rb
```

Expected: All tests pass.

**Step 3: Run full test suite**

```bash
rake test
```

Expected: All tests pass.

**Step 4: Commit**

```bash
git add app/services/recipe_broadcaster.rb
git commit -m "refactor: migrate RecipeBroadcaster to IngredientResolver"
```

---

### Task 10: Add regression test and update header comments

**Files:**
- Create: `test/services/ingredient_resolver_regression_test.rb`
- Modify: `app/services/shopping_list_builder.rb` (header comment)
- Modify: `app/services/recipe_availability_calculator.rb` (header comment)
- Modify: `app/services/ingredient_row_builder.rb` (header comment)

**Step 1: Write the regression test**

This is the integration test from the design doc — two recipes with differently-cased ingredient names, verifying both ShoppingListBuilder and RecipeAvailabilityCalculator agree.

```ruby
# frozen_string_literal: true

require 'test_helper'

class IngredientResolverRegressionTest < ActiveSupport::TestCase
  setup do
    setup_test_kitchen
    setup_test_category(name: 'Italian')

    create_catalog_entry('Parmesan', basis_grams: 10, aisle: 'Dairy')

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Pasta Alfredo

      Category: Italian

      ## Cook (toss)

      - Parmesan, 1 cup

      Toss.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Caesar Salad

      Category: Italian

      ## Toss (combine)

      - parmesan, 0.5 cup

      Toss.
    MD
  end

  test 'shopping list and availability agree on canonical name for different casings' do
    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'pasta-alfredo', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'caesar-salad', selected: true)

    resolver = IngredientCatalog.resolver_for(@kitchen)

    shopping = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).build
    all_names = shopping.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('parmesan').zero? },
                 'Expected one Parmesan entry in shopping list'
    assert_includes all_names, 'Parmesan',
                    'Expected canonical catalog name, not lowercase variant'

    plan.apply_action('check', name: 'Parmesan', checked: true)
    checked_off = plan.state.fetch('checked_off', [])

    availability = RecipeAvailabilityCalculator.new(
      kitchen: @kitchen, checked_off:, resolver:
    ).call

    assert_equal 0, availability['pasta-alfredo'][:missing],
                 'Parmesan checked off should satisfy Pasta Alfredo'
    assert_equal 0, availability['caesar-salad'][:missing],
                 'Parmesan checked off should satisfy Caesar Salad (lowercase "parmesan" in recipe)'
  end

  test 'uncataloged ingredients collapse across services with shared resolver' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Bruschetta

      Category: Italian

      ## Top (assemble)

      - Balsamic glaze, 2 tbsp

      Top.
    MD

    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Caprese

      Category: Italian

      ## Drizzle (serve)

      - balsamic glaze, 1 tbsp

      Drizzle.
    MD

    plan = MealPlan.for_kitchen(@kitchen)
    plan.apply_action('select', type: 'recipe', slug: 'bruschetta', selected: true)
    plan.apply_action('select', type: 'recipe', slug: 'caprese', selected: true)

    resolver = IngredientCatalog.resolver_for(@kitchen)
    shopping = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: plan, resolver:).build
    all_names = shopping.values.flatten.pluck(:name)

    assert_equal 1, all_names.count { |n| n.casecmp('balsamic glaze').zero? },
                 'Expected one Balsamic glaze entry, not two'
  end
end
```

**Step 2: Run the regression test**

```bash
ruby -Itest test/services/ingredient_resolver_regression_test.rb
```

Expected: All tests pass.

**Step 3: Update header comments**

Update the header comments on `ShoppingListBuilder`, `RecipeAvailabilityCalculator`, and `IngredientRowBuilder` to reference `IngredientResolver` instead of describing their own resolution logic.

ShoppingListBuilder header:

```ruby
# Produces the grocery shopping list from a MealPlan's selected recipes and quick
# bites. Aggregates ingredient quantities (via IngredientAggregator), resolves
# names through IngredientResolver, organizes items by grocery aisle, appends
# custom items, and sorts aisles by the kitchen's user-defined order.
#
# Collaborators:
# - IngredientResolver: canonical name resolution and catalog entry lookup
# - IngredientAggregator: merges quantities across recipes
# - GroceriesController#show and MealPlan.prune_stale_items: consumers
```

RecipeAvailabilityCalculator header:

```ruby
# Computes per-recipe and per-quick-bite ingredient availability for the menu
# page's "availability dots." For each recipe/quick bite, reports how many
# ingredients are still needed (not yet checked off on the grocery list).
#
# Collaborators:
# - IngredientResolver: canonical name resolution (case-insensitive, variant-aware)
# - MenuController: consumer for availability dot rendering
```

IngredientRowBuilder header:

```ruby
# Builds ingredient table row data for the ingredients index page, Turbo Stream
# updates, and real-time broadcasts. Resolves ingredient names through
# IngredientResolver, then computes nutrition/density status for each unique
# ingredient across all recipes.
#
# Collaborators:
# - IngredientResolver: canonical name resolution and catalog entry lookup
# - IngredientsController, NutritionEntriesController, RecipeBroadcaster: consumers
```

**Step 4: Run full test suite and lint**

```bash
rake
```

Expected: All tests pass, zero RuboCop offenses.

**Step 5: Commit**

```bash
git add test/services/ingredient_resolver_regression_test.rb app/services/shopping_list_builder.rb app/services/recipe_availability_calculator.rb app/services/ingredient_row_builder.rb
git commit -m "test: add regression tests for cross-service name resolution

Verifies ShoppingListBuilder and RecipeAvailabilityCalculator agree on
canonical names for differently-cased and uncataloged ingredients.
Updates header comments to reference IngredientResolver."
```

---

### Task 11: Update CLAUDE.md and clean up

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the Architecture section**

Add a mention of `IngredientResolver` in the nutrition pipeline paragraph. After the sentence about `IngredientRowBuilder`, add:

> `IngredientResolver` is the single resolution point for ingredient names — wraps `IngredientCatalog.lookup_for` with case-insensitive fallback and uncataloged variant collapsing. Constructed via `IngredientCatalog.resolver_for(kitchen)`, shared across services within a request.

**Step 2: Run full suite one final time**

```bash
rake
```

Expected: All tests pass, zero offenses.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add IngredientResolver to CLAUDE.md architecture section"
```

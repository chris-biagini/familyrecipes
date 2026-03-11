# Web Ingredient Editor Data Layer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Move USDA search/import capabilities into Rails services and controllers, add unit resolution to the editor form, and clean up the TUI-only code path in UsdaClient.

**Architecture:** New `UsdaImportService` (pure data transform) + `UsdaSearchController` (two JSON endpoints) + `needed_units` on `IngredientRowBuilder`. Controller reads API key from `current_kitchen.usda_api_key`.

**Tech Stack:** Rails 8, Minitest, existing `UsdaClient` + `UsdaPortionClassifier`

---

### Task 1: `UsdaImportService` — Tests

**Files:**
- Create: `test/services/usda_import_service_test.rb`

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require 'test_helper'

class UsdaImportServiceTest < ActiveSupport::TestCase
  USDA_DETAIL = {
    fdc_id: 9003,
    description: 'Apples, raw, with skin',
    data_type: 'SR Legacy',
    nutrients: {
      'basis_grams' => 100.0, 'calories' => 52.0, 'fat' => 0.17,
      'saturated_fat' => 0.028, 'trans_fat' => 0.0, 'cholesterol' => 0.0,
      'sodium' => 1.0, 'carbs' => 13.81, 'fiber' => 2.4,
      'total_sugars' => 10.39, 'added_sugars' => 0.0, 'protein' => 0.26
    },
    portions: [
      { modifier: 'cup, quartered or chopped', grams: 125.0, amount: 1.0 },
      { modifier: 'cup slices', grams: 109.0, amount: 1.0 },
      { modifier: 'large (3-1/4" dia)', grams: 223.0, amount: 1.0 },
      { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 },
      { modifier: 'small (2-3/4" dia)', grams: 149.0, amount: 1.0 },
      { modifier: 'NLEA serving', grams: 242.0, amount: 1.0 }
    ]
  }.freeze

  test 'maps nutrients to catalog schema' do
    result = UsdaImportService.call(USDA_DETAIL)

    assert_equal 100.0, result.nutrients[:basis_grams]
    assert_in_delta 52.0, result.nutrients[:calories]
    assert_in_delta 0.17, result.nutrients[:fat]
    assert_in_delta 13.81, result.nutrients[:carbs]
  end

  test 'auto-picks density from largest per-unit volume candidate' do
    result = UsdaImportService.call(USDA_DETAIL)

    assert_predicate result.density, :present?
    assert_equal 'cup', result.density[:unit]
    assert_in_delta 1.0, result.density[:volume]
    assert result.density[:grams].positive?
  end

  test 'returns nil density when no volume candidates' do
    detail = USDA_DETAIL.merge(portions: [
      { modifier: 'large', grams: 223.0, amount: 1.0 }
    ])

    result = UsdaImportService.call(detail)

    assert_nil result.density
  end

  test 'builds source metadata' do
    result = UsdaImportService.call(USDA_DETAIL)

    assert_equal 'usda', result.source[:type]
    assert_equal 'SR Legacy', result.source[:dataset]
    assert_equal 9003, result.source[:fdc_id]
    assert_equal 'Apples, raw, with skin', result.source[:description]
  end

  test 'extracts portion candidates with display names' do
    result = UsdaImportService.call(USDA_DETAIL)

    names = result.portions.pluck(:name)

    assert_includes names, 'large'
    assert_includes names, 'medium'
    assert_includes names, 'small'
  end

  test 'includes density candidates for informational display' do
    result = UsdaImportService.call(USDA_DETAIL)

    assert_predicate result.density_candidates, :present?
    assert result.density_candidates.all? { |c| c.key?(:modifier) }
  end

  test 'handles empty portions gracefully' do
    detail = USDA_DETAIL.merge(portions: [])

    result = UsdaImportService.call(detail)

    assert_nil result.density
    assert_empty result.portions
    assert_empty result.density_candidates
  end
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/services/usda_import_service_test.rb`
Expected: LoadError or NameError — `UsdaImportService` doesn't exist yet.

**Step 3: Commit**

```bash
git add test/services/usda_import_service_test.rb
git commit -m "test: add UsdaImportService tests (red)"
```

---

### Task 2: `UsdaImportService` — Implementation

**Files:**
- Create: `app/services/usda_import_service.rb`

**Step 1: Implement the service**

```ruby
# frozen_string_literal: true

# Transforms raw USDA FoodData Central detail (from UsdaClient#fetch) into
# structured form values for the ingredient editor. Extracts nutrients, auto-
# picks density from the largest volume-based portion candidate, and classifies
# portions into informational categories. Pure data transformation — no
# persistence, no side effects.
#
# Collaborators:
# - UsdaClient (produces the detail hash this service consumes)
# - UsdaPortionClassifier (classifies portions into density/portion/filtered)
# - UsdaSearchController (calls this after fetching USDA detail)
class UsdaImportService
  Result = Data.define(:nutrients, :density, :source, :portions,
                       :density_candidates)

  def self.call(detail)
    new(detail).call
  end

  def initialize(detail)
    @detail = detail
  end

  def call
    classified = FamilyRecipes::UsdaPortionClassifier.classify(@detail[:portions])

    Result.new(
      nutrients: extract_nutrients,
      density: pick_density(classified.density_candidates),
      source: build_source,
      portions: extract_portions(classified.portion_candidates),
      density_candidates: classified.density_candidates
    )
  end

  private

  def extract_nutrients
    raw = @detail[:nutrients]
    FamilyRecipes::NutritionConstraints::NUTRIENT_KEYS.each_with_object(
      { basis_grams: raw['basis_grams'] }
    ) do |key, hash|
      hash[key.to_sym] = raw[key.to_s]
    end
  end

  def pick_density(density_candidates)
    best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(density_candidates)
    return unless best

    unit = FamilyRecipes::UsdaPortionClassifier.normalize_volume_unit(best[:modifier])
    { grams: best[:each].round(2), volume: 1.0, unit: unit }
  end

  def build_source
    { type: 'usda', dataset: @detail[:data_type],
      fdc_id: @detail[:fdc_id], description: @detail[:description] }
  end

  def extract_portions(portion_candidates)
    portion_candidates.map do |candidate|
      { name: candidate[:display_name], grams: candidate[:each] }
    end
  end
end
```

**Step 2: Run tests to verify they pass**

Run: `ruby -Itest test/services/usda_import_service_test.rb`
Expected: All 7 tests PASS.

**Step 3: Run RuboCop on the new file**

Run: `bundle exec rubocop app/services/usda_import_service.rb`
Expected: No offenses.

**Step 4: Commit**

```bash
git add app/services/usda_import_service.rb
git commit -m "feat: add UsdaImportService for USDA-to-catalog data transform"
```

---

### Task 3: `UsdaSearchController` — Tests

**Files:**
- Create: `test/controllers/usda_search_controller_test.rb`

The controller needs to call `UsdaClient` which makes real HTTP requests. We
stub at the `UsdaClient` instance level. The controller creates the client
from `current_kitchen.usda_api_key`, so we set that in setup.

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require 'test_helper'

class UsdaSearchControllerTest < ActionDispatch::IntegrationTest
  SEARCH_RESPONSE = {
    foods: [
      { fdc_id: 9003, description: 'Apples, raw', data_type: 'SR Legacy',
        nutrient_summary: '52 cal | 0g fat | 14g carbs | 0g protein' }
    ],
    total_hits: 1, total_pages: 1, current_page: 0
  }.freeze

  FETCH_DETAIL = {
    fdc_id: 9003, description: 'Apples, raw, with skin', data_type: 'SR Legacy',
    nutrients: {
      'basis_grams' => 100.0, 'calories' => 52.0, 'fat' => 0.17,
      'saturated_fat' => 0.028, 'trans_fat' => 0.0, 'cholesterol' => 0.0,
      'sodium' => 1.0, 'carbs' => 13.81, 'fiber' => 2.4,
      'total_sugars' => 10.39, 'added_sugars' => 0.0, 'protein' => 0.26
    },
    portions: [
      { modifier: 'cup, quartered or chopped', grams: 125.0, amount: 1.0 },
      { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 }
    ]
  }.freeze

  setup do
    create_kitchen_and_user
    log_in
    @kitchen.update!(usda_api_key: 'test-key-123')
  end

  # --- search ---

  test 'search returns paginated results as JSON' do
    mock_client = Minitest::Mock.new
    mock_client.expect :search, SEARCH_RESPONSE, ['apples'], page: 0

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'apples' }, as: :json
    end

    assert_response :success
    body = response.parsed_body

    assert_equal 1, body['total_hits']
    assert_equal 1, body['foods'].size
    assert_equal 'Apples, raw', body['foods'].first['description']
    mock_client.verify
  end

  test 'search passes page parameter' do
    mock_client = Minitest::Mock.new
    mock_client.expect :search, SEARCH_RESPONSE, ['apples'], page: 2

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'apples', page: '2' }, as: :json
    end

    assert_response :success
    mock_client.verify
  end

  test 'search returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'apples' }, as: :json

    assert_response :unprocessable_content
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'search returns error on UsdaClient failure' do
    mock_client = Minitest::Mock.new
    mock_client.expect(:search, nil) { raise FamilyRecipes::UsdaClient::NetworkError, 'timeout' }

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'apples' }, as: :json
    end

    assert_response :unprocessable_content
    assert_match(/timeout/, response.parsed_body['error'])
  end

  test 'search requires membership' do
    Session.destroy_all

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'apples' }, as: :json

    assert_response :forbidden
  end

  # --- show (fetch detail) ---

  test 'show returns import-ready data with nutrients and portions' do
    mock_client = Minitest::Mock.new
    mock_client.expect :fetch, FETCH_DETAIL, fdc_id: '9003'

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_show_path('9003', kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :success
    body = response.parsed_body

    assert_in_delta 52.0, body.dig('nutrients', 'calories')
    assert_equal 'usda', body.dig('source', 'type')
    assert_equal 9003, body.dig('source', 'fdc_id')
    assert body['portions'].is_a?(Array)
    mock_client.verify
  end

  test 'show returns density when volume candidates exist' do
    mock_client = Minitest::Mock.new
    mock_client.expect :fetch, FETCH_DETAIL, fdc_id: '9003'

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_show_path('9003', kitchen_slug: kitchen_slug), as: :json
    end

    body = response.parsed_body

    assert_predicate body['density'], :present?
    assert_equal 'cup', body.dig('density', 'unit')
  end

  test 'show returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_show_path('9003', kitchen_slug: kitchen_slug), as: :json

    assert_response :unprocessable_content
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'show returns error on UsdaClient failure' do
    mock_client = Minitest::Mock.new
    mock_client.expect(:fetch, nil) { raise FamilyRecipes::UsdaClient::AuthError, 'bad key' }

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_show_path('9003', kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :unprocessable_content
    assert_match(/bad key/, response.parsed_body['error'])
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/controllers/usda_search_controller_test.rb`
Expected: NameError or routing error — controller and routes don't exist yet.

**Step 3: Commit**

```bash
git add test/controllers/usda_search_controller_test.rb
git commit -m "test: add UsdaSearchController tests (red)"
```

---

### Task 4: `UsdaSearchController` — Implementation + Routes

**Files:**
- Create: `app/controllers/usda_search_controller.rb`
- Modify: `config/routes.rb` (add 2 routes inside the kitchen scope)

**Step 1: Create the controller**

```ruby
# frozen_string_literal: true

# JSON API for USDA FoodData Central search and detail fetch. Reads the USDA
# API key from the current kitchen's encrypted settings. Search returns
# paginated results with nutrient previews; show fetches full detail and pipes
# it through UsdaImportService to produce editor-ready form values.
#
# Collaborators:
# - UsdaClient (HTTP adapter for USDA FoodData Central)
# - UsdaImportService (transforms raw USDA detail into catalog form values)
# - Kitchen#usda_api_key (encrypted API key storage)
class UsdaSearchController < ApplicationController
  before_action :require_membership
  before_action :require_api_key

  def search
    result = usda_client.search(params[:q], page: params.fetch(:page, 0).to_i)
    render json: result
  rescue FamilyRecipes::UsdaClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def show
    detail = usda_client.fetch(fdc_id: params[:fdc_id])
    import = UsdaImportService.call(detail)
    render json: import_json(import)
  rescue FamilyRecipes::UsdaClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def require_api_key
    return if current_kitchen.usda_api_key.present?

    render json: { error: 'no_api_key' }, status: :unprocessable_content
  end

  def usda_client
    FamilyRecipes::UsdaClient.new(api_key: current_kitchen.usda_api_key)
  end

  def import_json(import)
    { nutrients: import.nutrients, density: import.density,
      source: import.source, portions: import.portions,
      density_candidates: import.density_candidates }
  end
end
```

**Step 2: Add routes**

In `config/routes.rb`, inside the `scope '(/kitchens/:kitchen_slug)'` block,
after the `nutrition_entry_destroy` line, add:

```ruby
    get 'usda/search', to: 'usda_search#search', as: :usda_search
    get 'usda/:fdc_id', to: 'usda_search#show', as: :usda_show
```

**Step 3: Run tests to verify they pass**

Run: `ruby -Itest test/controllers/usda_search_controller_test.rb`
Expected: All 8 tests PASS.

**Step 4: Run RuboCop on the new files**

Run: `bundle exec rubocop app/controllers/usda_search_controller.rb`
Expected: No offenses.

**Step 5: Commit**

```bash
git add app/controllers/usda_search_controller.rb config/routes.rb
git commit -m "feat: add UsdaSearchController with search and show endpoints"
```

---

### Task 5: `IngredientRowBuilder#needed_units` — Tests

**Files:**
- Modify: `test/services/ingredient_row_builder_test.rb`

Add tests for the new `needed_units` method. This method walks recipes for a
given ingredient, collects units, and checks resolvability.

**Step 1: Add the tests**

Append the following test block to the existing test file, before the final
`end`:

```ruby
  # --- needed_units ---

  test 'needed_units returns units used across recipes for an ingredient' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')

    assert_includes units.pluck(:unit), 'cup'
  end

  test 'needed_units marks weight units as resolvable without catalog entry' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Bread

      ## Mix (combine)

      - Flour, 500 g

      Mix.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')
    gram_row = units.find { |u| u[:unit] == 'g' }

    assert gram_row[:resolvable]
    assert_equal 'weight', gram_row[:method]
  end

  test 'needed_units marks volume units as unresolvable without density' do
    create_catalog_entry('Flour', basis_grams: 30)

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')
    cup_row = units.find { |u| u[:unit] == 'cup' }

    assert_not cup_row[:resolvable]
    assert_equal 'no density', cup_row[:method]
  end

  test 'needed_units marks volume units as resolvable with density' do
    create_catalog_entry('Flour', basis_grams: 30)
    entry = IngredientCatalog.find_by(ingredient_name: 'Flour', kitchen_id: nil)
    entry.update!(density_grams: 125, density_volume: 1, density_unit: 'cup')

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Flour')
    cup_row = units.find { |u| u[:unit] == 'cup' }

    assert cup_row[:resolvable]
  end

  test 'needed_units returns empty array for unknown ingredient' do
    builder = IngredientRowBuilder.new(kitchen: @kitchen)

    assert_empty builder.needed_units('Nonexistent')
  end

  test 'needed_units handles bare counts' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category)
      # Egg Dish

      ## Cook (fry)

      - Eggs, 3

      Cook.
    MD

    builder = IngredientRowBuilder.new(kitchen: @kitchen)
    units = builder.needed_units('Eggs')
    bare = units.find { |u| u[:unit].nil? }

    assert bare.present?
    assert_not bare[:resolvable]
  end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb -n /needed_units/`
Expected: NoMethodError — `needed_units` doesn't exist yet.

**Step 3: Commit**

```bash
git add test/services/ingredient_row_builder_test.rb
git commit -m "test: add IngredientRowBuilder#needed_units tests (red)"
```

---

### Task 6: `IngredientRowBuilder#needed_units` — Implementation

**Files:**
- Modify: `app/services/ingredient_row_builder.rb`

Add `needed_units` as a public method and the private helpers it needs. The
method collects all units for an ingredient across recipes, deduplicates, and
checks resolvability via `NutritionCalculator`.

**Step 1: Add the public method**

After `next_needing_attention`, add:

```ruby
  def needed_units(ingredient_name)
    entry = @resolver.catalog_entry(ingredient_name)
    units = collect_units_for(ingredient_name)
    return [] if units.empty?

    calculator = FamilyRecipes::NutritionCalculator.new(
      entry ? { ingredient_name => entry } : {}, omit_set: Set.new
    )
    calc_entry = calculator.nutrition_data[ingredient_name]

    units.map { |unit| build_unit_row(unit, calculator, calc_entry, entry) }
  end
```

**Step 2: Add the private helpers**

In the `private` section, add:

```ruby
  WEIGHT_UNITS = FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS.keys.freeze
  VOLUME_UNITS = FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.keys.freeze

  def collect_units_for(ingredient_name)
    keys = @resolver.all_keys_for(ingredient_name).to_set(&:downcase)
    units = Set.new

    recipes.each do |recipe|
      recipe.ingredients.each do |ingredient|
        next unless keys.include?(ingredient.name.downcase)

        ingredient.amounts.each { |a| units << a&.unit }
      end
    end

    units.to_a
  end

  def build_unit_row(unit, calculator, calc_entry, entry)
    resolvable = calc_entry && calculator.resolvable?(1, unit, calc_entry)
    { unit:, resolvable: resolvable || false, method: resolution_method(unit, resolvable, entry) }
  end

  def resolution_method(unit, resolvable, entry)
    return 'no nutrition data' unless entry&.basis_grams.present?

    if unit.nil?
      resolvable ? 'via ~unitless' : 'no ~unitless portion'
    elsif WEIGHT_UNITS.include?(unit.downcase)
      'weight'
    elsif VOLUME_UNITS.include?(unit.downcase)
      resolvable ? 'via density' : 'no density'
    elsif resolvable
      "via #{unit}"
    else
      'no portion'
    end
  end
```

**Step 3: Run tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_row_builder_test.rb`
Expected: All tests PASS (both existing and new).

**Step 4: Run RuboCop**

Run: `bundle exec rubocop app/services/ingredient_row_builder.rb`
Expected: No offenses.

**Step 5: Commit**

```bash
git add app/services/ingredient_row_builder.rb
git commit -m "feat: add IngredientRowBuilder#needed_units for unit resolution analysis"
```

---

### Task 7: Wire `needed_units` into the Editor Form

**Files:**
- Modify: `app/controllers/ingredients_controller.rb`
- Modify: `app/views/ingredients/_editor_form.html.erb`

**Step 1: Pass `needed_units` to the editor partial**

In `IngredientsController#edit`, after loading ingredient data, compute
needed_units and pass it to the partial:

```ruby
  def edit
    ingredient_name, entry = load_ingredient_data
    aisles = current_kitchen.all_aisles
    sources = sources_for_ingredient(ingredient_name)
    needed_units = row_builder.needed_units(ingredient_name)

    render partial: 'ingredients/editor_form',
           locals: { ingredient_name:, entry:, available_aisles: aisles, sources:, needed_units: }
  end
```

**Step 2: Add the recipe units section to the editor form**

In `_editor_form.html.erb`, after the aliases section (after the closing
`</fieldset>` of aliases, before the `<% if sources.any? %>` block), add:

```erb
    <% if needed_units.any? %>
      <div class="editor-section editor-recipe-units">
        <div class="editor-section-title">Recipe Units</div>
        <p class="editor-help">
          Units used in recipes. A checkmark means the app can convert this unit to grams.
        </p>
        <% needed_units.each do |nu| %>
          <div class="recipe-unit-row">
            <span class="recipe-unit-status"><%= nu[:resolvable] ? "\u2713" : "\u2717" %></span>
            <span class="recipe-unit-name"><%= nu[:unit] || '(bare count)' %></span>
            <span class="recipe-unit-method"><%= nu[:method] %></span>
          </div>
        <% end %>
      </div>
    <% end %>
```

**Step 3: Update the locals declaration at the top of the partial**

Change the first line from:
```erb
<%# locals: (ingredient_name:, entry:, available_aisles:, sources: []) %>
```
to:
```erb
<%# locals: (ingredient_name:, entry:, available_aisles:, sources: [], needed_units: []) %>
```

**Step 4: Run existing tests to ensure nothing breaks**

Run: `ruby -Itest test/controllers/ingredients_controller_test.rb`
Expected: All existing tests PASS.

**Step 5: Commit**

```bash
git add app/controllers/ingredients_controller.rb app/views/ingredients/_editor_form.html.erb
git commit -m "feat: show recipe unit resolution status in ingredient editor"
```

---

### Task 8: Clean up `UsdaClient` — Remove TUI-only Code

**Files:**
- Modify: `lib/familyrecipes/usda_client.rb`
- Modify: `test/lib/usda_client_test.rb` (if tests reference `load_api_key`)

**Step 1: Check for tests referencing `load_api_key`**

Run: `grep -rn 'load_api_key\|parse_env_file' test/`

If tests exist for these methods, remove them. They tested TUI-only behavior.

**Step 2: Remove `load_api_key` and `parse_env_file` from `UsdaClient`**

Delete the `self.load_api_key` and `self.parse_env_file` methods (lines 51-66
approximately).

**Step 3: Update the header comment**

Change the collaborators list from referencing `bin/nutrition` to:

```ruby
  # Collaborators: UsdaSearchController (web search/fetch endpoints),
  # UsdaImportService (consumes fetch results), UsdaPortionClassifier
  # (classifies portions downstream).
```

**Step 4: Run full test suite**

Run: `rake test`
Expected: All tests PASS. If anything in `bin/nutrition` or `NutritionTui`
references `load_api_key`, that's expected breakage (TUI is abandoned).

**Step 5: Run RuboCop**

Run: `bundle exec rubocop lib/familyrecipes/usda_client.rb`
Expected: No offenses.

**Step 6: Commit**

```bash
git add lib/familyrecipes/usda_client.rb
git commit -m "refactor: remove TUI-only load_api_key from UsdaClient"
```

If test files were modified:
```bash
git add lib/familyrecipes/usda_client.rb test/lib/usda_client_test.rb
git commit -m "refactor: remove TUI-only load_api_key from UsdaClient"
```

---

### Task 9: Full Suite Verification

**Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests PASS.

**Step 2: Run lint**

Run: `rake lint`
Expected: No offenses.

**Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: No new violations (the new ERB uses `<%= %>` which auto-escapes).

**Step 4: Commit any remaining fixes, then final verification**

Run: `rake`
Expected: Both lint and test pass cleanly.

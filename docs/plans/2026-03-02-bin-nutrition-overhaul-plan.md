# bin/nutrition Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Overhaul the `bin/nutrition` CLI tool with a reusable USDA client, TTY gem suite for interactive comfort, search pagination, inline density/portion/nutrient editing, and code cleanup.

**Architecture:** Extract `FamilyRecipes::UsdaClient` into `lib/familyrecipes/` for reuse by future web integration. Rewrite the TUI layer using the TTY gem suite (tty-prompt, tty-table, tty-spinner, tty-box, pastel). Keep YAML as the write target. Extract the YAML↔AR attribute bridge onto `IngredientCatalog` so the rake task and CLI share one mapping.

**Tech Stack:** Ruby, TTY gems, USDA FoodData Central API, Minitest

**Design doc:** `docs/plans/2026-03-02-bin-nutrition-overhaul-design.md`

---

### Task 0: Add TTY gems to Gemfile

**Files:**
- Modify: `Gemfile`

**Step 1: Add gems**

Add to the existing `:development` group in `Gemfile`, after the rubocop gems:

```ruby
group :development do
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false

  gem 'pastel'
  gem 'tty-box'
  gem 'tty-prompt'
  gem 'tty-spinner'
  gem 'tty-table'
end
```

**Step 2: Bundle install**

Run: `bundle install`
Expected: All gems resolve and install successfully.

**Step 3: Verify gems load**

Run: `ruby -e "require 'bundler/setup'; require 'tty-prompt'; puts TTY::Prompt"`
Expected: `TTY::Prompt`

**Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add TTY gem suite for bin/nutrition TUI"
```

---

### Task 1: Extract FamilyRecipes::UsdaClient

**Files:**
- Create: `lib/familyrecipes/usda_client.rb`
- Modify: `lib/familyrecipes.rb` (add require)
- Create: `test/usda_client_test.rb`
- Modify: `.rubocop.yml` (exclude new test from Rails/RefuteMethods)

This is the biggest task. The class owns all USDA API interaction and returns data in our canonical catalog format. It has no TUI dependencies and will be reusable for web integration.

**Step 1: Write the test file**

Create `test/usda_client_test.rb`. Uses `Minitest::Test` (no Rails needed). Tests stub `Net::HTTP.start` to avoid real API calls.

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/familyrecipes'

require 'json'
require 'net/http'

class UsdaClientTest < Minitest::Test
  def setup
    @client = FamilyRecipes::UsdaClient.new(api_key: 'test-key')
  end

  # --- search ---

  def test_search_returns_structured_results
    with_api_response(200, search_response_body) do
      result = @client.search('flour')

      assert_equal 42, result[:total_hits]
      assert_equal 5, result[:total_pages]
      assert_equal 0, result[:current_page]
      assert_equal 1, result[:foods].size

      food = result[:foods].first
      assert_equal 168_913, food[:fdc_id]
      assert_equal 'Wheat flour, white, all-purpose', food[:description]
      assert_includes food[:nutrient_summary], '364 cal'
    end
  end

  def test_search_with_pagination_params
    with_api_response(200, search_response_body) do
      # Just verify it doesn't raise — pagination params go to the API
      result = @client.search('flour', page: 2, page_size: 20)
      assert_equal 42, result[:total_hits]
    end
  end

  def test_search_with_empty_results
    with_api_response(200, { 'foods' => [], 'totalHits' => 0, 'totalPages' => 0, 'currentPage' => 0 }) do
      result = @client.search('xyznonexistent')
      assert_empty result[:foods]
      assert_equal 0, result[:total_hits]
    end
  end

  # --- fetch ---

  def test_fetch_extracts_nutrients
    with_api_response(200, food_detail_body) do
      result = @client.fetch(fdc_id: 168_913)

      assert_equal 168_913, result[:fdc_id]
      assert_equal 100.0, result[:nutrients]['basis_grams']
      assert_equal 364.0, result[:nutrients]['calories']
      assert_equal 1.0, result[:nutrients]['fat']
      assert_equal 76.0, result[:nutrients]['carbs']
      assert_equal 0.0, result[:nutrients]['added_sugars']
    end
  end

  def test_fetch_classifies_portions
    with_api_response(200, food_detail_body) do
      result = @client.fetch(fdc_id: 168_913)
      portions = result[:portions]

      assert_kind_of Array, portions[:volume]
      assert_kind_of Array, portions[:non_volume]
      assert(portions[:volume].any? { |p| p[:modifier].downcase.include?('cup') })
    end
  end

  # --- error handling ---

  def test_network_error_on_connection_failure
    Net::HTTP.stub(:start, ->(*) { raise SocketError, 'getaddrinfo: Name or service not known' }) do
      assert_raises(FamilyRecipes::UsdaClient::NetworkError) { @client.search('flour') }
    end
  end

  def test_network_error_on_timeout
    Net::HTTP.stub(:start, ->(*) { raise Net::OpenTimeout, 'execution expired' }) do
      assert_raises(FamilyRecipes::UsdaClient::NetworkError) { @client.search('flour') }
    end
  end

  def test_auth_error_on_401
    with_api_response(401, { 'error' => { 'message' => 'Invalid API key' } }) do
      assert_raises(FamilyRecipes::UsdaClient::AuthError) { @client.search('flour') }
    end
  end

  def test_rate_limit_error_on_429
    with_api_response(429, { 'error' => 'Too many requests' }) do
      error = assert_raises(FamilyRecipes::UsdaClient::RateLimitError) { @client.search('flour') }
      assert_includes error.message, 'Rate limited'
    end
  end

  def test_server_error_on_500
    with_api_response(500, { 'error' => 'Internal server error' }) do
      assert_raises(FamilyRecipes::UsdaClient::ServerError) { @client.search('flour') }
    end
  end

  def test_parse_error_on_malformed_json
    mock_http = build_mock_http(200, 'this is not json')
    Net::HTTP.stub(:start, ->(*, &block) { block.call(mock_http) }) do
      assert_raises(FamilyRecipes::UsdaClient::ParseError) { @client.search('flour') }
    end
  end

  # --- load_api_key ---

  def test_load_api_key_from_env
    ENV.stub(:[], ->(k) { k == 'USDA_API_KEY' ? 'env-key' : nil }) do
      assert_equal 'env-key', FamilyRecipes::UsdaClient.load_api_key
    end
  end

  def test_load_api_key_returns_nil_without_key
    ENV.stub(:[], ->(_) { nil }) do
      assert_nil FamilyRecipes::UsdaClient.load_api_key(project_root: '/nonexistent')
    end
  end

  private

  def with_api_response(code, body)
    mock_http = build_mock_http(code, body.is_a?(String) ? body : body.to_json)
    Net::HTTP.stub(:start, ->(*, &block) { block.call(mock_http) }) do
      yield
    end
  end

  def build_mock_http(code, body_string)
    response = Net::HTTPResponse::CODE_TO_OBJ[code.to_s].new('1.1', code.to_s, '')
    response.instance_variable_set(:@body, body_string)
    response.instance_variable_set(:@read, true)

    mock = Object.new
    mock.define_singleton_method(:request) { |_| response }
    mock
  end

  def search_response_body
    {
      'foods' => [{
        'fdcId' => 168_913,
        'description' => 'Wheat flour, white, all-purpose',
        'dataType' => 'SR Legacy',
        'foodNutrients' => [
          { 'nutrientNumber' => '208', 'value' => 364 },
          { 'nutrientNumber' => '204', 'value' => 1.0 },
          { 'nutrientNumber' => '205', 'value' => 76.0 },
          { 'nutrientNumber' => '203', 'value' => 10.0 }
        ]
      }],
      'totalHits' => 42,
      'totalPages' => 5,
      'currentPage' => 0
    }
  end

  def food_detail_body
    {
      'fdcId' => 168_913,
      'description' => 'Wheat flour, white, all-purpose, enriched, unbleached',
      'dataType' => 'SR Legacy',
      'foodNutrients' => [
        { 'nutrient' => { 'number' => '208' }, 'amount' => 364.0 },
        { 'nutrient' => { 'number' => '204' }, 'amount' => 1.0 },
        { 'nutrient' => { 'number' => '205' }, 'amount' => 76.0 },
        { 'nutrient' => { 'number' => '203' }, 'amount' => 10.0 },
        { 'nutrient' => { 'number' => '307' }, 'amount' => 2.0 },
        { 'nutrient' => { 'number' => '606' }, 'amount' => 0.2 },
        { 'nutrient' => { 'number' => '605' }, 'amount' => 0.0 },
        { 'nutrient' => { 'number' => '601' }, 'amount' => 0.0 },
        { 'nutrient' => { 'number' => '291' }, 'amount' => 2.7 },
        { 'nutrient' => { 'number' => '269' }, 'amount' => 0.3 }
      ],
      'foodPortions' => [
        { 'modifier' => 'cup', 'gramWeight' => 125.0, 'amount' => 1.0 },
        { 'modifier' => 'tbsp', 'gramWeight' => 7.8, 'amount' => 1.0 },
        { 'modifier' => 'oz', 'gramWeight' => 28.35, 'amount' => 1.0 }
      ]
    }
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/usda_client_test.rb`
Expected: Failures/errors because `FamilyRecipes::UsdaClient` doesn't exist yet.

**Step 3: Write the UsdaClient class**

Create `lib/familyrecipes/usda_client.rb`:

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

module FamilyRecipes
  # Wraps the USDA FoodData Central API for ingredient catalog curation.
  # Handles search (with pagination), detail fetch, nutrient extraction,
  # and portion classification. Returns data shaped to the ingredient
  # catalog's canonical model. Used by bin/nutrition (CLI) and future
  # web integration.
  #
  # All network errors are wrapped in UsdaClient::Error subclasses so
  # callers can display human-readable messages without rescuing
  # low-level exceptions.
  class UsdaClient
    Error = Class.new(StandardError)
    NetworkError = Class.new(Error)
    RateLimitError = Class.new(Error)
    AuthError = Class.new(Error)
    ServerError = Class.new(Error)
    ParseError = Class.new(Error)

    BASE_URI = 'https://api.nal.usda.gov/fdc/v1'

    NUTRIENT_MAP = {
      '208' => 'calories',
      '204' => 'fat',
      '606' => 'saturated_fat',
      '605' => 'trans_fat',
      '601' => 'cholesterol',
      '307' => 'sodium',
      '205' => 'carbs',
      '291' => 'fiber',
      '269' => 'total_sugars',
      '203' => 'protein'
    }.freeze

    VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons].freeze

    SEARCH_PREVIEW_NUTRIENTS = {
      '208' => 'cal', '204' => 'fat', '205' => 'carbs', '203' => 'protein'
    }.freeze

    def initialize(api_key:)
      @api_key = api_key
    end

    def search(query, page: 0, page_size: 10)
      body = { query: query, dataType: ['SR Legacy'],
               pageSize: page_size, pageNumber: page }
      response = post('/foods/search', body)

      {
        foods: (response['foods'] || []).map { |f| format_search_result(f) },
        total_hits: response['totalHits'] || 0,
        total_pages: response['totalPages'] || 0,
        current_page: response['currentPage'] || 0
      }
    end

    def fetch(fdc_id:)
      response = get("/food/#{fdc_id}")

      {
        fdc_id: response['fdcId'],
        description: response['description'],
        data_type: response['dataType'] || 'SR Legacy',
        nutrients: extract_nutrients(response),
        portions: classify_portions(response)
      }
    end

    def self.load_api_key(project_root: nil)
      return ENV['USDA_API_KEY'] if ENV['USDA_API_KEY']

      root = project_root || File.expand_path('../..', __dir__)
      env_path = File.join(root, '.env')
      return nil unless File.exist?(env_path)

      File.readlines(env_path).each do |line|
        key, value = line.strip.split('=', 2)
        return value if key == 'USDA_API_KEY' && value && !value.empty?
      end
      nil
    end

    private

    def post(path, body)
      uri = URI("#{BASE_URI}#{path}")
      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      request['X-Api-Key'] = @api_key
      request.body = body.to_json
      execute(uri, request)
    end

    def get(path)
      uri = URI("#{BASE_URI}#{path}")
      request = Net::HTTP::Get.new(uri)
      request['X-Api-Key'] = @api_key
      execute(uri, request)
    end

    def execute(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      handle_response(response)
    rescue SocketError, Errno::ECONNREFUSED,
           Net::OpenTimeout, Net::ReadTimeout => error
      raise NetworkError, "Connection failed: #{error.message}"
    end

    def handle_response(response)
      case response.code.to_i
      when 200..299
        parse_json(response.body)
      when 401, 403
        raise AuthError, 'Invalid API key — check USDA_API_KEY'
      when 429
        retry_after = response['Retry-After']
        msg = 'Rate limited by USDA API'
        msg += " — retry after #{retry_after}s" if retry_after
        raise RateLimitError, msg
      else
        raise ServerError, "USDA API returned #{response.code}: #{response.message}"
      end
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise ParseError, "Malformed response from USDA: #{error.message}"
    end

    def format_search_result(food)
      nutrient_lookup = (food['foodNutrients'] || [])
                          .to_h { |fn| [fn['nutrientNumber'], fn['value']] }
      summary = SEARCH_PREVIEW_NUTRIENTS.map do |number, label|
        value = (nutrient_lookup[number] || 0).round(0).to_i
        label == 'cal' ? "#{value} #{label}" : "#{value}g #{label}"
      end

      { fdc_id: food['fdcId'], description: food['description'],
        data_type: food['dataType'], nutrient_summary: summary.join(' | ') }
    end

    def extract_nutrients(response)
      nutrients = { 'basis_grams' => 100.0 }
      NUTRIENT_MAP.each_value { |key| nutrients[key] = 0.0 }

      (response['foodNutrients'] || []).each do |fn|
        our_key = NUTRIENT_MAP[fn.dig('nutrient', 'number')]
        next unless our_key

        nutrients[our_key] = (fn['amount'] || 0.0).round(4)
      end

      nutrients['added_sugars'] = 0.0
      nutrients
    end

    def classify_portions(response)
      (response['foodPortions'] || []).each_with_object(volume: [], non_volume: []) do |portion, acc|
        modifier = portion['modifier'].to_s
        grams = portion['gramWeight']
        amount = portion['amount'] || 1.0
        next if modifier.empty? || !grams&.positive?

        entry = { modifier: modifier, grams: grams, amount: amount }
        bucket = volume_unit?(modifier) ? :volume : :non_volume
        acc[bucket] << entry
      end
    end

    def volume_unit?(modifier)
      VOLUME_UNITS.include?(modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip)
    end
  end
end
```

**Step 4: Wire into familyrecipes.rb**

Add to `lib/familyrecipes.rb`, after the `build_validator` require:

```ruby
require_relative 'familyrecipes/usda_client'
```

**Step 5: Add test exclusion to .rubocop.yml**

Add `test/usda_client_test.rb` to the `Rails/RefuteMethods` exclusion list.

**Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/usda_client_test.rb`
Expected: All tests pass.

Run: `bundle exec rubocop lib/familyrecipes/usda_client.rb test/usda_client_test.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add lib/familyrecipes/usda_client.rb lib/familyrecipes.rb \
        test/usda_client_test.rb .rubocop.yml
git commit -m "feat: extract FamilyRecipes::UsdaClient from bin/nutrition

Reusable USDA FoodData Central API client with pagination support,
nutrient extraction, portion classification, and error handling.
Ref: GH #140"
```

---

### Task 2: Extract IngredientCatalog.attrs_from_yaml

The YAML↔AR attribute mapping currently lives in `catalog_sync.rake` as `catalog_attrs` and is duplicated in `catalog_sync_test.rb` as `build_attrs`. Extract to a class method on `IngredientCatalog` so both consumers (and `bin/nutrition` in the future) share one implementation.

**Files:**
- Modify: `app/models/ingredient_catalog.rb`
- Modify: `lib/tasks/catalog_sync.rake`
- Modify: `test/lib/catalog_sync_test.rb`
- Modify: `test/models/ingredient_catalog_test.rb`

**Step 1: Write the test**

Add to `test/models/ingredient_catalog_test.rb`:

```ruby
test 'attrs_from_yaml extracts all fields from a complete entry' do
  entry = {
    'aisle' => 'Baking',
    'nutrients' => { 'basis_grams' => 30, 'calories' => 110, 'fat' => 0.5,
                     'saturated_fat' => 0.1, 'trans_fat' => 0, 'cholesterol' => 0,
                     'sodium' => 0, 'carbs' => 23, 'fiber' => 1, 'total_sugars' => 0,
                     'added_sugars' => 0, 'protein' => 3 },
    'density' => { 'grams' => 30.0, 'volume' => 0.25, 'unit' => 'cup' },
    'portions' => { 'stick' => 113.0 },
    'aliases' => ['AP flour', 'Plain flour'],
    'sources' => [{ 'type' => 'usda', 'fdc_id' => 168_913 }]
  }

  attrs = IngredientCatalog.attrs_from_yaml(entry)

  assert_equal 'Baking', attrs[:aisle]
  assert_equal 30, attrs[:basis_grams]
  assert_equal 110, attrs[:calories]
  assert_equal 30.0, attrs[:density_grams]
  assert_equal 0.25, attrs[:density_volume]
  assert_equal 'cup', attrs[:density_unit]
  assert_equal({ 'stick' => 113.0 }, attrs[:portions])
  assert_equal ['AP flour', 'Plain flour'], attrs[:aliases]
end

test 'attrs_from_yaml handles entry with no density' do
  entry = { 'nutrients' => { 'basis_grams' => 100, 'calories' => 50 } }
  attrs = IngredientCatalog.attrs_from_yaml(entry)

  assert_nil attrs[:density_grams]
  assert_equal({}, attrs[:portions])
  assert_equal([], attrs[:aliases])
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /attrs_from_yaml/`
Expected: `NoMethodError: undefined method 'attrs_from_yaml'`

**Step 3: Add the class method**

Add to `app/models/ingredient_catalog.rb`, after the `lookup_for` method:

```ruby
def self.attrs_from_yaml(entry)
  attrs = { aisle: entry['aisle'] }

  if (nutrients = entry['nutrients'])
    NUTRIENT_COLUMNS.each { |col| attrs[col] = nutrients[col.to_s] }
    attrs[:basis_grams] = nutrients['basis_grams']
  end

  if (density = entry['density'])
    attrs[:density_grams] = density['grams']
    attrs[:density_volume] = density['volume']
    attrs[:density_unit] = density['unit']
  end

  attrs[:aliases] = entry['aliases'] || []
  attrs[:portions] = entry['portions'] || {}
  attrs[:sources] = entry['sources'] || []

  attrs
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /attrs_from_yaml/`
Expected: 2 tests, 2 passes.

**Step 5: Update catalog_sync.rake to use it**

Replace the `catalog_attrs` function and update `sync_catalog_entry`:

```ruby
# frozen_string_literal: true

def sync_catalog_entry(name, entry)
  profile = IngredientCatalog.find_or_initialize_by(kitchen_id: nil, ingredient_name: name)
  profile.assign_attributes(IngredientCatalog.attrs_from_yaml(entry))

  return :created if profile.new_record? && profile.save!
  return :updated if profile.changed? && profile.save!

  :unchanged
end

namespace :catalog do
  # ... task body unchanged ...
end
```

**Step 6: Update catalog_sync_test.rb to use model method**

Replace the private `build_attrs` helper with `IngredientCatalog.attrs_from_yaml`:

- In `test 'all catalog entries pass model validations'`: change `build_attrs(entry)` → `IngredientCatalog.attrs_from_yaml(entry)`
- In `test 'sync preserves aliases from YAML entries'`: change `build_attrs(entry)` → `IngredientCatalog.attrs_from_yaml(entry)`
- Remove the private `build_attrs` method entirely.

**Step 7: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 8: Commit**

```bash
git add app/models/ingredient_catalog.rb lib/tasks/catalog_sync.rake \
        test/models/ingredient_catalog_test.rb test/lib/catalog_sync_test.rb
git commit -m "refactor: extract IngredientCatalog.attrs_from_yaml

Shared YAML→AR attribute bridge. Replaces catalog_attrs in rake task
and build_attrs in test. Single source of truth for the mapping."
```

---

### Task 3: Dead code removal + Ruby style cleanup

Clean up `bin/nutrition` before the TUI rewrite so we're working with clean code.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Remove dead code**

- Delete the `resolve_name` method (lines 110–112) — it's a no-op that returns its argument.
- Delete its call site in the main dispatcher (line 770): change `resolved = resolve_name(ingredient_name, ctx)` to just use `ingredient_name` directly. Remove the `exit 0 unless resolved` guard since the method never returned nil.
- In `edit_sources`, rename the menu option from `a. Add source` to `a. Add USDA source` for clarity.

**Step 2: Fix Ruby style — build_lookup**

Rewrite using `each_with_object`:

```ruby
def build_lookup(nutrition_data)
  nutrition_data.each_with_object({}) do |(name, entry), lookup|
    lookup[name] = name
    lookup[name.downcase] = name

    FamilyRecipes::Inflector.ingredient_variants(name).each do |variant|
      lookup[variant] ||= name
      lookup[variant.downcase] ||= name
    end

    (entry['aliases'] || []).each do |alias_name|
      next if nutrition_data.key?(alias_name)

      lookup[alias_name] ||= name
      lookup[alias_name.downcase] ||= name
    end
  end
end
```

**Step 3: Fix Ruby style — find_needed_units**

Flatten the nested iteration:

```ruby
def find_needed_units(name, ctx)
  ctx[:recipes].flat_map do |recipe|
    recipe.all_ingredients_with_quantities(ctx[:recipe_map])
          .select { |ing_name, _| ing_name == name }
          .flat_map { |_, amounts| amounts.compact.map(&:unit) }
  end.uniq
end
```

**Step 4: Remove constants that moved to UsdaClient**

Delete from `bin/nutrition`:
- `NUTRIENT_MAP` (now `FamilyRecipes::UsdaClient::NUTRIENT_MAP`)
- `VOLUME_UNITS` (now `FamilyRecipes::UsdaClient::VOLUME_UNITS`)
- `SEARCH_NUTRIENTS` (now `SEARCH_PREVIEW_NUTRIENTS` in client)

Keep `NUTRIENTS` (display-only, used by the TUI layer).

**Step 5: Replace API functions with UsdaClient**

Replace `search_usda`, `fetch_usda_detail`, `extract_nutrients`, `classify_portions`, `volume_unit?`, `normalize_volume_unit`, `load_api_key` with calls to the client. The main dispatcher becomes:

```ruby
api_key = FamilyRecipes::UsdaClient.load_api_key(project_root: PROJECT_ROOT)
# ...
client = FamilyRecipes::UsdaClient.new(api_key: api_key)
```

Functions like `enter_usda`, `search_and_pick` receive `client` as an argument instead of `api_key`.

**Step 6: Verify**

Run: `bundle exec rubocop bin/nutrition`
Expected: No new offenses (bin/ is excluded from metrics).

Run: `bin/nutrition --coverage`
Expected: Coverage report prints normally.

**Step 7: Commit**

```bash
git add bin/nutrition
git commit -m "refactor: dead code removal + Ruby style cleanup in bin/nutrition

Remove resolve_name stub, fix Enumerable violations, replace inline
API calls with UsdaClient. Ref: GH #140 items 5-6."
```

---

### Task 4: TUI foundation + search with pagination

Replace the manual `print`/`$stdin.gets` search-and-pick loop with tty-prompt, tty-spinner, and tty-box. This is the first TUI conversion and establishes patterns for subsequent tasks.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add TTY requires and instance setup**

At the top of `bin/nutrition`, after existing requires:

```ruby
require 'tty-prompt'
require 'tty-table'
require 'tty-spinner'
require 'tty-box'
require 'pastel'
```

After constant definitions, set up shared instances:

```ruby
PROMPT = TTY::Prompt.new
PASTEL = Pastel.new
```

**Step 2: Create a spinner helper for API calls**

```ruby
def with_spinner(message, &block)
  spinner = TTY::Spinner.new("[:spinner] #{message}", format: :dots)
  spinner.auto_spin
  result = block.call
  spinner.success
  result
rescue FamilyRecipes::UsdaClient::Error => error
  spinner.error
  puts PASTEL.red(error.message)
  nil
end
```

**Step 3: Rewrite search_and_pick with pagination**

Replace the entire `search_and_pick` method. Key changes:
- Use `PROMPT.select` for arrow-key menu navigation
- Hold `page` state in a loop for forward/back navigation
- Default search query strips punctuation instead of parenthetical: `name.gsub(/[(),]/, ' ').squeeze(' ').strip`
- Show page info in a tty-box header
- Use `with_spinner` during API calls
- Rescue `UsdaClient::Error` to stay in the loop on failure

```ruby
def default_search_query(name)
  name.gsub(/[(),]/, ' ').squeeze(' ').strip
end

def search_and_pick(client, name)
  query = default_search_query(name)

  loop do
    query = PROMPT.ask('Search USDA:', default: query)
    return nil if query.nil?

    page = 0
    loop do
      result = with_spinner("Searching for \"#{query}\"...") do
        client.search(query, page: page)
      end
      break unless result

      if result[:foods].empty?
        puts PASTEL.yellow('No results found.')
        break
      end

      choices = build_search_choices(result)
      selection = PROMPT.select(search_header(result), choices, per_page: 15)

      case selection
      when :next_page then page += 1
      when :prev_page then page -= 1
      when :search    then break
      when :quit      then return nil
      else
        detail = with_spinner("Fetching #{selection[:description]}...") do
          client.fetch(fdc_id: selection[:fdc_id])
        end
        return detail if detail
      end
    end
  end
end

def search_header(result)
  "Page #{result[:current_page] + 1} of #{result[:total_pages]} " \
    "(#{result[:total_hits]} results)"
end

def build_search_choices(result)
  choices = result[:foods].map do |food|
    { name: "#{food[:description]}\n    #{PASTEL.dim(food[:nutrient_summary])}",
      value: food }
  end

  choices << { name: PASTEL.cyan('Next page →'), value: :next_page } if result[:current_page] + 1 < result[:total_pages]
  choices << { name: PASTEL.cyan('← Previous page'), value: :prev_page } if result[:current_page] > 0
  choices << { name: 'Search again', value: :search }
  choices << { name: 'Quit', value: :quit }
  choices
end
```

**Step 4: Update enter_usda to use client**

```ruby
def enter_usda(client, name)
  detail = search_and_pick(client, name)
  return nil unless detail

  density = pick_density(detail[:portions][:volume])
  portions = build_non_volume_portions(detail[:portions])

  entry = { 'nutrients' => detail[:nutrients] }
  entry['density'] = density if density
  entry['portions'] = portions unless portions.empty?
  entry['sources'] = [{
    'type' => 'usda',
    'dataset' => detail[:data_type],
    'fdc_id' => detail[:fdc_id],
    'description' => detail[:description]
  }]

  entry
end
```

**Step 5: Verify interactively**

Run: `bin/nutrition "Flour (whole wheat)"`
Expected:
- Default search suggestion is `Flour whole wheat` (not just `Flour`)
- Spinner shows during API call
- Arrow-key menu appears with search results
- "Next page →" option visible
- Selecting a result fetches detail with spinner
- Error messages display in color if API fails

**Step 6: Commit**

```bash
git add bin/nutrition
git commit -m "feat: search pagination + TTY foundation in bin/nutrition

tty-prompt arrow-key menus, tty-spinner for API calls, search
pagination via USDA pageNumber API. Default search strips punctuation
to keep all keywords. Ref: GH #140 items 1, 4."
```

---

### Task 5: Entry display with tty-box and tty-table

Replace `display_entry` and `display_unit_coverage` with formatted TTY output.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Rewrite display_entry**

Use tty-table for nutrients and tty-box for the overall entry panel:

```ruby
def display_entry(name, entry)
  puts "\n"
  puts PASTEL.bold("--- #{name} ---")

  display_nutrients_table(entry)
  display_density(entry)
  display_portions(entry)
  display_aliases(entry)
  display_sources(entry['sources']) if entry['sources']&.any?
end

def display_nutrients_table(entry)
  basis = entry.dig('nutrients', 'basis_grams') || '?'
  puts PASTEL.dim("  Nutrients (per #{basis}g):")

  rows = NUTRIENTS.map do |n|
    indent = '  ' * n[:indent]
    value = entry.dig('nutrients', n[:key]) || 0
    unit_str = n[:unit].empty? ? '' : " #{n[:unit]}"
    ["  #{indent}#{n[:label]}", "#{value}#{unit_str}"]
  end

  table = TTY::Table.new(rows: rows)
  puts table.render(:basic, padding: [0, 1, 0, 2])
end

def display_density(entry)
  density = entry['density']
  if density
    puts PASTEL.dim("  Density: ") + "#{density['grams']}g per #{density['volume']} #{density['unit']}"
  else
    puts PASTEL.dim("  Density: ") + PASTEL.yellow('none')
  end
end

def display_portions(entry)
  portions = entry['portions'] || {}
  if portions.any?
    summary = portions.map { |k, v| "#{k}=#{v}g" }.join(', ')
    puts PASTEL.dim("  Portions: ") + summary
  else
    puts PASTEL.dim("  Portions: ") + PASTEL.yellow('none')
  end
end

def display_aliases(entry)
  aliases = entry['aliases'] || []
  if aliases.any?
    puts PASTEL.dim("  Aliases: ") + aliases.join(', ')
  else
    puts PASTEL.dim("  Aliases: ") + 'none'
  end
end
```

**Step 2: Rewrite display_unit_coverage with color**

```ruby
def display_unit_coverage(name, entry, needed_units)
  return if needed_units.empty?

  calculator = FamilyRecipes::NutritionCalculator.new({ name => entry })
  entry_data = calculator.nutrition_data[name]
  return unless entry_data

  puts PASTEL.dim("\n  Unit coverage for recipes:")
  needed_units.each do |unit|
    label = unit || '(bare count)'
    resolved = calculator.resolvable?(1, unit, entry_data)
    status = resolved ? PASTEL.green('OK') : PASTEL.red('MISSING')
    puts "    #{label}: #{status}"
  end
end
```

**Step 3: Rewrite display_sources**

```ruby
def display_sources(sources)
  label = sources.size == 1 ? 'Source' : 'Sources'
  puts PASTEL.dim("  #{label}: ") + sources.map { |s| format_source(s) }.join('; ')
end
```

**Step 4: Verify interactively**

Run: `bin/nutrition "Butter"`
Expected: Nutrient table is aligned, density/portions show with dim labels, unit coverage shows green OK / red MISSING.

**Step 5: Commit**

```bash
git add bin/nutrition
git commit -m "feat: entry display with tty-table and pastel colors

Formatted nutrient tables, color-coded unit coverage, dim labels
for density/portions/sources. Ref: GH #140."
```

---

### Task 6: Review loop + expanded edit menu

Rewrite `review_and_save` and `edit_entry` with tty-prompt menus. Add density, portions, and nutrients editing submenus.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Rewrite review_and_save**

```ruby
def review_and_save(name, entry, needed_units, nutrition_data, client:)
  loop do
    display_entry(name, entry)
    display_unit_coverage(name, entry, needed_units)

    action = PROMPT.select("\nAction:", [
      { name: 'Save', value: :save },
      { name: 'Edit', value: :edit },
      { name: 'Discard and start fresh', value: :discard }
    ])

    case action
    when :save
      entry['aliases'] = prompt_aliases(name, entry)
      nutrition_data[name] = entry
      save_nutrition_data(nutrition_data)
      return
    when :discard
      enter_new_ingredient(name, needed_units, nutrition_data, client: client)
      return
    when :edit
      entry = edit_entry(name, entry, needed_units, client: client)
    end
  end
end
```

**Step 2: Rewrite edit_entry with expanded menu**

```ruby
def edit_entry(name, entry, needed_units, client:)
  loop do
    display_entry(name, entry)
    display_unit_coverage(name, entry, needed_units)

    density_label = entry['density'] ? "#{entry['density']['grams']}g/#{entry['density']['volume']} #{entry['density']['unit']}" : 'none'
    portions_count = (entry['portions'] || {}).size

    action = PROMPT.select("\nEdit:", [
      { name: "Density (#{density_label})", value: :density },
      { name: "Portions (#{portions_count} defined)", value: :portions },
      { name: 'Nutrients', value: :nutrients },
      { name: 'Re-import from USDA', value: :reimport },
      { name: 'Sources', value: :sources },
      { name: 'Done editing', value: :done }
    ])

    case action
    when :density   then edit_density(entry)
    when :portions  then edit_portions(entry)
    when :nutrients then edit_nutrients(entry)
    when :reimport
      new_entry = enter_usda(client, name)
      entry = new_entry if new_entry
    when :sources
      entry['sources'] = edit_sources(entry['sources'] || [])
    when :done
      return entry
    end
  end
end
```

**Step 3: Add density editing submenu**

```ruby
def edit_density(entry)
  action = PROMPT.select('Density:', [
    { name: 'Enter custom values', value: :custom },
    { name: 'Remove density', value: :remove },
    { name: 'Cancel', value: :cancel }
  ])

  case action
  when :custom
    grams = PROMPT.ask('Grams:', convert: :float)
    volume = PROMPT.ask('Volume:', convert: :float)
    unit = PROMPT.ask('Unit (e.g., cup, tbsp, tsp):')
    entry['density'] = { 'grams' => grams, 'volume' => volume, 'unit' => unit }
  when :remove
    entry.delete('density')
  end
end
```

**Step 4: Add portions editing submenu**

```ruby
def edit_portions(entry)
  entry['portions'] ||= {}

  loop do
    if entry['portions'].any?
      puts PASTEL.dim("\n  Current portions:")
      entry['portions'].each { |k, v| puts "    #{k} = #{v}g" }
    end

    choices = [{ name: 'Add portion', value: :add }]
    choices << { name: 'Edit portion', value: :edit } if entry['portions'].any?
    choices << { name: 'Remove portion', value: :remove } if entry['portions'].any?
    choices << { name: 'Done', value: :done }

    action = PROMPT.select('Portions:', choices)

    case action
    when :add
      name_suggestion = entry['portions'].key?('~unitless') ? nil : '~unitless'
      portion_name = PROMPT.ask('Portion name:', default: name_suggestion)
      grams = PROMPT.ask('Gram weight:', convert: :float)
      entry['portions'][portion_name] = grams if portion_name && grams
    when :edit
      key = PROMPT.select('Edit which?', entry['portions'].keys)
      new_value = PROMPT.ask("New gram weight for #{key}:", default: entry['portions'][key].to_s, convert: :float)
      entry['portions'][key] = new_value if new_value
    when :remove
      key = PROMPT.select('Remove which?', entry['portions'].keys)
      entry['portions'].delete(key) if PROMPT.yes?("Remove #{key}?")
    when :done
      return
    end
  end
end
```

**Step 5: Add nutrients editing submenu**

```ruby
def edit_nutrients(entry)
  entry['nutrients'] ||= {}

  nutrient = PROMPT.select('Edit which nutrient?',
    NUTRIENTS.map { |n| { name: "#{n[:label]}: #{entry.dig('nutrients', n[:key]) || 0}", value: n[:key] } } +
    [{ name: 'Done', value: :done }])

  return if nutrient == :done

  current = entry.dig('nutrients', nutrient) || 0
  new_value = PROMPT.ask("New value for #{nutrient}:", default: current.to_s, convert: :float)
  entry['nutrients'][nutrient] = new_value if new_value
end
```

**Step 6: Rewrite edit_sources with TTY**

```ruby
def edit_sources(sources)
  loop do
    if sources.any?
      puts PASTEL.dim("\n  Sources:")
      sources.each_with_index { |s, i| puts "    #{i + 1}. #{format_source(s)}" }
    else
      puts PASTEL.dim("\n  Sources: none")
    end

    choices = [{ name: 'Add USDA source', value: :add }]
    choices << { name: 'Remove source', value: :remove } if sources.any?
    choices << { name: 'Done', value: :done }

    action = PROMPT.select('Sources:', choices)

    case action
    when :add    then sources << prompt_usda_source
    when :remove then remove_source(sources)
    when :done   then return sources
    end
  end
end

def remove_source(sources)
  labels = sources.each_with_index.map { |s, i| { name: format_source(s), value: i } }
  idx = PROMPT.select('Remove which?', labels)
  sources.delete_at(idx) if PROMPT.yes?('Confirm removal?')
end

def prompt_usda_source
  {
    'type' => 'usda',
    'dataset' => PROMPT.ask('Dataset:', default: 'SR Legacy'),
    'fdc_id' => PROMPT.ask('FDC ID:', convert: :int),
    'description' => PROMPT.ask('Description:')
  }.compact
end
```

**Step 7: Update all callers**

Update all function signatures that previously took `api_key:` to take `client:` instead:
- `review_and_save`
- `edit_entry`
- `enter_new_ingredient`
- `handle_ingredient`
- `run_missing_mode`

**Step 8: Verify interactively**

Run: `bin/nutrition "Butter"`
- Review screen shows with arrow-key action menu
- Edit menu shows all 6 options (density, portions, nutrients, reimport, sources, done)
- Each submenu works with arrow-key navigation
- Save prompts for aliases then writes YAML

**Step 9: Commit**

```bash
git add bin/nutrition
git commit -m "feat: expanded edit menu with density/portion/nutrient editing

tty-prompt menus for review and edit loops. Interactive density,
portions (including ~unitless), and nutrient value editing without
leaving the tool. Ref: GH #140 item 2."
```

---

### Task 7: Alias multi-select + smarter search query

Replace the comma-separated alias input with a tty-prompt multi-select.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Rewrite prompt_aliases**

```ruby
def suggest_aliases(name, _entry)
  base, qualifier = name.match(/\A(.+?)\s*\(([^)]+)\)\z/)&.captures || [name, nil]
  return [] unless qualifier

  [base.strip, "#{qualifier.strip.capitalize} #{base.strip.downcase}"].uniq - [name]
end

def prompt_aliases(name, entry)
  existing = entry['aliases'] || []
  suggestions = suggest_aliases(name, entry) - existing

  all_options = existing.map { |a| { name: a, value: a } } +
                suggestions.map { |a| { name: "#{a} #{PASTEL.dim('(suggested)')}", value: a } }

  if all_options.empty?
    custom = PROMPT.ask("Aliases for #{name} (comma-separated, or Enter to skip):")
    return parse_comma_aliases(custom)
  end

  defaults = existing.dup
  selected = PROMPT.multi_select("Aliases for #{name}:", all_options, default: defaults)

  custom = PROMPT.ask('Additional aliases (comma-separated, or Enter to skip):')
  (selected + parse_comma_aliases(custom)).uniq
end

def parse_comma_aliases(input)
  return [] if input.nil? || input.strip.empty?

  input.split(',').map(&:strip).reject(&:empty?)
end
```

**Step 2: Verify interactively**

Run: `bin/nutrition "Flour (all-purpose)"`
- After save, alias prompt shows multi-select with existing aliases pre-checked
- Suggestions ("Flour", "All-purpose flour") shown with dim "(suggested)" label
- Space toggles, Enter confirms
- Additional custom aliases can be typed

**Step 3: Commit**

```bash
git add bin/nutrition
git commit -m "feat: alias multi-select with tty-prompt

Existing aliases pre-checked, suggestions shown unchecked, custom
entry via comma-separated follow-up. Ref: GH #140 item 7."
```

---

### Task 8: Missing + coverage modes with TTY

Rewrite `run_missing_mode` and `run_coverage_mode` with color-coded output and tty-table.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Rewrite run_missing_mode**

Replace `puts` with pastel-colored output. Replace the `print 'Enter data? (y/n):'` pattern with `PROMPT.yes?`. Use tty-table for the missing/unresolvable lists.

```ruby
def run_missing_mode(nutrition_data, ctx, client:)
  result = find_missing_ingredients(nutrition_data, ctx)
  missing = result[:missing]
  recipes_map = result[:ingredients_to_recipes]
  unresolvable = result[:unresolvable]

  display_missing_report(missing, recipes_map)
  display_unresolvable_report(unresolvable)

  if missing.empty? && unresolvable.empty?
    puts PASTEL.green('All ingredients have nutrition data and resolvable units!')
    return
  end

  puts "\n#{PASTEL.bold("#{missing.size} missing")}, #{PASTEL.bold("#{unresolvable.size} unresolvable")}.\n"
  return unless PROMPT.yes?('Enter data now?')

  missing.each do |name|
    puts "\n#{PASTEL.bold("=== #{name} ===")}"
    handle_ingredient(name, nutrition_data, ctx, client: client)
  end

  unresolvable.sort_by { |_, info| -info[:recipes].size }.each do |name, _info|
    puts "\n#{PASTEL.bold("=== #{name} (fix unit conversions) ===")}"
    handle_ingredient(name, nutrition_data, ctx, client: client)
  end
end

def display_missing_report(missing, recipes_map)
  return if missing.empty?

  puts PASTEL.bold("\nMissing nutrition data (#{missing.size}):")
  missing.each do |name|
    recipes = recipes_map[name].uniq.sort
    count_label = recipes.size == 1 ? '1 recipe' : "#{recipes.size} recipes"
    puts "  #{PASTEL.red('●')} #{name} (#{count_label}: #{recipes.join(', ')})"
  end
end

def display_unresolvable_report(unresolvable)
  return if unresolvable.empty?

  puts PASTEL.bold("\nMissing unit conversions (#{unresolvable.size}):")
  unresolvable.sort_by { |_, info| [-info[:recipes].size, _] }.each do |name, info|
    units = info[:units].to_a.sort.join(', ')
    count_label = info[:recipes].size == 1 ? '1 recipe' : "#{info[:recipes].size} recipes"
    puts "  #{PASTEL.yellow('●')} #{name}: '#{units}' (#{count_label})"
  end
end
```

**Step 2: Rewrite run_coverage_mode**

```ruby
def run_coverage_mode
  nutrition_data = load_nutrition_data
  ctx = load_context

  result = find_missing_ingredients(nutrition_data, ctx)
  missing = result[:missing]
  recipes_map = result[:ingredients_to_recipes]

  total = recipes_map.size
  missing_count = missing.size
  found = total - missing_count
  omitted = nutrition_data.count { |_, e| e['aisle'] == 'omit' }

  resolvable_map = count_resolvable(nutrition_data, ctx)
  resolvable = resolvable_map.count { |_, v| v }

  puts PASTEL.bold("\nIngredient Coverage Report")

  rows = [
    ['Total unique ingredients', total.to_s],
    ['Catalog entries found', "#{found} (#{format_pct(found, total)})"],
    ['Fully resolvable', "#{resolvable} (#{format_pct(resolvable, total)})"],
    ['Missing entirely', "#{missing_count} (#{format_pct(missing_count, total)})"],
    ['Omitted', omitted.to_s]
  ]

  table = TTY::Table.new(rows: rows)
  puts table.render(:basic, padding: [0, 2, 0, 2])

  print_top_missing(missing, recipes_map)
end
```

**Step 3: Verify**

Run: `bin/nutrition --coverage`
Expected: Color-coded table output.

Run: `bin/nutrition --missing`
Expected: Red dots for missing, yellow for unresolvable, confirm prompt with `PROMPT.yes?`.

**Step 4: Commit**

```bash
git add bin/nutrition
git commit -m "feat: TTY output for missing + coverage modes

Color-coded reports, tty-table for coverage summary, tty-prompt
for batch entry confirmation. Ref: GH #140."
```

---

### Task 9: Final cleanup + verification

Clean up any remaining manual I/O patterns, run lint, run tests, verify all modes interactively.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Audit for remaining $stdin.gets calls**

Search for any remaining `$stdin.gets` or bare `print` calls in `bin/nutrition`. Replace with `PROMPT.ask`, `PROMPT.select`, or `PROMPT.yes?` as appropriate.

The main dispatcher's interactive ingredient prompt:

```ruby
unless ingredient_name
  ingredient_name = PROMPT.ask('Ingredient name:')
end
```

**Step 2: Clean up format_source**

Keep the display branches for label/other source types (legacy data). Remove any now-dead helper code.

**Step 3: Run lint**

Run: `bundle exec rubocop bin/nutrition lib/familyrecipes/usda_client.rb`
Expected: No offenses.

**Step 4: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 5: Interactive smoke test all modes**

1. `bin/nutrition --help` — verify help text is current
2. `bin/nutrition --coverage` — verify colored coverage report
3. `bin/nutrition --missing` — verify colored missing report + batch entry prompt
4. `bin/nutrition "Butter"` — verify full flow: search → select → review → edit → save
5. `bin/nutrition` — verify interactive ingredient name prompt

**Step 6: Update --help text**

Make sure the help output mentions pagination and reflects the current CLI interface.

**Step 7: Commit**

```bash
git add bin/nutrition
git commit -m "feat: complete bin/nutrition TUI overhaul

Final cleanup: remaining manual I/O replaced with tty-prompt,
help text updated. All modes verified. Closes GH #140."
```

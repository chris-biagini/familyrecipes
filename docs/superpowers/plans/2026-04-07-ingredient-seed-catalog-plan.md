# Ingredient Seed Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pipeline of one-time scripts to generate a curated seed catalog of ~500 common ingredients with verified USDA nutrition data.

**Architecture:** Four-phase pipeline: (1) generate categorized ingredient list, (2) search USDA API + AI-assisted match selection, (3) human review via static HTML page, (4) generate YAML for the existing catalog. Scripts are standalone Ruby in `scripts/seed_catalog/`, intermediate data in `data/seed_catalog/`. The AI pick step (Phase 2b) runs inside Claude Code — no external Anthropic API calls.

**Tech Stack:** Ruby (stdlib only — net/http, json, yaml, erb), USDA FoodData Central API, existing `lib/familyrecipes/` modules for portion classification.

---

## Pipeline Overview

After all scripts are built, the end-to-end workflow is:

1. Edit `data/seed_catalog/ingredient_list.md` (user curates the ingredient names)
2. `USDA_API_KEY=xxx ruby scripts/seed_catalog/usda_search.rb` (fetch USDA search results)
3. Claude Code subagents enrich `data/seed_catalog/usda_search_results.json` with AI picks
4. `ruby scripts/seed_catalog/generate_review.rb` (generate HTML review page)
5. Open `data/seed_catalog/review.html` in browser, review picks, export decisions
6. `USDA_API_KEY=xxx ruby scripts/seed_catalog/generate_yaml.rb` (generate catalog YAML)
7. Diff `data/seed_catalog/seed_catalog.yaml` against existing catalog and merge

## File Structure

```
scripts/seed_catalog/
  shared.rb               # Shared utilities (parsing, JSON I/O, catalog entry builder)
  usda_search.rb          # Phase 2a: USDA API search
  generate_review.rb      # Phase 3: HTML review page generator
  generate_yaml.rb        # Phase 4: YAML catalog generation

data/seed_catalog/
  ingredient_list.md      # Phase 1: ~500 categorized ingredients (user-edited)
  usda_search_results.json # Intermediate: search results + AI picks
  review.html             # Generated: interactive review page
  reviewed_results.json   # Exported from review page (user decisions)
  seed_catalog.yaml       # Output: final YAML for merging into catalog

test/seed_catalog/
  shared_test.rb          # Tests for parsing and catalog entry builder
  fixtures/
    sample_ingredient_list.md
    sample_usda_detail.json
```

---

### Task 1: Shared Utilities and Test Infrastructure

**Files:**
- Create: `scripts/seed_catalog/shared.rb`
- Create: `test/seed_catalog/shared_test.rb`
- Create: `test/seed_catalog/fixtures/sample_ingredient_list.md`
- Create: `test/seed_catalog/fixtures/sample_usda_detail.json`
- Create: `data/seed_catalog/.gitkeep`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p scripts/seed_catalog data/seed_catalog test/seed_catalog/fixtures
touch data/seed_catalog/.gitkeep
```

- [ ] **Step 2: Write test fixtures**

Create `test/seed_catalog/fixtures/sample_ingredient_list.md`:

```markdown
# Ingredient List

## Produce
- Apples
- Carrots
- Garlic

## Dairy & Eggs
- Butter
- Milk
```

Create `test/seed_catalog/fixtures/sample_usda_detail.json` — a realistic
USDA detail response for testing the catalog entry builder:

```json
{
  "fdc_id": "173430",
  "description": "Butter, without salt",
  "data_type": "SR Legacy",
  "nutrients": {
    "basis_grams": 100.0,
    "calories": 717.0,
    "fat": 81.11,
    "saturated_fat": 51.368,
    "trans_fat": 3.278,
    "cholesterol": 215.0,
    "sodium": 11.0,
    "carbs": 0.06,
    "fiber": 0.0,
    "total_sugars": 0.06,
    "protein": 0.85,
    "added_sugars": 0.0
  },
  "portions": [
    { "modifier": "cup", "grams": 227.0, "amount": 1.0 },
    { "modifier": "tbsp", "grams": 14.2, "amount": 1.0 },
    { "modifier": "pat (1\" sq, 1/3\" high)", "grams": 5.0, "amount": 1.0 },
    { "modifier": "stick", "grams": 113.0, "amount": 1.0 }
  ]
}
```

- [ ] **Step 3: Write failing tests for shared module**

Create `test/seed_catalog/shared_test.rb`:

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'yaml'
require_relative '../../scripts/seed_catalog/shared'

class SeedCatalogSharedTest < Minitest::Test
  FIXTURES = File.expand_path('fixtures', __dir__)

  def test_parse_ingredient_list
    path = File.join(FIXTURES, 'sample_ingredient_list.md')
    result = SeedCatalog.parse_ingredient_list(path)

    assert_equal 5, result.size
    assert_equal 'Apples', result[0][:name]
    assert_equal 'Produce', result[0][:category]
    assert_equal 'Milk', result[4][:name]
    assert_equal 'Dairy & Eggs', result[4][:category]
  end

  def test_parse_ingredient_list_skips_blank_lines_and_prose
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.md')
      File.write(path, <<~MD)
        # Ingredient List

        Some intro text that should be ignored.

        ## Produce
        - Apples

        - Carrots
      MD

      result = SeedCatalog.parse_ingredient_list(path)

      assert_equal 2, result.size
      assert_equal 'Apples', result[0][:name]
      assert_equal 'Carrots', result[1][:name]
    end
  end

  def test_json_round_trip
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'test.json')
      data = [{ 'name' => 'Butter', 'category' => 'Dairy' }]

      SeedCatalog.write_json(path, data)
      result = SeedCatalog.read_json(path)

      assert_equal data, result
    end
  end

  def test_read_json_returns_empty_array_for_missing_file
    result = SeedCatalog.read_json('/nonexistent/path.json')

    assert_equal [], result
  end

  def test_build_catalog_entry
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated',
                                                    aliases: ['Sweet cream butter'])

    assert_equal 100.0, entry['nutrients']['basis_grams']
    assert_equal 717.0, entry['nutrients']['calories']
    assert_equal 81.11, entry['nutrients']['fat']

    source = entry['sources'].first
    assert_equal 'usda', source['type']
    assert_equal 'SR Legacy', source['dataset']
    assert_equal 173_430, source['fdc_id']
    assert_equal 'Butter, without salt', source['description']

    assert_equal 'Refrigerated', entry['aisle']
    assert_equal ['Sweet cream butter'], entry['aliases']

    assert entry.key?('density'), 'Expected density from cup portion'
    assert_equal 'cup', entry['density']['unit']
    assert_equal 1.0, entry['density']['volume']
    assert_equal 227.0, entry['density']['grams']
  end

  def test_build_catalog_entry_omits_empty_aliases
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated', aliases: [])

    refute entry.key?('aliases')
  end

  def test_build_catalog_entry_produces_valid_yaml
    detail = load_fixture(:sample_usda_detail)
    entry = SeedCatalog.build_catalog_entry(detail, aisle: 'Refrigerated', aliases: [])

    catalog = { 'Butter (unsalted)' => entry }
    yaml_str = YAML.dump(catalog)
    roundtripped = YAML.safe_load(yaml_str)

    assert_equal entry['nutrients']['calories'],
                 roundtripped['Butter (unsalted)']['nutrients']['calories']
    assert_equal 'usda', roundtripped['Butter (unsalted)']['sources'].first['type']
  end

  private

  def load_fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")), symbolize_names: true)
  end
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `ruby test/seed_catalog/shared_test.rb`
Expected: Errors — `cannot load such file -- scripts/seed_catalog/shared`

- [ ] **Step 5: Write shared module**

Create `scripts/seed_catalog/shared.rb`:

```ruby
# frozen_string_literal: true

# Shared utilities for the seed catalog pipeline scripts.
# Standalone — no Rails dependency. Uses lib/familyrecipes/ modules
# for USDA portion classification only.

require 'json'
require 'fileutils'

# Load FamilyRecipes domain modules for portion classification.
# These are standalone (no Rails required).
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'familyrecipes/usda_client'
require 'familyrecipes/usda_portion_classifier'

module SeedCatalog
  DATA_DIR = File.expand_path('../../data/seed_catalog', __dir__)

  # --- File I/O ---

  def self.parse_ingredient_list(path)
    category = nil

    File.readlines(path, chomp: true).each_with_object([]) do |line, list|
      if line.start_with?('## ')
        category = line.delete_prefix('## ').strip
      elsif line.start_with?('- ')
        name = line.delete_prefix('- ').strip
        list << { name: name, category: category } unless name.empty?
      end
    end
  end

  def self.read_json(path)
    return [] unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def self.write_json(path, data)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(data))
  end

  # --- Catalog Entry Builder ---

  # Transforms a UsdaClient#fetch detail hash into a hash matching
  # the ingredient-catalog.yaml schema. Uses UsdaPortionClassifier
  # for density and portion extraction.
  def self.build_catalog_entry(detail, aisle:, aliases: [])
    entry = {}
    entry['nutrients'] = build_nutrients(detail[:nutrients])
    entry['sources'] = [build_source(detail)]
    add_density_and_portions(entry, detail[:portions])
    entry['aisle'] = aisle
    entry['aliases'] = aliases unless aliases.empty?
    entry
  end

  def self.build_nutrients(raw)
    raw.transform_keys(&:to_s).slice(
      'basis_grams', 'calories', 'fat', 'saturated_fat', 'trans_fat',
      'cholesterol', 'sodium', 'carbs', 'fiber', 'total_sugars',
      'protein', 'added_sugars'
    )
  end
  private_class_method :build_nutrients

  def self.build_source(detail)
    {
      'type' => 'usda',
      'dataset' => detail[:data_type],
      'fdc_id' => detail[:fdc_id].to_s.to_i,
      'description' => detail[:description]
    }
  end
  private_class_method :build_source

  def self.add_density_and_portions(entry, raw_portions)
    return if raw_portions.nil? || raw_portions.empty?

    classified = FamilyRecipes::UsdaPortionClassifier.classify(raw_portions)

    best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(
      classified.density_candidates
    )
    if best
      unit = FamilyRecipes::UsdaPortionClassifier.normalize_volume_unit(best[:modifier])
      entry['density'] = {
        'grams' => best[:each].round(2),
        'volume' => 1.0,
        'unit' => unit
      }
    end

    return if classified.portion_candidates.empty?

    entry['portions'] = classified.portion_candidates.each_with_object({}) do |p, h|
      name = FamilyRecipes::UsdaPortionClassifier.strip_parenthetical(p[:modifier]).strip
      h[name] = p[:each].round(2)
    end
  end
  private_class_method :add_density_and_portions
end
```

**Note on requires:** The script adds `lib/` to the load path and requires
the FamilyRecipes modules directly. These modules (`usda_client.rb`,
`usda_portion_classifier.rb`) are standalone Ruby — no Rails required.
If the requires fail because `FamilyRecipes` module is not yet defined,
add `module FamilyRecipes; end` before the requires. If
`usda_portion_classifier` needs `unit_resolver` or `inflector`, add those
requires explicitly. Verify by running:
`ruby -e "require_relative 'scripts/seed_catalog/shared'"` from project root.

- [ ] **Step 6: Run tests to verify they pass**

Run: `ruby test/seed_catalog/shared_test.rb`
Expected: 7 tests, 0 failures. Fix any require issues with the
FamilyRecipes module loading — see note above.

- [ ] **Step 7: Commit**

```bash
git add scripts/seed_catalog/shared.rb test/seed_catalog/ data/seed_catalog/.gitkeep
git commit -m "Add shared utilities for seed catalog pipeline"
```

---

### Task 2: USDA Search Script

**Files:**
- Create: `scripts/seed_catalog/usda_search.rb`

**Context:** This script reads the ingredient list, calls the USDA FoodData
Central search API for each ingredient, and writes the results to a JSON
file. It is resumable — already-searched ingredients are skipped on restart.

Read `scripts/seed_catalog/shared.rb` and `lib/familyrecipes/usda_client.rb`
before starting.

- [ ] **Step 1: Write the search script**

Create `scripts/seed_catalog/usda_search.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 2a: Search USDA FoodData Central for each ingredient in the
# ingredient list. Writes results to usda_search_results.json.
# Resumable — skips ingredients already in the output file.
#
# Usage: USDA_API_KEY=xxx ruby scripts/seed_catalog/usda_search.rb
#        USDA_API_KEY=xxx ruby scripts/seed_catalog/usda_search.rb path/to/list.md

require_relative 'shared'

RESULTS_PATH = File.join(SeedCatalog::DATA_DIR, 'usda_search_results.json')
SEARCH_PAGE_SIZE = 15

def run(ingredient_list_path) # rubocop:disable Metrics/MethodLength
  api_key = ENV.fetch('USDA_API_KEY') { abort 'Set USDA_API_KEY environment variable' }
  client = FamilyRecipes::UsdaClient.new(api_key: api_key)

  ingredients = SeedCatalog.parse_ingredient_list(ingredient_list_path)
  results = SeedCatalog.read_json(RESULTS_PATH)
  searched = results.map { |r| r['name'] }.to_set

  remaining = ingredients.reject { |i| searched.include?(i[:name]) }
  puts "#{ingredients.size} total, #{searched.size} already searched, #{remaining.size} remaining"

  remaining.each_with_index do |ingredient, index|
    print "[#{index + 1}/#{remaining.size}] #{ingredient[:name]}... "

    response = client.search(ingredient[:name], page_size: SEARCH_PAGE_SIZE)

    results << {
      'name' => ingredient[:name],
      'category' => ingredient[:category],
      'usda_results' => format_results(response[:foods])
    }

    SeedCatalog.write_json(RESULTS_PATH, results)
    puts "#{response[:foods].size} results"

    sleep 0.3
  rescue FamilyRecipes::UsdaClient::RateLimitError
    puts 'Rate limited — waiting 60s'
    sleep 60
    retry
  rescue FamilyRecipes::UsdaClient::Error => e
    puts "Error: #{e.message} — skipping"
  end

  puts "Done. Results saved to #{RESULTS_PATH}"
end

def format_results(foods)
  foods.map do |food|
    {
      'fdc_id' => food[:fdc_id].to_s.to_i,
      'description' => food[:description],
      'dataset' => food[:data_type],
      'nutrient_summary' => food[:nutrient_summary]
    }
  end
end

if $PROGRAM_NAME == __FILE__
  list_path = ARGV[0] || File.join(SeedCatalog::DATA_DIR, 'ingredient_list.md')
  abort "Ingredient list not found: #{list_path}" unless File.exist?(list_path)
  run(list_path)
end
```

- [ ] **Step 2: Verify the script loads without errors**

Run: `ruby -c scripts/seed_catalog/usda_search.rb`
Expected: `Syntax OK`

Run (from project root): `ruby -e "require_relative 'scripts/seed_catalog/usda_search'"`
Expected: No errors (the `if $PROGRAM_NAME == __FILE__` guard prevents execution)

- [ ] **Step 3: Commit**

```bash
git add scripts/seed_catalog/usda_search.rb
git commit -m "Add USDA search script for seed catalog pipeline"
```

---

### Task 3: Review HTML Generator

**Files:**
- Create: `scripts/seed_catalog/generate_review.rb`

**Context:** This script reads the enriched JSON (after AI picks have been
added) and generates a static HTML page for human review. The HTML includes
embedded JavaScript for status tracking, localStorage persistence, and JSON
export. All DOM construction must use `textContent`/`createElement` — no
`innerHTML` (consistent with the project's strict CSP practices).

Read `scripts/seed_catalog/shared.rb` before starting. The input JSON at
this point has the structure:

```json
[{
  "name": "Butter (unsalted)",
  "category": "Dairy & Eggs",
  "usda_results": [
    { "fdc_id": 173430, "description": "Butter, without salt", "dataset": "SR Legacy" }
  ],
  "ai_pick": { "fdc_id": 173430, "reasoning": "Standard unsalted butter" },
  "aisle": "Refrigerated",
  "aliases": ["Sweet cream butter"]
}]
```

- [ ] **Step 1: Write the review page generator**

Create `scripts/seed_catalog/generate_review.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 3: Generate an interactive HTML review page from the enriched
# search results JSON. The page embeds the data and uses vanilla JS
# for review workflow, localStorage persistence, and JSON export.
#
# Usage: ruby scripts/seed_catalog/generate_review.rb

require_relative 'shared'

RESULTS_PATH = File.join(SeedCatalog::DATA_DIR, 'usda_search_results.json')
REVIEW_PATH = File.join(SeedCatalog::DATA_DIR, 'review.html')

AISLES = %w[
  Baking Beverages Bread Cereal Condiments Frozen Gourmet
  Health Household International Miscellaneous Pantry Personal
  Produce Refrigerated Snacks Specialty Spices
].freeze

def run # rubocop:disable Metrics/MethodLength
  data = SeedCatalog.read_json(RESULTS_PATH)
  abort 'No search results found. Run usda_search.rb first.' if data.empty?

  without_picks = data.count { |d| d['ai_pick'].nil? }
  if without_picks.positive?
    warn "Warning: #{without_picks}/#{data.size} ingredients have no AI pick yet."
  end

  html = build_html(data)
  File.write(REVIEW_PATH, html)
  puts "Review page written to #{REVIEW_PATH} (#{data.size} ingredients)"
end

def build_html(data) # rubocop:disable Metrics/MethodLength
  <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <title>Seed Catalog Review</title>
    <style>
    #{css}
    </style>
    </head>
    <body>
    <h1>Seed Catalog Review</h1>
    <div class="controls">
      <label>Category: <select id="cat-filter"><option value="">All</option></select></label>
      <label>Status: <select id="status-filter">
        <option value="">All</option>
        <option value="pending">Pending</option>
        <option value="accept">Accepted</option>
        <option value="override">Override</option>
        <option value="skip">Skip</option>
        <option value="manual">Manual</option>
      </select></label>
      <span id="stats"></span>
      <button id="export-btn">Export Decisions</button>
      <button id="clear-btn">Clear All Decisions</button>
    </div>
    <table>
    <thead><tr>
      <th class="col-name">Ingredient</th>
      <th class="col-cat">Category</th>
      <th class="col-pick">AI Pick</th>
      <th class="col-reason">Reasoning</th>
      <th class="col-alts">Alternatives</th>
      <th class="col-aisle">Aisle</th>
      <th class="col-aliases">Aliases</th>
      <th class="col-status">Status</th>
      <th class="col-override">Override FDC ID</th>
      <th class="col-notes">Notes</th>
    </tr></thead>
    <tbody id="tbody"></tbody>
    </table>

    <script type="application/json" id="ingredient-data">
    #{JSON.generate(data)}
    </script>
    <script type="application/json" id="aisle-list">
    #{JSON.generate(AISLES)}
    </script>
    <script>
    #{javascript}
    </script>
    </body>
    </html>
  HTML
end

def css
  <<~CSS
    * { box-sizing: border-box; }
    body {
      font-family: system-ui, sans-serif; margin: 0 auto;
      padding: 16px; max-width: 1600px; font-size: 14px;
    }
    h1 { margin: 0 0 12px; }
    .controls {
      display: flex; align-items: center; gap: 12px;
      margin-bottom: 12px; flex-wrap: wrap;
    }
    .controls label { font-weight: 500; }
    #stats { margin-left: auto; color: #555; }
    button { padding: 6px 14px; cursor: pointer; }
    table { border-collapse: collapse; width: 100%; }
    th, td {
      border: 1px solid #ccc; padding: 6px 8px;
      text-align: left; vertical-align: top;
    }
    th { background: #f0f0f0; position: sticky; top: 0; z-index: 1; }
    .col-name { min-width: 140px; font-weight: 600; }
    .col-cat { min-width: 100px; }
    .col-pick { min-width: 200px; }
    .col-reason { min-width: 140px; font-size: 13px; color: #555; }
    .col-alts { min-width: 200px; font-size: 13px; }
    .col-aisle { min-width: 100px; }
    .col-aliases { min-width: 120px; }
    .col-status { min-width: 90px; }
    .col-override { min-width: 100px; }
    .col-notes { min-width: 100px; }
    a { color: #0066cc; }
    tr[data-status="accept"] { background: #e8f5e9; }
    tr[data-status="skip"] { background: #fce4ec; }
    tr[data-status="manual"] { background: #fff3e0; }
    tr[data-status="override"] { background: #e3f2fd; }
    select, input { padding: 4px; font-size: 13px; }
    td input[type="text"] { width: 100%; }
    td input[type="number"] { width: 80px; }
    .alt-link { display: block; margin: 2px 0; }
    .no-pick { color: #999; font-style: italic; }
  CSS
end

def javascript # rubocop:disable Metrics/MethodLength
  <<~'JS'
    (function() {
      var data = JSON.parse(document.getElementById('ingredient-data').textContent);
      var aisles = JSON.parse(document.getElementById('aisle-list').textContent);
      var STORAGE_KEY = 'seed_catalog_review';
      var decisions = loadDecisions();
      var tbody = document.getElementById('tbody');
      var catFilter = document.getElementById('cat-filter');
      var statusFilter = document.getElementById('status-filter');

      initCategoryFilter();
      renderTable();
      updateStats();

      catFilter.addEventListener('change', renderTable);
      statusFilter.addEventListener('change', renderTable);
      document.getElementById('export-btn').addEventListener('click', exportDecisions);
      document.getElementById('clear-btn').addEventListener('click', function() {
        if (confirm('Clear all review decisions?')) {
          decisions = {};
          localStorage.removeItem(STORAGE_KEY);
          renderTable();
          updateStats();
        }
      });

      function usdaLink(fdcId) {
        return 'https://fdc.nal.usda.gov/food-details/' + fdcId + '/nutrients';
      }

      function initCategoryFilter() {
        var cats = [];
        data.forEach(function(d) {
          if (d.category && cats.indexOf(d.category) === -1) cats.push(d.category);
        });
        cats.sort().forEach(function(c) {
          var opt = document.createElement('option');
          opt.value = c;
          opt.textContent = c;
          catFilter.appendChild(opt);
        });
      }

      function getDecision(name) {
        return decisions[name] || {
          status: 'pending', override_fdc_id: '', aisle: '', aliases: '', notes: ''
        };
      }

      function setDecision(name, field, value) {
        if (!decisions[name]) {
          decisions[name] = {
            status: 'pending', override_fdc_id: '', aisle: '', aliases: '', notes: ''
          };
        }
        decisions[name][field] = value;
        localStorage.setItem(STORAGE_KEY, JSON.stringify(decisions));
        updateStats();
      }

      function renderTable() {
        while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
        var catVal = catFilter.value;
        var statusVal = statusFilter.value;
        data.forEach(function(item, idx) {
          var dec = getDecision(item.name);
          if (catVal && item.category !== catVal) return;
          if (statusVal && dec.status !== statusVal) return;
          tbody.appendChild(buildRow(item, idx, dec));
        });
      }

      function buildRow(item, idx, dec) {
        var tr = document.createElement('tr');
        tr.setAttribute('data-status', dec.status);

        addCell(tr, item.name);
        addCell(tr, item.category || '');
        addPickCell(tr, item);
        addCell(tr, (item.ai_pick && item.ai_pick.reasoning) || '');
        addAltsCell(tr, item);
        addAisleCell(tr, item, dec);
        addInputCell(tr, item, dec, 'aliases', (item.aliases || []).join(', '));
        addStatusCell(tr, item, dec);
        addOverrideCell(tr, item, dec);
        addInputCell(tr, item, dec, 'notes', '');

        return tr;
      }

      function addCell(tr, text) {
        var td = document.createElement('td');
        td.textContent = text;
        tr.appendChild(td);
      }

      function addPickCell(tr, item) {
        var td = document.createElement('td');
        if (item.ai_pick) {
          var a = document.createElement('a');
          a.href = usdaLink(item.ai_pick.fdc_id);
          a.target = '_blank';
          var desc = findDesc(item, item.ai_pick.fdc_id) || 'Unknown';
          a.textContent = item.ai_pick.fdc_id + ': ' + desc;
          td.appendChild(a);
        } else {
          var span = document.createElement('span');
          span.className = 'no-pick';
          span.textContent = 'No AI pick';
          td.appendChild(span);
        }
        tr.appendChild(td);
      }

      function addAltsCell(tr, item) {
        var td = document.createElement('td');
        (item.usda_results || []).forEach(function(r) {
          if (item.ai_pick && r.fdc_id === item.ai_pick.fdc_id) return;
          var a = document.createElement('a');
          a.href = usdaLink(r.fdc_id);
          a.target = '_blank';
          a.className = 'alt-link';
          var label = r.fdc_id + ': ' + r.description;
          if (r.dataset) label += ' [' + r.dataset + ']';
          a.textContent = label;
          td.appendChild(a);
        });
        tr.appendChild(td);
      }

      function addAisleCell(tr, item, dec) {
        var td = document.createElement('td');
        var sel = document.createElement('select');
        var empty = document.createElement('option');
        empty.value = '';
        empty.textContent = '\u2014';
        sel.appendChild(empty);
        aisles.forEach(function(a) {
          var opt = document.createElement('option');
          opt.value = a;
          opt.textContent = a;
          sel.appendChild(opt);
        });
        sel.value = dec.aisle || item.aisle || '';
        sel.addEventListener('change', function() {
          setDecision(item.name, 'aisle', this.value);
        });
        td.appendChild(sel);
        tr.appendChild(td);
      }

      function addInputCell(tr, item, dec, field, fallback) {
        var td = document.createElement('td');
        var input = document.createElement('input');
        input.type = 'text';
        input.value = dec[field] || fallback;
        input.addEventListener('change', function() {
          setDecision(item.name, field, this.value);
        });
        td.appendChild(input);
        tr.appendChild(td);
      }

      function addStatusCell(tr, item, dec) {
        var td = document.createElement('td');
        var sel = document.createElement('select');
        ['pending', 'accept', 'override', 'skip', 'manual'].forEach(function(s) {
          var opt = document.createElement('option');
          opt.value = s;
          opt.textContent = s.charAt(0).toUpperCase() + s.slice(1);
          sel.appendChild(opt);
        });
        sel.value = dec.status;
        sel.addEventListener('change', function() {
          setDecision(item.name, 'status', this.value);
          tr.setAttribute('data-status', this.value);
        });
        td.appendChild(sel);
        tr.appendChild(td);
      }

      function addOverrideCell(tr, item, dec) {
        var td = document.createElement('td');
        var input = document.createElement('input');
        input.type = 'number';
        input.value = dec.override_fdc_id || '';
        input.placeholder = 'FDC ID';
        input.addEventListener('change', function() {
          setDecision(item.name, 'override_fdc_id', this.value);
        });
        td.appendChild(input);
        tr.appendChild(td);
      }

      function findDesc(item, fdcId) {
        var match = (item.usda_results || []).filter(function(r) {
          return r.fdc_id === fdcId;
        });
        return match.length > 0 ? match[0].description : null;
      }

      function updateStats() {
        var total = data.length;
        var counts = { pending: 0, accept: 0, override: 0, skip: 0, manual: 0 };
        data.forEach(function(d) {
          var s = getDecision(d.name).status;
          counts[s] = (counts[s] || 0) + 1;
        });
        var reviewed = total - counts.pending;
        document.getElementById('stats').textContent =
          reviewed + '/' + total + ' reviewed | ' +
          counts.accept + ' accepted, ' + counts.override + ' override, ' +
          counts.skip + ' skip, ' + counts.manual + ' manual';
      }

      function loadDecisions() {
        try {
          var stored = localStorage.getItem(STORAGE_KEY);
          return stored ? JSON.parse(stored) : {};
        } catch(e) { return {}; }
      }

      function exportDecisions() {
        var exported = data.map(function(item) {
          var dec = getDecision(item.name);
          var out = JSON.parse(JSON.stringify(item));
          out.review = {
            status: dec.status,
            override_fdc_id: dec.override_fdc_id
              ? parseInt(dec.override_fdc_id, 10) : null,
            aisle: dec.aisle || item.aisle || null,
            aliases: dec.aliases
              ? dec.aliases.split(',').map(function(s) {
                  return s.trim();
                }).filter(Boolean)
              : (item.aliases || []),
            notes: dec.notes || null
          };
          return out;
        });
        var blob = new Blob(
          [JSON.stringify(exported, null, 2)],
          { type: 'application/json' }
        );
        var a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = 'reviewed_results.json';
        a.click();
        URL.revokeObjectURL(a.href);
      }
    })();
  JS
end

if $PROGRAM_NAME == __FILE__
  run
end
```

- [ ] **Step 2: Verify the script loads without errors**

Run: `ruby -c scripts/seed_catalog/generate_review.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Smoke test with fixture data**

Create a small test JSON and run the generator:

```bash
cp /dev/stdin data/seed_catalog/usda_search_results.json << 'EOF'
[{
  "name": "Butter (unsalted)",
  "category": "Dairy & Eggs",
  "usda_results": [
    { "fdc_id": 173430, "description": "Butter, without salt", "dataset": "SR Legacy" },
    { "fdc_id": 173431, "description": "Butter, whipped, without salt", "dataset": "SR Legacy" }
  ],
  "ai_pick": { "fdc_id": 173430, "reasoning": "Standard unsalted stick butter" },
  "aisle": "Refrigerated",
  "aliases": ["Sweet cream butter"]
}]
EOF
ruby scripts/seed_catalog/generate_review.rb
```

Expected: `Review page written to .../review.html (1 ingredients)`

Verify the HTML file exists and contains the expected structure:
```bash
grep -c 'Butter (unsalted)' data/seed_catalog/review.html
grep -c 'fdc.nal.usda.gov/food-details/173430' data/seed_catalog/review.html
```

Expected: Both return `1` or more.

Clean up: `rm data/seed_catalog/usda_search_results.json data/seed_catalog/review.html`

- [ ] **Step 4: Commit**

```bash
git add scripts/seed_catalog/generate_review.rb
git commit -m "Add review HTML generator for seed catalog pipeline"
```

---

### Task 4: YAML Generation Script

**Files:**
- Create: `scripts/seed_catalog/generate_yaml.rb`

**Context:** This script reads the reviewed JSON (exported from the HTML
review page) and generates a YAML file in the same format as the existing
`ingredient-catalog.yaml`. For each accepted/overridden ingredient, it
fetches the full USDA detail to get nutrients, density, and portions.

Read `scripts/seed_catalog/shared.rb` and `lib/familyrecipes/usda_client.rb`
before starting.

- [ ] **Step 1: Write the YAML generation script**

Create `scripts/seed_catalog/generate_yaml.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 4: Generate ingredient-catalog.yaml entries from the reviewed
# search results. Fetches full USDA nutrient detail for each approved
# ingredient via the USDA API.
#
# Usage: USDA_API_KEY=xxx ruby scripts/seed_catalog/generate_yaml.rb
#        USDA_API_KEY=xxx ruby scripts/seed_catalog/generate_yaml.rb path/to/reviewed.json

require 'yaml'
require_relative 'shared'

REVIEWED_PATH = File.join(SeedCatalog::DATA_DIR, 'reviewed_results.json')
OUTPUT_PATH = File.join(SeedCatalog::DATA_DIR, 'seed_catalog.yaml')

EXISTING_CATALOG_PATH = File.join(
  File.expand_path('../../db/seeds/resources', __dir__),
  'ingredient-catalog.yaml'
)

def run(reviewed_path) # rubocop:disable Metrics/MethodLength
  api_key = ENV.fetch('USDA_API_KEY') { abort 'Set USDA_API_KEY environment variable' }
  client = FamilyRecipes::UsdaClient.new(api_key: api_key)

  reviewed = SeedCatalog.read_json(reviewed_path)
  abort 'No reviewed data found. Export from the review page first.' if reviewed.empty?

  existing = load_existing_names
  actionable = reviewed.select { |item| processable?(item) }
  puts "#{actionable.size} to process (#{reviewed.size} total)"

  catalog = {}

  actionable.each_with_index do |item, index|
    name = item['name']

    if existing.include?(name.downcase)
      puts "[#{index + 1}/#{actionable.size}] #{name} — already in catalog, skipping"
      next
    end

    fdc_id = resolve_fdc_id(item)
    print "[#{index + 1}/#{actionable.size}] #{name} (FDC #{fdc_id})... "

    detail = client.fetch(fdc_id: fdc_id.to_s)
    review = item['review']
    aisle = review['aisle'] || item['aisle'] || 'Miscellaneous'
    aliases = review['aliases'] || item['aliases'] || []

    catalog[name] = SeedCatalog.build_catalog_entry(
      detail, aisle: aisle, aliases: aliases
    )
    puts 'ok'

    sleep 0.3
  rescue FamilyRecipes::UsdaClient::RateLimitError
    puts 'Rate limited — waiting 60s'
    sleep 60
    retry
  rescue FamilyRecipes::UsdaClient::Error => e
    puts "Error: #{e.message} — skipping"
  end

  write_catalog(catalog)
  puts "Wrote #{catalog.size} entries to #{OUTPUT_PATH}"
end

def processable?(item)
  status = item.dig('review', 'status')
  status == 'accept' || status == 'override'
end

def resolve_fdc_id(item)
  review = item['review']
  if review['status'] == 'override' && review['override_fdc_id']
    review['override_fdc_id']
  else
    item.dig('ai_pick', 'fdc_id')
  end
end

def load_existing_names
  return Set.new unless File.exist?(EXISTING_CATALOG_PATH)

  yaml = YAML.safe_load_file(EXISTING_CATALOG_PATH, permitted_classes: [],
                                                     permitted_symbols: [],
                                                     aliases: false)
  yaml.keys.map(&:downcase).to_set
end

def write_catalog(catalog)
  sorted = catalog.sort_by { |name, _| name.downcase }.to_h
  File.write(OUTPUT_PATH, YAML.dump(sorted))
end

if $PROGRAM_NAME == __FILE__
  path = ARGV[0] || REVIEWED_PATH
  abort "Reviewed file not found: #{path}" unless File.exist?(path)
  run(path)
end
```

- [ ] **Step 2: Verify the script loads without errors**

Run: `ruby -c scripts/seed_catalog/generate_yaml.rb`
Expected: `Syntax OK`

Run (from project root): `ruby -e "require_relative 'scripts/seed_catalog/generate_yaml'"`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add scripts/seed_catalog/generate_yaml.rb
git commit -m "Add YAML generation script for seed catalog pipeline"
```

---

### Task 5: Generate Ingredient List

**Files:**
- Create: `data/seed_catalog/ingredient_list.md`

**Context:** Generate a list of ~500 common ingredients used in typical North
American home cooking, organized by category. Follow the naming conventions
from the existing catalog.

Read the existing catalog names first:
```bash
grep -E '^[A-Za-z]' db/seeds/resources/ingredient-catalog.yaml
```

Study the naming patterns described in the design spec
(`docs/superpowers/specs/2026-04-07-ingredient-seed-catalog-design.md`),
under "Naming conventions":

- Capitalized natural language: "Heavy cream", not "heavy cream"
- Parenthetical qualifiers for variants: "Flour (all-purpose)"
- Parenthetical for form/packaging: "Tomatoes (canned)"
- Bare name = most common variant ("Milk" = whole)
- Nutritionally significant variants get separate entries
- Cheese by name without suffix: "Cheddar", not "Cheddar cheese"
- Singular or plural based on what reads naturally in a recipe
- Brands when that is what people buy: "Worcestershire sauce"

- [ ] **Step 1: Generate the categorized ingredient list**

Create `data/seed_catalog/ingredient_list.md` with ~500 ingredients grouped
under `##` category headers. Each ingredient is a `- ` bullet. Categories:

- **Produce — Vegetables** (~65 items): alliums (onion, garlic, shallots,
  leeks, green onions), root vegetables, nightshades, brassicas, leafy
  greens, squash family, peppers by color, mushrooms, corn, peas, beans
  (fresh), etc.

- **Produce — Fruits** (~30 items): common fruits, citrus, berries
  (individually), tropical, stone fruits, melons, dried fruits (raisins,
  dates, dried cranberries)

- **Produce — Fresh Herbs** (~15 items): basil, cilantro, parsley, dill,
  mint, rosemary, thyme, chives, sage, tarragon, oregano (fresh),
  lemongrass, ginger (fresh)

- **Dairy & Eggs** (~35 items): milk variants (whole, 2%, skim), cream
  types, cultured dairy (sour cream, yogurt, Greek yogurt, buttermilk),
  butter variants, eggs/whites/yolks, cheeses by name (cheddar, mozzarella,
  parmesan, Swiss, provolone, feta, goat cheese, ricotta, brie, blue
  cheese, cream cheese, cottage cheese, etc.)

- **Meat & Poultry** (~30 items): chicken cuts (breast, thigh, drumstick,
  whole, ground), beef cuts (ground, stew, steak, roast), pork cuts
  (chops, tenderloin, shoulder, ground), lamb, turkey (ground, breast),
  bacon, ham, sausage types, deli meats

- **Seafood** (~20 items): salmon, shrimp, tuna (canned), cod, tilapia,
  halibut, crab, scallops, mussels, clams, sardines (canned), anchovies

- **Pantry — Canned & Jarred** (~25 items): tomato products (canned,
  paste, sauce, passata, sun-dried), beans (black, kidney, cannellini,
  chickpeas — all canned), coconut milk, olives, capers, artichoke hearts,
  roasted red peppers, pumpkin puree (canned)

- **Pantry — Grains, Pasta & Rice** (~25 items): rice variants (white,
  brown, jasmine, basmati, arborio), pasta shapes, egg noodles, couscous,
  quinoa, farro, oats (rolled, steel-cut), bread crumbs, cornmeal, polenta

- **Pantry — Oils & Vinegars** (~15 items): olive oil, olive oil
  (extra-virgin), vegetable oil, canola oil, sesame oil, coconut oil,
  avocado oil, vinegars (white, apple cider, balsamic, red wine, rice)

- **Pantry — Nuts & Seeds** (~15 items): almonds, walnuts, pecans,
  peanuts, cashews, pine nuts, pistachios, sesame seeds, sunflower seeds,
  chia seeds, flaxseed, peanut butter, almond butter, tahini

- **Baking** (~25 items): flours (AP, bread, whole wheat, cake,
  almond, coconut), sugars (white, brown, powdered), leaveners,
  cocoa powder, chocolate chips, chocolate (baking), vanilla extract,
  almond extract, cornstarch, cream of tartar, molasses, corn syrup,
  gelatin, food coloring

- **Spices & Seasonings** (~50 items): salt (table, kosher), pepper,
  garlic powder, onion powder, paprika, smoked paprika, cumin, chili
  powder, oregano, Italian seasoning, cinnamon, nutmeg, ginger (ground),
  cayenne, turmeric, coriander, cardamom, cloves, allspice, bay leaves,
  red pepper flakes, curry powder, five-spice, mustard (dry), celery
  salt, seasoning salt, MSG, vanilla bean, saffron, etc.

- **Condiments & Sauces** (~30 items): soy sauce, Worcestershire sauce,
  hot sauce, ketchup, mustard (yellow, Dijon, whole grain), mayonnaise,
  honey, maple syrup, barbecue sauce, hoisin sauce, fish sauce, sriracha,
  oyster sauce, teriyaki sauce, salsa, pasta sauce (jarred), pesto,
  miso paste, horseradish, Tabasco, relish, jam/jelly

- **Refrigerated** (~12 items): tofu, tortillas (flour, corn), puff
  pastry, pie crust, pizza dough, fresh mozzarella, hummus, kimchi

- **Frozen** (~15 items): frozen peas, frozen corn, frozen spinach,
  frozen broccoli, frozen mixed vegetables, frozen berries, frozen
  shrimp, frozen pie crust, ice cream (vanilla), frozen hash browns

- **Bread & Bakery** (~12 items): bread (white, whole wheat), sandwich
  rolls, hamburger buns, hot dog buns, pita, naan, English muffins,
  tortilla chips, crackers, breadsticks, croutons

- **Beverages & Cooking Liquids** (~15 items): chicken broth, beef broth,
  vegetable broth, wine (white, cooking), wine (red, cooking), beer,
  coffee, tea, apple juice, orange juice, lemon juice (bottled),
  lime juice (bottled), coconut water

Target: ~480-520 items total. The above guidance is approximate — use
judgment to include the most commonly used ingredients in each category.

- [ ] **Step 2: Verify the list parses correctly**

Run from project root:
```bash
ruby -e "require_relative 'scripts/seed_catalog/shared'; puts SeedCatalog.parse_ingredient_list('data/seed_catalog/ingredient_list.md').size"
```

Expected: A number between 470 and 530.

- [ ] **Step 3: Commit**

```bash
git add data/seed_catalog/ingredient_list.md
git commit -m "Add curated ingredient list for seed catalog (~500 ingredients)"
```

---

## AI Pick Workflow (Between Tasks 2 and 3)

After running the USDA search script, the intermediate JSON contains search
results but no AI picks. The pick step runs inside Claude Code:

1. Read `data/seed_catalog/usda_search_results.json`
2. For batches of ~20-30 ingredients, review the USDA search results and
   select the best match — prefer SR Legacy entries
3. Add `ai_pick` (with `fdc_id` and `reasoning`), `aisle`, and `aliases`
   fields to each ingredient in the JSON
4. Write the enriched JSON back to the same file

This is an interactive step run via Claude Code subagents after the USDA
search completes and before the review page generation. The subagent prompt
for each batch should include the batch of ingredients with their USDA
results, the fixed aisle list, and instructions to prefer SR Legacy and
suggest 0-3 aliases per ingredient.

---

## RuboCop Notes

The scripts in `scripts/seed_catalog/` are standalone one-time-use files.
They may need `rubocop:disable` comments for `Metrics/MethodLength` on the
longer methods. The test file uses `Minitest::Test` (not ActiveSupport) and
needs to be added to the `Rails/RefuteMethods` exclusion in `.rubocop.yml`
alongside the existing parser test exclusions.

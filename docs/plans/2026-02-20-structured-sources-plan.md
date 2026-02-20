# Structured Source Metadata Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace flat `source` strings in nutrition-data.yaml with typed `sources` arrays for richer, machine-parseable provenance metadata.

**Architecture:** One-time migration script converts existing entries. `bin/nutrition` updated to read/write/edit the new format. No changes to NutritionCalculator or templates.

**Tech Stack:** Ruby, USDA FoodData Central API, YAML

---

### Task 1: Write the migration script

**Files:**
- Create: `bin/migrate-sources`

Write a standalone Ruby script that:
1. Loads `resources/nutrition-data.yaml`
2. Loads USDA API key (same `load_api_key` pattern as `bin/nutrition`)
3. Iterates every entry that has a string `source` key
4. For USDA entries (matching `/USDA SR Legacy \(FDC (\d+)\)/`):
   - Extract the FDC ID from the regex match
   - Fetch the food detail from `https://api.nal.usda.gov/fdc/v1/food/{fdcId}` using the API key
   - Build `{ 'type' => 'usda', 'dataset' => food_detail['dataType'], 'fdc_id' => fdc_id, 'description' => food_detail['description'] }`
   - On API failure: warn and build the source without `description`
   - Rate-limit: sleep briefly between API calls to be polite
5. For non-USDA entries (currently 4: Bouillon, Flour all-purpose, Maldon salt, Sugar white):
   - Build `{ 'type' => 'label', 'product' => original_source_string }`
6. Replace `source` (string) with `sources` (array of one hash) on each entry
7. Write the YAML back out using the same `save_nutrition_data` pattern (sorted, rounded)

The 4 non-USDA source strings are:
- `"Wegmans Broth Concentrate, Chicken-Less Vegetarian"`
- `"King Arthur Flour All-Purpose"`
- `"Maldon Salt (nutrition facts label)"`
- `"Wegmans Granulated White Sugar"`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time migration: convert flat source strings to structured sources arrays.
# Requires USDA_API_KEY for fetching food descriptions.
# Usage: bin/migrate-sources

require 'yaml'
require 'net/http'
require 'json'

PROJECT_ROOT = File.expand_path('..', __dir__)
NUTRITION_PATH = File.join(PROJECT_ROOT, 'resources/nutrition-data.yaml')

def load_api_key
  return ENV['USDA_API_KEY'] if ENV['USDA_API_KEY']

  env_path = File.join(PROJECT_ROOT, '.env')
  return nil unless File.exist?(env_path)

  File.readlines(env_path).each do |line|
    key, value = line.strip.split('=', 2)
    return value if key == 'USDA_API_KEY' && value && !value.empty?
  end
  nil
end

def fetch_usda_detail(api_key, fdc_id)
  uri = URI("https://api.nal.usda.gov/fdc/v1/food/#{fdc_id}")
  request = Net::HTTP::Get.new(uri)
  request['X-Api-Key'] = api_key

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  JSON.parse(response.body)
rescue StandardError => error
  warn "  API error for FDC #{fdc_id}: #{error.message}"
  nil
end

def migrate_usda_source(source_string, api_key)
  match = source_string.match(/USDA SR Legacy \(FDC (\d+)\)/)
  return nil unless match

  fdc_id = match[1].to_i
  source = { 'type' => 'usda', 'dataset' => 'SR Legacy', 'fdc_id' => fdc_id }

  if api_key
    detail = fetch_usda_detail(api_key, fdc_id)
    if detail && detail['description']
      source['description'] = detail['description']
      source['dataset'] = detail['dataType'] if detail['dataType']
    end
    sleep 0.25 # rate limit
  else
    warn "  No API key — skipping description fetch for FDC #{fdc_id}"
  end

  source
end

def migrate_label_source(source_string)
  { 'type' => 'label', 'product' => source_string }
end

def save_nutrition_data(data)
  sorted = data.sort_by { |k, _| k.downcase }.to_h

  sorted.each_value do |entry|
    entry['nutrients'].transform_values! { |v| v.is_a?(Float) ? v.round(4) : v } if entry['nutrients'].is_a?(Hash)
    entry['portions'].transform_values! { |v| v.is_a?(Float) ? v.round(2) : v } if entry['portions'].is_a?(Hash)
    next unless entry['density'].is_a?(Hash)

    entry['density']['grams'] = entry['density']['grams'].round(2) if entry['density']['grams'].is_a?(Float)
    entry['density']['volume'] = entry['density']['volume'].round(4) if entry['density']['volume'].is_a?(Float)
  end

  File.write(NUTRITION_PATH, YAML.dump(sorted))
end

# --- Main ---

api_key = load_api_key
warn 'WARNING: No USDA_API_KEY found. USDA descriptions will be omitted.' unless api_key

data = YAML.safe_load_file(NUTRITION_PATH) || {}

usda_count = 0
label_count = 0
already_migrated = 0

data.each do |name, entry|
  if entry['sources']
    already_migrated += 1
    next
  end

  source_string = entry.delete('source')
  next unless source_string

  usda_source = migrate_usda_source(source_string, api_key)
  if usda_source
    puts "#{name}: USDA FDC #{usda_source['fdc_id']} -> #{usda_source['description'] || '(no description)'}"
    entry['sources'] = [usda_source]
    usda_count += 1
  else
    puts "#{name}: label -> #{source_string}"
    entry['sources'] = [migrate_label_source(source_string)]
    label_count += 1
  end
end

save_nutrition_data(data)
puts "\nMigrated #{usda_count} USDA + #{label_count} label entries. #{already_migrated} already migrated."
puts "Saved to #{NUTRITION_PATH}"
```

**Step 1: Create the script**

Write the above to `bin/migrate-sources` and make it executable.

**Step 2: Run it**

Run: `bin/migrate-sources`
Expected: Each ingredient printed with its migration result. USDA entries get descriptions fetched. Non-USDA entries get `type: label`. YAML rewritten.

**Step 3: Verify the output**

Spot-check the YAML:
- USDA entry should have `sources:` array with `type: usda`, `dataset`, `fdc_id`, `description`
- Label entry should have `sources:` array with `type: label`, `product`
- No `source:` string keys remain

**Step 4: Commit**

```bash
git add bin/migrate-sources resources/nutrition-data.yaml
git commit -m "Migrate flat source strings to structured sources arrays

Fetches USDA food descriptions via API. Converts 36 USDA entries
and 4 label entries to typed source objects."
```

---

### Task 2: Update `enter_usda` to write new format

**Files:**
- Modify: `bin/nutrition:539-555` (`enter_usda` method)

Replace line 552:
```ruby
entry['source'] = "USDA SR Legacy (FDC #{food_detail['fdcId']})"
```

With:
```ruby
entry['sources'] = [{
  'type' => 'usda',
  'dataset' => food_detail['dataType'] || 'SR Legacy',
  'fdc_id' => food_detail['fdcId'],
  'description' => food_detail['description']
}]
```

**Step 1: Make the edit**

**Step 2: Verify manually**

Run `bin/nutrition "test ingredient"`, pick a USDA entry, verify the review screen shows the new sources format. Discard without saving.

**Step 3: Commit**

```bash
git add bin/nutrition
git commit -m "Update enter_usda to write structured sources"
```

---

### Task 3: Update `enter_manual` to write new format

**Files:**
- Modify: `bin/nutrition:451-495` (`enter_manual` method)

Replace the brand/product prompt (lines 472-474):
```ruby
print "\nBrand/product (optional): "
source = $stdin.gets&.strip
source = nil if source&.empty?
```

With two separate prompts:
```ruby
print "\nBrand (optional): "
brand = $stdin.gets&.strip
brand = nil if brand&.empty?

print "Product (optional): "
product = $stdin.gets&.strip
product = nil if product&.empty?
```

Replace the source assignment (line 492):
```ruby
entry['source'] = source if source
```

With:
```ruby
if brand || product
  label_source = { 'type' => 'label' }
  label_source['brand'] = brand if brand
  label_source['product'] = product if product
  entry['sources'] = [label_source]
end
```

**Step 1: Make the edits**

**Step 2: Verify manually**

Run `bin/nutrition --manual "test"`, enter brand and product separately, verify the review screen shows structured sources.

**Step 3: Commit**

```bash
git add bin/nutrition
git commit -m "Update enter_manual to write structured sources"
```

---

### Task 4: Update `display_entry` to show structured sources

**Files:**
- Modify: `bin/nutrition:239-266` (`display_entry` method)

Replace line 265:
```ruby
puts "  Source: #{entry['source']}" if entry['source']
```

With a helper that formats each source type:

```ruby
display_sources(entry['sources']) if entry['sources']&.any?
```

Add a new method `display_sources` and a helper `format_source`:

```ruby
def format_source(source)
  case source['type']
  when 'usda'
    parts = ["USDA #{source['dataset']} (FDC #{source['fdc_id']})"]
    parts << source['description'] if source['description']
    parts << "Note: #{source['note']}" if source['note']
    parts.join(' — ')
  when 'label'
    parts = [source['brand'], source['product']].compact
    label = parts.any? ? parts.join(' — ') : 'Unknown product'
    label += " (#{source['note']})" if source['note']
    "Label: #{label}"
  when 'other'
    parts = [source['name'], source['detail']].compact
    label = parts.any? ? parts.join(': ') : 'Unknown'
    label += " (#{source['note']})" if source['note']
    label
  else
    source.to_s
  end
end

def display_sources(sources)
  if sources.size == 1
    puts "  Source: #{format_source(sources.first)}"
  else
    puts '  Sources:'
    sources.each { |s| puts "    - #{format_source(s)}" }
  end
end
```

**Step 1: Add the helper methods and update `display_entry`**

**Step 2: Verify**

Run `bin/nutrition "Baking powder"` (existing USDA entry) — should display nicely with description. Press `s` to re-save or just exit.

**Step 3: Commit**

```bash
git add bin/nutrition
git commit -m "Update display_entry for structured sources"
```

---

### Task 5: Update `edit_entry` source editing

**Files:**
- Modify: `bin/nutrition:586-640` (`edit_entry` method)

Replace the simple source edit (lines 632-635, menu option `'5'`):
```ruby
when '5'
  print "\nSource [#{entry['source']}]: "
  input = $stdin.gets&.strip
  entry['source'] = input unless input.nil? || input.empty?
```

With a sources management sub-menu:

```ruby
when '5'
  entry['sources'] = edit_sources(entry['sources'] || [])
```

Add a new `edit_sources` method:

```ruby
def edit_sources(sources)
  loop do
    puts "\n  Sources:"
    if sources.empty?
      puts '    (none)'
    else
      sources.each_with_index { |s, i| puts "    #{i + 1}. #{format_source(s)}" }
    end

    puts "\n  a. Add source"
    puts "  r. Remove source" if sources.any?
    puts "  d. Done"
    print "  Action: "
    choice = $stdin.gets&.strip&.downcase

    case choice
    when 'a'
      new_source = prompt_new_source
      sources << new_source if new_source
    when 'r'
      next if sources.empty?

      print "  Remove which? (1-#{sources.size}): "
      idx = $stdin.gets&.strip.to_i - 1
      sources.delete_at(idx) if idx >= 0 && idx < sources.size
    when 'd'
      return sources
    end
  end
end

def prompt_new_source
  puts "\n  Source type:"
  puts '    1. USDA'
  puts '    2. Label (nutrition facts)'
  puts '    3. Other'
  print '  Type: '
  choice = $stdin.gets&.strip

  case choice
  when '1'
    source = { 'type' => 'usda' }
    print '  Dataset (e.g. SR Legacy): '
    source['dataset'] = $stdin.gets&.strip
    print '  FDC ID: '
    id_input = $stdin.gets&.strip
    source['fdc_id'] = id_input.to_i if id_input && !id_input.empty?
    print '  Description: '
    desc = $stdin.gets&.strip
    source['description'] = desc if desc && !desc.empty?
    print '  Note (optional): '
    note = $stdin.gets&.strip
    source['note'] = note if note && !note.empty?
    source
  when '2'
    source = { 'type' => 'label' }
    print '  Brand (optional): '
    brand = $stdin.gets&.strip
    source['brand'] = brand if brand && !brand.empty?
    print '  Product (optional): '
    product = $stdin.gets&.strip
    source['product'] = product if product && !product.empty?
    print '  Note (optional): '
    note = $stdin.gets&.strip
    source['note'] = note if note && !note.empty?
    source
  when '3'
    source = { 'type' => 'other' }
    print '  Name: '
    name = $stdin.gets&.strip
    source['name'] = name if name && !name.empty?
    print '  Detail (optional): '
    detail = $stdin.gets&.strip
    source['detail'] = detail if detail && !detail.empty?
    print '  Note (optional): '
    note = $stdin.gets&.strip
    source['note'] = note if note && !note.empty?
    source
  end
end
```

Also update the edit menu label (line 596) from `'5. Source'` to `'5. Sources'`.

**Step 1: Add the helper methods and update the edit menu**

**Step 2: Verify**

Run `bin/nutrition "Baking powder"`, choose edit, choose `5. Sources`. Verify add/remove work. Discard without saving.

**Step 3: Commit**

```bash
git add bin/nutrition
git commit -m "Update edit_entry with sources management sub-menu"
```

---

### Task 6: Update `save_nutrition_data` to handle sources

**Files:**
- Modify: `bin/nutrition:55-69` (`save_nutrition_data`)

The current `save_nutrition_data` only rounds numeric values in `nutrients`, `portions`, and `density`. The `sources` array will pass through YAML.dump fine without special handling, but we should ensure `source` (old key) is never accidentally written alongside `sources`.

No code change needed — YAML.dump handles arrays of hashes natively. But verify during testing that the output looks clean.

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (nutrition data section)

Replace the example showing `source: King Arthur Flour` with the new `sources:` array format. Update the `bin/nutrition` documentation to mention the structured sources.

Example update for the nutrition data section:

```yaml
Flour (all-purpose):
  nutrients:
    basis_grams: 30.0
    calories: 110.0
    fat: 0.0
    # ... (11 FDA-label nutrients)
  density:
    grams: 30.0
    volume: 0.25
    unit: cup
  portions:
    stick: 113.0
    ~unitless: 50
  sources:                        # provenance metadata (array of typed objects)
    - type: usda                  # usda | label | other
      dataset: SR Legacy          # FDC dataset name
      fdc_id: 168913              # FoodData Central ID
      description: "Wheat flour, white, all-purpose, enriched, unbleached"
```

**Step 1: Update CLAUDE.md**

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Update CLAUDE.md for structured sources format"
```

---

### Task 8: Run lint and verify

**Step 1: Run linter**

Run: `rake lint`
Expected: No new offenses from changes to `bin/nutrition`.

**Step 2: Run tests**

Run: `rake test`
Expected: All tests pass (no tests reference `source` field).

**Step 3: Run a full build**

Run: `bin/generate`
Expected: Clean build. No warnings related to sources.

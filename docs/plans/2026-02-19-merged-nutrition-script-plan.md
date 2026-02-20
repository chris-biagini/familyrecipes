# Merged Nutrition Script Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Merge `bin/nutrition-entry` and `bin/nutrition-usda` into a single `bin/nutrition` script with USDA-first flow, manual fallback, edit mode for existing entries, and improved `--missing` batch iteration.

**Architecture:** Single monolithic script in `bin/nutrition`. Shared infrastructure (constants, data I/O, name resolution, recipe scanning) at the top. Interactive flows built from small composable prompt functions. `NutritionEntryHelpers` stays in `lib/` unchanged. The script loads recipes and alias map once at startup and threads them through all functions.

**Tech Stack:** Ruby 3.2+, USDA FoodData Central API (SR Legacy), YAML, existing FamilyRecipes library.

**Key reference files:**
- Design doc: `docs/plans/2026-02-19-merged-nutrition-script-design.md`
- Prior design: `docs/plans/2026-02-19-usda-nutrition-import-design.md`
- Old scripts: `bin/nutrition-entry`, `bin/nutrition-usda`
- Entry helpers: `lib/familyrecipes/nutrition_entry_helpers.rb`
- Calculator: `lib/familyrecipes/nutrition_calculator.rb`
- Nutrition data: `resources/nutrition-data.yaml`
- Grocery data: `resources/grocery-info.yaml`

---

### Task 1: Create bin/nutrition with shared infrastructure

Create the new script with constants, data I/O, and name/recipe resolution. This is mostly moving and deduplicating code from both old scripts, with one key improvement: recipes and alias map are loaded once into a context hash, not re-parsed per function call.

**Files:**
- Create: `bin/nutrition`

**Step 1: Create the script with constants and data I/O**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'net/http'
require 'json'
require_relative '../lib/familyrecipes'

PROJECT_ROOT = File.expand_path('..', __dir__)
NUTRITION_PATH = File.join(PROJECT_ROOT, 'resources/nutrition-data.yaml')
GROCERY_PATH = File.join(PROJECT_ROOT, 'resources/grocery-info.yaml')
RECIPES_DIR = File.join(PROJECT_ROOT, 'recipes')

Helpers = FamilyRecipes::NutritionEntryHelpers

# FDA label order: 11 nutrients
NUTRIENTS = [
  { key: 'calories',      label: 'Calories', unit: '', indent: 0 },
  { key: 'fat',           label: 'Total fat',       unit: 'g',  indent: 0 },
  { key: 'saturated_fat', label: 'Saturated fat',   unit: 'g',  indent: 1 },
  { key: 'trans_fat',     label: 'Trans fat',       unit: 'g',  indent: 1 },
  { key: 'cholesterol',   label: 'Cholesterol',     unit: 'mg', indent: 0 },
  { key: 'sodium',        label: 'Sodium',          unit: 'mg', indent: 0 },
  { key: 'carbs',         label: 'Total carbs',     unit: 'g',  indent: 0 },
  { key: 'fiber',         label: 'Fiber',           unit: 'g',  indent: 1 },
  { key: 'total_sugars',  label: 'Total sugars',    unit: 'g',  indent: 1 },
  { key: 'added_sugars',  label: 'Added sugars',    unit: 'g',  indent: 2 },
  { key: 'protein',       label: 'Protein',         unit: 'g',  indent: 0 }
].freeze

# USDA nutrient number -> our key (per 100g basis)
NUTRIENT_MAP = {
  '208' => 'calories',      # Energy (kcal)
  '204' => 'fat',           # Total lipid (fat)
  '606' => 'saturated_fat', # Fatty acids, total saturated
  '605' => 'trans_fat',     # Fatty acids, total trans
  '601' => 'cholesterol',   # Cholesterol
  '307' => 'sodium',        # Sodium
  '205' => 'carbs',         # Carbohydrate, by difference
  '291' => 'fiber',         # Fiber, total dietary
  '269' => 'total_sugars',  # Sugars, total
  '203' => 'protein'        # Protein
}.freeze

VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons].freeze
```

**Step 2: Add data I/O with density.volume rounding fix**

```ruby
def load_nutrition_data
  return {} unless File.exist?(NUTRITION_PATH)

  YAML.safe_load_file(NUTRITION_PATH, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
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
  puts "Saved to #{NUTRITION_PATH}"
end
```

Note: `density.volume` now gets the same cosmetic rounding treatment. Uses 4 decimal places since volume can be fractional (e.g. 0.25 cup, 0.333 cup).

**Step 3: Add context loading and name resolution**

Load recipes and alias map once, pass through as a context hash:

```ruby
def load_context
  grocery_aisles = FamilyRecipes.parse_grocery_info(GROCERY_PATH)
  alias_map = FamilyRecipes.build_alias_map(grocery_aisles)
  recipes = FamilyRecipes.parse_recipes(RECIPES_DIR)
  recipe_map = recipes.to_h { |r| [r.id, r] }
  omit_set = (grocery_aisles['Omit_From_List'] || []).flat_map do |item|
    [item[:name], *item[:aliases]].map(&:downcase)
  end.to_set

  { grocery_aisles: grocery_aisles, alias_map: alias_map, recipes: recipes,
    recipe_map: recipe_map, omit_set: omit_set }
end

def resolve_name(raw_name, ctx)
  canonical = ctx[:alias_map][raw_name.downcase]
  if canonical
    puts "  -> Resolved to \"#{canonical}\"" if canonical != raw_name
    return canonical
  end

  puts "  \"#{raw_name}\" not found in grocery-info.yaml. Recipes won't match this entry."
  print '  Continue anyway? (y/n): '
  input = $stdin.gets&.strip
  return nil unless input&.downcase == 'y'

  raw_name
end

def find_needed_units(name, ctx)
  units = Set.new
  ctx[:recipes].each do |recipe|
    recipe.all_ingredients_with_quantities(ctx[:alias_map], ctx[:recipe_map]).each do |ing_name, amounts|
      next unless ing_name == name

      amounts.each do |amount|
        next if amount.nil?

        _, unit = amount
        units << unit
      end
    end
  end
  units.to_a
end
```

**Step 4: Add API key loading**

```ruby
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
```

**Step 5: Make it executable, verify it loads**

Run: `chmod +x bin/nutrition && ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 6: Commit**

```bash
git add bin/nutrition
git commit -m "Add bin/nutrition skeleton with shared infrastructure"
```

---

### Task 2: Add USDA API and display helpers

Move USDA API functions from `nutrition-usda` and build the display helpers used by all flows.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add USDA API functions**

These come directly from `bin/nutrition-usda` without changes:

```ruby
# --- USDA API ---

def search_usda(api_key, query)
  uri = URI('https://api.nal.usda.gov/fdc/v1/foods/search')
  body = {
    query: query,
    dataType: ['SR Legacy'],
    pageSize: 10
  }.to_json

  request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
  request['X-Api-Key'] = api_key
  request.body = body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  JSON.parse(response.body)
end

def fetch_usda_detail(api_key, fdc_id)
  uri = URI("https://api.nal.usda.gov/fdc/v1/food/#{fdc_id}")
  request = Net::HTTP::Get.new(uri)
  request['X-Api-Key'] = api_key

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  JSON.parse(response.body)
end
```

**Step 2: Add USDA data extraction functions**

From `bin/nutrition-usda`:

```ruby
# --- USDA data extraction ---

def extract_nutrients(food_detail)
  nutrients = { 'basis_grams' => 100.0 }
  NUTRIENT_MAP.each_value { |key| nutrients[key] = 0.0 }

  food_detail['foodNutrients']&.each do |fn|
    number = fn.dig('nutrient', 'number')
    next unless number

    our_key = NUTRIENT_MAP[number]
    next unless our_key

    nutrients[our_key] = (fn['amount'] || 0.0).round(4)
  end

  # added_sugars not in SR Legacy
  nutrients['added_sugars'] = 0.0
  nutrients
end

def volume_unit?(modifier)
  clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
  VOLUME_UNITS.include?(clean)
end

def normalize_volume_unit(modifier)
  clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
  case clean
  when 'cups' then 'cup'
  when 'tablespoon', 'tablespoons' then 'tbsp'
  when 'teaspoon', 'teaspoons' then 'tsp'
  else clean
  end
end

def classify_portions(food_detail)
  volume = []
  non_volume = []

  food_detail['foodPortions']&.each do |portion|
    modifier = portion['modifier'].to_s
    next if modifier.empty?

    grams = portion['gramWeight']
    amount = portion['amount'] || 1.0
    next unless grams&.positive?

    entry = { modifier: modifier, grams: grams, amount: amount }

    if volume_unit?(modifier)
      volume << entry
    else
      non_volume << entry
    end
  end

  { volume: volume, non_volume: non_volume }
end

def pick_density(volume_portions)
  return nil if volume_portions.empty?

  best = volume_portions.max_by { |p| p[:grams] }
  unit = normalize_volume_unit(best[:modifier])

  { 'grams' => best[:grams].round(2), 'volume' => best[:amount], 'unit' => unit }
end

def build_non_volume_portions(classified)
  classified[:non_volume].to_h do |p|
    unit = p[:modifier].downcase.sub(/\s*\(.*\)/, '').strip
    grams = (p[:grams] / p[:amount]).round(2)
    [unit, grams]
  end
end
```

Note: `build_non_volume_portions` rewritten using `to_h` instead of `each` + accumulator.

**Step 3: Add display helpers**

These are used by all flows (USDA, manual, edit):

```ruby
# --- Display ---

def display_entry(name, entry)
  puts "\n--- #{name} ---"

  basis = entry.dig('nutrients', 'basis_grams') || '?'
  puts "  Nutrients (per #{basis}g):"
  NUTRIENTS.each do |n|
    indent = '  ' * n[:indent]
    value = entry.dig('nutrients', n[:key]) || 0
    unit_str = n[:unit].empty? ? '' : " #{n[:unit]}"
    puts "    #{indent}#{n[:label]}: #{value}#{unit_str}"
  end

  density = entry['density']
  if density
    puts "  Density: #{density['grams']}g per #{density['volume']} #{density['unit']}"
  else
    puts '  Density: none'
  end

  portions = entry['portions'] || {}
  if portions.any?
    puts "  Portions: #{portions.map { |k, v| "#{k}=#{v}g" }.join(', ')}"
  else
    puts '  Portions: none'
  end

  puts "  Source: #{entry['source']}" if entry['source']
end

def display_unit_coverage(name, entry, needed_units)
  return if needed_units.empty?

  calculator = FamilyRecipes::NutritionCalculator.new({ name => entry })
  entry_data = calculator.nutrition_data[name]
  return unless entry_data

  puts "\n  Unit coverage for recipes:"
  needed_units.each do |unit|
    label = unit || '(bare count)'
    resolved = calculator.resolvable?(1, unit, entry_data)
    status = resolved ? 'OK' : 'MISSING'
    puts "    #{label}: #{status}"
  end
end
```

**Step 4: Syntax check**

Run: `ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 5: Commit**

```bash
git add bin/nutrition
git commit -m "Add USDA API and display helpers to bin/nutrition"
```

---

### Task 3: Add prompt helpers and manual entry flow

Move the interactive prompt functions from `nutrition-entry` and build the complete manual entry flow.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add basic prompt helpers**

From `nutrition-entry`:

```ruby
# --- Prompts ---

def prompt_number(prompt_text, allow_empty_zero: true)
  loop do
    print prompt_text
    input = $stdin.gets&.strip
    return nil if input.nil?
    return :quit if input.downcase == 'q'

    if input.empty?
      return 0.0 if allow_empty_zero

      puts "  Value required. Enter a number, or 'q' to quit."
      next
    end

    value = Float(input, exception: false)
    return value if value

    puts '  Not a number, try again:'
  end
end

def prompt_serving_size
  loop do
    print "\nServing size: "
    input = $stdin.gets&.strip
    return nil if input.nil? || input.empty?
    return :quit if input.downcase == 'q'

    parsed = Helpers.parse_serving_size(input)
    return parsed if parsed

    puts "Could not extract gram weight from '#{input}'."
    puts "Include the gram weight, e.g. '30g', '1/4 cup (30g)', '1 slice (21g)', '30 grams'"
    puts "Try again, or 'q' to quit:"
  end
end
```

**Step 2: Add nutrient entry prompt**

```ruby
def prompt_nutrients(defaults: nil)
  if defaults
    puts "\nNutrients (Enter = keep current, 'q' = quit):"
  else
    puts "\nPer serving (Enter = 0, 'q' = quit):"
  end

  result = {}
  NUTRIENTS.each do |nutrient|
    indent = '  ' * nutrient[:indent]
    unit_str = nutrient[:unit].empty? ? '' : " (#{nutrient[:unit]})"
    current = defaults&.dig(nutrient[:key])
    default_str = current ? " [#{current}]" : ''
    prompt_text = "#{indent}#{nutrient[:label]}#{unit_str}#{default_str}: "

    if defaults
      # Edit mode: Enter keeps current value
      print prompt_text
      input = $stdin.gets&.strip
      return nil if input.nil?
      return nil if input.downcase == 'q'

      if input.empty?
        result[nutrient[:key]] = current || 0.0
      else
        value = Float(input, exception: false)
        result[nutrient[:key]] = value || (current || 0.0)
      end
    else
      value = prompt_number(prompt_text)
      return nil if value.nil? || value == :quit

      result[nutrient[:key]] = value
    end
  end
  result
end
```

Note: `prompt_nutrients` now accepts optional `defaults:` hash for edit mode. When defaults are present, Enter keeps the current value instead of entering 0.

**Step 3: Add portions prompt**

From `nutrition-entry`, with minor cleanup:

```ruby
def prompt_portions(auto_portions, needed_units, existing: {})
  portions = existing.dup

  puts "\nPortions (grams per 1 unit — volume units derived from density):"
  puts "  Enter = accept, '-' = skip/remove, 'done' = finish"

  if needed_units&.any?
    needed_str = needed_units.map { |u| u || '(bare count)' }.sort.join(', ')
    puts "  Recipes use: #{needed_str}"
  end

  # Auto-portions from serving size (discrete items like "1 slice")
  auto_portions.each do |unit, grams|
    next if portions.key?(unit)

    needed_tag = needed_units&.include?(unit) ? ' *' : ''
    print "  #{unit} [#{grams}] (from label)#{needed_tag}: "
    input = $stdin.gets&.strip
    return portions if input&.downcase == 'done'

    if input != '-'
      if input.nil? || input.empty?
        portions[unit] = grams
      else
        value = Float(input, exception: false)
        portions[unit] = value if value
      end
    end
  end

  # Show existing portions (edit mode)
  portions.each do |unit, grams|
    next if auto_portions.key?(unit)

    needed_tag = needed_units&.include?(unit) || (unit == '~unitless' && needed_units&.include?(nil)) ? ' *' : ''
    print "  #{unit} [#{grams}]#{needed_tag}: "
    input = $stdin.gets&.strip
    return portions if input&.downcase == 'done'

    if input == '-'
      portions.delete(unit)
    elsif input && !input.empty?
      value = Float(input, exception: false)
      portions[unit] = value if value
    end
  end

  # ~unitless prompt if not already present
  unless portions.key?('~unitless')
    needed_tag = needed_units&.include?(nil) ? ' *' : ''
    print "  ~unitless#{needed_tag}: "
    input = $stdin.gets&.strip
    unless input&.downcase == 'done' || input.nil? || input.empty? || input == '-'
      value = Float(input, exception: false)
      portions['~unitless'] = value if value
    end
  end

  # Prompt for non-volume needed units not yet covered
  volume_units = %w[cup tbsp tsp ml l]
  needed_units&.each do |unit|
    next if unit.nil?
    next if portions.key?(unit)
    next if volume_units.include?(unit.downcase)

    print "  #{unit} *: "
    input = $stdin.gets&.strip
    break if input&.downcase == 'done'
    next if input.nil? || input.empty? || input == '-'

    value = Float(input, exception: false)
    portions[unit] = value if value
  end

  # Custom units
  loop do
    print '  Additional unit (or Enter to finish): '
    input = $stdin.gets&.strip
    break if input.nil? || input.empty?

    print "    grams per 1 #{input}: "
    value_str = $stdin.gets&.strip
    value = Float(value_str, exception: false)
    portions[input] = value if value
  end

  portions
end
```

Note: accepts `existing:` hash for edit mode. Existing portions are shown with current values as defaults, `-` removes them.

**Step 4: Add manual entry flow**

```ruby
def enter_manual(name, needed_units)
  puts "\n--- #{name} (manual entry) ---"

  parsed = prompt_serving_size
  return nil if parsed.nil? || parsed == :quit

  display = "  -> #{parsed[:grams]}g"
  display += " | #{parsed[:volume_amount]} #{parsed[:volume_unit]}" if parsed[:volume_amount]
  if parsed[:auto_portion]
    display += "\n  -> auto-portion: #{parsed[:auto_portion][:unit]} = #{parsed[:auto_portion][:grams]}g"
  end
  puts display

  per_serving = prompt_nutrients
  return nil unless per_serving

  # Per-100g cross-check
  factor = 100.0 / parsed[:grams]
  summary = NUTRIENTS.map { |n| "#{n[:key]}=#{(per_serving[n[:key]] * factor).round(1)}" }.join(', ')
  puts "\n  (Per 100g: #{summary})"

  print "\nBrand/product (optional): "
  source = $stdin.gets&.strip
  source = nil if source&.empty?

  auto_portions = {}
  auto_portions[parsed[:auto_portion][:unit]] = parsed[:auto_portion][:grams] if parsed[:auto_portion]

  portions = prompt_portions(auto_portions, needed_units)

  # Build entry
  nutrients = per_serving.merge('basis_grams' => parsed[:grams])
  entry = { 'nutrients' => nutrients }
  if parsed[:volume_amount]
    entry['density'] = {
      'grams' => parsed[:grams],
      'volume' => parsed[:volume_amount],
      'unit' => parsed[:volume_unit]
    }
  end
  entry['portions'] = portions unless portions.empty?
  entry['source'] = source if source

  entry
end
```

**Step 5: Syntax check**

Run: `ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 6: Commit**

```bash
git add bin/nutrition
git commit -m "Add prompt helpers and manual entry flow to bin/nutrition"
```

---

### Task 4: Add USDA flow with manual fallback and Save/Edit/Discard

Build the USDA search-and-pick workflow and the post-entry review prompt shared by both flows.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add USDA search and pick**

```ruby
def search_and_pick(api_key, name)
  default_query = name.sub(/\s*\(.*\)/, '').strip

  loop do
    print "\nSearch USDA [#{default_query}]: "
    input = $stdin.gets&.strip
    return :manual if input&.downcase == 'q'

    query = input.nil? || input.empty? ? default_query : input

    puts "Searching for \"#{query}\"..."
    result = search_usda(api_key, query)
    foods = result['foods'] || []

    if foods.empty?
      puts '  No results found. Try a different search, or q for manual entry.'
      next
    end

    puts "\nResults:"
    foods.each_with_index do |food, idx|
      puts "  #{idx + 1}. [#{food['fdcId']}] #{food['description']}"
    end
    puts '  s. Search again'
    puts '  q. Manual entry instead'

    print "\nPick (1-#{foods.size}): "
    choice = $stdin.gets&.strip
    return :manual if choice&.downcase == 'q'
    next if choice&.downcase == 's'

    idx = choice.to_i - 1
    next unless idx >= 0 && idx < foods.size

    fdc_id = foods[idx]['fdcId']
    puts "\nFetching detail for #{foods[idx]['description']}..."
    return fetch_usda_detail(api_key, fdc_id)
  end
end
```

Note: returns `:manual` instead of `nil` when user presses `q`, enabling graceful fallback.

**Step 2: Add USDA entry builder**

```ruby
def enter_usda(api_key, name, needed_units)
  food_detail = search_and_pick(api_key, name)
  return :manual if food_detail == :manual
  return nil unless food_detail

  nutrients = extract_nutrients(food_detail)
  classified = classify_portions(food_detail)
  density = pick_density(classified[:volume])
  portions = build_non_volume_portions(classified)

  entry = { 'nutrients' => nutrients }
  entry['density'] = density if density
  entry['portions'] = portions unless portions.empty?
  entry['source'] = "USDA SR Legacy (FDC #{food_detail['fdcId']})"

  entry
end
```

**Step 3: Add Save/Edit/Discard review loop**

This is the shared post-entry prompt used by both USDA and manual flows:

```ruby
def review_and_save(name, entry, needed_units, nutrition_data, api_key: nil)
  loop do
    display_entry(name, entry)
    display_unit_coverage(name, entry, needed_units)

    puts "\n  s. Save"
    puts '  e. Edit'
    puts '  d. Discard'
    print "\nAction: "
    choice = $stdin.gets&.strip&.downcase

    case choice
    when 's'
      nutrition_data[name] = entry
      save_nutrition_data(nutrition_data)
      return
    when 'd'
      puts 'Discarded.'
      return
    when 'e'
      entry = edit_entry(name, entry, needed_units, api_key: api_key)
    end
  end
end
```

**Step 4: Syntax check**

Run: `ruby -c bin/nutrition`
Expected: Will fail because `edit_entry` is not yet defined. Add a placeholder:

```ruby
def edit_entry(name, entry, needed_units, api_key: nil)
  puts '  (edit not yet implemented)'
  entry
end
```

Run: `ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 5: Commit**

```bash
git add bin/nutrition
git commit -m "Add USDA flow with manual fallback and review loop"
```

---

### Task 5: Add edit mode for existing and new entries

Replace the placeholder `edit_entry` with the full edit menu. Also build the entry point for editing existing ingredients.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Implement edit_entry**

```ruby
def edit_entry(name, entry, needed_units, api_key: nil)
  loop do
    display_entry(name, entry)
    display_unit_coverage(name, entry, needed_units)

    puts "\n  Edit:"
    puts '  1. Re-import from USDA' if api_key
    puts '  2. Nutrients'
    puts '  3. Density'
    puts '  4. Portions'
    puts '  5. Source'
    puts '  s. Done editing'
    print "\nAction: "
    choice = $stdin.gets&.strip

    case choice
    when '1'
      next unless api_key

      new_entry = enter_usda(api_key, name, needed_units)
      entry = new_entry if new_entry && new_entry != :manual
    when '2'
      new_nutrients = prompt_nutrients(defaults: entry['nutrients']&.except('basis_grams'))
      if new_nutrients
        basis = entry.dig('nutrients', 'basis_grams') || 100.0
        entry['nutrients'] = new_nutrients.merge('basis_grams' => basis)
      end
    when '3'
      parsed = prompt_serving_size
      if parsed && parsed != :quit
        entry['nutrients']['basis_grams'] = parsed[:grams] if entry['nutrients']
        if parsed[:volume_amount]
          entry['density'] = {
            'grams' => parsed[:grams],
            'volume' => parsed[:volume_amount],
            'unit' => parsed[:volume_unit]
          }
        else
          entry.delete('density')
        end
      end
    when '4'
      auto_portions = {}
      existing = entry['portions'] || {}
      entry['portions'] = prompt_portions(auto_portions, needed_units, existing: existing)
      entry.delete('portions') if entry['portions'].empty?
    when '5'
      print "\nSource [#{entry['source']}]: "
      input = $stdin.gets&.strip
      entry['source'] = input unless input.nil? || input.empty?
    when 's'
      return entry
    end
  end
end
```

**Step 2: Add the new-ingredient orchestrator**

This is the main flow for entering a brand-new ingredient:

```ruby
def enter_new_ingredient(name, needed_units, nutrition_data, api_key:, manual: false)
  entry = nil

  if api_key && !manual
    entry = enter_usda(api_key, name, needed_units)
    # Fallback to manual if user pressed 'q' during USDA search
    entry = nil if entry == :manual
  end

  entry ||= enter_manual(name, needed_units)
  return unless entry

  review_and_save(name, entry, needed_units, nutrition_data, api_key: api_key)
end
```

**Step 3: Add the existing-ingredient handler**

```ruby
def edit_existing_ingredient(name, entry, needed_units, nutrition_data, api_key:)
  puts "\n#{name} already has data."
  updated = edit_entry(name, entry.dup, needed_units, api_key: api_key)

  if updated != entry
    nutrition_data[name] = updated
    save_nutrition_data(nutrition_data)
  else
    puts 'No changes.'
  end
end
```

Wait — this bypasses the Save/Edit/Discard review since we're already in edit mode. The edit menu itself has "Done editing" which returns to the caller. But we need a save step. Let me reconsider.

Actually, the edit menu for existing entries should use `review_and_save` too. The flow is:
1. Show existing entry
2. Drop into edit menu (which is actually `review_and_save` starting in edit mode)

Revise to:

```ruby
def handle_ingredient(name, nutrition_data, ctx, api_key:, manual: false)
  needed_units = find_needed_units(name, ctx)
  existing = nutrition_data[name]

  if existing
    review_and_save(name, existing.dup, needed_units, nutrition_data, api_key: api_key)
  else
    enter_new_ingredient(name, needed_units, nutrition_data, api_key: api_key, manual: manual)
  end
end
```

For existing entries, `review_and_save` shows the current entry and offers Save/Edit/Discard — where Save means "no changes needed", Edit opens the edit menu, and Discard starts fresh via the new-ingredient flow. Update `review_and_save` to handle Discard-and-restart:

```ruby
def review_and_save(name, entry, needed_units, nutrition_data, api_key: nil)
  loop do
    display_entry(name, entry)
    display_unit_coverage(name, entry, needed_units)

    puts "\n  s. Save"
    puts '  e. Edit'
    puts '  d. Discard and start fresh'
    print "\nAction: "
    choice = $stdin.gets&.strip&.downcase

    case choice
    when 's'
      nutrition_data[name] = entry
      save_nutrition_data(nutrition_data)
      return
    when 'd'
      puts 'Starting fresh...'
      return enter_new_ingredient(name, needed_units, nutrition_data, api_key: api_key)
    when 'e'
      entry = edit_entry(name, entry, needed_units, api_key: api_key)
    end
  end
end
```

**Step 4: Remove placeholder edit_entry, syntax check**

Run: `ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 5: Commit**

```bash
git add bin/nutrition
git commit -m "Add edit mode for existing and new entries"
```

---

### Task 6: Add --missing mode

Build the two-phase missing mode: report, then batch iterate.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add find_missing_ingredients**

This combines the richer report from `nutrition-entry` (missing + unresolvable) with the batch iteration from `nutrition-usda`:

```ruby
def find_missing_ingredients(nutrition_data, ctx)
  ingredients_to_recipes = Hash.new { |h, k| h[k] = [] }
  ctx[:recipes].each do |recipe|
    recipe.all_ingredient_names(ctx[:alias_map]).each do |name|
      ingredients_to_recipes[name] << recipe.title unless ctx[:omit_set].include?(name.downcase)
    end
  end

  missing = ingredients_to_recipes.keys.reject { |name| nutrition_data.key?(name) }
  missing.sort_by! { |name| [-ingredients_to_recipes[name].uniq.size, name] }

  # Find entries with unresolvable units
  calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: ctx[:omit_set])

  unresolvable = Hash.new { |h, k| h[k] = { units: Set.new, recipes: [] } }

  ctx[:recipes].each do |recipe|
    recipe.all_ingredients_with_quantities(ctx[:alias_map], ctx[:recipe_map]).each do |name, amounts|
      next if ctx[:omit_set].include?(name.downcase)

      entry = nutrition_data[name]
      next unless entry

      amounts.each do |amount|
        next if amount.nil?
        next if amount.value.nil?

        next if calculator.resolvable?(amount.value, amount.unit, entry)

        info = unresolvable[name]
        info[:units] << (amount.unit || '(bare count)')
        info[:recipes] |= [recipe.title]
      end
    end
  end

  { missing: missing, ingredients_to_recipes: ingredients_to_recipes, unresolvable: unresolvable }
end
```

Note: uses the `amount.value` / `amount.unit` accessors consistent with the calculator (the old `nutrition-usda` used array destructuring `value, unit = amount` which suggests the data might be arrays — check `nutrition-entry` which uses the same pattern). Looking at the calculator code at line 68-69, it uses `amount.value` and `amount.unit`, so these are objects with accessors, not arrays. The old scripts' array destructuring works because Ruby's multiple assignment works with objects that respond to `to_ary` or positional args — but actually, looking more carefully at `nutrition-entry` line 190 `_, unit = amount` this suggests they ARE arrays. However, the calculator at line 68-69 uses `amount.value` and `amount.unit`.

This discrepancy needs investigation. Check what `all_ingredients_with_quantities` actually returns. The old scripts may have been written against a different version of the API. Use the calculator's `.value`/`.unit` convention since that's the code that actually works and is tested.

**Step 2: Add --missing display and iteration**

```ruby
def run_missing_mode(nutrition_data, ctx, api_key:)
  result = find_missing_ingredients(nutrition_data, ctx)
  missing = result[:missing]
  recipes_map = result[:ingredients_to_recipes]
  unresolvable = result[:unresolvable]

  # Phase 1: Report
  if missing.any?
    puts "Missing nutrition data (#{missing.size}):"
    missing.each do |name|
      recipes = recipes_map[name].uniq.sort
      count_label = recipes.size == 1 ? '1 recipe' : "#{recipes.size} recipes"
      puts "  - #{name} (#{count_label}: #{recipes.join(', ')})"
    end
    puts ''
  end

  if unresolvable.any?
    puts "Missing unit conversions (#{unresolvable.size}):"
    unresolvable.sort_by { |name, info| [-info[:recipes].size, name] }.each do |name, info|
      recipes = info[:recipes].sort
      units = info[:units].to_a.sort.join(', ')
      count_label = recipes.size == 1 ? '1 recipe' : "#{recipes.size} recipes"
      puts "  - #{name}: '#{units}' (#{count_label}: #{recipes.join(', ')})"
    end
    puts ''
  end

  if missing.empty? && unresolvable.empty?
    puts 'All ingredients have nutrition data and resolvable units!'
    return
  end

  puts "#{missing.size} missing data, #{unresolvable.size} missing conversions.\n\n"

  # Phase 2: Batch iterate
  print 'Enter data? (y/n): '
  input = $stdin.gets&.strip
  return unless input&.downcase == 'y'

  # Iterate missing entries (most-used first — already sorted)
  missing.each do |name|
    puts "\n=== #{name} ==="
    handle_ingredient(name, nutrition_data, ctx, api_key: api_key)
    puts ''
  end

  # Iterate unresolvable entries (edit mode for portions)
  unresolvable.sort_by { |_, info| -info[:recipes].size }.each do |name, _info|
    puts "\n=== #{name} (fix unit conversions) ==="
    handle_ingredient(name, nutrition_data, ctx, api_key: api_key)
    puts ''
  end
end
```

**Step 3: Syntax check**

Run: `ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 4: Commit**

```bash
git add bin/nutrition
git commit -m "Add --missing mode with report and batch iteration"
```

---

### Task 7: Add main entry point and argument parsing

Wire everything together with the main block, help text, and API key auto-detection.

**Files:**
- Modify: `bin/nutrition`

**Step 1: Add help text and main block**

```ruby
# --- Main ---

if ARGV.include?('--help') || ARGV.include?('-h')
  puts 'Usage:'
  puts '  bin/nutrition                        Interactive prompt'
  puts '  bin/nutrition "Cream cheese"         Enter/edit data for an ingredient'
  puts '  bin/nutrition --missing              Report + batch iterate missing data'
  puts '  bin/nutrition --manual "Flour"       Force manual entry (skip USDA)'
  puts ''
  puts 'Auto-detects USDA_API_KEY for USDA-first mode. Without a key, defaults'
  puts 'to manual entry from package labels.'
  puts ''
  puts 'USDA setup: set USDA_API_KEY in .env or environment.'
  puts '  Free key: https://fdc.nal.usda.gov/api-key-signup'
  puts ''
  puts 'Serving size examples (manual mode):'
  puts '  100g                     Just gram weight'
  puts '  1/4 cup (30g)            Volume + grams (creates density)'
  puts '  1 slice (21g)            Discrete + grams (auto-portion)'
  exit 0
end

api_key = load_api_key
manual_mode = ARGV.include?('--manual')

if api_key
  puts 'USDA mode (API key found). Use --manual to enter from labels instead.' unless manual_mode
else
  puts 'No USDA_API_KEY found. Using manual entry mode. See --help for USDA setup.'
end

nutrition_data = load_nutrition_data
ctx = load_context

if ARGV.include?('--missing')
  run_missing_mode(nutrition_data, ctx, api_key: manual_mode ? nil : api_key)
else
  ingredient_name = ARGV.reject { |a| a.start_with?('-') }.first

  unless ingredient_name
    print 'Ingredient name: '
    ingredient_name = $stdin.gets&.strip
  end

  if ingredient_name.nil? || ingredient_name.empty?
    warn 'No ingredient name provided.'
    exit 1
  end

  resolved = resolve_name(ingredient_name, ctx)
  exit 0 unless resolved

  handle_ingredient(resolved, nutrition_data, ctx, api_key: manual_mode ? nil : api_key)
end
```

**Step 2: Syntax check and make executable**

Run: `chmod +x bin/nutrition && ruby -c bin/nutrition`
Expected: `Syntax OK`

**Step 3: Manual smoke test**

Run: `bin/nutrition --help`
Expected: Help text displays and exits cleanly.

Run: `bin/nutrition --missing`
Expected: Loads recipes, shows missing/unresolvable report.

**Step 4: Commit**

```bash
git add bin/nutrition
git commit -m "Add main entry point and argument parsing to bin/nutrition"
```

---

### Task 8: Investigate amount data structure

Before deleting old scripts, verify how `all_ingredients_with_quantities` returns amounts. The calculator uses `amount.value` / `amount.unit` but the old scripts use array destructuring (`_, unit = amount`). Need to confirm which is correct.

**Files:**
- Read: `lib/familyrecipes/ingredient_aggregator.rb` or wherever `all_ingredients_with_quantities` is defined

**Step 1: Find and read the method**

Search for the `all_ingredients_with_quantities` method definition. Check what it returns — are amounts arrays `[value, unit]` or objects with `.value`/`.unit` accessors?

**Step 2: Update bin/nutrition if needed**

If amounts are arrays, update `find_missing_ingredients` to use array destructuring. If objects, leave as-is.

**Step 3: Commit if changes made**

```bash
git add bin/nutrition
git commit -m "Fix amount data structure access in find_missing_ingredients"
```

---

### Task 9: Delete old scripts and update docs

**Files:**
- Delete: `bin/nutrition-entry`
- Delete: `bin/nutrition-usda`
- Modify: `CLAUDE.md`

**Step 1: Delete old scripts**

```bash
git rm bin/nutrition-entry bin/nutrition-usda
```

**Step 2: Update CLAUDE.md**

Find the nutrition entry tool references and update them. The relevant sections are:
- The "Two entry tools" section — replace with single tool
- Any other references to `bin/nutrition-entry` or `bin/nutrition-usda`

Replace the two-tool section with:

```markdown
**Entry tool:**

\`\`\`bash
bin/nutrition "Cream cheese"   # Enter/edit data (USDA-first or manual)
bin/nutrition --missing         # Report + batch iterate missing ingredients
bin/nutrition --manual "Flour"  # Force manual entry from package labels
\`\`\`

`bin/nutrition` auto-detects `USDA_API_KEY` (from `.env` or environment): when present, it searches the USDA SR Legacy dataset first and falls back to manual entry; when absent, it defaults to manual entry from package labels. Existing entries open in an edit menu for surgical fixes (e.g., adding missing portions). Requires `USDA_API_KEY` for USDA mode (free at https://fdc.nal.usda.gov/api-key-signup).
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "Replace bin/nutrition-entry and bin/nutrition-usda with bin/nutrition

Closes the merge of both scripts into a single tool with USDA-first
flow, manual fallback, edit mode, and improved --missing iteration."
```

---

### Task 10: Run tests and verify

**Step 1: Run full test suite**

Run: `rake`
Expected: All tests pass, no lint errors. The lib/ code is unchanged so existing tests should be unaffected.

**Step 2: Manual end-to-end test**

Test the key flows:
1. `bin/nutrition --help` — displays help
2. `bin/nutrition --missing` — shows report
3. `bin/nutrition "Flour (all-purpose)"` — shows existing entry, opens edit menu
4. `bin/nutrition --manual "TestIngredient"` — goes through manual flow (can discard)
5. `bin/nutrition "TestIngredient"` — goes through USDA flow (if API key present)

**Step 3: Final commit if any fixes needed**

---

## Notes for the implementer

- **Amount data structure (Task 8):** This is a known uncertainty. The old scripts use `_, unit = amount` (array-style) but the calculator uses `amount.value`/`amount.unit` (object-style). Investigate before the delete step. One of them may be wrong, or Ruby may support both patterns.
- **`enter_new_ingredient` flow:** When USDA search returns `:manual`, the function falls through to `enter_manual`. When `enter_manual` returns `nil` (user quit), the whole flow exits gracefully.
- **Edit menu option 3 (Density):** Re-prompts serving size and updates both `basis_grams` and density. This is the right behavior for manual edits but would be wrong for USDA entries where basis_grams is always 100. Consider whether editing density on a USDA entry should leave basis_grams at 100 and only update the density hash. This is a judgment call during implementation.
- **The `review_and_save` Discard path** calls `enter_new_ingredient` which creates a new entry flow. Make sure this doesn't result in double-saving if the new flow also calls `review_and_save`.

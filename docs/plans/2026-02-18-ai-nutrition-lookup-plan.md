# AI-Assisted Nutrition Lookup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `--auto` mode to `bin/nutrition-lookup` that uses Claude CLI to pick USDA entries and set portion weights, replacing human judgment with AI world knowledge.

**Architecture:** The existing script gets a new `--auto` flag. For each missing ingredient, it searches USDA, fetches detail for the top results, sends everything to `claude -p` with a structured JSON schema, and saves the response. All existing USDA API functions are reused unchanged.

**Tech Stack:** Ruby (existing script), Claude CLI (`claude -p --json-schema`), USDA FoodData Central API (existing)

---

### Task 1: Add `call_claude` helper function

**Files:**
- Modify: `bin/nutrition-lookup`

**Step 1: Write the `call_claude` function**

Add after the existing `parse_usda_portions` function, before `interactive_lookup`:

```ruby
def call_claude(prompt, model: 'haiku')
  cmd = [
    'claude', '-p', prompt,
    '--model', model,
    '--output-format', 'json',
    '--no-session-persistence',
    '--max-budget-usd', '0.05'
  ]

  stdout, status = Open3.capture2(*cmd)
  unless status.success?
    $stderr.puts "Claude CLI error (exit #{status.exitstatus})"
    return nil
  end

  parsed = JSON.parse(stdout)
  # --output-format json wraps the response; extract the text result
  text = parsed['result'] || parsed['content'] || stdout
  JSON.parse(text)
rescue JSON::ParserError => e
  $stderr.puts "Failed to parse Claude response: #{e.message}"
  nil
end
```

Add `require 'open3'` at the top of the file with the other requires.

**Step 2: Test manually from IRB or a throwaway script**

Run:
```bash
echo 'require "open3"; require "json"; stdout, status = Open3.capture2("claude", "-p", "Return JSON: {\"test\": true}", "--model", "haiku", "--output-format", "json", "--no-session-persistence"); puts status.success?; puts stdout' | ruby
```
Expected: `true` and a JSON response.

**Step 3: Commit**

```bash
git add bin/nutrition-lookup
git commit -m "feat(nutrition): add call_claude helper for AI-assisted lookup"
```

---

### Task 2: Add `build_claude_prompt` function

**Files:**
- Modify: `bin/nutrition-lookup`

**Step 1: Write the `build_claude_prompt` function**

Add after `call_claude`:

```ruby
def build_claude_prompt(ingredient_name, foods_with_details)
  entries = foods_with_details.map.with_index do |(food, nutrients, api_portions), i|
    portions_str = if api_portions.any?
      "Portions: " + api_portions.map { |k, v| "#{k}=#{v}g" }.join(', ')
    else
      "Portions: none found"
    end

    data_type = food['dataType'] || 'Unknown'
    <<~ENTRY
      #{i + 1}. [#{data_type}] #{food['description']} (FDC #{food['fdcId']})
         #{format_nutrients_preview(nutrients)}
         #{portions_str}
    ENTRY
  end

  <<~PROMPT
    You are populating a nutrition database for a family recipe website.

    Ingredient name (as used in recipes): "#{ingredient_name}"

    USDA search results (nutrients are per 100g):

    #{entries.join("\n")}

    Pick the single best match for typical home cooking and return a JSON object.

    Guidelines:
    - Prefer "Foundation" data over "SR Legacy" when nutrition values are similar
    - Prefer whole/with skin/raw over processed unless the ingredient name suggests otherwise
    - Skip entries with obviously wrong data (e.g., 0 calories for a food that clearly has calories)
    - For portions, use USDA values when they seem reasonable; override from your world knowledge if not
    - Include ~unitless (grams per single item) only if the ingredient is commonly counted individually (eggs, lemons, apples — not flour, oil, sugar)
    - Include stick only for butter
    - Only include portion units that make practical sense for this specific ingredient
    - If none of the search results are a good match, return {"skip": true, "reasoning": "explanation"}
  PROMPT
end
```

**Step 2: Verify prompt renders correctly**

Add a temporary test at the bottom of the file (or check manually) to ensure the prompt renders cleanly for a sample ingredient. Remove after verifying.

**Step 3: Commit**

```bash
git add bin/nutrition-lookup
git commit -m "feat(nutrition): add build_claude_prompt for auto mode"
```

---

### Task 3: Add `auto_lookup` function

**Files:**
- Modify: `bin/nutrition-lookup`

**Step 1: Write the `auto_lookup` function**

Add after `build_claude_prompt`:

```ruby
def auto_lookup(ingredient_name, nutrition_data, model:)
  foods = search_usda(ingredient_name)
  if foods.empty?
    puts "  SKIP (no USDA results)"
    return nil
  end

  # Fetch detail (for portions) for top 5 results only
  foods_with_details = foods.first(5).map do |food|
    nutrients = extract_nutrients(food)
    detail = get_food_detail(food['fdcId'])
    api_portions = detail ? parse_usda_portions(detail) : {}
    [food, nutrients, api_portions]
  end

  prompt = build_claude_prompt(ingredient_name, foods_with_details)
  result = call_claude(prompt, model: model)

  unless result
    puts "  SKIP (Claude response error)"
    return nil
  end

  if result['skip']
    puts "  SKIP (#{result['reasoning']})"
    return nil
  end

  # Validate required fields
  unless result['fdc_id'] && result['per_100g']
    puts "  SKIP (malformed response: missing fdc_id or per_100g)"
    return nil
  end

  entry = {
    'fdc_id' => result['fdc_id'],
    'per_100g' => {
      'calories' => (result.dig('per_100g', 'calories') || 0).round(2),
      'protein' => (result.dig('per_100g', 'protein') || 0).round(2),
      'fat' => (result.dig('per_100g', 'fat') || 0).round(2),
      'carbs' => (result.dig('per_100g', 'carbs') || 0).round(2),
      'fiber' => (result.dig('per_100g', 'fiber') || 0).round(2),
      'sodium' => (result.dig('per_100g', 'sodium') || 0).round(2)
    }
  }

  portions = result['portions']
  entry['portions'] = portions if portions && !portions.empty?

  reasoning = result['reasoning'] || 'no reasoning given'
  cals = entry['per_100g']['calories']
  puts "  OK  FDC #{entry['fdc_id']} (#{cals}cal/100g) — #{reasoning}"

  nutrition_data[ingredient_name] = entry
  entry
end
```

**Step 2: Commit**

```bash
git add bin/nutrition-lookup
git commit -m "feat(nutrition): add auto_lookup function for AI-driven ingredient selection"
```

---

### Task 4: Add JSON schema constant

**Files:**
- Modify: `bin/nutrition-lookup`

**Step 1: Add the schema constant**

Add near the top of the file with the other constants:

```ruby
AUTO_JSON_SCHEMA = {
  type: 'object',
  properties: {
    fdc_id: { type: 'integer' },
    reasoning: { type: 'string' },
    per_100g: {
      type: 'object',
      properties: {
        calories: { type: 'number' },
        protein: { type: 'number' },
        fat: { type: 'number' },
        carbs: { type: 'number' },
        fiber: { type: 'number' },
        sodium: { type: 'number' }
      },
      required: %w[calories protein fat carbs fiber sodium]
    },
    portions: {
      type: 'object',
      additionalProperties: { type: 'number' }
    },
    skip: { type: 'boolean' }
  },
  required: %w[reasoning]
}.freeze
```

**Step 2: Update `call_claude` to use the schema**

Change the `cmd` array in `call_claude` to include the schema:

```ruby
def call_claude(prompt, model: 'haiku')
  cmd = [
    'claude', '-p', prompt,
    '--model', model,
    '--output-format', 'json',
    '--json-schema', JSON.generate(AUTO_JSON_SCHEMA),
    '--no-session-persistence',
    '--max-budget-usd', '0.05'
  ]
  # ... rest unchanged
end
```

**Step 3: Commit**

```bash
git add bin/nutrition-lookup
git commit -m "feat(nutrition): add JSON schema constraint for Claude responses"
```

---

### Task 5: Wire up `--auto` flag in main

**Files:**
- Modify: `bin/nutrition-lookup`

**Step 1: Update the help text**

Add the `--auto` and `--model` descriptions:

```ruby
if ARGV.include?('--help') || ARGV.include?('-h')
  puts "Usage:"
  puts "  bin/nutrition-lookup \"Ingredient Name\"    Look up one ingredient interactively"
  puts "  bin/nutrition-lookup --missing              Find and fill unmapped ingredients interactively"
  puts "  bin/nutrition-lookup --auto                 Fill all missing ingredients using AI (Claude CLI)"
  puts "  bin/nutrition-lookup --auto --model sonnet  Use a specific Claude model (default: haiku)"
  puts ""
  puts "Requires USDA_API_KEY environment variable (free from https://api.data.gov/signup/)"
  puts "--auto mode also requires the Claude CLI (claude) to be installed and authenticated."
  exit 0
end
```

**Step 2: Add `--auto` handling in the main block**

Replace the `if ARGV.include?('--missing')` block with:

```ruby
if ARGV.include?('--auto')
  model_idx = ARGV.index('--model')
  model = model_idx ? ARGV[model_idx + 1] || 'haiku' : 'haiku'

  missing = find_missing_ingredients(nutrition_data)
  if missing.empty?
    puts "All ingredients are mapped!"
    exit 0
  end

  puts "#{missing.length} unmapped ingredients. Running auto-lookup with model: #{model}\n\n"

  added = 0
  skipped = 0
  missing.each_with_index do |name, i|
    puts "[#{i + 1}/#{missing.length}] #{name}"
    result = auto_lookup(name, nutrition_data, model: model)
    if result
      save_nutrition_data(nutrition_data)
      added += 1
    else
      skipped += 1
    end
  end

  puts "\nDone. Added #{added}/#{missing.length} ingredients. #{skipped} skipped."
  puts "Review: git diff resources/nutrition-data.yaml"
elsif ARGV.include?('--missing')
  # ... existing --missing code unchanged
```

**Step 3: Commit**

```bash
git add bin/nutrition-lookup
git commit -m "feat(nutrition): wire up --auto flag for AI-driven bulk lookup"
```

---

### Task 6: End-to-end test with a single ingredient

**Step 1: Run auto mode for a single test**

To test without processing all missing ingredients, temporarily test with a direct call:

```bash
cd /home/chris/familyrecipes
ruby -e '
  require "bundler/setup"
  require_relative "lib/familyrecipes"
  load "bin/nutrition-lookup"
' 2>&1 || true
```

Or better, test `--auto` and observe the first ingredient:

```bash
bin/nutrition-lookup --auto --model haiku
```

Watch the output for the first few ingredients. Ctrl-C after seeing a few results if needed.

Expected output:
```
38 unmapped ingredients. Running auto-lookup with model: haiku

[1/38] Apples
  OK  FDC 171688 (52cal/100g) — Foundation data, raw with skin matches typical home use
[2/38] Basil (fresh)
  OK  FDC 172232 (23cal/100g) — Foundation data, fresh basil
...
```

**Step 2: Review the data**

```bash
git diff resources/nutrition-data.yaml
```

Spot-check a few entries for reasonableness.

**Step 3: Commit the result (if satisfied)**

```bash
git add resources/nutrition-data.yaml
git commit -m "data: populate nutrition data for remaining ingredients via AI lookup"
```

---

### Task 7: Verify site build with new data

**Step 1: Build the site**

```bash
bin/generate
```

Expected: No errors. Recipes that previously showed "data unavailable" disclaimers should now show full nutrition facts.

**Step 2: Run tests**

```bash
rake test
```

Expected: All tests pass. The new nutrition data doesn't affect existing tests (they use their own fixture data).

**Step 3: Visual check**

Check a few recipe pages in the browser at `http://rika:8888` to verify nutrition facts render correctly with the new data.

# Range-Aware Ingredient Scaling Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ingredient scaling operate on both sides of quantity ranges (e.g., "2-3" becomes "4-6" at 2×), with en-dash display rendering and native numeric columns.

**Architecture:** Add `quantity_low`/`quantity_high` decimal columns to `ingredients`. Parse ranges at import time via `FamilyRecipes::Ingredient.parse_range`. Display uses en-dashes and vulgar fraction glyphs; storage and serialization use hyphens and ASCII fractions. Client-side scaling reads both endpoints from data attributes.

**Tech Stack:** Ruby/Rails, Stimulus (JavaScript), SQLite, Minitest, Node test runner

**Spec:** `docs/plans/2026-03-16-range-aware-scaling-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/familyrecipes/ingredient.rb` | Modify | Add `parse_range`, `normalize_quantity` class methods |
| `lib/familyrecipes/vulgar_fractions.rb` | Modify | Add `to_fraction_string` (decimal → ASCII fraction) |
| `app/models/ingredient.rb` | Modify | Update `quantity_value`, `quantity_display` for new columns |
| `app/services/markdown_importer.rb` | Modify | Normalize + parse range in `import_ingredient` |
| `lib/familyrecipes/recipe_serializer.rb` | Modify | Reconstruct quantity from numeric columns in `build_ingredient_ir` |
| `app/helpers/recipes_helper.rb` | Modify | Update `ingredient_data_attrs`, `scaled_quantity_display` for ranges |
| `app/javascript/controllers/recipe_state_controller.js` | Modify | Scale both range endpoints in `applyScale` |
| `app/javascript/utilities/vulgar_fractions.js` | Modify | Add `toFractionString` (decimal → ASCII fraction) |
| `db/migrate/007_add_quantity_range_columns.rb` | Create | Add columns + backfill |
| `db/seeds/recipes/Baking/Pancakes.md` | Modify | Add range ingredient for test coverage |
| Tests (multiple) | Modify/Create | See individual tasks |

---

## Chunk 1: Domain Layer — Parsing, Normalization, and Fraction Conversion

### Task 1: Add `VulgarFractions.to_fraction_string` (Ruby)

Converts a float to the most readable ASCII fraction string. Inverse of `VulgarFractions.format` but outputs ASCII instead of Unicode glyphs.

**Files:**
- Modify: `lib/familyrecipes/vulgar_fractions.rb`
- Modify: `test/vulgar_fractions_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/vulgar_fractions_test.rb`:

```ruby
# --- to_fraction_string ---

def test_to_fraction_string_integer
  assert_equal '2', FamilyRecipes::VulgarFractions.to_fraction_string(2.0)
end

def test_to_fraction_string_half
  assert_equal '1/2', FamilyRecipes::VulgarFractions.to_fraction_string(0.5)
end

def test_to_fraction_string_third
  assert_equal '1/3', FamilyRecipes::VulgarFractions.to_fraction_string(1.0 / 3)
end

def test_to_fraction_string_two_thirds
  assert_equal '2/3', FamilyRecipes::VulgarFractions.to_fraction_string(2.0 / 3)
end

def test_to_fraction_string_quarter
  assert_equal '1/4', FamilyRecipes::VulgarFractions.to_fraction_string(0.25)
end

def test_to_fraction_string_three_quarters
  assert_equal '3/4', FamilyRecipes::VulgarFractions.to_fraction_string(0.75)
end

def test_to_fraction_string_eighth
  assert_equal '1/8', FamilyRecipes::VulgarFractions.to_fraction_string(0.125)
end

def test_to_fraction_string_mixed_half
  assert_equal '1 1/2', FamilyRecipes::VulgarFractions.to_fraction_string(1.5)
end

def test_to_fraction_string_mixed_quarter
  assert_equal '2 1/4', FamilyRecipes::VulgarFractions.to_fraction_string(2.25)
end

def test_to_fraction_string_mixed_three_quarters
  assert_equal '1 3/4', FamilyRecipes::VulgarFractions.to_fraction_string(1.75)
end

def test_to_fraction_string_non_matching_decimal
  assert_equal '1.37', FamilyRecipes::VulgarFractions.to_fraction_string(1.37)
end

def test_to_fraction_string_zero
  assert_equal '0', FamilyRecipes::VulgarFractions.to_fraction_string(0.0)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/vulgar_fractions_test.rb -n /to_fraction_string/`
Expected: FAIL — `NoMethodError: undefined method 'to_fraction_string'`

- [ ] **Step 3: Implement `to_fraction_string`**

In `lib/familyrecipes/vulgar_fractions.rb`, add a `FRACTION_STRINGS` constant (reverse of `GLYPHS` but with ASCII output) and the method. Place after the `format` method:

```ruby
FRACTION_STRINGS = {
  1 / 2r => '1/2',
  1 / 3r => '1/3',
  2 / 3r => '2/3',
  1 / 4r => '1/4',
  3 / 4r => '3/4',
  1 / 8r => '1/8',
  3 / 8r => '3/8',
  5 / 8r => '5/8',
  7 / 8r => '7/8'
}.freeze

def to_fraction_string(value)
  return value.to_i.to_s if integer?(value)

  integer_part = value.to_i
  frac = find_fraction_string(fractional_part(value))

  return format_ascii_fraction(integer_part, frac) if frac

  format_decimal(value)
end
```

Add private helpers:

```ruby
def find_fraction_string(fractional_value)
  FRACTION_STRINGS.find { |rational, _| (fractional_value - rational.to_f).abs < TOLERANCE }&.last
end

def format_ascii_fraction(integer_part, frac)
  integer_part.zero? ? frac : "#{integer_part} #{frac}"
end
```

Update `private_class_method` line to include `:find_fraction_string, :format_ascii_fraction`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/vulgar_fractions_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes/vulgar_fractions.rb test/vulgar_fractions_test.rb
git commit -m "feat: add VulgarFractions.to_fraction_string for ASCII fraction output (#247)"
```

---

### Task 2: Add `FamilyRecipes::Ingredient.normalize_quantity` and `parse_range`

Two new class methods on the domain parser class. `normalize_quantity` converts vulgar glyphs to ASCII fractions and en-dashes to hyphens. `parse_range` splits a value string on the first hyphen/en-dash and returns `[low, high]`.

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb`
- Modify: `test/ingredient_test.rb`

**Reference:**
- `lib/familyrecipes/numeric_parsing.rb` — `NumericParsing::VULGAR_GLYPHS` has the glyph→rational map
- `lib/familyrecipes/numeric_parsing.rb` — `NumericParsing.parse_fraction` for parsing each side

- [ ] **Step 1: Write failing tests for `normalize_quantity`**

Add to `test/ingredient_test.rb`:

```ruby
# normalize_quantity tests
def test_normalize_quantity_vulgar_half
  assert_equal '1/2 cup', FamilyRecipes::Ingredient.normalize_quantity('½ cup')
end

def test_normalize_quantity_vulgar_quarter
  assert_equal '1/4 cup', FamilyRecipes::Ingredient.normalize_quantity('¼ cup')
end

def test_normalize_quantity_mixed_vulgar
  assert_equal '2 1/2 cups', FamilyRecipes::Ingredient.normalize_quantity('2½ cups')
end

def test_normalize_quantity_en_dash_to_hyphen
  assert_equal '2-3 cups', FamilyRecipes::Ingredient.normalize_quantity('2–3 cups')
end

def test_normalize_quantity_vulgar_and_en_dash
  assert_equal '1/2-1 sticks', FamilyRecipes::Ingredient.normalize_quantity('½–1 sticks')
end

def test_normalize_quantity_already_ascii
  assert_equal '2-3 cups', FamilyRecipes::Ingredient.normalize_quantity('2-3 cups')
end

def test_normalize_quantity_nil
  assert_nil FamilyRecipes::Ingredient.normalize_quantity(nil)
end

def test_normalize_quantity_blank
  assert_nil FamilyRecipes::Ingredient.normalize_quantity('  ')
end

def test_normalize_quantity_freeform
  assert_equal 'a pinch', FamilyRecipes::Ingredient.normalize_quantity('a pinch')
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n /normalize_quantity/`
Expected: FAIL — `NoMethodError: undefined method 'normalize_quantity'`

- [ ] **Step 3: Implement `normalize_quantity`**

In `lib/familyrecipes/ingredient.rb`, add the class method:

```ruby
VULGAR_TO_ASCII = FamilyRecipes::NumericParsing::VULGAR_GLYPHS.transform_values { |r|
  num, den = r.numerator, r.denominator
  "#{num}/#{den}"
}.freeze

VULGAR_REPLACE_PATTERN = /(\d*)\s*(#{FamilyRecipes::NumericParsing::VULGAR_PATTERN})/

def self.normalize_quantity(raw)
  return nil if raw.nil? || raw.strip.empty?

  result = raw.strip
  result = result.gsub(VULGAR_REPLACE_PATTERN) { |_|
    prefix = Regexp.last_match(1)
    glyph = Regexp.last_match(2)
    ascii = VULGAR_TO_ASCII[glyph]
    prefix.empty? ? ascii : "#{prefix} #{ascii}"
  }
  result.tr('–', '-')
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/ingredient_test.rb -n /normalize_quantity/`
Expected: All PASS

- [ ] **Step 5: Write failing tests for `parse_range`**

Add to `test/ingredient_test.rb`:

```ruby
# parse_range tests
def test_parse_range_simple
  assert_equal [2.0, 3.0], FamilyRecipes::Ingredient.parse_range('2-3')
end

def test_parse_range_fractions
  low, high = FamilyRecipes::Ingredient.parse_range('1/2-1')
  assert_in_delta 0.5, low
  assert_in_delta 1.0, high
end

def test_parse_range_single_value
  assert_equal [2.0, nil], FamilyRecipes::Ingredient.parse_range('2')
end

def test_parse_range_single_fraction
  low, high = FamilyRecipes::Ingredient.parse_range('1/2')
  assert_in_delta 0.5, low
  assert_nil high
end

def test_parse_range_low_greater_than_high
  assert_equal [nil, nil], FamilyRecipes::Ingredient.parse_range('1-1/2')
end

def test_parse_range_nil
  assert_equal [nil, nil], FamilyRecipes::Ingredient.parse_range(nil)
end

def test_parse_range_blank
  assert_equal [nil, nil], FamilyRecipes::Ingredient.parse_range('  ')
end

def test_parse_range_non_numeric
  assert_equal [nil, nil], FamilyRecipes::Ingredient.parse_range('a pinch')
end

def test_parse_range_equal_endpoints
  assert_equal [2.0, nil], FamilyRecipes::Ingredient.parse_range('2-2')
end

def test_parse_range_mixed_number_high
  low, high = FamilyRecipes::Ingredient.parse_range('3/4-1 1/2')
  assert_in_delta 0.75, low
  assert_in_delta 1.5, high
end
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n /parse_range/`
Expected: FAIL — `NoMethodError: undefined method 'parse_range'`

- [ ] **Step 7: Implement `parse_range`**

In `lib/familyrecipes/ingredient.rb`, add the class method:

```ruby
def self.parse_range(value_str)
  return [nil, nil] if value_str.nil? || value_str.strip.empty?

  str = value_str.strip
  parts = str.split(/[-–]/, 2)

  return parse_single_value(str) unless parts.size == 2

  low = safe_parse(parts[0].strip)
  high = safe_parse(parts[1].strip)

  return [nil, nil] unless low && high
  return [low, nil] if (low - high).abs < 0.0001
  return [nil, nil] if low > high

  [low, high]
end
```

Add private helpers:

```ruby
def self.parse_single_value(str)
  value = safe_parse(str)
  value ? [value, nil] : [nil, nil]
end

def self.safe_parse(str)
  NumericParsing.parse_fraction(str)
rescue ArgumentError
  nil
end

private_class_method :parse_single_value, :safe_parse
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: All PASS

- [ ] **Step 9: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "feat: add normalize_quantity and parse_range to FamilyRecipes::Ingredient (#247)"
```

---

### Task 3: Add `toFractionString` to JavaScript `vulgar_fractions.js`

Mirror of Ruby `VulgarFractions.to_fraction_string` for the graphical editor serialization path.

**Files:**
- Modify: `app/javascript/utilities/vulgar_fractions.js`

**Note:** JS tests use Node's built-in test runner (`node --test test/javascript/*.mjs`). There are no existing JS tests for `vulgar_fractions.js`, so we add a new test file.

- [ ] **Step 1: Write failing JS test**

Create `test/javascript/vulgar_fractions_test.mjs`:

```javascript
import assert from "node:assert/strict"
import { test } from "node:test"
import { toFractionString } from "../../app/javascript/utilities/vulgar_fractions.js"

test("integer returns plain number", () => {
  assert.equal(toFractionString(2.0), "2")
})

test("half returns 1/2", () => {
  assert.equal(toFractionString(0.5), "1/2")
})

test("third returns 1/3", () => {
  assert.equal(toFractionString(1/3), "1/3")
})

test("quarter returns 1/4", () => {
  assert.equal(toFractionString(0.25), "1/4")
})

test("three quarters returns 3/4", () => {
  assert.equal(toFractionString(0.75), "3/4")
})

test("mixed half returns 1 1/2", () => {
  assert.equal(toFractionString(1.5), "1 1/2")
})

test("mixed quarter returns 2 1/4", () => {
  assert.equal(toFractionString(2.25), "2 1/4")
})

test("non-matching decimal returns rounded", () => {
  assert.equal(toFractionString(1.37), "1.37")
})

test("zero returns 0", () => {
  assert.equal(toFractionString(0), "0")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL — `toFractionString is not a function` (not yet exported)

- [ ] **Step 3: Implement `toFractionString`**

In `app/javascript/utilities/vulgar_fractions.js`, add after the `VULGAR_FRACTIONS` array:

```javascript
const FRACTION_STRINGS = [
  [1/2, '1/2'], [1/3, '1/3'], [2/3, '2/3'],
  [1/4, '1/4'], [3/4, '3/4'],
  [1/8, '1/8'], [3/8, '3/8'], [5/8, '5/8'], [7/8, '7/8']
]

export function toFractionString(value) {
  if (Number.isInteger(value) || Math.abs(value - Math.round(value)) < 0.001) {
    return String(Math.round(value))
  }
  const intPart = Math.floor(value)
  const fracPart = value - intPart
  const match = FRACTION_STRINGS.find(([v]) => Math.abs(fracPart - v) < 0.001)
  if (match) return intPart === 0 ? match[1] : `${intPart} ${match[1]}`
  const rounded = Math.round(value * 100) / 100
  return String(rounded)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add app/javascript/utilities/vulgar_fractions.js test/javascript/vulgar_fractions_test.mjs
git commit -m "feat: add toFractionString to JS vulgar_fractions utility (#247)"
```

---

## Chunk 2: Data Model, Migration, and AR Model

### Task 4: Migration — add `quantity_low` and `quantity_high` columns with backfill

**Files:**
- Create: `db/migrate/007_add_quantity_range_columns.rb`

**Reference:**
- `db/migrate/006_migrate_quick_bites_headers.rb` for migration stub pattern
- `lib/familyrecipes/numeric_parsing.rb` for fraction parsing logic

- [ ] **Step 1: Write the migration**

Create `db/migrate/007_add_quantity_range_columns.rb`:

```ruby
# frozen_string_literal: true

class AddQuantityRangeColumns < ActiveRecord::Migration[8.1]
  # Inline parsing stub — must not reference application models.
  module QuantityParser
    VULGAR_GLYPHS = {
      '½' => 0.5, '⅓' => 1.0 / 3, '⅔' => 2.0 / 3,
      '¼' => 0.25, '¾' => 0.75,
      '⅛' => 0.125, '⅜' => 0.375, '⅝' => 0.625, '⅞' => 0.875
    }.freeze

    VULGAR_PATTERN = /[#{VULGAR_GLYPHS.keys.join}]/

    module_function

    def parse_value(str)
      return nil if str.nil? || str.strip.empty?

      s = normalize(str.strip)
      parts = s.split(/[-]/, 2)

      if parts.size == 2
        low = safe_parse(parts[0].strip)
        high = safe_parse(parts[1].strip)
        return [low, high] if low && high && low < high
        return [low, nil] if low && high && (low - high).abs < 0.0001
      end

      value = safe_parse(s)
      value ? [value, nil] : [nil, nil]
    end

    VULGAR_TO_ASCII = {
      '½' => '1/2', '⅓' => '1/3', '⅔' => '2/3',
      '¼' => '1/4', '¾' => '3/4',
      '⅛' => '1/8', '⅜' => '3/8', '⅝' => '5/8', '⅞' => '7/8'
    }.freeze

    def normalize(s)
      result = s.gsub(/(\d*)\s*(#{VULGAR_PATTERN})/) do
        prefix = Regexp.last_match(1)
        glyph = Regexp.last_match(2)
        ascii = VULGAR_TO_ASCII[glyph]
        prefix.empty? ? ascii : "#{prefix} #{ascii}"
      end
      result.tr("\u2013", '-')
    end

    def safe_parse(s)
      return nil if s.nil? || s.empty?

      if (match = s.match(/\A(\d+)\s+(\d+\/\d+)\z/))
        return match[1].to_f + parse_fraction(match[2])
      end

      return parse_fraction(s) if s.include?('/')

      Float(s, exception: false)
    end

    def parse_fraction(s)
      num, den = s.split('/', 2).map { |p| Float(p, exception: false) }
      return nil unless num && den && !den.zero?

      num / den
    end
  end

  def change
    add_column :ingredients, :quantity_low, :decimal
    add_column :ingredients, :quantity_high, :decimal

    reversible do |dir|
      dir.up { backfill }
    end
  end

  private

  def backfill
    rows = execute("SELECT id, quantity FROM ingredients WHERE quantity IS NOT NULL")
    rows.each do |row|
      id = row['id'] || row[0]
      qty = row['quantity'] || row[1]
      low, high = QuantityParser.parse_value(qty)
      next unless low

      if high
        execute("UPDATE ingredients SET quantity_low = #{low}, quantity_high = #{high} WHERE id = #{id}")
      else
        execute("UPDATE ingredients SET quantity_low = #{low} WHERE id = #{id}")
      end
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `bundle exec rails db:migrate`
Expected: Migration succeeds, `quantity_low` and `quantity_high` columns added

- [ ] **Step 3: Verify backfill**

Run: `bundle exec rails runner "puts Ingredient.where.not(quantity_low: nil).count"`
Expected: A number > 0 (existing ingredients with numeric quantities got backfilled)

- [ ] **Step 4: Commit**

```bash
git add db/migrate/007_add_quantity_range_columns.rb db/schema.rb
git commit -m "feat: add quantity_low/quantity_high columns with backfill migration (#247)"
```

---

### Task 5: Update AR `Ingredient` model

Update `quantity_value` and `quantity_display` to use the new numeric columns.

**Files:**
- Modify: `app/models/ingredient.rb`
- Modify: `test/models/ingredient_test.rb` (AR model tests)

**Reference:**
- `app/models/ingredient.rb:14-28` — current `quantity_display`, `quantity_value`, `quantity_unit`
- `lib/familyrecipes/vulgar_fractions.rb` — `VulgarFractions.format` for display

- [ ] **Step 1: Write failing tests**

Check what exists in `test/models/ingredient_test.rb` first. Add tests for range-aware behavior:

```ruby
test 'quantity_value returns high end for range' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)

  assert_equal '3', ingredient.quantity_value
end

test 'quantity_value returns low for non-range' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Flour', quantity_low: 2.0)

  assert_equal '2', ingredient.quantity_value
end

test 'quantity_value returns nil when no numeric quantity' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Salt', quantity: 'a pinch')

  assert_nil ingredient.quantity_value
end

test 'quantity_value strips trailing .0' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Eggs', quantity_low: 3.0)

  assert_equal '3', ingredient.quantity_value
end

test 'quantity_value preserves decimals' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Salt', quantity_low: 0.5)

  assert_equal '0.5', ingredient.quantity_value
end

test 'quantity_display for range with unit' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Flour', quantity_low: 2.0, quantity_high: 3.0, unit: 'cup')

  assert_equal "2\u20133 cups", ingredient.quantity_display
end

test 'quantity_display for fractional range' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Butter', quantity_low: 0.5, quantity_high: 1.0, unit: 'stick')

  assert_equal "\u00BD\u20131 stick", ingredient.quantity_display
end

test 'quantity_display for non-range with vulgar fraction' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Butter', quantity_low: 0.5, unit: 'cup')

  assert_equal "\u00BD cup", ingredient.quantity_display
end

test 'quantity_display for non-numeric falls back to raw' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Basil', quantity: 'a few leaves')

  assert_equal 'a few leaves', ingredient.quantity_display
end

test 'quantity_display for unitless range' do
  ingredient = Ingredient.new(step: @step, position: 1, name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)

  assert_equal "2\u20133", ingredient.quantity_display
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/ingredient_test.rb`
Expected: FAIL — methods return wrong values (old implementation)

- [ ] **Step 3: Update `Ingredient` model**

Replace the body of `app/models/ingredient.rb`:

```ruby
class Ingredient < ApplicationRecord
  belongs_to :step, inverse_of: :ingredients

  validates :name, presence: true
  validates :position, presence: true

  def quantity_display
    return [quantity, unit].compact.join(' ').presence unless quantity_low

    formatted = range? ? "#{format_value(quantity_low)}\u2013#{format_value(quantity_high)}" : format_value(quantity_low)
    unit_str = pluralized_unit
    [formatted, unit_str].compact.join(' ')
  end

  def quantity_value
    value = quantity_high || quantity_low
    return unless value

    format_decimal(value)
  end

  def quantity_unit
    return unless unit

    FamilyRecipes::Inflector.normalize_unit(unit)
  end

  def range?
    quantity_high.present?
  end

  private

  def format_value(val)
    FamilyRecipes::VulgarFractions.format(val.to_f, unit: quantity_unit)
  end

  def format_decimal(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end

  def pluralized_unit
    return unless unit

    display_value = quantity_high || quantity_low
    FamilyRecipes::Inflector.unit_display(unit, display_value.to_f)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/models/ingredient_test.rb`
Expected: All PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `bundle exec rake test`
Expected: Some failures expected in controller/helper tests that check `data-quantity-value` — these are addressed in later tasks. The model and domain tests should pass.

- [ ] **Step 6: Commit**

```bash
git add app/models/ingredient.rb test/models/ingredient_test.rb
git commit -m "feat: update AR Ingredient for quantity_low/quantity_high columns (#247)"
```

---

## Chunk 3: Import Pipeline and Serializer

### Task 6: Update `MarkdownImporter#import_ingredient`

Wire up normalization and range parsing in the import path.

**Files:**
- Modify: `app/services/markdown_importer.rb:138-148`

- [ ] **Step 1: Update `import_ingredient`**

Replace the `import_ingredient` method in `app/services/markdown_importer.rb`:

```ruby
def import_ingredient(step, data, position)
  normalized = FamilyRecipes::Ingredient.normalize_quantity(data[:quantity])
  qty, unit = FamilyRecipes::Ingredient.split_quantity(normalized)
  low, high = FamilyRecipes::Ingredient.parse_range(qty)

  step.ingredients.create!(
    name: data[:name],
    quantity: qty,
    quantity_low: low,
    quantity_high: high,
    unit: unit,
    prep_note: data[:prep_note],
    position: position
  )
end
```

- [ ] **Step 2: Write integration test for range import**

Add to the importer test file (find it first — likely `test/services/markdown_importer_test.rb` or similar):

```ruby
test 'imports ingredient with range quantity' do
  markdown = "# Test\n\n## Step\n\n- Eggs, 2-3\n\nScramble them."
  result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
  ingredient = result.recipe.steps.first.ingredients.first

  assert_equal 'Eggs', ingredient.name
  assert_equal '2-3', ingredient.quantity
  assert_in_delta 2.0, ingredient.quantity_low
  assert_in_delta 3.0, ingredient.quantity_high
  assert_nil ingredient.unit
end

test 'imports ingredient with fractional range' do
  markdown = "# Test\n\n## Step\n\n- Butter, 1/2-1 stick\n\nMelt it."
  result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
  ingredient = result.recipe.steps.first.ingredients.first

  assert_in_delta 0.5, ingredient.quantity_low
  assert_in_delta 1.0, ingredient.quantity_high
  assert_equal 'stick', ingredient.unit
end

test 'normalizes vulgar fractions on import' do
  markdown = "# Test\n\n## Step\n\n- Butter, ½ cup\n\nMelt it."
  result = MarkdownImporter.import(markdown, kitchen: @kitchen, category: @category)
  ingredient = result.recipe.steps.first.ingredients.first

  assert_equal '1/2', ingredient.quantity
  assert_in_delta 0.5, ingredient.quantity_low
  assert_nil ingredient.quantity_high
end
```

- [ ] **Step 3: Run tests**

Run: `ruby -Itest test/services/markdown_importer_test.rb` (or wherever the file lives)
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/markdown_importer.rb test/services/markdown_importer_test.rb
git commit -m "feat: normalize and parse ranges in MarkdownImporter (#247)"
```

---

### Task 7: Update `RecipeSerializer#build_ingredient_ir`

Reconstruct quantity string from numeric columns for the IR hash.

**Files:**
- Modify: `lib/familyrecipes/recipe_serializer.rb:157-159`
- Modify: `test/recipe_serializer_test.rb`

**Reference:**
- Current `build_ingredient_ir` joins `ing.quantity` and `ing.unit` into a single string

- [ ] **Step 1: Write round-trip test for range serialization**

This test needs AR records, so it must go in a Rails test file. Add to an existing serializer integration test or create one at `test/services/recipe_serializer_integration_test.rb`:

```ruby
test 'round-trips range ingredient through serializer' do
  markdown = "# Range Test\n\n## Step\n\n- Eggs, 2-3\n- Flour, 1/2-1 cup\n\nMix."
  recipe = create_recipe(markdown)
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
  serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

  assert_includes serialized, '- Eggs, 2-3'
  assert_includes serialized, '- Flour, 1/2-1 cup'
end

test 'serializes non-range ingredient from numeric columns' do
  markdown = "# Simple Test\n\n## Step\n\n- Flour, 2 cups\n\nMix."
  recipe = create_recipe(markdown)
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
  serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

  assert_includes serialized, '- Flour, 2 cups'
end

test 'serializes non-numeric quantity as-is' do
  markdown = "# Freeform Test\n\n## Step\n\n- Basil, a few leaves\n\nAdd."
  recipe = create_recipe(markdown)
  ir = FamilyRecipes::RecipeSerializer.from_record(recipe.reload)
  serialized = FamilyRecipes::RecipeSerializer.serialize(ir)

  assert_includes serialized, '- Basil, a few leaves'
end
```

- [ ] **Step 2: Update `build_ingredient_ir`**

In `lib/familyrecipes/recipe_serializer.rb`, replace `build_ingredient_ir`:

```ruby
def build_ingredient_ir(ing)
  quantity = serialize_ingredient_quantity(ing)
  { name: ing.name, quantity: quantity, prep_note: ing.prep_note }
end

def serialize_ingredient_quantity(ing)
  return [ing.quantity, ing.unit].compact.join(' ').presence unless ing.quantity_low

  parts = if ing.quantity_high
             "#{VulgarFractions.to_fraction_string(ing.quantity_low.to_f)}-#{VulgarFractions.to_fraction_string(ing.quantity_high.to_f)}"
           else
             VulgarFractions.to_fraction_string(ing.quantity_low.to_f)
           end

  [parts, ing.unit].compact.join(' ')
end
```

Add `serialize_ingredient_quantity` to the `private_class_method` list.

- [ ] **Step 3: Run tests**

Run: `ruby -Itest test/recipe_serializer_test.rb` (parser-level round trips)
Then: `ruby -Itest test/services/recipe_serializer_integration_test.rb` (AR-level)
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add lib/familyrecipes/recipe_serializer.rb test/recipe_serializer_test.rb test/services/recipe_serializer_integration_test.rb
git commit -m "feat: serialize ranges from numeric columns in RecipeSerializer (#247)"
```

---

## Chunk 4: Display, Helpers, and Client-Side Scaling

### Task 8: Update `recipes_helper.rb` — data attributes and display

**Files:**
- Modify: `app/helpers/recipes_helper.rb:100-164`
- Modify: `test/helpers/recipes_helper_test.rb`

- [ ] **Step 1: Write failing tests**

Add to `test/helpers/recipes_helper_test.rb`:

```ruby
test 'ingredient_data_attrs emits quantity-low for non-range' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
  attrs = ingredient_data_attrs(ingredient)

  assert_includes attrs, 'data-quantity-low="2.0"'
  assert_not_includes attrs, 'data-quantity-high'
  assert_not_includes attrs, 'data-quantity-value'
end

test 'ingredient_data_attrs emits both low and high for range' do
  ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)
  attrs = ingredient_data_attrs(ingredient)

  assert_includes attrs, 'data-quantity-low="2.0"'
  assert_includes attrs, 'data-quantity-high="3.0"'
end

test 'ingredient_data_attrs pre-multiplies by scale_factor' do
  ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)
  attrs = ingredient_data_attrs(ingredient, scale_factor: 2.0)

  assert_includes attrs, 'data-quantity-low="4.0"'
  assert_includes attrs, 'data-quantity-high="6.0"'
end

test 'ingredient_data_attrs returns empty for non-numeric' do
  ingredient = Ingredient.new(name: 'Salt', quantity: 'a pinch')
  attrs = ingredient_data_attrs(ingredient)

  assert_not_includes attrs, 'data-quantity-low'
end

test 'scaled_quantity_display for range at 1x' do
  ingredient = Ingredient.new(name: 'Eggs', quantity_low: 2.0, quantity_high: 3.0)
  display = scaled_quantity_display(ingredient, 1.0)

  assert_equal "2\u20133", display
end

test 'scaled_quantity_display for range at 2x' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, quantity_high: 3.0, unit: 'cup')
  display = scaled_quantity_display(ingredient, 2.0)

  assert_equal "4\u20136 cups", display
end

test 'scaled_quantity_display for non-range at 2x' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
  display = scaled_quantity_display(ingredient, 2.0)

  assert_equal '4 cups', display
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: FAIL

- [ ] **Step 3: Update `ingredient_data_attrs`**

In `app/helpers/recipes_helper.rb`, replace `ingredient_data_attrs`:

```ruby
def ingredient_data_attrs(item, scale_factor: 1.0)
  attrs = {}
  return tag.attributes(attrs) unless item.quantity_low

  attrs[:'data-quantity-low'] = item.quantity_low.to_f * scale_factor
  attrs[:'data-quantity-high'] = item.quantity_high.to_f * scale_factor if item.quantity_high
  attrs[:'data-quantity-unit'] = item.quantity_unit if item.quantity_unit
  add_unit_plural_attr(attrs, item.quantity_unit)
  add_name_inflection_attrs(attrs, item) unless item.quantity_unit

  tag.attributes(attrs)
end
```

- [ ] **Step 4: Update `scaled_quantity_display`**

Replace `scaled_quantity_display`:

```ruby
def scaled_quantity_display(item, scale_factor)
  return item.quantity_display if !item.quantity_low || scale_factor == 1.0 # rubocop:disable Lint/FloatComparison

  display_value = (item.quantity_high || item.quantity_low).to_f * scale_factor
  unit_str = scaled_unit_display(item, display_value)

  if item.quantity_high
    low = FamilyRecipes::VulgarFractions.format(item.quantity_low.to_f * scale_factor, unit: item.quantity_unit)
    high = FamilyRecipes::VulgarFractions.format(item.quantity_high.to_f * scale_factor, unit: item.quantity_unit)
    ["#{low}\u2013#{high}", unit_str].compact.join(' ')
  else
    formatted = FamilyRecipes::VulgarFractions.format(item.quantity_low.to_f * scale_factor, unit: item.quantity_unit)
    [formatted, unit_str].compact.join(' ')
  end
end

def scaled_unit_display(item, display_value)
  return unless item.quantity_unit

  FamilyRecipes::Inflector.unit_display(item.quantity_unit, display_value)
end
```

Add `scaled_unit_display` to the `private` section.

- [ ] **Step 5: Run tests**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb
git commit -m "feat: update recipes_helper for range data attributes and display (#247)"
```

---

### Task 9: Update `recipe_state_controller.js` — client-side range scaling

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:164-183`

- [ ] **Step 1: Update `applyScale` ingredient section**

In `app/javascript/controllers/recipe_state_controller.js`, replace the `li[data-quantity-value]` block (lines 165-183) with:

```javascript
this.element
  .querySelectorAll('li[data-quantity-low]')
  .forEach(li => {
    const low = parseFloat(li.dataset.quantityLow)
    const high = li.dataset.quantityHigh ? parseFloat(li.dataset.quantityHigh) : null
    const unitSingular = li.dataset.quantityUnit || ''
    const unitPlural = li.dataset.quantityUnitPlural || unitSingular
    const scaledLow = low * factor
    const scaledHigh = high ? high * factor : null
    const displayValue = scaledHigh || scaledLow
    const unit = isVulgarSingular(displayValue) ? unitSingular : unitPlural

    const pretty = scaledHigh
      ? `${formatVulgar(scaledLow, unitSingular)}\u2013${formatVulgar(scaledHigh, unitSingular)}`
      : formatVulgar(scaledLow, unitSingular)

    const span = li.querySelector('.quantity')
    if (span) span.textContent = pretty + (unit ? ` ${unit}` : '')

    const nameEl = li.querySelector('.ingredient-name')
    if (nameEl && li.dataset.nameSingular) {
      nameEl.textContent = isVulgarSingular(displayValue)
        ? li.dataset.nameSingular
        : li.dataset.namePlural
    }
  })
```

- [ ] **Step 2: Rebuild JS**

Run: `npm run build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "feat: scale both range endpoints in recipe_state_controller (#247)"
```

---

### Task 10: Update controller test fixture and add seed range data

Fix the `data-quantity-value` assertion in the recipes controller test and add a range ingredient to a seed recipe.

**Files:**
- Modify: `test/controllers/recipes_controller_test.rb:88-92`
- Modify: `db/seeds/recipes/Baking/Pancakes.md`

- [ ] **Step 1: Fix controller test**

In `test/controllers/recipes_controller_test.rb`, update the assertion:

Change `assert_match(/data-quantity-value=/, response.body)` to `assert_match(/data-quantity-low=/, response.body)`

- [ ] **Step 2: Add range ingredient to seed recipe**

In `db/seeds/recipes/Baking/Pancakes.md`, change the `Eggs` line from:

```
- Eggs, 1
```

to:

```
- Eggs, 1-2
```

This gives us a range ingredient in seed data for development and testing.

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rake test`
Expected: All PASS

Run: `npm test`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add test/controllers/recipes_controller_test.rb db/seeds/recipes/Baking/Pancakes.md
git commit -m "fix: update test fixture for data-quantity-low, add range seed data (#247)"
```

---

## Chunk 5: Final Verification

### Task 11: Full regression check and lint

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rake`
Expected: 0 RuboCop offenses, all tests PASS

- [ ] **Step 2: Run JS tests**

Run: `npm test`
Expected: All PASS

- [ ] **Step 3: Update `html_safe_allowlist.yml` if line numbers shifted**

Check: `bundle exec rake lint:html_safe`
If failures, update the allowlist file with corrected line numbers.

- [ ] **Step 4: Smoke test with dev server (optional)**

Run: `bin/dev`
Navigate to a recipe page with scaled ingredients. Verify range display and scaling.

- [ ] **Step 5: Final commit referencing the issue**

```bash
git add -A
git commit -m "chore: final lint and allowlist updates for range-aware scaling

Resolves #247"
```

# Fraction Display Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix unit-aware fraction display so metric quantities stay decimal while everything else gets vulgar fractions, and accept vulgar fraction glyphs as parser input.

**Architecture:** Extend `VulgarFractions` (Ruby + JS) with a `unit:` parameter and `METRIC_UNITS` deny-list. Enhance `NumericParsing` and `FamilyRecipes::Ingredient.numeric_value` to handle Unicode vulgar glyphs as input. Update server-side rendering and client-side scaling to pass unit context through the formatting pipeline.

**Tech Stack:** Ruby (Minitest), JavaScript (Stimulus/importmap), ERB templates

**Design doc:** `docs/plans/2026-03-01-fraction-display-design.md`

---

### Task 0: Add vulgar glyph parsing to NumericParsing

**Files:**
- Modify: `lib/familyrecipes/numeric_parsing.rb:8-39`
- Test: `test/numeric_parsing_test.rb`

**Step 1: Write failing tests**

Add to `test/numeric_parsing_test.rb`:

```ruby
def test_vulgar_half
  assert_in_delta 0.5, FamilyRecipes::NumericParsing.parse_fraction('½'), 0.001
end

def test_vulgar_third
  assert_in_delta 0.333, FamilyRecipes::NumericParsing.parse_fraction('⅓'), 0.001
end

def test_vulgar_two_thirds
  assert_in_delta 0.667, FamilyRecipes::NumericParsing.parse_fraction('⅔'), 0.001
end

def test_vulgar_quarter
  assert_in_delta 0.25, FamilyRecipes::NumericParsing.parse_fraction('¼'), 0.001
end

def test_vulgar_three_quarters
  assert_in_delta 0.75, FamilyRecipes::NumericParsing.parse_fraction('¾'), 0.001
end

def test_vulgar_eighth
  assert_in_delta 0.125, FamilyRecipes::NumericParsing.parse_fraction('⅛'), 0.001
end

def test_mixed_vulgar
  assert_in_delta 2.5, FamilyRecipes::NumericParsing.parse_fraction('2½'), 0.001
end

def test_mixed_vulgar_with_space
  assert_in_delta 1.25, FamilyRecipes::NumericParsing.parse_fraction('1 ¼'), 0.001
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/numeric_parsing_test.rb`
Expected: 8 failures — `ArgumentError: invalid numeric string`

**Step 3: Implement vulgar glyph support**

In `lib/familyrecipes/numeric_parsing.rb`, add constant and preprocessing before the existing `Float()` call:

```ruby
VULGAR_GLYPHS = {
  '½' => 1 / 2r, '⅓' => 1 / 3r, '⅔' => 2 / 3r,
  '¼' => 1 / 4r, '¾' => 3 / 4r,
  '⅛' => 1 / 8r, '⅜' => 3 / 8r, '⅝' => 5 / 8r, '⅞' => 7 / 8r
}.freeze

VULGAR_PATTERN = /[#{VULGAR_GLYPHS.keys.join}]/
```

Add a new method:

```ruby
def parse_vulgar(str)
  return nil unless str.match?(VULGAR_PATTERN)

  glyph = str[VULGAR_PATTERN]
  prefix = str[0...str.index(glyph)].strip
  integer_part = prefix.empty? ? 0.0 : Float(prefix, exception: false)
  raise ArgumentError, "invalid numeric string: #{str.inspect}" unless integer_part

  integer_part + VULGAR_GLYPHS[glyph].to_f
end
```

Call `parse_vulgar` early in `parse_fraction`:

```ruby
def parse_fraction(str)
  return nil if str.nil?

  str = str.to_s.strip
  raise ArgumentError, "invalid numeric string: #{str.inspect}" if str.empty?

  vulgar_result = parse_vulgar(str)
  return vulgar_result if vulgar_result

  # ... existing fraction/float logic unchanged
end
```

Make `parse_vulgar` a `private_class_method`.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/numeric_parsing_test.rb`
Expected: All 18 tests pass (10 existing + 8 new)

**Step 5: Commit**

```bash
git add lib/familyrecipes/numeric_parsing.rb test/numeric_parsing_test.rb
git commit -m "feat: parse vulgar fraction glyphs in NumericParsing (#120)"
```

---

### Task 1: Add vulgar glyph support to FamilyRecipes::Ingredient.numeric_value

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb:11-27`
- Test: `test/ingredient_test.rb`

**Context:** `numeric_value` returns a **string** (e.g., `"0.5"`), not a float. Callers do `.to_f` on the result. Currently `"½"` falls through to `|| value_str`, returning `"½"`, and `"½".to_f` is `0.0` — broken.

**Step 1: Write failing tests**

Add to `test/ingredient_test.rb`:

```ruby
def test_quantity_value_vulgar_half
  ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '½ cup')

  assert_equal '0.5', ingredient.quantity_value
end

def test_quantity_value_vulgar_quarter
  ingredient = FamilyRecipes::Ingredient.new(name: 'Oil', quantity: '¼ cup')

  assert_equal '0.25', ingredient.quantity_value
end

def test_quantity_value_mixed_vulgar
  ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '2½ cups')

  assert_equal '2.5', ingredient.quantity_value
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: 3 failures — `"½" != "0.5"`, etc.

**Step 3: Implement vulgar glyph handling**

In `lib/familyrecipes/ingredient.rb`, update `numeric_value` to try `NumericParsing.parse_fraction` when the value contains a vulgar glyph:

```ruby
def self.numeric_value(raw)
  return nil if raw.nil? || raw.strip.empty?

  value_str = raw.strip
  value_str = value_str.split(/[-–]/).last.strip if value_str.match?(/[-–]/)

  return QUANTITY_FRACTIONS[value_str] if QUANTITY_FRACTIONS.key?(value_str)
  return NumericParsing.parse_fraction(value_str).to_s if value_str.match?(NumericParsing::VULGAR_PATTERN)

  value_str
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "feat: handle vulgar fraction glyphs in Ingredient.numeric_value (#120)"
```

---

### Task 2: Add unit-aware formatting to VulgarFractions (Ruby)

**Files:**
- Modify: `lib/familyrecipes/vulgar_fractions.rb:8-63`
- Test: `test/vulgar_fractions_test.rb`

**Step 1: Write failing tests**

Add to `test/vulgar_fractions_test.rb`:

```ruby
# --- unit-aware formatting ---

def test_metric_unit_keeps_decimal
  assert_equal '12.5', FamilyRecipes::VulgarFractions.format(12.5, unit: 'g')
end

def test_metric_kg_keeps_decimal
  assert_equal '0.5', FamilyRecipes::VulgarFractions.format(0.5, unit: 'kg')
end

def test_metric_ml_keeps_decimal
  assert_equal '2.5', FamilyRecipes::VulgarFractions.format(2.5, unit: 'ml')
end

def test_metric_l_keeps_decimal
  assert_equal '0.25', FamilyRecipes::VulgarFractions.format(0.25, unit: 'l')
end

def test_metric_integer_stays_integer
  assert_equal '12', FamilyRecipes::VulgarFractions.format(12.0, unit: 'g')
end

def test_us_customary_gets_vulgar
  assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5, unit: 'cup')
end

def test_unitless_gets_vulgar
  assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5, unit: nil)
end

def test_unknown_unit_gets_vulgar
  assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5, unit: 'cloves')
end

def test_backward_compatible_without_unit
  assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5)
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/vulgar_fractions_test.rb`
Expected: 4 failures (metric tests) — they get vulgar fractions instead of decimals. The 5 backward-compatible tests should pass.

**Step 3: Implement unit-aware formatting**

In `lib/familyrecipes/vulgar_fractions.rb`:

Add constant after `TOLERANCE`:

```ruby
METRIC_UNITS = %w[g kg ml l].to_set.freeze
```

Add predicate (as `module_function` like the others):

```ruby
def metric_unit?(unit)
  METRIC_UNITS.include?(unit&.downcase)
end
```

Update `format` signature and add early return:

```ruby
def format(value, unit: nil)
  return format_decimal(value) if metric_unit?(unit)
  return value.to_i.to_s if integer?(value)

  integer_part = value.to_i
  glyph = find_glyph(fractional_part(value))

  return format_with_glyph(integer_part, glyph) if glyph

  format_decimal(value)
end
```

Add `metric_unit?` to `private_class_method` list.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/vulgar_fractions_test.rb`
Expected: All 30 tests pass (21 existing + 9 new)

**Step 5: Update the existing caller that passes no unit**

In `app/helpers/recipes_helper.rb:98`, the `per_serving_label` method calls `VulgarFractions.format(ups)` without a unit — this is intentional since nutrition label fractions should always be vulgar. No change needed.

**Step 6: Commit**

```bash
git add lib/familyrecipes/vulgar_fractions.rb test/vulgar_fractions_test.rb
git commit -m "feat: unit-aware VulgarFractions.format with metric bypass (#120)"
```

---

### Task 3: Add unit-aware formatting to vulgar_fractions.js

**Files:**
- Modify: `app/javascript/utilities/vulgar_fractions.js:1-27`

**Step 1: Add METRIC_UNITS and update formatVulgar**

```javascript
const METRIC_UNITS = new Set(['g', 'kg', 'ml', 'l'])

export function formatVulgar(value, unit = null) {
  if (unit && METRIC_UNITS.has(unit.toLowerCase())) {
    if (Number.isInteger(value)) return String(value)
    const rounded = Math.round(value * 100) / 100
    return String(rounded)
  }
  if (Number.isInteger(value)) return String(value)
  // ... rest unchanged
}
```

**Step 2: Verify existing behavior preserved**

Run the full test suite to check nothing breaks: `rake test`

**Step 3: Commit**

```bash
git add app/javascript/utilities/vulgar_fractions.js
git commit -m "feat: unit-aware formatVulgar in JS with metric bypass (#120)"
```

---

### Task 4: Update server-side rendering for unit-aware display

**Files:**
- Modify: `app/helpers/recipes_helper.rb:56-77`
- Modify: `app/views/recipes/_step.html.erb:30-32`

**Step 1: Update `scaled_quantity_display`**

Replace the current `scaled_quantity_display` method (lines 71-77) with unit-aware formatting:

```ruby
def scaled_quantity_display(item, scale_factor)
  return format_quantity_display(item) unless scale_factor != 1.0 && item.quantity_value

  scaled = item.quantity_value.to_f * scale_factor
  formatted = FamilyRecipes::VulgarFractions.format(scaled, unit: item.quantity_unit)
  [formatted, item.unit].compact.join(' ')
end

def format_quantity_display(item)
  return unless item.quantity_value

  formatted = FamilyRecipes::VulgarFractions.format(item.quantity_value.to_f, unit: item.quantity_unit)
  [formatted, item.unit].compact.join(' ')
end
```

Remove the `Lint/FloatComparison` disable/enable comments — the `!=` check is fine for this use case (scale_factor is always a literal `1.0` from the view).

**Step 2: Run the full test suite**

Run: `rake test`
Expected: All tests pass. Check for any integration tests that assert raw decimal display for metric quantities — those should still show decimals.

**Step 3: Commit**

```bash
git add app/helpers/recipes_helper.rb
git commit -m "feat: unit-aware server-side quantity display (#120)"
```

---

### Task 5: Update client-side scaling to pass unit

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:171-192`

**Step 1: Pass unit to formatVulgar in ingredient scaling**

On line 182, change:

```javascript
const pretty = formatVulgar(scaled)
```

to:

```javascript
const pretty = formatVulgar(scaled, unitSingular)
```

`unitSingular` is already available from `li.dataset.quantityUnit || ''` on line 178. Empty string for unitless will be falsy enough — but actually `''` is falsy in JS so `formatVulgar` will treat it as `null` and use vulgar fractions. Perfect.

**Step 2: Verify yield line formatting**

The yield line block (lines 220-243) calls `formatVulgar(scaled)` on line 236. Yield lines (e.g., "Makes 12 cookies") should always use vulgar fractions — they're never metric. No change needed here.

**Step 3: Run the full test suite and manually verify**

Run: `rake test`
Start the dev server: `bin/dev`
Open Pizza Dough recipe, click Scale, enter `1` — verify `12.5 g` stays as `12.5 g` (not `12½ g`).
Scale by `2` — verify `25 g` (not `25`... wait, 25 is integer so both paths give `25`). Test with a recipe that has fractional US customary quantities to verify vulgar fractions still work.

**Step 4: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "feat: pass unit to formatVulgar in client-side scaling (#120)"
```

---

### Task 6: Add pint, quart, gallon to Inflector

**Files:**
- Modify: `lib/familyrecipes/inflector.rb:33-42`
- Test: `test/inflector_test.rb` (if exists, otherwise `test/models/ingredient_test.rb` for unit normalization)

**Step 1: Add abbreviations**

In `lib/familyrecipes/inflector.rb`, add to the ABBREVIATIONS hash:

```ruby
'pt' => 'pt', 'pint' => 'pt', 'pints' => 'pt',
'qt' => 'qt', 'quart' => 'qt', 'quarts' => 'qt',
'gal' => 'gal', 'gallon' => 'gal', 'gallons' => 'gal',
```

**Step 2: Add plurals to KNOWN_PLURALS**

```ruby
'pint' => 'pints', 'quart' => 'quarts', 'gallon' => 'gallons',
```

**Step 3: Run the test suite**

Run: `rake test`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add lib/familyrecipes/inflector.rb
git commit -m "feat: add pint, quart, gallon to Inflector (#120)"
```

---

### Task 7: Run full lint and test suite, verify end-to-end

**Files:** None (verification only)

**Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. Fix any issues introduced.

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass.

**Step 3: Check html_safe allowlist**

Run: `rake lint:html_safe`
Expected: No new violations. The changes don't add any `.html_safe` calls.

**Step 4: Manual smoke test**

Start `bin/dev` and verify:
1. Pizza Dough: `12.5 g` stays decimal on initial render and after scale-by-1
2. A recipe with `½ cup` shows vulgar fraction on initial render
3. Scaling a US customary recipe by 2 shows correct vulgar fractions
4. Scaling a metric recipe keeps decimals throughout

**Step 5: Final commit if any fixes needed**

```bash
git commit -m "fix: address lint/test issues from fraction display (#120)"
```

# Unknown Quantities Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make the recipe page resilient to non-numeric quantities like "a few leaves" — display them verbatim, skip them in math, and fix the BigDecimal serialization crash.

**Architecture:** Four small changes: guard `split_quantity` and `numeric_value` against non-numeric input, update view helpers to fall back to `quantity_display`, and coerce BigDecimal scalars in `Result#as_json`. All downstream consumers already handle nil quantities correctly.

**Tech Stack:** Ruby, Rails helpers, Minitest

---

### Task 0: Fix BigDecimal serialization in Result#as_json

The crash. `total_weight_grams` (BigDecimal) serializes as a string in JSON,
then `per_serving_weight` calls `&.positive?` on the string → NoMethodError.

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:61-67`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Write failing test**

Add to `NutritionCalculatorTest` (at the end, before the final `end`):

```ruby
def test_as_json_coerces_numeric_scalars_to_float
  result = NutritionCalculator::Result.new(
    totals: { calories: BigDecimal('100') },
    serving_count: BigDecimal('4'),
    per_serving: { calories: BigDecimal('25') },
    per_unit: nil,
    makes_quantity: BigDecimal('8'),
    makes_unit_singular: 'taco',
    makes_unit_plural: 'tacos',
    units_per_serving: BigDecimal('2'),
    total_weight_grams: BigDecimal('592.5'),
    missing_ingredients: [],
    partial_ingredients: [],
    skipped_ingredients: []
  )

  json = result.as_json

  assert_instance_of Float, json['total_weight_grams']
  assert_instance_of Float, json['serving_count']
  assert_instance_of Float, json['makes_quantity']
  assert_instance_of Float, json['units_per_serving']
  assert_in_delta 592.5, json['total_weight_grams']
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n test_as_json_coerces_numeric_scalars_to_float`
Expected: FAIL — `json['total_weight_grams']` is a String, not Float.

**Step 3: Fix as_json**

In `lib/familyrecipes/nutrition_calculator.rb`, replace the `as_json` method
(lines 61-67):

```ruby
def as_json(_options = nil)
  to_h.transform_keys(&:to_s).tap do |h|
    %w[totals per_serving per_unit].each do |key|
      h[key] = h[key]&.transform_keys(&:to_s)&.transform_values(&:to_f)
    end
    %w[total_weight_grams serving_count makes_quantity units_per_serving].each do |key|
      h[key] = h[key]&.to_f
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n test_as_json_coerces_numeric_scalars_to_float`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "fix: coerce BigDecimal scalars to float in Result#as_json"
```

---

### Task 1: Guard split_quantity against non-numeric first tokens

`split_quantity("a few leaves")` currently returns `["a", "few leaves"]`.
It should return `["a few leaves", nil]` because `"a"` isn't numeric.

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb:27-37`
- Test: `test/ingredient_test.rb`
- Test: `test/services/markdown_importer_test.rb:270-278`

**Step 1: Write failing tests**

Add to `IngredientTest` (before the final `end`):

```ruby
def test_split_quantity_non_numeric_keeps_whole_string
  assert_equal ['a few leaves', nil], FamilyRecipes::Ingredient.split_quantity('a few leaves')
end

def test_split_quantity_freeform_single_word
  assert_equal ['some', nil], FamilyRecipes::Ingredient.split_quantity('some')
end

def test_split_quantity_freeform_handful
  assert_equal ['a handful', nil], FamilyRecipes::Ingredient.split_quantity('a handful')
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n /split_quantity/`
Expected: FAIL — returns `["a", "few leaves"]` instead of `["a few leaves", nil]`.

**Step 3: Add numeric-looking guard to split_quantity**

In `lib/familyrecipes/ingredient.rb`, replace `split_quantity` (lines 27-37):

```ruby
def self.split_quantity(raw)
  return [nil, nil] if raw.nil? || raw.strip.empty?

  parts = raw.strip.split(' ', 3)
  return [raw.strip, nil] unless numeric_token?(parts[0])

  if parts.size >= 2 && fraction_token?(parts[1])
    ["#{parts[0]} #{parts[1]}", parts[2]]
  else
    value, unit = raw.strip.split(' ', 2)
    [value, unit]
  end
end
```

Add new private class method (after `fraction_token?`):

```ruby
def self.numeric_token?(token)
  token.match?(/\A\d/) || token.match?(NumericParsing::VULGAR_PATTERN)
end
private_class_method :numeric_token?
```

**Step 4: Run all ingredient and split_quantity tests**

Run: `ruby -Itest test/ingredient_test.rb && ruby -Itest test/services/markdown_importer_test.rb -n /quantity_splitting/`
Expected: PASS — existing tests still pass, new tests pass.

**Step 5: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "fix: split_quantity preserves freeform text when first token is non-numeric"
```

---

### Task 2: Make numeric_value return nil for non-numeric strings

`numeric_value("a few leaves")` currently returns `"a few leaves"` (the raw
string). It should return `nil` so downstream code treats it as unquantified.

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb:12-23`
- Test: `test/ingredient_test.rb`

**Step 1: Write failing tests**

Add to `IngredientTest`:

```ruby
def test_quantity_value_nil_for_freeform_text
  ingredient = FamilyRecipes::Ingredient.new(name: 'Basil', quantity: 'a few leaves')

  assert_nil ingredient.quantity_value
end

def test_quantity_value_nil_for_single_word_freeform
  ingredient = FamilyRecipes::Ingredient.new(name: 'Parsley', quantity: 'some')

  assert_nil ingredient.quantity_value
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n /freeform/`
Expected: FAIL — returns `"a few leaves"` instead of nil.

**Step 3: Add Float guard to numeric_value**

In `lib/familyrecipes/ingredient.rb`, replace `numeric_value` (lines 12-23):

```ruby
def self.numeric_value(raw)
  return nil if raw.nil? || raw.strip.empty?

  value_str = raw.strip
  value_str = value_str.split(/[-–]/).last.strip if value_str.match?(/[-–]/)

  if value_str.match?(%r{/}o) || value_str.match?(NumericParsing::VULGAR_PATTERN)
    return NumericParsing.parse_fraction(value_str).to_s
  end

  return nil unless Float(value_str, exception: false)

  value_str
end
```

**Step 4: Run all ingredient tests**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: PASS — all existing numeric tests still pass, freeform tests pass.

**Step 5: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "fix: numeric_value returns nil for non-numeric quantity strings"
```

---

### Task 3: Update view helpers to display freeform quantities verbatim

When `quantity_value` is nil but `quantity_display` has text (freeform), render
it verbatim — no scaling, no vulgar fraction formatting.

**Files:**
- Modify: `app/helpers/recipes_helper.rb:128-141`
- Test: `test/helpers/recipes_helper_test.rb`

**Step 1: Write failing tests**

Add to `RecipesHelperTest`:

```ruby
test 'format_quantity_display shows freeform quantity verbatim' do
  item = Ingredient.new(name: 'Basil', quantity: 'a few', unit: 'leaves', position: 0)

  result = send(:format_quantity_display, item)

  assert_equal 'a few leaves', result
end

test 'scaled_quantity_display does not scale freeform quantity' do
  item = Ingredient.new(name: 'Basil', quantity: 'a few', unit: 'leaves', position: 0)

  result = send(:scaled_quantity_display, item, 2.0)

  assert_equal 'a few leaves', result
end
```

Note: After Task 1's split_quantity fix, "a few leaves" will store as
`quantity: "a few leaves"`, `unit: nil`. But existing DB rows may still have
the old split. These tests use the old split to cover both cases — the helper
should handle either.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb -n /freeform/`
Expected: FAIL — currently returns "0 leaves" (via `"a few".to_f` → 0.0).

**Step 3: Update helper methods**

In `app/helpers/recipes_helper.rb`, replace `scaled_quantity_display`
(lines 128-134):

```ruby
def scaled_quantity_display(item, scale_factor)
  return item.quantity_display if !item.quantity_value || scale_factor == 1.0 # rubocop:disable Lint/FloatComparison

  scaled = item.quantity_value.to_f * scale_factor
  formatted = FamilyRecipes::VulgarFractions.format(scaled, unit: item.quantity_unit)
  [formatted, item.unit].compact.join(' ')
end
```

Replace `format_quantity_display` (lines 136-141):

```ruby
def format_quantity_display(item)
  item.quantity_display
end
```

**Step 4: Run all helper tests**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb
git commit -m "fix: display freeform quantities verbatim, skip scaling"
```

---

### Task 4: Integration test — full render of recipe with freeform quantity

Verify the recipe page renders without error when an ingredient has a
freeform quantity.

**Files:**
- Test: `test/controllers/recipes_controller_test.rb`

**Step 1: Write integration test**

Add to the recipes controller test:

```ruby
test 'show renders recipe with freeform quantity ingredient' do
  recipe = create_recipe("# Salad\n\n## Toss\n\n- Basil, a few leaves\n- Lettuce, 1 head\n\nToss.")

  get recipe_path(recipe.slug)

  assert_response :success
  assert_select 'b.ingredient-name', text: 'Basil'
  assert_select 'li', text: /a few leaves/
end
```

Check how `create_recipe` works in the test file — it may be a local helper
or use `MarkdownImporter`. If it doesn't exist, use the same recipe creation
pattern as other tests in that file.

**Step 2: Run test**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n /freeform_quantity/`
Expected: PASS (if all prior tasks are done).

**Step 3: Run full test suite**

Run: `rake test`
Expected: All green.

**Step 4: Commit**

```bash
git add test/controllers/recipes_controller_test.rb
git commit -m "test: integration test for freeform quantity rendering"
```

---

### Task 5: Re-seed and verify the live page

Re-import the Simple Tomato Sauce recipe so the DB has correct data, then
verify the page loads.

**Step 1: Re-seed the database**

Run: `rails db:seed`

This re-imports all seed recipes through `MarkdownImporter`, which now uses
the fixed `split_quantity`. Basil will store as `quantity: "a few leaves"`,
`unit: nil`.

**Step 2: Verify the page loads**

Run: `curl -s http://rika:3030/recipes/simple-tomato-sauce | grep -o 'a few leaves'`
Expected: `a few leaves`

**Step 3: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

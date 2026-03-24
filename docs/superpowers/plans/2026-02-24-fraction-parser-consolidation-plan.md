# Fraction Parser Consolidation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate three inconsistent fraction parsers into a single `FamilyRecipes::NumericParsing.parse_fraction` method that raises `ArgumentError` for bad input. Closes #89.

**Architecture:** New `FamilyRecipes::NumericParsing` module in `lib/familyrecipes/`. Three call sites delegate to it. TDD — tests first, implementation second, caller rewiring last.

**Tech Stack:** Ruby, Minitest

---

### Task 1: Create NumericParsing with tests (TDD)

**Files:**
- Create: `test/numeric_parsing_test.rb`
- Create: `lib/familyrecipes/numeric_parsing.rb`
- Modify: `lib/familyrecipes.rb:69` (add require)

**Step 1: Write the failing tests**

Create `test/numeric_parsing_test.rb`:

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class NumericParsingTest < Minitest::Test
  def test_integer
    assert_in_delta 3.0, FamilyRecipes::NumericParsing.parse_fraction('3')
  end

  def test_decimal
    assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1.5')
  end

  def test_fraction
    assert_in_delta 0.5, FamilyRecipes::NumericParsing.parse_fraction('1/2'), 0.001
  end

  def test_fraction_with_decimal_numerator
    assert_in_delta 0.75, FamilyRecipes::NumericParsing.parse_fraction('1.5/2'), 0.001
  end

  def test_zero
    assert_in_delta 0.0, FamilyRecipes::NumericParsing.parse_fraction('0')
  end

  def test_nil_returns_nil
    assert_nil FamilyRecipes::NumericParsing.parse_fraction(nil)
  end

  def test_strips_whitespace
    assert_in_delta 3.0, FamilyRecipes::NumericParsing.parse_fraction('  3  ')
  end

  def test_division_by_zero_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('1/0') }
  end

  def test_garbage_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('abc') }
  end

  def test_empty_string_raises
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('') }
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/numeric_parsing_test.rb`
Expected: errors about undefined `NumericParsing`

**Step 3: Write the module**

Create `lib/familyrecipes/numeric_parsing.rb`:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  module NumericParsing
    module_function

    def parse_fraction(str)
      return nil if str.nil?

      str = str.to_s.strip
      raise ArgumentError, "invalid numeric string: #{str.inspect}" if str.empty?

      if str.include?('/')
        parse_fraction_parts(str)
      else
        result = Float(str, exception: false)
        raise ArgumentError, "invalid numeric string: #{str.inspect}" unless result

        result
      end
    end

    def parse_fraction_parts(str)
      num_str, den_str = str.split('/', 2)
      num = Float(num_str, exception: false)
      den = Float(den_str, exception: false)

      raise ArgumentError, "invalid numeric string: #{str.inspect}" unless num && den
      raise ArgumentError, "division by zero: #{str.inspect}" if den.zero?

      num / den
    end

    private_class_method :parse_fraction_parts
  end
end
```

**Step 4: Register the require**

In `lib/familyrecipes.rb`, add the require **before** the existing `require_relative 'familyrecipes/quantity'` line (line 69):

```ruby
require_relative 'familyrecipes/numeric_parsing'
require_relative 'familyrecipes/quantity'
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/numeric_parsing_test.rb`
Expected: all 10 pass

**Step 6: Commit**

```bash
git add lib/familyrecipes/numeric_parsing.rb lib/familyrecipes.rb test/numeric_parsing_test.rb
git commit -m "feat: add FamilyRecipes::NumericParsing with robust fraction parsing (#89)"
```

---

### Task 2: Rewire IngredientParser.parse_multiplier

**Files:**
- Modify: `lib/familyrecipes/ingredient_parser.rb:60-66`

**Step 1: Run existing cross-reference tests (baseline)**

Run: `ruby -Itest test/cross_reference_test.rb`
Expected: all pass

**Step 2: Replace parse_multiplier body**

In `lib/familyrecipes/ingredient_parser.rb`, replace lines 60-66:

```ruby
  # Before:
  def self.parse_multiplier(str)
    return 1.0 if str.nil?
    return str.to_f unless str.include?('/')

    num, den = str.split('/')
    num.to_f / den.to_i
  end

  # After:
  def self.parse_multiplier(str)
    FamilyRecipes::NumericParsing.parse_fraction(str) || 1.0
  end
```

**Step 3: Run cross-reference and ingredient parser tests**

Run: `ruby -Itest test/cross_reference_test.rb test/ingredient_parser_test.rb`
Expected: all pass (regex-constrained input means no behavior change for valid data)

**Step 4: Commit**

```bash
git add lib/familyrecipes/ingredient_parser.rb
git commit -m "refactor: IngredientParser delegates to NumericParsing (#89)"
```

---

### Task 3: Rewire ScalableNumberPreprocessor.parse_numeral

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb:70-75`

**Step 1: Run existing preprocessor tests (baseline)**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: all pass

**Step 2: Replace parse_numeral body**

In `lib/familyrecipes/scalable_number_preprocessor.rb`, replace lines 70-75:

```ruby
  # Before:
  def parse_numeral(str)
    return str.to_f unless str.include?('/')

    numerator, denominator = str.split('/')
    numerator.to_f / denominator.to_i
  end

  # After:
  def parse_numeral(str)
    FamilyRecipes::NumericParsing.parse_fraction(str)
  end
```

**Step 3: Run preprocessor tests**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: all pass

**Step 4: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb
git commit -m "refactor: ScalableNumberPreprocessor delegates to NumericParsing (#89)"
```

---

### Task 4: Delete NutritionEntryHelpers.parse_fraction, update caller and tests

**Files:**
- Modify: `lib/familyrecipes/nutrition_entry_helpers.rb:9-19` (delete method)
- Modify: `lib/familyrecipes/nutrition_entry_helpers.rb:43` (update caller in `parse_serving_size`)
- Modify: `test/nutrition_entry_helpers_test.rb:80-102` (update tests)

**Step 1: Run existing tests (baseline)**

Run: `ruby -Itest test/nutrition_entry_helpers_test.rb`
Expected: all pass

**Step 2: Delete parse_fraction and update parse_serving_size**

In `lib/familyrecipes/nutrition_entry_helpers.rb`:

1. Delete `self.parse_fraction` (lines 9-19).

2. Replace the `parse_fraction` call in `parse_serving_size` (line 43) with a call to `NumericParsing.parse_fraction` wrapped in a rescue:

```ruby
      # Before (line 43):
      amount = parse_fraction(match[1])
      return result unless amount&.positive?

      # After:
      amount = FamilyRecipes::NumericParsing.parse_fraction(match[1])
      return result unless amount&.positive?
    rescue ArgumentError
      return result
```

The `rescue ArgumentError` handles messy user-pasted serving size strings gracefully — returning the partial result (grams only) instead of crashing.

**Step 3: Update tests**

In `test/nutrition_entry_helpers_test.rb`, the `parse_fraction` tests (lines 80-102) now test `NumericParsing` directly. Replace the block:

```ruby
  # --- parse_fraction (now delegates to NumericParsing) ---

  def test_parse_fraction_simple_integer
    assert_in_delta(3.0, FamilyRecipes::NumericParsing.parse_fraction('3'))
  end

  def test_parse_fraction_decimal
    assert_in_delta(1.5, FamilyRecipes::NumericParsing.parse_fraction('1.5'))
  end

  def test_parse_fraction_fraction
    assert_in_delta 0.5, FamilyRecipes::NumericParsing.parse_fraction('1/2'), 0.001
  end

  def test_parse_fraction_zero
    assert_in_delta(0.0, FamilyRecipes::NumericParsing.parse_fraction('0'))
  end

  def test_parse_fraction_division_by_zero
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('/0') }
  end

  def test_parse_fraction_garbage
    assert_raises(ArgumentError) { FamilyRecipes::NumericParsing.parse_fraction('abc') }
  end
```

**Step 4: Run tests**

Run: `ruby -Itest test/nutrition_entry_helpers_test.rb`
Expected: all pass

**Step 5: Commit**

```bash
git add lib/familyrecipes/nutrition_entry_helpers.rb test/nutrition_entry_helpers_test.rb
git commit -m "refactor: delete NutritionEntryHelpers.parse_fraction, delegate to NumericParsing (#89)"
```

---

### Task 5: Full test suite and final commit

**Step 1: Run full test suite**

Run: `rake test`
Expected: all tests pass

**Step 2: Run lint**

Run: `rake lint`
Expected: no offenses

**Step 3: Final commit closing the issue**

If any lint fixes were needed, commit them:

```bash
git commit -am "fix: lint cleanup for fraction parser consolidation

Closes #89"
```

If no fixes needed, amend the previous commit message to include `Closes #89`:
No extra commit needed — the issue is already tagged in the earlier commits.

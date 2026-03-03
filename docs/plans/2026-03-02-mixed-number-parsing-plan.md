# Mixed Number Parsing (Issue #139) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Support ASCII mixed numbers (`1 1/2 cups`) in ingredient quantities, numeric parsing, and scalable instruction numbers.

**Architecture:** Fix bottom-up — `NumericParsing` (foundation), then `Ingredient#parsed_quantity` (consumer), then `ScalableNumberPreprocessor` (instruction markers). Each layer gets TDD tests before implementation.

**Tech Stack:** Ruby, Minitest

---

### Task 1: Add mixed ASCII fraction support to NumericParsing

**Files:**
- Modify: `lib/familyrecipes/numeric_parsing.rb:8-71`
- Test: `test/numeric_parsing_test.rb`

**Step 1: Write failing tests**

Add to `test/numeric_parsing_test.rb`:

```ruby
def test_mixed_ascii_fraction
  assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1 1/2'), 0.001
end

def test_mixed_ascii_fraction_three_quarters
  assert_in_delta 2.75, FamilyRecipes::NumericParsing.parse_fraction('2 3/4'), 0.001
end

def test_mixed_ascii_fraction_with_extra_spaces
  assert_in_delta 1.5, FamilyRecipes::NumericParsing.parse_fraction('1  1/2'), 0.001
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/numeric_parsing_test.rb -n /mixed_ascii/`
Expected: 3 failures (ArgumentError raised for "1 1/2")

**Step 3: Implement mixed ASCII pattern**

In `lib/familyrecipes/numeric_parsing.rb`, add `MIXED_ASCII_PATTERN` constant after `MIXED_VULGAR_PATTERN` (line 16):

```ruby
MIXED_ASCII_PATTERN = %r{\A(\d+)\s+(\d+/\d+)\z}
```

Modify `parse_ascii_fraction` (line 29) to check for mixed numbers before falling through to `parse_fraction_parts`:

```ruby
def parse_ascii_fraction(str)
  mixed = str.match(MIXED_ASCII_PATTERN)
  return mixed[1].to_f + parse_fraction_parts(mixed[2]) if mixed

  return parse_fraction_parts(str) if str.include?('/')

  result = Float(str, exception: false)
  raise ArgumentError, "invalid numeric string: #{str.inspect}" unless result

  result
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/numeric_parsing_test.rb`
Expected: All pass (existing + 3 new)

**Step 5: Commit**

```bash
git add lib/familyrecipes/numeric_parsing.rb test/numeric_parsing_test.rb
git commit -m "fix: support mixed ASCII fractions in NumericParsing (closes #139)"
```

---

### Task 2: Fix Ingredient#parsed_quantity for mixed numbers

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb:48-56`
- Test: `test/ingredient_test.rb`

**Depends on:** Task 1 (NumericParsing must handle `"1 1/2"`)

**Step 1: Write failing tests**

Add to `test/ingredient_test.rb`:

```ruby
def test_quantity_value_mixed_ascii
  ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

  assert_equal '1.5', ingredient.quantity_value
end

def test_quantity_unit_mixed_ascii
  ingredient = FamilyRecipes::Ingredient.new(name: 'Flour', quantity: '1 1/2 cups')

  assert_equal 'cup', ingredient.quantity_unit
end

def test_quantity_value_mixed_ascii_three_quarters
  ingredient = FamilyRecipes::Ingredient.new(name: 'Butter', quantity: '2 3/4 tbsp')

  assert_equal '2.75', ingredient.quantity_value
end

def test_quantity_value_mixed_ascii_no_unit
  ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

  assert_equal '1.5', ingredient.quantity_value
end

def test_quantity_unit_mixed_ascii_no_unit
  ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: '1 1/2')

  assert_nil ingredient.quantity_unit
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n /mixed_ascii/`
Expected: Failures — `quantity_value` returns `"1"` instead of `"1.5"`, `quantity_unit` returns nonsense

**Step 3: Implement mixed number detection in parsed_quantity**

Replace `parsed_quantity` and add `fraction_token?` in `lib/familyrecipes/ingredient.rb` (lines 54-56):

```ruby
def parsed_quantity
  @parsed_quantity ||= begin
    parts = @quantity.strip.split(' ', 3)
    if parts.size >= 2 && fraction_token?(parts[1])
      ["#{parts[0]} #{parts[1]}", parts[2]]
    else
      @quantity.strip.split(' ', 2)
    end
  end
end

def fraction_token?(token)
  token.match?(%r{\A\d+/\d+\z}) || token.match?(NumericParsing::VULGAR_PATTERN)
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: All pass (existing + 5 new)

**Step 5: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "fix: handle mixed numbers in Ingredient#parsed_quantity"
```

---

### Task 3: Support mixed numbers in ScalableNumberPreprocessor

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb:18-32`
- Test: `test/scalable_number_preprocessor_test.rb`

**Depends on:** Task 1 (parse_numeral delegates to NumericParsing.parse_fraction)

**Step 1: Write failing tests**

Add to `test/scalable_number_preprocessor_test.rb`:

```ruby
def test_mixed_number_with_asterisk
  result = ScalableNumberPreprocessor.process_instructions('Add 1 1/2* cups.')

  assert_includes result, 'data-base-value="1.5"'
  assert_includes result, 'data-original-text="1 1/2"'
  refute_includes result, '1 1/2*'
end

def test_yield_line_mixed_number
  result = ScalableNumberPreprocessor.process_yield_line('Makes 1 1/2 dozen.')

  assert_includes result, 'data-base-value="1.5"'
  assert_includes result, 'data-original-text="1 1/2"'
end

def test_yield_with_unit_mixed_number
  result = ScalableNumberPreprocessor.process_yield_with_unit('1 1/2 dozen', 'dozen', 'dozen')

  assert_includes result, 'data-base-value="1.5"'
  assert_includes result, 'data-unit-singular="dozen"'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb -n /mixed/`
Expected: Failures — patterns don't match mixed numbers

**Step 3: Extend regex patterns**

In `lib/familyrecipes/scalable_number_preprocessor.rb`, update `INSTRUCTION_PATTERN` (line 18) to add mixed number alternative **before** the simple numeral alternative:

```ruby
INSTRUCTION_PATTERN = %r{
  (?:
    (#{WORD_PATTERN})\*                                       # word number with asterisk
  |
    (\d+\s+\d+/\d+|\d+(?:\.\d+)?(?:/\d+(?:\.\d+)?)?)\*      # numeral with asterisk
  )
}ix
```

Update `YIELD_NUMBER_PATTERN` (line 26) similarly:

```ruby
YIELD_NUMBER_PATTERN = %r{
  (?:
    \b(#{WORD_PATTERN})\b                                     # word number
  |
    \b(\d+\s+\d+/\d+|\d+(?:\.\d+)?(?:/\d+(?:\.\d+)?)?)\b    # numeral
  )
}ix
```

The key change in both: `\d+\s+\d+/\d+` is added as the **first** alternative in the numeral group so the regex engine tries mixed numbers before falling through to simple numerals.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: All pass (existing + 3 new)

**Step 5: Run full test suite and lint**

Run: `bundle exec rubocop && rake test`
Expected: 0 offenses, all tests pass

**Step 6: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb test/scalable_number_preprocessor_test.rb
git commit -m "fix: support mixed numbers in ScalableNumberPreprocessor"
```

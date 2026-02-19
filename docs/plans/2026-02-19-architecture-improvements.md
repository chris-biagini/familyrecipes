# Architecture Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce primitive obsession with value objects, enforce immutability on frozen data structures, and decompose SiteGenerator's validation into a dedicated class.

**Architecture:** Three orthogonal changes: (1) `Quantity` value object replaces `[value, unit]` tuples across 6+ files, (2) `LineToken` and `NutritionCalculator::Result` convert from mutable `Struct` to immutable `Data.define`, (3) validation methods extract from SiteGenerator into `BuildValidator`.

**Tech Stack:** Ruby 3.2+ `Data.define`, Minitest, RuboCop

---

### Task 1: Create Quantity Value Object

**Files:**
- Create: `lib/familyrecipes/quantity.rb`
- Create: `test/quantity_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

**Step 1: Write the test file**

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class QuantityTest < Minitest::Test
  def test_creates_with_value_and_unit
    q = Quantity[10, 'g']

    assert_equal 10, q.value
    assert_equal 'g', q.unit
  end

  def test_creates_with_nil_unit
    q = Quantity[3, nil]

    assert_equal 3, q.value
    assert_nil q.unit
  end

  def test_equality
    assert_equal Quantity[10, 'g'], Quantity[10, 'g']
    refute_equal Quantity[10, 'g'], Quantity[10, 'oz']
    refute_equal Quantity[10, 'g'], Quantity[5, 'g']
  end

  def test_frozen
    q = Quantity[10, 'g']

    assert_predicate q, :frozen?
  end

  def test_deconstruct_for_pattern_matching
    q = Quantity[10, 'g']

    case q
    in [value, unit]
      assert_equal 10, value
      assert_equal 'g', unit
    end
  end

  def test_deconstruct_keys
    q = Quantity[10, 'g']

    case q
    in { value: v, unit: u }
      assert_equal 10, v
      assert_equal 'g', u
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Itest test/quantity_test.rb`
Expected: NameError — `uninitialized constant QuantityTest::Quantity`

**Step 3: Write the implementation**

```ruby
# frozen_string_literal: true

# Quantity value object
#
# Immutable representation of an ingredient quantity (value + unit).
# Replaces bare [value, unit] tuples throughout the codebase.

Quantity = Data.define(:value, :unit)
```

Add to `lib/familyrecipes.rb` — insert `require_relative 'familyrecipes/quantity'` as the FIRST require (before all other classes, since they depend on it), right after the `end` of the `FamilyRecipes` module definition at line 166, before the existing requires at line 170:

```ruby
require_relative 'familyrecipes/quantity'
require_relative 'familyrecipes/scalable_number_preprocessor'
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Itest test/quantity_test.rb`
Expected: 6 tests, 0 failures

**Step 5: Run full suite to confirm no regressions**

Run: `rake`
Expected: All pass, no lint errors

**Step 6: Commit**

```
git add lib/familyrecipes/quantity.rb test/quantity_test.rb lib/familyrecipes.rb
git commit -m "Add Quantity value object (Data.define)"
```

---

### Task 2: Update IngredientAggregator to Produce Quantity

**Files:**
- Modify: `lib/familyrecipes/ingredient_aggregator.rb`
- Modify: `test/ingredient_aggregator_test.rb`

**Step 1: Update tests to expect Quantity objects**

In `ingredient_aggregator_test.rb`, change assertions from array indexing to Quantity attribute access:

`test_sums_same_unit` (line 14-15):
```ruby
# Before:
assert_in_delta(200.0, result[0][0])
assert_equal 'g', result[0][1]

# After:
assert_in_delta 200.0, result[0].value
assert_equal 'g', result[0].unit
```

`test_keeps_different_units_separate` (line 26):
```ruby
# Before:
units = result.map { |a| a[1] }.sort

# After:
units = result.map(&:unit).sort
```

`test_mixed_quantified_and_unquantified` (line 38-40):
```ruby
# Before:
numeric = result.find { |a| a.is_a?(Array) }
assert_equal [50.0, 'g'], numeric

# After:
numeric = result.find { |a| a.is_a?(Quantity) }
assert_equal Quantity[50.0, 'g'], numeric
```

`test_unitless_numeric_sums` (line 61-62):
```ruby
# Before:
assert_in_delta(3.0, result[0][0])
assert_nil result[0][1]

# After:
assert_in_delta 3.0, result[0].value
assert_nil result[0].unit
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec ruby -Itest test/ingredient_aggregator_test.rb`
Expected: Failures — results are still arrays, not Quantity objects

**Step 3: Update implementation**

In `ingredient_aggregator.rb`, change line 25:
```ruby
# Before:
amounts = sums.map { |unit, value| [value, unit] }

# After:
amounts = sums.map { |unit, value| Quantity[value, unit] }
```

**Step 4: Run test to verify it passes**

Run: `bundle exec ruby -Itest test/ingredient_aggregator_test.rb`
Expected: 5 tests, 0 failures

**Step 5: DO NOT run full suite yet** — downstream tests (recipe_test, cross_reference_test, nutrition_calculator_test) will now fail because they still expect arrays. That's expected. Commit this checkpoint.

**Step 6: Commit**

```
git add lib/familyrecipes/ingredient_aggregator.rb test/ingredient_aggregator_test.rb
git commit -m "Update IngredientAggregator to produce Quantity objects"
```

---

### Task 3: Update CrossReference + Recipe to Work with Quantity

**Files:**
- Modify: `lib/familyrecipes/cross_reference.rb`
- Modify: `lib/familyrecipes/recipe.rb`
- Modify: `test/cross_reference_test.rb`
- Modify: `test/recipe_test.rb`

**Step 1: Update CrossReference implementation**

In `cross_reference.rb`, change `expanded_ingredients` (lines 26-31):
```ruby
# Before:
scaled = amounts.map do |amount|
  next nil if amount.nil?

  value, unit = amount
  [value * @multiplier, unit]
end

# After:
scaled = amounts.map do |amount|
  next nil if amount.nil?

  Quantity[amount.value * @multiplier, amount.unit]
end
```

**Step 2: Update Recipe#merge_amounts**

In `recipe.rb`, change `merge_amounts` (lines 92-102):
```ruby
# Before:
def merge_amounts(existing, new_amounts)
  all = existing + new_amounts
  has_nil = all.include?(nil)
  sums = all.compact.each_with_object(Hash.new(0.0)) do |(value, unit), h|
    h[unit] += value
  end

  result = sums.map { |unit, value| [value, unit] }
  result << nil if has_nil
  result
end

# After:
def merge_amounts(existing, new_amounts)
  all = existing + new_amounts
  has_nil = all.include?(nil)
  sums = all.compact.each_with_object(Hash.new(0.0)) do |quantity, h|
    h[quantity.unit] += quantity.value
  end

  result = sums.map { |unit, value| Quantity[value, unit] }
  result << nil if has_nil
  result
end
```

**Step 3: Update cross_reference_test.rb**

`test_cross_reference_expanded_ingredients` (lines 111, 116):
```ruby
# Before:
assert_in_delta(1000.0, flour[1].find { |a| a&.first }&.first)
...
assert_in_delta(650.0, water[1].find { |a| a&.first }&.first)

# After:
assert_in_delta 1000.0, flour[1].find { |a| a.is_a?(Quantity) }.value
...
assert_in_delta 650.0, water[1].find { |a| a.is_a?(Quantity) }.value
```

**Step 4: Update recipe_test.rb**

`test_ingredients_with_quantities_sums_same_unit_across_steps` (lines 35-36):
```ruby
# Before:
assert_in_delta(200.0, amounts[0][0])
assert_equal 'g', amounts[0][1]

# After:
assert_in_delta 200.0, amounts[0].value
assert_equal 'g', amounts[0].unit
```

`test_ingredients_with_quantities_mixed_quantified_and_unquantified` (lines 63-65):
```ruby
# Before:
numeric = amounts.find { |a| a.is_a?(Array) }
assert_equal [50.0, 'g'], numeric

# After:
numeric = amounts.find { |a| a.is_a?(Quantity) }
assert_equal Quantity[50.0, 'g'], numeric
```

`test_ingredients_with_quantities_different_units_kept_separate` (line 94):
```ruby
# Before:
units = amounts.map { |a| a[1] }.sort

# After:
units = amounts.map(&:unit).sort
```

`test_ingredients_with_quantities_unitless_numeric` (lines 159-160):
```ruby
# Before:
assert_in_delta(3.0, amounts[0][0])
assert_nil amounts[0][1]

# After:
assert_in_delta 3.0, amounts[0].value
assert_nil amounts[0].unit
```

`test_recipe_all_ingredients_with_quantities_scales_sub_recipe` (line 165):
```ruby
# Before:
assert_in_delta(1000.0, flour[1].find { |a| a&.first }&.first)

# After:
assert_in_delta 1000.0, flour[1].find { |a| a.is_a?(Quantity) }.value
```

**Step 5: Run tests**

Run: `bundle exec ruby -Itest test/cross_reference_test.rb test/recipe_test.rb`
Expected: All pass

**Step 6: Commit**

```
git add lib/familyrecipes/cross_reference.rb lib/familyrecipes/recipe.rb test/cross_reference_test.rb test/recipe_test.rb
git commit -m "Update CrossReference and Recipe to use Quantity objects"
```

---

### Task 4: Update NutritionCalculator + SiteGenerator to Consume Quantity

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb`
- Modify: `lib/familyrecipes/site_generator.rb`
- Modify: `test/nutrition_calculator_test.rb` (if needed)

**Step 1: Update NutritionCalculator#calculate**

In `nutrition_calculator.rb`, change lines 67-71:
```ruby
# Before:
amounts.each do |amount|
  next if amount.nil?

  value, unit = amount
  next if value.nil?

  grams = to_grams(value, unit, entry)

# After:
amounts.each do |amount|
  next if amount.nil?
  next if amount.value.nil?

  grams = to_grams(amount.value, amount.unit, entry)
```

**Step 2: Update NutritionCalculator#resolvable?**

In `nutrition_calculator.rb`, change `resolvable?` — the signature takes `value, unit` directly, not a Quantity. The callers already destructure. Check who calls it.

Check `site_generator.rb` line 260: `@nutrition_calculator.resolvable?(value, unit, entry)` — this is called with destructured values from the tuple. Update to:

In `site_generator.rb`, change `validate_nutrition` lines 256-260:
```ruby
# Before:
non_nil_amounts.each do |value, unit|
  next if value.nil?

  next if @nutrition_calculator.resolvable?(value, unit, entry)

# After:
non_nil_amounts.each do |quantity|
  next if quantity.value.nil?

  next if @nutrition_calculator.resolvable?(quantity.value, quantity.unit, entry)
```

And line 263 in the same method:
```ruby
# Before:
info[:units] << (unit || '(bare count)')

# After:
info[:units] << (quantity.unit || '(bare count)')
```

**Step 3: Run tests**

Run: `rake test`
Expected: All 239 tests pass

**Step 4: Run lint**

Run: `rake lint`
Expected: No offenses

**Step 5: Commit**

```
git add lib/familyrecipes/nutrition_calculator.rb lib/familyrecipes/site_generator.rb
git commit -m "Update NutritionCalculator and SiteGenerator to consume Quantity"
```

---

### Task 5: Convert LineToken from Struct to Data.define

**Files:**
- Modify: `lib/familyrecipes/line_classifier.rb:10`
- Modify: `test/line_classifier_test.rb` (minimal — Data.define uses keyword-only construction, but LineToken is already constructed with `keyword_init: true`)

**Step 1: Update LineToken definition**

In `line_classifier.rb`, change line 10:
```ruby
# Before:
LineToken = Struct.new(:type, :content, :line_number, keyword_init: true)

# After:
LineToken = Data.define(:type, :content, :line_number)
```

**Step 2: Run tests**

Run: `bundle exec ruby -Itest test/line_classifier_test.rb`
Expected: All 11 tests pass (Data.define supports `keyword_init` by default and attribute readers work the same)

**Step 3: Run full suite**

Run: `rake`
Expected: All pass, no lint errors

**Step 4: Commit**

```
git add lib/familyrecipes/line_classifier.rb
git commit -m "Convert LineToken from Struct to Data.define for immutability"
```

---

### Task 6: Convert NutritionCalculator::Result from Struct to Data.define

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:22-30`

**Step 1: Update Result definition**

In `nutrition_calculator.rb`, change lines 22-30:
```ruby
# Before:
Result = Struct.new(
  :totals, :serving_count, :per_serving,
  :missing_ingredients, :partial_ingredients,
  keyword_init: true
) do
  def complete?
    missing_ingredients.empty? && partial_ingredients.empty?
  end
end

# After:
Result = Data.define(
  :totals, :serving_count, :per_serving,
  :missing_ingredients, :partial_ingredients
) do
  def complete?
    missing_ingredients.empty? && partial_ingredients.empty?
  end
end
```

**Step 2: Run tests**

Run: `bundle exec ruby -Itest test/nutrition_calculator_test.rb`
Expected: All 34 tests pass

**Step 3: Run full suite**

Run: `rake`
Expected: All pass, no lint errors

**Step 4: Commit**

```
git add lib/familyrecipes/nutrition_calculator.rb
git commit -m "Convert NutritionCalculator::Result from Struct to Data.define"
```

---

### Task 7: Extract BuildValidator from SiteGenerator

This is the largest task. We're moving 4 methods (~120 lines) from SiteGenerator into a new class.

**Files:**
- Create: `lib/familyrecipes/build_validator.rb`
- Create: `test/build_validator_test.rb`
- Modify: `lib/familyrecipes/site_generator.rb`
- Modify: `lib/familyrecipes.rb` (add require)
- Modify: `test/cross_reference_test.rb` (validation tests reference SiteGenerator — move to build_validator_test.rb)

**Step 1: Write the BuildValidator test file**

Move the 3 validation tests from `test/cross_reference_test.rb` (lines 181-231) into a new file, updating them to use `BuildValidator` directly:

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class BuildValidatorTest < Minitest::Test
  def test_detects_unresolved_cross_reference
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead.", id: 'pizza-dough')
    pizza = make_recipe("# Test Pizza\n\n## Dough (make dough)\n\n- @[Nonexistent Recipe]\n\nStretch.", id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Unresolved cross-reference/, error.message)
    assert_match(/Nonexistent Recipe/, error.message)
  end

  def test_detects_circular_reference
    a = make_recipe("# Recipe A\n\n## Step (do it)\n\n- @[Recipe B]\n\nDo.", id: 'recipe-a')
    b = make_recipe("# Recipe B\n\n## Step (do it)\n\n- @[Recipe A]\n\nDo.", id: 'recipe-b')
    validator = build_validator(recipes: [a, b])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(/Circular cross-reference/, error.message)
  end

  def test_detects_title_filename_mismatch
    recipe = make_recipe("# Actual Title\n\n## Step (do it)\n\n- Flour, 500 g\n\nMix.", id: 'wrong-slug')
    validator = build_validator(recipes: [recipe])

    error = assert_raises(StandardError) { validator.validate_cross_references }

    assert_match(%r{Title/filename mismatch}, error.message)
  end

  def test_valid_cross_references_pass
    dough = make_recipe("# Pizza Dough\n\n## Mix (make dough)\n\n- Flour, 500 g\n\nKnead.", id: 'pizza-dough')
    pizza = make_recipe("# Test Pizza\n\n## Dough (make dough)\n\n- @[Pizza Dough]\n\nStretch.", id: 'test-pizza')
    validator = build_validator(recipes: [dough, pizza])

    # Should not raise
    validator.validate_cross_references
  end

  private

  def make_recipe(markdown, id: 'test-recipe')
    Recipe.new(markdown_source: markdown, id: id, category: 'Test')
  end

  def build_validator(recipes: [], quick_bites: [])
    recipe_map = recipes.to_h { |r| [r.id, r] }
    FamilyRecipes::BuildValidator.new(
      recipes: recipes,
      quick_bites: quick_bites,
      recipe_map: recipe_map,
      alias_map: {},
      known_ingredients: Set.new,
      omit_set: Set.new,
      nutrition_calculator: nil
    )
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec ruby -Itest test/build_validator_test.rb`
Expected: NameError — `uninitialized constant FamilyRecipes::BuildValidator`

**Step 3: Create BuildValidator class**

Create `lib/familyrecipes/build_validator.rb`. Copy the 4 methods (`validate_cross_references`, `detect_cycles`, `validate_ingredients`, `validate_nutrition`) from `site_generator.rb`, adapting them to use instance variables from the constructor instead of SiteGenerator's ivars:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  class BuildValidator
    def initialize(recipes:, quick_bites:, recipe_map:, alias_map:,
                   known_ingredients:, omit_set:, nutrition_calculator:)
      @recipes = recipes
      @quick_bites = quick_bites
      @recipe_map = recipe_map
      @alias_map = alias_map
      @known_ingredients = known_ingredients
      @omit_set = omit_set
      @nutrition_calculator = nutrition_calculator
    end

    def validate_cross_references
      print 'Validating cross-references...'

      @recipes.each do |recipe|
        title_slug = FamilyRecipes.slugify(recipe.title)
        if title_slug != recipe.id
          raise StandardError,
                "Title/filename mismatch: \"#{recipe.title}\" (slug: #{title_slug}) vs filename slug: #{recipe.id}"
        end

        recipe.cross_references.each do |xref|
          next if @recipe_map.key?(xref.target_slug)

          raise StandardError,
                "Unresolved cross-reference in \"#{recipe.title}\": " \
                "@[#{xref.target_title}] (slug: #{xref.target_slug})"
        end

        detect_cycles(recipe, [])
      end

      print "done!\n"
    end

    def validate_ingredients
      print 'Validating ingredients...'

      ingredients_to_recipes = Hash.new { |h, k| h[k] = [] }
      @recipes.each do |recipe|
        recipe.all_ingredients.each do |ingredient|
          ingredients_to_recipes[ingredient.name] << recipe.title
        end
      end
      @quick_bites.each do |quick_bite|
        quick_bite.ingredients.each do |ingredient_name|
          ingredients_to_recipes[ingredient_name] << quick_bite.title
        end
      end

      unknown_ingredients = ingredients_to_recipes.keys.reject do |name|
        @known_ingredients.include?(name.downcase)
      end.to_set
      if unknown_ingredients.any?
        puts "\n"
        puts 'WARNING: The following ingredients are not in grocery-info.yaml:'
        unknown_ingredients.sort.each do |ing|
          recipes = ingredients_to_recipes[ing].uniq.sort
          puts "  - #{ing} (in: #{recipes.join(', ')})"
        end
        puts 'Add them to grocery-info.yaml or add as aliases to existing items.'
        puts ''
      else
        print "done! (All ingredients validated.)\n"
      end
    end

    def validate_nutrition
      return unless @nutrition_calculator

      print 'Validating nutrition data...'

      ingredients_to_recipes = @recipes.each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, index|
        recipe.all_ingredient_names(@alias_map).each do |name|
          index[name] << recipe.title unless @omit_set.include?(name.downcase)
        end
      end

      missing = ingredients_to_recipes.keys.reject { |name| @nutrition_calculator.nutrition_data.key?(name) }

      unresolvable = Hash.new { |h, k| h[k] = { units: Set.new, recipes: [] } }
      unquantified = Hash.new { |h, k| h[k] = [] }
      @recipes.each do |recipe|
        recipe.all_ingredients_with_quantities(@alias_map, @recipe_map).each do |name, amounts|
          next if @omit_set.include?(name.downcase)

          entry = @nutrition_calculator.nutrition_data[name]
          next unless entry

          non_nil_amounts = amounts.compact
          unquantified[name] |= [recipe.title] if non_nil_amounts.empty?

          non_nil_amounts.each do |quantity|
            next if quantity.value.nil?

            next if @nutrition_calculator.resolvable?(quantity.value, quantity.unit, entry)

            info = unresolvable[name]
            info[:units] << (quantity.unit || '(bare count)')
            info[:recipes] |= [recipe.title]
          end
        end
      end

      has_warnings = missing.any? || unresolvable.any? || unquantified.any?

      if missing.any?
        puts "\n"
        puts 'WARNING: Missing nutrition data:'
        missing.sort.each do |name|
          recipes = ingredients_to_recipes[name].uniq.sort
          puts "  - #{name} (in: #{recipes.join(', ')})"
        end
      end

      if unresolvable.any?
        puts "\n" unless missing.any?
        puts 'WARNING: Missing unit conversions:'
        unresolvable.sort_by { |name, _| name }.each do |name, info|
          recipes = info[:recipes].sort
          units = info[:units].to_a.sort.join(', ')
          puts "  - #{name}: '#{units}' (in: #{recipes.join(', ')})"
        end
      end

      if unquantified.any?
        puts "\n" unless missing.any? || unresolvable.any?
        puts 'NOTE: Unquantified ingredients (not counted in nutrition):'
        unquantified.sort_by { |name, _| name }.each do |name, recipes|
          puts "  - #{name} (in: #{recipes.sort.join(', ')})"
        end
      end

      if has_warnings
        puts ''
        puts 'Use bin/nutrition-entry to add data, or edit resources/nutrition-data.yaml directly.'
        puts ''
      else
        print "done! (All ingredients have nutrition data.)\n"
      end
    end

    private

    def detect_cycles(recipe, visited)
      if visited.include?(recipe.id)
        cycle = visited[visited.index(recipe.id)..] + [recipe.id]
        raise StandardError, "Circular cross-reference detected: #{cycle.join(' -> ')}"
      end

      recipe.cross_references.each do |xref|
        target = @recipe_map[xref.target_slug]
        next unless target

        detect_cycles(target, visited + [recipe.id])
      end
    end
  end
end
```

Add to `lib/familyrecipes.rb` — insert `require_relative 'familyrecipes/build_validator'` before the `site_generator` require.

**Step 4: Run BuildValidator tests**

Run: `bundle exec ruby -Itest test/build_validator_test.rb`
Expected: 4 tests, 0 failures

**Step 5: Update SiteGenerator to delegate**

In `site_generator.rb`:

1. Remove the `validate_cross_references`, `detect_cycles`, `validate_ingredients`, and `validate_nutrition` methods entirely.

2. Add a private method:
```ruby
def build_validator
  @build_validator ||= BuildValidator.new(
    recipes: @recipes,
    quick_bites: @quick_bites,
    recipe_map: @recipe_map,
    alias_map: @alias_map,
    known_ingredients: @known_ingredients,
    omit_set: @omit_set,
    nutrition_calculator: @nutrition_calculator
  )
end
```

3. Update the `generate` method to delegate:
```ruby
def generate
  load_grocery_info
  load_nutrition_data
  parse_recipes
  parse_quick_bites
  build_recipe_map
  build_validator.validate_cross_references
  generate_recipe_pages
  copy_resources
  generate_homepage
  generate_index
  build_validator.validate_ingredients
  build_validator.validate_nutrition
  generate_groceries_page
end
```

**Step 6: Remove old validation tests from cross_reference_test.rb**

Delete the 3 tests at lines 181-231 in `test/cross_reference_test.rb`:
- `test_site_generator_detects_unresolved_cross_reference`
- `test_site_generator_detects_circular_reference`
- `test_site_generator_detects_title_filename_mismatch`

These are now covered by `build_validator_test.rb`.

**Step 7: Run full suite**

Run: `rake`
Expected: All tests pass, no lint errors. Verify the RuboCop `# rubocop:disable Metrics` comment is no longer needed (it was on the `validate_nutrition` method which is now in BuildValidator with its own class metrics).

**Step 8: Commit**

```
git add lib/familyrecipes/build_validator.rb test/build_validator_test.rb lib/familyrecipes.rb lib/familyrecipes/site_generator.rb test/cross_reference_test.rb
git commit -m "Extract BuildValidator from SiteGenerator"
```

---

### Task 8: Final Verification + Cleanup

**Step 1: Run full build**

Run: `bin/generate`
Expected: Clean build with all recipes, no errors

**Step 2: Run full test + lint suite**

Run: `rake`
Expected: All tests pass, no RuboCop offenses

**Step 3: Verify SiteGenerator size reduction**

Check that SiteGenerator is now ~220 lines (down from 340). Check that the `# rubocop:disable Metrics` comment is gone. Verify RuboCop ClassLength limit (275) is comfortably met.

**Step 4: Review for any remaining [value, unit] patterns**

Search the codebase for any remaining bare array quantity patterns that should be Quantity objects. Grep for patterns like `[value, unit]` or `amount[0]`, `amount[1]`.

Run: Search for `\[0\]` and `\[1\]` in test files and source files that deal with quantities.

**Step 5: Commit any cleanup**

```
git add -A
git commit -m "Final cleanup: architecture improvements complete"
```

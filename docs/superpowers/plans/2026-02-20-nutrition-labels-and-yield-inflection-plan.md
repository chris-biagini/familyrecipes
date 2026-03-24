# Nutrition Labels and Yield Inflection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show contextual nutrition column headers ("Per Cookie", "Per Serving (6 cookies)") using Makes/Serves front matter, and inflect the yield line unit noun when scaling ("Makes: 1 pancake" vs "Makes: 12 pancakes").

**Architecture:** Add a `VulgarFractions` helper module (Ruby) and equivalent JS lookup for formatting fractional quantities as Unicode glyphs. Expand `NutritionCalculator::Result` to expose per-unit values and unit metadata. Update the recipe template to render dynamic column headers. Update `ScalableNumberPreprocessor` to emit a `.yield` wrapper span with singular/plural data attributes. Update `recipe-state-manager.js` to inflect nouns during scaling.

**Tech Stack:** Ruby (Minitest), ERB templates, vanilla JS. No new dependencies.

---

### Task 1: VulgarFractions Ruby Module

**Files:**
- Create: `lib/familyrecipes/vulgar_fractions.rb`
- Create: `test/vulgar_fractions_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

This module converts a numeric value to a display string using Unicode vulgar fraction glyphs where possible, and classifies whether a displayed value should take a singular noun.

**Step 1: Write the tests**

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class VulgarFractionsTest < Minitest::Test
  # --- format ---

  def test_integer_formats_as_integer
    assert_equal '6', FamilyRecipes::VulgarFractions.format(6.0)
  end

  def test_one_formats_as_integer
    assert_equal '1', FamilyRecipes::VulgarFractions.format(1.0)
  end

  def test_zero_formats_as_integer
    assert_equal '0', FamilyRecipes::VulgarFractions.format(0.0)
  end

  def test_half_formats_as_vulgar
    assert_equal "\u00BD", FamilyRecipes::VulgarFractions.format(0.5)
  end

  def test_third_formats_as_vulgar
    assert_equal "\u2153", FamilyRecipes::VulgarFractions.format(1.0 / 3)
  end

  def test_two_thirds_formats_as_vulgar
    assert_equal "\u2154", FamilyRecipes::VulgarFractions.format(2.0 / 3)
  end

  def test_quarter_formats_as_vulgar
    assert_equal "\u00BC", FamilyRecipes::VulgarFractions.format(0.25)
  end

  def test_three_quarters_formats_as_vulgar
    assert_equal "\u00BE", FamilyRecipes::VulgarFractions.format(0.75)
  end

  def test_eighth_formats_as_vulgar
    assert_equal "\u215B", FamilyRecipes::VulgarFractions.format(0.125)
  end

  def test_three_eighths_formats_as_vulgar
    assert_equal "\u215C", FamilyRecipes::VulgarFractions.format(0.375)
  end

  def test_five_eighths_formats_as_vulgar
    assert_equal "\u215D", FamilyRecipes::VulgarFractions.format(0.625)
  end

  def test_seven_eighths_formats_as_vulgar
    assert_equal "\u215E", FamilyRecipes::VulgarFractions.format(0.875)
  end

  def test_mixed_number_with_half
    assert_equal "1\u00BD", FamilyRecipes::VulgarFractions.format(1.5)
  end

  def test_mixed_number_with_third
    assert_equal "1\u2153", FamilyRecipes::VulgarFractions.format(4.0 / 3)
  end

  def test_mixed_number_with_quarter
    assert_equal "2\u00BC", FamilyRecipes::VulgarFractions.format(2.25)
  end

  def test_non_matching_decimal_formats_as_decimal
    assert_equal '0.4', FamilyRecipes::VulgarFractions.format(0.4)
  end

  def test_non_matching_mixed_formats_as_decimal
    assert_equal '1.4', FamilyRecipes::VulgarFractions.format(1.4)
  end

  def test_large_integer
    assert_equal '24', FamilyRecipes::VulgarFractions.format(24.0)
  end

  # --- singular_noun? ---

  def test_singular_for_exactly_one
    assert FamilyRecipes::VulgarFractions.singular_noun?(1.0)
  end

  def test_singular_for_pure_vulgar_fraction
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.5)
  end

  def test_singular_for_quarter
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.25)
  end

  def test_singular_for_third
    assert FamilyRecipes::VulgarFractions.singular_noun?(1.0 / 3)
  end

  def test_singular_for_eighth
    assert FamilyRecipes::VulgarFractions.singular_noun?(0.125)
  end

  def test_plural_for_mixed_number
    refute FamilyRecipes::VulgarFractions.singular_noun?(1.5)
  end

  def test_plural_for_integer_greater_than_one
    refute FamilyRecipes::VulgarFractions.singular_noun?(6.0)
  end

  def test_plural_for_zero
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.0)
  end

  def test_plural_for_non_matching_decimal
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.4)
  end

  def test_plural_for_non_matching_decimal_less_than_one
    refute FamilyRecipes::VulgarFractions.singular_noun?(0.7)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/vulgar_fractions_test.rb`
Expected: Errors — `VulgarFractions` not defined.

**Step 3: Write the implementation**

```ruby
# frozen_string_literal: true

module FamilyRecipes
  module VulgarFractions
    # Fractional value => Unicode glyph, with tolerance for float imprecision
    GLYPHS = {
      1 / 2r  => "\u00BD",  # ½
      1 / 3r  => "\u2153",  # ⅓
      2 / 3r  => "\u2154",  # ⅔
      1 / 4r  => "\u00BC",  # ¼
      3 / 4r  => "\u00BE",  # ¾
      1 / 8r  => "\u215B",  # ⅛
      3 / 8r  => "\u215C",  # ⅜
      5 / 8r  => "\u215D",  # ⅝
      7 / 8r  => "\u215E"   # ⅞
    }.freeze

    TOLERANCE = 0.001

    module_function

    def format(value)
      return value.to_i.to_s if value == value.to_i && fractional_part(value).abs < TOLERANCE

      integer_part = value.to_i
      frac = fractional_part(value)

      glyph = find_glyph(frac)

      if glyph
        integer_part.zero? ? glyph : "#{integer_part}#{glyph}"
      else
        # Round to avoid floating point noise, strip trailing zeros
        rounded = (value * 100).round / 100.0
        format_decimal(rounded)
      end
    end

    def singular_noun?(value)
      return true if (value - 1.0).abs < TOLERANCE

      value < 1.0 && value > 0 && !find_glyph(value).nil?
    end

    def find_glyph(fractional_value)
      GLYPHS.each do |rational, glyph|
        return glyph if (fractional_value - rational.to_f).abs < TOLERANCE
      end
      nil
    end

    def format_decimal(value)
      str = value.to_s
      str.sub(/\.?0+\z/, '')
    end

    def fractional_part(value)
      value - value.to_i
    end
  end
end
```

**Step 4: Add require to `lib/familyrecipes.rb`**

Look for the existing requires and add `require_relative 'familyrecipes/vulgar_fractions'` in alphabetical order among the other module requires.

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/vulgar_fractions_test.rb`
Expected: All pass.

**Step 6: Run full test suite**

Run: `rake test`
Expected: All pass, no regressions.

**Step 7: Commit**

```bash
git add lib/familyrecipes/vulgar_fractions.rb test/vulgar_fractions_test.rb lib/familyrecipes.rb
git commit -m "feat: add VulgarFractions module for Unicode fraction formatting"
```

---

### Task 2: Expand NutritionCalculator::Result with Per-Unit Data

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:22-29` (Result struct), `:82-91` (calculate method), `:152-158` (parse_serving_count)
- Modify: `test/nutrition_calculator_test.rb`

The Result struct needs new fields for per-unit nutrition values and unit metadata so the template can render contextual columns.

**Step 1: Write the tests**

Add these tests to `test/nutrition_calculator_test.rb`:

```ruby
  # --- Per-unit nutrition ---

  def test_per_unit_with_makes
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 24 cookies

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 24, result.makes_quantity
    assert_equal 'cookie', result.makes_unit_singular
    assert_equal 'cookies', result.makes_unit_plural
    assert_in_delta 1820.0 / 24, result.per_unit[:calories], 1
  end

  def test_per_unit_nil_without_makes
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Serves: 4

      ## Mix (combine)

      - Flour (all-purpose), 400 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_nil result.per_unit
    assert_nil result.makes_quantity
  end

  def test_units_per_serving_with_both
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 24 cookies
      Serves: 4

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_in_delta 6.0, result.units_per_serving, 0.01
  end

  def test_units_per_serving_nil_without_both
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 12 bagels

      ## Mix (combine)

      - Flour (all-purpose), 480 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_nil result.units_per_serving
  end

  def test_per_unit_with_irregular_plural
    recipe = make_recipe(<<~MD)
      # Test

      Category: Test
      Makes: 2 loaves

      ## Mix (combine)

      - Flour (all-purpose), 500 g

      Mix.
    MD

    result = @calculator.calculate(recipe, @alias_map, @recipe_map)

    assert_equal 'loaf', result.makes_unit_singular
    assert_equal 'loaves', result.makes_unit_plural
  end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: Errors — Result doesn't have `per_unit`, `makes_quantity`, etc.

**Step 3: Implement the changes**

In `lib/familyrecipes/nutrition_calculator.rb`:

1. Expand the `Result` struct (line 22):

```ruby
    Result = Data.define(
      :totals, :serving_count, :per_serving, :per_unit,
      :makes_quantity, :makes_unit_singular, :makes_unit_plural,
      :units_per_serving,
      :missing_ingredients, :partial_ingredients
    ) do
      def complete?
        missing_ingredients.empty? && partial_ingredients.empty?
      end
    end
```

2. Update the `calculate` method (around line 82-91) to compute per-unit values and extract unit metadata:

```ruby
      serving_count = parse_serving_count(recipe)
      per_serving = (NUTRIENTS.to_h { |n| [n, totals[n] / serving_count] } if serving_count)

      makes_qty = recipe.makes_quantity&.to_i
      unit_noun = recipe.makes_unit_noun
      per_unit = (NUTRIENTS.to_h { |n| [n, totals[n] / makes_qty] } if makes_qty&.positive?)

      unit_singular = Inflector.singular(unit_noun) if unit_noun
      unit_plural = Inflector.plural(unit_singular) if unit_singular

      units_per_serving = (makes_qty.to_f / serving_count if makes_qty && serving_count)

      Result.new(
        totals: totals,
        serving_count: serving_count,
        per_serving: per_serving,
        per_unit: per_unit,
        makes_quantity: makes_qty,
        makes_unit_singular: unit_singular,
        makes_unit_plural: unit_plural,
        units_per_serving: units_per_serving,
        missing_ingredients: missing,
        partial_ingredients: partial
      )
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: All pass.

**Step 5: Run full test suite**

Run: `rake test`
Expected: All pass.

**Step 6: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "feat: expose per-unit nutrition and unit metadata on Result"
```

---

### Task 3: Update Nutrition Table Template

**Files:**
- Modify: `templates/web/recipe-template.html.erb:69-111`

The template needs dynamic column logic based on the nutrition result's new fields.

**Step 1: Understand the column logic**

The column rules (from the design doc):
- **Makes qty = 1**: relabel rightmost column as "Per [Unit]" (singular). If Serves exists, add "Per Serving (fraction unit)" as the first data column.
- **Makes qty > 1**: show "Per [Unit]" (singular) column. If Serves exists, show "Per Serving (N units)" column. Always show "Total" last.
- **No Makes, just Serves**: "Per Serving" + "Total".
- **Neither**: "Total" only.

**Step 2: Replace the nutrition table section**

Replace lines 69-111 of `templates/web/recipe-template.html.erb` with:

```erb
      <%- if nutrition && nutrition.totals.values.any? { |v| v > 0 } -%>
      <aside class="nutrition-facts">
        <h2>Nutrition Facts</h2>
        <%- # Column logic
            has_per_unit = nutrition.per_unit && nutrition.makes_quantity && nutrition.makes_quantity > 0
            unit_qty_is_one = has_per_unit && nutrition.makes_quantity == 1
            has_per_serving = nutrition.per_serving && nutrition.serving_count

            # Build column list: [label, values_hash]
            columns = []

            if has_per_unit && !unit_qty_is_one
              # Per Serving column (if serves exists)
              if has_per_serving
                ups = nutrition.units_per_serving
                formatted_ups = VulgarFractions.format(ups)
                singular = VulgarFractions.singular_noun?(ups)
                ups_unit = singular ? nutrition.makes_unit_singular : nutrition.makes_unit_plural
                columns << ["Per Serving (#{formatted_ups} #{ups_unit})", nutrition.per_serving]
              end
              # Per Unit column
              columns << ["Per #{nutrition.makes_unit_singular.capitalize}", nutrition.per_unit]
              # Total column
              columns << ['Total', nutrition.totals]
            elsif unit_qty_is_one
              # Per Serving column (if serves exists)
              if has_per_serving
                ups = nutrition.units_per_serving
                formatted_ups = VulgarFractions.format(ups)
                singular = VulgarFractions.singular_noun?(ups)
                ups_unit = singular ? nutrition.makes_unit_singular : nutrition.makes_unit_plural
                columns << ["Per Serving (#{formatted_ups} #{ups_unit})", nutrition.per_serving]
              end
              # Relabel Total as Per Unit
              columns << ["Per #{nutrition.makes_unit_singular.capitalize}", nutrition.totals]
            elsif has_per_serving
              # Serves only, no Makes
              columns << ['Per Serving', nutrition.per_serving]
              columns << ['Total', nutrition.totals]
            else
              # Neither
              columns << ['Total', nutrition.totals]
            end
        -%>
        <table>
          <thead>
            <tr>
              <th></th>
              <%- columns.each do |label, _| -%>
              <th><%= label %></th>
              <%- end -%>
            </tr>
          </thead>
          <tbody>
            <%- [
              ['Calories', :calories, '', 0],
              ['Total Fat', :fat, 'g', 0],
              ['Sat. Fat', :saturated_fat, 'g', 1],
              ['Trans Fat', :trans_fat, 'g', 1],
              ['Cholesterol', :cholesterol, 'mg', 0],
              ['Sodium', :sodium, 'mg', 0],
              ['Total Carbs', :carbs, 'g', 0],
              ['Fiber', :fiber, 'g', 1],
              ['Total Sugars', :total_sugars, 'g', 1],
              ['Added Sugars', :added_sugars, 'g', 2],
              ['Protein', :protein, 'g', 0],
            ].each do |label, key, unit, indent| -%>
            <tr<%= %( class="indent-#{indent}") if indent > 0 %>>
              <td><%= label %></td>
              <%- columns.each_with_index do |(_, values), col_idx| -%>
              <%- is_total = (col_idx == columns.size - 1 && columns.last[0] == 'Total') -%>
              <td<%= %( data-nutrient="#{key}" data-base-value="#{values[key].round(1)}") if is_total %>><%= values[key].round %><%= unit %></td>
              <%- end -%>
            </tr>
            <%- end -%>
          </tbody>
        </table>
        <%- unless nutrition.complete? -%>
        <p class="nutrition-note">*Approximate. Data unavailable for: <%= (nutrition.missing_ingredients + nutrition.partial_ingredients).uniq.join(', ') %>.</p>
        <%- end -%>
      </aside>
      <%- end -%>
```

**Important note about `data-nutrient` and `data-base-value`:** These attributes are used by the JS scaler to update the Total column when scaling. They should only appear on the Total column cells. The `is_total` check ensures this — it's `true` only for the last column when that column is labeled "Total". When makes_quantity is 1, the rightmost column is "Per [Unit]" (which numerically equals Total) but should NOT scale, since the per-unit values are fixed reference points.

**Step 3: Run full test suite and build**

Run: `rake test && bin/generate`
Expected: All tests pass. Build succeeds. Visually verify a recipe page to see the new column headers.

**Step 4: Commit**

```bash
git add templates/web/recipe-template.html.erb
git commit -m "feat: contextual nutrition column headers using Makes/Serves"
```

---

### Task 4: Yield Line Wrapper Markup

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb` (add `process_yield_with_unit`)
- Modify: `test/scalable_number_preprocessor_test.rb`
- Modify: `templates/web/recipe-template.html.erb:20-24`

Wrap the Makes yield line in a `.yield` span with singular/plural data attributes.

**Step 1: Write the tests**

Add these tests to `test/scalable_number_preprocessor_test.rb`:

```ruby
  # --- process_yield_with_unit tests ---

  def test_yield_with_unit_wraps_number_and_noun
    result = ScalableNumberPreprocessor.process_yield_with_unit('12 pancakes', 'pancake', 'pancakes')

    assert_includes result, 'class="yield"'
    assert_includes result, 'data-base-value="12.0"'
    assert_includes result, 'data-unit-singular="pancake"'
    assert_includes result, 'data-unit-plural="pancakes"'
    assert_includes result, '<span class="scalable"'
    assert_includes result, '>12</span> pancakes'
  end

  def test_yield_with_unit_handles_word_numbers
    result = ScalableNumberPreprocessor.process_yield_with_unit('two loaves', 'loaf', 'loaves')

    assert_includes result, 'data-base-value="2"'
    assert_includes result, 'data-unit-singular="loaf"'
    assert_includes result, 'data-unit-plural="loaves"'
    assert_includes result, '>two</span> loaves'
  end

  def test_yield_with_unit_handles_single_item
    result = ScalableNumberPreprocessor.process_yield_with_unit('1 loaf', 'loaf', 'loaves')

    assert_includes result, 'data-base-value="1.0"'
    assert_includes result, '>1</span> loaf'
  end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: Errors — `process_yield_with_unit` not defined.

**Step 3: Implement `process_yield_with_unit`**

Add to `lib/familyrecipes/scalable_number_preprocessor.rb` after `process_yield_line`:

```ruby
  def process_yield_with_unit(text, unit_singular, unit_plural)
    text.sub(YIELD_NUMBER_PATTERN) do
      value = ::Regexp.last_match(1) ? WORD_VALUES[::Regexp.last_match(1).downcase] : parse_numeral(::Regexp.last_match(2))
      original_text = ::Regexp.last_match(1) || ::Regexp.last_match(2)
      inner_span = build_span(value, original_text)
      rest = text[::Regexp.last_match.end(0)..]
      %(<span class="yield" data-base-value="#{value}" data-unit-singular="#{unit_singular}" data-unit-plural="#{unit_plural}">#{inner_span}#{rest}</span>)
    end
  end
```

**Step 4: Update the template**

In `templates/web/recipe-template.html.erb`, replace lines 20-24:

```erb
        <p class="recipe-meta">
          <a href="index.html#<%= slugify.call(category) %>"><%= category %></a><%- if makes -%>
          <%- if nutrition&.makes_unit_singular -%>
          · Makes <%= ScalableNumberPreprocessor.process_yield_with_unit(makes, nutrition.makes_unit_singular, nutrition.makes_unit_plural) %><%- else -%>
          · Makes <%= ScalableNumberPreprocessor.process_yield_line(makes) %><%- end -%><%- end -%><%- if serves -%>
          · Serves <%= ScalableNumberPreprocessor.process_yield_line(serves.to_s) %><%- end -%>
        </p>
```

Note: We use `nutrition&.makes_unit_singular` because nutrition may be nil for recipes without nutrition data. In that case, fall back to the old `process_yield_line` behavior.

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: All pass.

**Step 6: Run full test suite and build**

Run: `rake test && bin/generate`
Expected: All pass. Build succeeds.

**Step 7: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb test/scalable_number_preprocessor_test.rb templates/web/recipe-template.html.erb
git commit -m "feat: yield line wrapper span with singular/plural data attributes"
```

---

### Task 5: JavaScript — Yield Line Inflection and Vulgar Fractions

**Files:**
- Modify: `resources/web/recipe-state-manager.js:146-190` (applyScale method)

Add vulgar fraction formatting and `.yield` span handling to the JS scaler.

**Step 1: Add vulgar fraction helper**

Add this above the `RecipeStateManager` class in `recipe-state-manager.js`:

```javascript
const VULGAR_FRACTIONS = [
  [1/2, '\u00BD'], [1/3, '\u2153'], [2/3, '\u2154'],
  [1/4, '\u00BC'], [3/4, '\u00BE'],
  [1/8, '\u215B'], [3/8, '\u215C'], [5/8, '\u215D'], [7/8, '\u215E']
];

function formatVulgar(value) {
  if (Number.isInteger(value)) return String(value);
  const intPart = Math.floor(value);
  const fracPart = value - intPart;
  const match = VULGAR_FRACTIONS.find(([v]) => Math.abs(fracPart - v) < 0.001);
  if (match) return intPart === 0 ? match[1] : `${intPart}${match[1]}`;
  const rounded = Math.round(value * 100) / 100;
  return String(rounded);
}

function isVulgarSingular(value) {
  if (Math.abs(value - 1) < 0.001) return true;
  if (value <= 0 || value >= 1) return false;
  return VULGAR_FRACTIONS.some(([v]) => Math.abs(value - v) < 0.001);
}
```

**Step 2: Update `.scalable` scaling to skip spans inside `.yield` containers**

In the `applyScale` method, the existing `.scalable[data-base-value]` handler (lines 173-189) must skip spans that are children of `.yield` elements, since those are handled separately. Change the selector:

```javascript
    // Scale marked numbers (yield line + instruction numbers)
    // Skip scalable spans inside .yield containers — those are handled below
    document.querySelectorAll('.scalable[data-base-value]').forEach(span => {
      if (span.closest('.yield')) return;
      // ... rest unchanged
    });
```

**Step 3: Add `.yield` span handler**

Add after the `.scalable` block, still inside `applyScale`:

```javascript
    // Scale yield line with inflected unit nouns
    document.querySelectorAll('.yield[data-base-value]').forEach(container => {
      const base = parseFloat(container.dataset.baseValue);
      const scaled = base * factor;
      const singular = container.dataset.unitSingular || '';
      const plural = container.dataset.unitPlural || singular;

      const scalableSpan = container.querySelector('.scalable');
      if (!scalableSpan) return;

      const pretty = formatVulgar(scaled);
      const unit = isVulgarSingular(scaled) ? singular : plural;

      scalableSpan.textContent = pretty;
      if (factor === 1) {
        scalableSpan.classList.remove('scaled');
        scalableSpan.removeAttribute('title');
      } else {
        scalableSpan.classList.add('scaled');
        scalableSpan.title = 'Originally: ' + scalableSpan.dataset.originalText;
      }

      // Update text node after the scalable span
      const textAfterSpan = scalableSpan.nextSibling;
      if (textAfterSpan && textAfterSpan.nodeType === Node.TEXT_NODE) {
        textAfterSpan.textContent = ' ' + unit;
      }
    });
```

**Step 4: Run build and test manually**

Run: `bin/generate && bin/serve`

Test manually in browser:
1. Open a recipe with Makes (e.g., Pancakes at localhost:8888/pancakes)
2. Click Scale, enter 1/12
3. Verify yield line shows "Makes 1 pancake" (singular)
4. Scale ×2, verify "Makes 24 pancakes" (plural)
5. Scale ×1, verify "Makes 12 pancakes" (original restored)

**Step 5: Commit**

```bash
git add resources/web/recipe-state-manager.js
git commit -m "feat: yield line inflection and vulgar fraction formatting in JS"
```

---

### Task 6: Integration Test and Polish

**Files:**
- Modify: `test/site_generator_test.rb` (if there are relevant integration tests)
- Potentially modify: `resources/web/style.css` (if column widths need adjustment)

**Step 1: Run the full test suite**

Run: `rake`
Expected: Lint passes, all tests pass.

**Step 2: Run build and visually verify**

Run: `bin/generate && bin/serve`

Check these recipes in the browser:
- **Chocolate Chip Cookies** (Makes: 24 cookies) — should show "Per Cookie" + "Total"
- **Pancakes** (Makes: 12 pancakes) — should show "Per Pancake" + "Total"
- **Gougères** (Makes: 30 gougères, no Serves) — should show "Per Gougère" + "Total"
- **Red Beans and Rice** (Serves: 4, no Makes) — should show "Per Serving" + "Total"
- **Baked Ziti** (Serves: 4, no Makes) — should show "Per Serving" + "Total"
- **Soda Bread** (Makes: 1 loaf) — should show single "Per Loaf" column
- **Basic Pizza** (Makes: 2 pizzas, Serves: 4) — should show "Per Pizza" + "Per Serving (1 pizza)" + "Total"
- A recipe with no Makes or Serves — should show "Total" only

For each, verify scaling works: the yield line inflects nouns, the Total column scales, and per-unit/per-serving columns stay fixed.

**Step 3: Fix any issues found**

Address styling, layout, or logic issues discovered during manual testing.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: polish nutrition labels and yield inflection"
```

---

### Summary of all tasks

| Task | Description | Key files |
|------|-------------|-----------|
| 1 | VulgarFractions Ruby module | `lib/familyrecipes/vulgar_fractions.rb`, test |
| 2 | Expand NutritionCalculator::Result | `lib/familyrecipes/nutrition_calculator.rb`, test |
| 3 | Update nutrition table template | `templates/web/recipe-template.html.erb` |
| 4 | Yield line wrapper markup | `scalable_number_preprocessor.rb`, template, test |
| 5 | JS yield inflection + vulgar fractions | `recipe-state-manager.js` |
| 6 | Integration testing and polish | Manual verification, fixes |

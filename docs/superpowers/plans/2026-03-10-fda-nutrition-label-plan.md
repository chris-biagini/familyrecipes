# FDA Nutrition Label Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the multi-column nutrition table with an FDA-style Nutrition Facts label showing per-serving values, serving weight in grams, and % Daily Values.

**Architecture:** Add `total_weight_grams` to `NutritionCalculator::Result` by summing resolved ingredient weights. Add `DAILY_VALUES` to `NutritionConstraints`. Rewrite the view partial and CSS to match FDA label typography. Remove nutrition scaling from recipe_state Stimulus controller.

**Tech Stack:** Ruby, ERB, CSS, Stimulus JS, Minitest.

---

### Task 0: Add DAILY_VALUES to NutritionConstraints

**Files:**
- Modify: `lib/familyrecipes/nutrition_constraints.rb:16-30`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Add `daily_value` field to NutrientDef and update NUTRIENT_DEFS**

In `lib/familyrecipes/nutrition_constraints.rb`, change the `NutrientDef` definition and all entries:

```ruby
NutrientDef = Data.define(:key, :label, :unit, :indent, :daily_value)

NUTRIENT_DEFS = [
  NutrientDef.new(key: :calories,      label: 'Calories',      unit: '',   indent: 0, daily_value: nil),
  NutrientDef.new(key: :fat,           label: 'Total Fat',     unit: 'g',  indent: 0, daily_value: 78),
  NutrientDef.new(key: :saturated_fat, label: 'Saturated Fat', unit: 'g',  indent: 1, daily_value: 20),
  NutrientDef.new(key: :trans_fat,     label: 'Trans Fat',     unit: 'g',  indent: 1, daily_value: nil),
  NutrientDef.new(key: :cholesterol,   label: 'Cholesterol',   unit: 'mg', indent: 0, daily_value: 300),
  NutrientDef.new(key: :sodium,        label: 'Sodium',        unit: 'mg', indent: 0, daily_value: 2300),
  NutrientDef.new(key: :carbs,         label: 'Total Carbs',   unit: 'g',  indent: 0, daily_value: 275),
  NutrientDef.new(key: :fiber,         label: 'Fiber',         unit: 'g',  indent: 1, daily_value: 28),
  NutrientDef.new(key: :total_sugars,  label: 'Total Sugars',  unit: 'g',  indent: 1, daily_value: nil),
  NutrientDef.new(key: :added_sugars,  label: 'Added Sugars',  unit: 'g',  indent: 2, daily_value: 50),
  NutrientDef.new(key: :protein,       label: 'Protein',       unit: 'g',  indent: 0, daily_value: 50)
].freeze
```

**Step 2: Add a DAILY_VALUES convenience hash**

Below NUTRIENT_DEFS, add:

```ruby
DAILY_VALUES = NUTRIENT_DEFS
  .select(&:daily_value)
  .to_h { |d| [d.key, d.daily_value] }
  .freeze
```

**Step 3: Run existing tests to confirm nothing breaks**

Run: `ruby -Itest test/nutrition_calculator_test.rb && bundle exec rubocop lib/familyrecipes/nutrition_constraints.rb`
Expected: All tests PASS, no RuboCop offenses.

**Step 4: Commit**

```bash
git add lib/familyrecipes/nutrition_constraints.rb
git commit -m "feat: add daily_value field to NutrientDef and DAILY_VALUES hash"
```

---

### Task 1: Compute total_weight_grams in NutritionCalculator

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:27-36` (Result), `:74-81` (sum_totals), `:53-66` (calculate)
- Test: `test/nutrition_calculator_test.rb`

**Context:** The calculator already resolves each ingredient to grams via `to_grams()` in `accumulate_amounts`. We need to accumulate the total grams alongside the nutrient totals.

**Step 1: Write failing tests for total_weight_grams**

Add to `test/nutrition_calculator_test.rb`:

```ruby
# --- Total weight ---

def test_total_weight_grams_from_gram_ingredients
  recipe = make_recipe(<<~MD)
    # Test

    Serves: 2

    ## Mix (combine)

    - Flour (all-purpose), 200 g
    - Eggs, 2

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # 200g flour + 2 eggs * 50g = 300g total
  assert_in_delta 300, result.total_weight_grams, 0.1
end

def test_total_weight_grams_with_volume_ingredients
  recipe = make_recipe(<<~MD)
    # Test

    Serves: 1

    ## Mix (combine)

    - Butter, 2 tbsp

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # 2 tbsp butter via density: 2 * 14.787ml * (227/236.588) g/ml = 28.37g
  expected_grams = 2 * 14.787 * (227.0 / 236.588)
  assert_in_delta expected_grams, result.total_weight_grams, 0.5
end

def test_total_weight_grams_excludes_unresolvable
  recipe = make_recipe(<<~MD)
    # Test

    Serves: 1

    ## Mix (combine)

    - Flour (all-purpose), 100 g
    - Flour (all-purpose), 2 bushels

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # Only the 100g resolves; the "bushels" amount is partial
  assert_in_delta 100, result.total_weight_grams, 0.1
end

def test_total_weight_grams_zero_when_nothing_resolves
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Unicorn dust, 50 g

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  assert_in_delta 0, result.total_weight_grams, 0.01
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n /total_weight/`
Expected: FAIL — `NoMethodError: undefined method 'total_weight_grams'`

**Step 3: Add total_weight_grams to Result**

In `lib/familyrecipes/nutrition_calculator.rb`, update the Result definition:

```ruby
Result = Data.define(
  :totals, :serving_count, :per_serving, :per_unit,
  :makes_quantity, :makes_unit_singular, :makes_unit_plural,
  :units_per_serving, :total_weight_grams,
  :missing_ingredients, :partial_ingredients, :skipped_ingredients
) do
  def complete?
    missing_ingredients.empty? && partial_ingredients.empty?
  end
end
```

**Step 4: Track weight accumulation in sum_totals and accumulate_amounts**

Change `sum_totals` to return weight alongside totals:

```ruby
def sum_totals(recipe, recipe_map)
  active = recipe.all_ingredients_with_quantities(recipe_map)
                 .reject { |name, _| @omit_set.include?(name.downcase) }
  known, unknown = active.partition { |name, _| @nutrition_data.key?(name) }

  totals = NUTRIENTS.index_with { |_n| 0.0 }
  weight = { grams: 0.0 }
  missing, partial, skipped = partition_ingredients(totals, weight, known, unknown)
  [totals, weight[:grams], missing, partial, skipped]
end
```

Update `partition_ingredients` to pass weight through:

```ruby
def partition_ingredients(totals, weight, known, unknown)
  known_quantified, known_skipped = split_by_quantified(known)
  unknown_quantified, unknown_skipped = split_by_quantified(unknown)

  partial = known_quantified.each_with_object([]) do |(name, amounts), partials|
    accumulate_amounts(totals, weight, partials, name, amounts, @nutrition_data[name])
  end

  skipped = known_skipped.map(&:first).concat(unknown_skipped.map(&:first))
  [unknown_quantified.map(&:first), partial, skipped]
end
```

Update `accumulate_amounts` to track weight:

```ruby
def accumulate_amounts(totals, weight, partial, name, amounts, entry)
  amounts.each do |amount|
    next if amount.nil? || amount.value.nil?

    grams = to_grams(amount.value, amount.unit, entry)
    if grams.nil?
      partial << name unless partial.include?(name)
      next
    end

    weight[:grams] += grams
    NUTRIENTS.each { |nutrient| totals[nutrient] += nutrient_per_gram(entry, nutrient) * grams }
  end
end
```

**Step 5: Wire total_weight_grams into calculate**

```ruby
def calculate(recipe, recipe_map)
  totals, total_weight, missing, partial, skipped = sum_totals(recipe, recipe_map)
  serving_count = parse_serving_count(recipe)

  Result.new(
    totals: totals,
    serving_count: serving_count,
    per_serving: divide_nutrients(totals, serving_count),
    total_weight_grams: total_weight,
    **per_unit_metadata(recipe, totals, serving_count),
    missing_ingredients: missing,
    partial_ingredients: partial,
    skipped_ingredients: skipped
  )
end
```

**Step 6: Run tests**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: ALL tests PASS (including new total_weight tests and all existing tests).

**Step 7: Lint**

Run: `bundle exec rubocop lib/familyrecipes/nutrition_calculator.rb`
Expected: No new offenses (existing rubocop:disable comments may still be present).

**Step 8: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "feat: compute total_weight_grams in NutritionCalculator"
```

---

### Task 2: Serialize total_weight_grams in RecipeNutritionJob

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb:59-72`
- Test: `test/jobs/recipe_nutrition_job_test.rb`

**Step 1: Write failing test**

Add to `test/jobs/recipe_nutrition_job_test.rb`:

```ruby
test 'stores total_weight_grams in nutrition_data' do
  markdown = "# Bread\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
  recipe = import_without_nutrition(markdown)

  RecipeNutritionJob.perform_now(recipe)
  recipe.reload

  assert_in_delta 60.0, recipe.nutrition_data['total_weight_grams'], 0.1
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n test_stores_total_weight_grams`
Expected: FAIL — `total_weight_grams` key missing from serialized hash.

**Step 3: Add to serialize_result**

In `app/jobs/recipe_nutrition_job.rb`, add the key to `serialize_result`:

```ruby
def serialize_result(result)
  {
    'totals' => stringify_nutrient_keys(result.totals),
    'serving_count' => result.serving_count,
    'per_serving' => stringify_nutrient_keys(result.per_serving),
    'per_unit' => stringify_nutrient_keys(result.per_unit),
    'makes_quantity' => result.makes_quantity,
    'makes_unit_singular' => result.makes_unit_singular,
    'makes_unit_plural' => result.makes_unit_plural,
    'units_per_serving' => result.units_per_serving,
    'total_weight_grams' => result.total_weight_grams,
    'missing_ingredients' => result.missing_ingredients,
    'partial_ingredients' => result.partial_ingredients,
    'skipped_ingredients' => result.skipped_ingredients
  }
end
```

**Step 4: Run all job tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb test/jobs/recipe_nutrition_job_test.rb
git commit -m "feat: serialize total_weight_grams in RecipeNutritionJob"
```

---

### Task 3: Rewrite RecipesHelper for FDA label

**Files:**
- Modify: `app/helpers/recipes_helper.rb`
- Test: `test/helpers/recipes_helper_test.rb` (create if needed)

**Context:** Replace `nutrition_columns`, `per_unit_column`, `per_serving_column`, `total_column`, and `per_serving_label` with FDA-label helpers. Keep non-nutrition methods unchanged.

**Step 1: Check if helper tests exist**

Run: `ls test/helpers/`
If no `recipes_helper_test.rb` exists, create it. If it does, read it to understand existing coverage.

**Step 2: Write tests for new helper methods**

Create `test/helpers/recipes_helper_test.rb` if it doesn't exist:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipesHelperTest < ActionView::TestCase
  # --- serving_size_text ---

  test 'serving_size_text with makes and serves' do
    nutrition = {
      'serving_count' => 4, 'makes_quantity' => 8,
      'makes_unit_singular' => 'taco', 'makes_unit_plural' => 'tacos',
      'units_per_serving' => 2.0, 'total_weight_grams' => 592.0
    }

    assert_equal '2 tacos (148 g)', serving_size_text(nutrition)
  end

  test 'serving_size_text with makes only (no serves)' do
    nutrition = {
      'serving_count' => 12, 'makes_quantity' => 12,
      'makes_unit_singular' => 'pancake', 'makes_unit_plural' => 'pancakes',
      'units_per_serving' => nil, 'total_weight_grams' => 600.0
    }

    assert_equal '1 pancake (50 g)', serving_size_text(nutrition)
  end

  test 'serving_size_text with serves only (no makes)' do
    nutrition = {
      'serving_count' => 4, 'makes_quantity' => nil,
      'total_weight_grams' => 400.0
    }

    result = serving_size_text(nutrition)
    assert_includes result, '100 g'
  end

  test 'serving_size_text with neither makes nor serves' do
    nutrition = {
      'serving_count' => nil, 'makes_quantity' => nil,
      'total_weight_grams' => 300.0
    }

    result = serving_size_text(nutrition)
    assert_includes result, '300 g'
  end

  # --- servings_per_recipe_text ---

  test 'servings_per_recipe_text with serving count' do
    assert_equal '4 servings per recipe', servings_per_recipe_text({ 'serving_count' => 4 })
  end

  test 'servings_per_recipe_text without serving count' do
    assert_equal '1 serving per recipe', servings_per_recipe_text({ 'serving_count' => nil })
  end

  # --- percent_daily_value ---

  test 'percent_daily_value for fat' do
    assert_equal 13, percent_daily_value(:fat, 10.0)
  end

  test 'percent_daily_value for nutrient with no daily value' do
    assert_nil percent_daily_value(:trans_fat, 5.0)
  end

  test 'percent_daily_value rounds to nearest integer' do
    # 2300mg sodium = 100%
    assert_equal 100, percent_daily_value(:sodium, 2300.0)
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: FAIL — methods don't exist yet.

**Step 4: Rewrite the helper**

Replace the private nutrition column methods and add new FDA-label methods in `app/helpers/recipes_helper.rb`. Remove `nutrition_columns`, `per_unit?`, `per_unit_column`, `per_serving_column`, `total_column`, `per_serving_label`. Add:

```ruby
def servings_per_recipe_text(nutrition)
  count = nutrition['serving_count'] || 1
  "#{count} #{'serving'.pluralize(count)} per recipe"
end

def serving_size_text(nutrition)
  weight = per_serving_weight(nutrition)
  weight_str = weight ? " (#{weight.round} g)" : ''

  unit_desc = serving_unit_description(nutrition)
  "#{unit_desc}#{weight_str}".strip
end

def percent_daily_value(nutrient_key, amount)
  dv = FamilyRecipes::NutritionConstraints::DAILY_VALUES[nutrient_key]
  return unless dv

  (amount.to_f / dv * 100).round
end

private

def per_serving_weight(nutrition)
  total = nutrition['total_weight_grams']
  return unless total&.positive?

  count = nutrition['serving_count'] || 1
  total.to_f / count
end

def serving_unit_description(nutrition)
  makes_qty = nutrition['makes_quantity']
  serving_count = nutrition['serving_count']
  ups = nutrition['units_per_serving']

  if makes_qty && ups
    formatted = FamilyRecipes::VulgarFractions.format(ups)
    unit = FamilyRecipes::VulgarFractions.singular_noun?(ups) ? nutrition['makes_unit_singular'] : nutrition['makes_unit_plural']
    "#{formatted} #{unit}"
  elsif makes_qty && serving_count
    per_serving = makes_qty.to_f / serving_count
    formatted = FamilyRecipes::VulgarFractions.format(per_serving)
    unit = FamilyRecipes::VulgarFractions.singular_noun?(per_serving) ? nutrition['makes_unit_singular'] : nutrition['makes_unit_plural']
    "#{formatted} #{unit}"
  elsif serving_count && serving_count > 1
    fraction = FamilyRecipes::VulgarFractions.format(1.0 / serving_count)
    "#{fraction} recipe"
  else
    'entire recipe'
  end
end
```

Also update `NUTRITION_ROWS` to include `daily_value`:

```ruby
NUTRITION_ROWS = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map do |d|
  [d.label, d.key.to_s, d.unit, d.indent, d.daily_value]
end.freeze
```

**Step 5: Run tests**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: All tests PASS.

**Step 6: Run full test suite to check for breakage**

Run: `rake test`
Expected: Some tests may fail due to the view partial not yet being updated. That's expected — the partial rewrite is Task 4. The helper tests should all pass.

**Step 7: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb
git commit -m "feat: add FDA label helper methods (serving size, %DV)"
```

---

### Task 4: Rewrite _nutrition_table.html.erb for FDA label layout

**Files:**
- Modify: `app/views/recipes/_nutrition_table.html.erb`
- Modify: `config/html_safe_allowlist.yml:29-31` (update line numbers)

**Context:** Complete rewrite of the partial to match FDA Nutrition Facts label structure. The partial receives `nutrition:` local (the JSON hash from `recipe.nutrition_data`). Uses the new helper methods from Task 3.

**Step 1: Rewrite the partial**

Replace the entire content of `app/views/recipes/_nutrition_table.html.erb` with:

```erb
<aside class="nutrition-label">
  <header>
    <h2>Nutrition Facts</h2>
    <p class="servings"><%= servings_per_recipe_text(nutrition) %></p>
    <p class="serving-size"><span class="label">Serving size</span> <span class="value"><%= serving_size_text(nutrition) %></span></p>
  </header>

  <div class="calories-row">
    <span class="label">Calories</span>
    <span class="value"><%= nutrition.dig('per_serving', 'calories')&.to_f&.round || nutrition.dig('totals', 'calories')&.to_f&.round || 0 %></span>
  </div>

  <div class="nutrients">
    <p class="dv-header">% Daily Value*</p>
    <%- per_serving = nutrition['per_serving'] || nutrition['totals'] || {} -%>
    <%- RecipesHelper::NUTRITION_ROWS.each do |label, key, unit_label, indent, daily_value| -%>
      <%- next if key == 'calories' -%>
      <%- value = per_serving[key].to_f -%>
      <%- dv_percent = percent_daily_value(key.to_sym, value) -%>
      <div class="nutrient-row<%= " indent-#{indent}" if indent > 0 %>">
        <span class="name"><%= indent == 0 ? tag.strong(label) : label %> <%= "#{value.round}#{unit_label}" %></span>
        <%- if dv_percent -%>
          <span class="dv"><strong><%= dv_percent %>%</strong></span>
        <%- end -%>
      </div>
    <%- end -%>
  </div>

  <footer>
    <p>* The % Daily Value tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.</p>
  </footer>

  <% missing = nutrition_missing_ingredients(nutrition) %>
  <% partial = nutrition_partial_ingredients(nutrition) %>
  <% skipped = nutrition_skipped_ingredients(nutrition) %>
  <%- if missing.any? -%>
  <p class="nutrition-note">*Approximate. No nutrition data for:
    <%- missing.each_with_index do |name, i| -%>
      <%- if current_member? -%>
        <button type="button" class="btn-inline-link" data-open-editor data-ingredient-name="<%= name %>"><%= name %></button><%- else -%>
        <%= name %><%- end -%><%= ',' unless i == missing.size - 1 %>
    <%- end -%>.</p>
  <%- end -%>
  <%- if partial.any? -%>
  <p class="nutrition-note">*Approximate. Could not calculate:
    <%- partial.each_with_index do |name, i| -%>
      <%- if current_member? -%>
        <button type="button" class="btn-inline-link" data-open-editor data-ingredient-name="<%= name %>"><%= name %></button> (unknown portion size)<%- else -%>
        <%= name %> (unknown portion size)<%- end -%><%= ',' unless i == partial.size - 1 %>
    <%- end -%>.</p>
  <%- end -%>
  <%- if skipped.any? -%>
  <p class="nutrition-note">Not included (no quantity specified): <%= skipped.join(', ') %>.</p>
  <%- end -%>
</aside>
```

**Step 2: Update html_safe_allowlist.yml**

The old `_nutrition_table.html.erb` had two allowlisted lines (15 and 18) for `.html_safe` calls. The new partial has no `.html_safe` calls, so **remove** lines 29-31 from `config/html_safe_allowlist.yml`:

```yaml
# Remove these lines:
# _nutrition_table.html.erb — hardcoded literals, no user content
- "app/views/recipes/_nutrition_table.html.erb:15" # indent class: hardcoded integer
- "app/views/recipes/_nutrition_table.html.erb:18" # nutrient data attrs: hardcoded key + numeric value
```

**Step 3: Run html_safe lint**

Run: `rake lint:html_safe`
Expected: PASS — no unlisted .html_safe calls.

**Step 4: Run full test suite**

Run: `rake test`
Expected: Tests that assert on the old nutrition table HTML may fail. Fix those in the next task.

**Step 5: Commit**

```bash
git add app/views/recipes/_nutrition_table.html.erb config/html_safe_allowlist.yml
git commit -m "feat: rewrite nutrition partial to FDA label layout"
```

---

### Task 5: Replace CSS for FDA nutrition label

**Files:**
- Modify: `app/assets/stylesheets/style.css` (lines ~840-910, the `.nutrition-facts` block)

**Context:** Replace the old `.nutrition-facts` table styles with FDA-matching `.nutrition-label` styles. Use Helvetica Neue/Helvetica/Arial font stack, black/white coloring, thick/thin rules. The label should be a self-contained widget with its own background.

**Step 1: Remove old `.nutrition-facts` styles**

Delete the entire block from `.nutrition-facts` through `.nutrition-note` (approximately lines 840-913 in `style.css`).

**Step 2: Add new `.nutrition-label` styles**

Insert the new FDA-style CSS in the same location. Key design rules:
- `max-width: 20rem` (FDA labels are narrow)
- Black border, white background
- `font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif`
- "Nutrition Facts" in bold, large text
- Thick rule (7px) below header and below calories
- Medium rule (3px) at key section boundaries
- Thin rules (1px) between nutrient rows
- Calories value in large bold text
- Sub-nutrients indented via padding-left
- % Daily Value right-aligned
- Footnote in small italic text

```css
/***********************/
/* FDA Nutrition Label */
/***********************/

.nutrition-label {
  margin-top: 2.5rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--separator-color);
  max-width: 20rem;
  font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
  border: 2px solid #000;
  padding: 0.5rem;
  background: #fff;
  color: #000;
}

.nutrition-label h2 {
  font-size: 2rem;
  font-weight: 900;
  line-height: 1;
  margin: 0 0 0.25rem;
  letter-spacing: -0.02em;
}

.nutrition-label .servings {
  margin: 0;
  font-size: 0.85rem;
}

.nutrition-label .serving-size {
  display: flex;
  justify-content: space-between;
  margin: 0;
  font-size: 0.85rem;
  font-weight: 700;
  padding-bottom: 0.25rem;
  border-bottom: 7px solid #000;
}

.nutrition-label .calories-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  padding: 0.25rem 0;
  border-bottom: 3px solid #000;
}

.nutrition-label .calories-row .label {
  font-size: 0.85rem;
  font-weight: 700;
}

.nutrition-label .calories-row .value {
  font-size: 2rem;
  font-weight: 900;
  line-height: 1;
}

.nutrition-label .dv-header {
  text-align: right;
  font-size: 0.75rem;
  font-weight: 700;
  margin: 0;
  padding: 0.15rem 0;
  border-bottom: 1px solid #000;
}

.nutrition-label .nutrient-row {
  display: flex;
  justify-content: space-between;
  font-size: 0.85rem;
  padding: 0.15rem 0;
  border-bottom: 1px solid #000;
}

.nutrition-label .nutrient-row:last-child {
  border-bottom: 7px solid #000;
}

.nutrition-label .nutrient-row.indent-1 {
  padding-left: 1.5em;
}

.nutrition-label .nutrient-row.indent-2 {
  padding-left: 3em;
}

.nutrition-label .nutrient-row .dv {
  white-space: nowrap;
}

.nutrition-label footer {
  padding-top: 0.25rem;
}

.nutrition-label footer p {
  font-size: 0.7rem;
  margin: 0;
  line-height: 1.3;
}

.nutrition-note {
  font-size: 0.8rem;
  font-style: italic;
  color: var(--text-secondary);
  margin: 0.5rem 0 0;
}
```

**Step 3: Check for any `.nutrition-facts` references remaining in CSS**

Search for `.nutrition-facts` in `style.css` — there may be responsive overrides (e.g., in `@media` blocks). Remove or rename those too.

**Step 4: Run lint and tests**

Run: `bundle exec rubocop && rake test`
Expected: PASS (CSS changes don't affect Ruby tests, but confirm nothing else broke).

**Step 5: Commit**

```bash
git add app/assets/stylesheets/style.css
git commit -m "feat: FDA-style nutrition label CSS"
```

---

### Task 6: Remove nutrition scaling from recipe_state_controller.js

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:187-192`

**Context:** The old table had `data-nutrient` attributes on the Total column for client-side scaling. The new FDA label shows per-serving values only, which don't change when scaling. Remove the 6-line block that queries `.nutrition-facts td[data-nutrient]`.

**Step 1: Remove the nutrition scaling block**

In `app/javascript/controllers/recipe_state_controller.js`, find and remove:

```javascript
this.element.querySelectorAll('.nutrition-facts td[data-nutrient]').forEach(td => {
  const base = parseFloat(td.dataset.baseValue)
  const scaled = base * factor
  const unit = td.dataset.unit || ''
  td.textContent = `${Math.round(scaled)}${unit}`
})
```

This is inside the method that applies scaling. The selector `.nutrition-facts` no longer matches anything (class is now `.nutrition-label`), so it's dead code regardless, but clean it up.

**Step 2: Run full test suite**

Run: `rake test`
Expected: PASS.

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "fix: remove dead nutrition scaling code from recipe_state_controller"
```

---

### Task 7: Clean up unused helper methods and update NUTRITION_ROWS consumers

**Files:**
- Modify: `app/helpers/recipes_helper.rb`
- Modify: `app/helpers/ingredients_helper.rb` (if it references old NUTRITION_ROWS format)
- Test: Run full suite

**Context:** NUTRITION_ROWS now has 5 elements per row (added `daily_value`). Check all consumers:
- `_nutrition_table.html.erb` — already updated in Task 4
- `ingredients_helper.rb` — may destructure NUTRITION_ROWS

**Step 1: Search for NUTRITION_ROWS consumers**

Run: `grep -rn 'NUTRITION_ROWS' app/ lib/ test/`

Check each consumer handles the new 5-element tuple. If `ingredients_helper.rb` uses it, update destructuring to ignore the 5th element.

**Step 2: Check if `per_serving_label` html_safe allowlist entry needs cleanup**

The allowlist had `app/helpers/recipes_helper.rb:132` for `per_serving_label`. Since that method is removed, the line number will shift. Check:

Run: `rake lint:html_safe`

If it fails because the allowlist references a line that no longer has `.html_safe`, remove the stale entry from `config/html_safe_allowlist.yml`.

**Step 3: Run full test suite**

Run: `rake test && rake lint && rake lint:html_safe`
Expected: All PASS.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: clean up stale NUTRITION_ROWS consumers and allowlist entries"
```

---

### Task 8: Integration verification and edge case testing

**Files:**
- Test: `test/jobs/recipe_nutrition_job_test.rb` (add edge case tests)
- Test: Run existing integration tests

**Step 1: Add edge case tests for serving size with no makes/no serves**

Add to `test/jobs/recipe_nutrition_job_test.rb`:

```ruby
test 'stores total_weight_grams with no serves' do
  markdown = "# Bread\n\n## Mix\n\n- Flour, 60 g\n\nMix."
  recipe = import_without_nutrition(markdown)

  RecipeNutritionJob.perform_now(recipe)
  recipe.reload

  assert_in_delta 60.0, recipe.nutrition_data['total_weight_grams'], 0.1
  assert_nil recipe.nutrition_data['serving_count']
end
```

**Step 2: Run full test suite**

Run: `rake test`
Expected: All tests PASS.

**Step 3: Run the dev server and visually inspect**

Run: `bin/dev`
Navigate to a recipe with nutrition data (e.g., Pancakes). Verify:
- FDA-style label renders correctly
- "12 servings per recipe" header
- "1 pancake (X g)" serving size
- Calories displayed large
- % Daily Value column on right
- Proper thick/thin rules
- Footnote text at bottom
- Missing/partial/skipped notes still appear below

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "test: add edge case tests for FDA nutrition label"
```

---

### Task 9: Recalculate existing recipes' nutrition_data

**Context:** Existing recipes in the database don't have `total_weight_grams` in their `nutrition_data` JSON. The view will try to read it and get `nil`, which means serving weight won't display until recipes are re-saved. Need a one-time recalculation.

**Step 1: Create a rake task or use rails console**

Add a simple rake task in `lib/tasks/nutrition.rake` (or add to existing tasks):

```ruby
namespace :nutrition do
  desc 'Recalculate nutrition_data for all recipes (adds total_weight_grams)'
  task recalculate: :environment do
    Kitchen.find_each do |kitchen|
      ActsAsTenant.with_tenant(kitchen) do
        Recipe.find_each do |recipe|
          RecipeNutritionJob.perform_now(recipe)
        end
      end
    end
    puts "Recalculated nutrition for #{Recipe.count} recipes"
  end
end
```

**Step 2: Run the task against development database**

Run: `rake nutrition:recalculate`
Expected: All recipes updated with `total_weight_grams` in their JSON.

**Step 3: Commit**

```bash
git add lib/tasks/nutrition.rake
git commit -m "feat: add rake nutrition:recalculate task for backfilling total_weight_grams"
```

---

### Task 10: Final verification

**Step 1: Run full lint and test suite**

Run: `rake`
Expected: All lint checks and tests PASS.

**Step 2: Visual inspection of multiple recipes**

Check recipes with different yield configurations:
- Recipe with Makes + Serves (Quick Pizza: Makes 2 pizzas, Serves 4)
- Recipe with Makes only (Pancakes: Makes 12 pancakes)
- Recipe with Serves only
- Recipe with neither
- Recipe with missing/partial ingredients

**Step 3: Verify dark mode / theme compatibility**

The FDA label is explicitly white background with black text. Confirm it looks good as a self-contained widget in both light and dark themes (if dark mode exists).

**Step 4: Final commit if any adjustments needed**

```bash
git add -A
git commit -m "fix: final FDA label polish"
```

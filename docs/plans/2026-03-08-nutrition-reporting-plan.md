# Nutrition Reporting Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single generic "data unavailable" note below the nutrition table with three distinct messages that tell users exactly what's wrong and how to fix it.

**Architecture:** Add `skipped_ingredients` to `NutritionCalculator::Result`, track unquantified (non-omit) ingredients during calculation, serialize through `RecipeNutritionJob`, and render three separate notes in the view. Also fix the Eggs seed data.

**Tech Stack:** Ruby (Minitest), Rails views (ERB), YAML seed data.

---

### Task 1: Add `skipped_ingredients` to NutritionCalculator

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Write the failing test**

Add to `test/nutrition_calculator_test.rb`:

```ruby
def test_unquantified_ingredients_tracked_in_skipped
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 200 g
    - Olive oil

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  assert_includes result.skipped_ingredients, 'Olive oil'
  assert_in_delta 728, result.totals[:calories], 1
end

def test_omit_set_excluded_from_skipped
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 200 g
    - Water

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  refute_includes result.skipped_ingredients, 'Water'
end

def test_skipped_does_not_affect_complete
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 200 g
    - Olive oil

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # Skipped (to-taste) ingredients don't make a recipe "incomplete"
  assert_predicate result, :complete?
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n '/skipped|omit_set_excluded_from_skipped/'`
Expected: FAIL — `Result` doesn't have `skipped_ingredients`

**Step 3: Implement skipped tracking**

In `lib/familyrecipes/nutrition_calculator.rb`:

1. Add `skipped_ingredients` to `Result = Data.define(...)`:
```ruby
Result = Data.define(
  :totals, :serving_count, :per_serving, :per_unit,
  :makes_quantity, :makes_unit_singular, :makes_unit_plural,
  :units_per_serving,
  :missing_ingredients, :partial_ingredients, :skipped_ingredients
) do
  def complete?
    missing_ingredients.empty? && partial_ingredients.empty?
  end
end
```

2. Update `sum_totals` to track skipped ingredients. Change the method to also return a skipped list. When an amount is `nil` (unquantified), add the ingredient name to a `skipped` set — but only if the ingredient name (downcased) is not in `@omit_set`:

```ruby
def sum_totals(recipe, recipe_map)
  active = recipe.all_ingredients_with_quantities(recipe_map)
                 .reject { |name, _| @omit_set.include?(name.downcase) }
  known, unknown = active.partition { |name, _| @nutrition_data.key?(name) }

  totals = NUTRIENTS.index_with { |_n| 0.0 }
  skipped = []
  partial = known.each_with_object([]) do |(name, amounts), partials|
    if amounts.all?(&:nil?)
      skipped << name
    else
      accumulate_amounts(totals, partials, name, amounts, @nutrition_data[name])
    end
  end

  # Unknown ingredients with only nil amounts are also skipped, not missing
  missing = []
  unknown.each do |name, amounts|
    if amounts.all?(&:nil?)
      skipped << name
    else
      missing << name
    end
  end

  [totals, missing, partial, skipped]
end
```

3. Update `calculate` to pass `skipped` through:

```ruby
def calculate(recipe, recipe_map)
  totals, missing, partial, skipped = sum_totals(recipe, recipe_map)
  serving_count = parse_serving_count(recipe)

  Result.new(
    totals: totals,
    serving_count: serving_count,
    per_serving: divide_nutrients(totals, serving_count),
    **per_unit_metadata(recipe, totals, serving_count),
    missing_ingredients: missing,
    partial_ingredients: partial,
    skipped_ingredients: skipped
  )
end
```

**Step 4: Update the existing `test_unquantified_ingredients_silently_skipped`**

This test asserts `refute_includes result.missing_ingredients, 'Olive oil'` — that still passes. But the test name says "silently skipped" which is no longer accurate. Rename it to `test_unquantified_ingredients_excluded_from_missing` and keep its assertions. The new tests cover the `skipped_ingredients` behavior.

```ruby
def test_unquantified_ingredients_excluded_from_missing
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 200 g
    - Olive oil

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  assert_in_delta 728, result.totals[:calories], 1
  refute_includes result.missing_ingredients, 'Olive oil'
end
```

**Step 5: Run all calculator tests**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: All pass

**Step 6: Commit**

```
feat: track skipped (unquantified) ingredients in NutritionCalculator
```

---

### Task 2: Serialize `skipped_ingredients` in RecipeNutritionJob

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Test: `test/jobs/recipe_nutrition_job_test.rb`

**Step 1: Write the failing test**

Add to `test/jobs/recipe_nutrition_job_test.rb`:

```ruby
test 'records skipped ingredients for unquantified items' do
  markdown = "# Salad\n\n\n## Toss\n\n- Flour, 30 g\n- Pepper\n\nToss."
  recipe = import_without_nutrition(markdown)

  RecipeNutritionJob.perform_now(recipe)
  recipe.reload

  assert_includes recipe.nutrition_data['skipped_ingredients'], 'Pepper'
  refute_includes recipe.nutrition_data['missing_ingredients'], 'Pepper'
end
```

**Step 2: Run test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n 'test_records_skipped_ingredients'`
Expected: FAIL — `nutrition_data['skipped_ingredients']` is nil

**Step 3: Add serialization**

In `app/jobs/recipe_nutrition_job.rb`, update `serialize_result` to include `skipped_ingredients`:

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
    'missing_ingredients' => result.missing_ingredients,
    'partial_ingredients' => result.partial_ingredients,
    'skipped_ingredients' => result.skipped_ingredients
  }
end
```

**Step 4: Run all job tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All pass

**Step 5: Commit**

```
feat: serialize skipped_ingredients in RecipeNutritionJob
```

---

### Task 3: Update view and helper to render three distinct notes

**Files:**
- Modify: `app/helpers/recipes_helper.rb`
- Modify: `app/views/recipes/_nutrition_table.html.erb`

**Step 1: Update the helper**

In `app/helpers/recipes_helper.rb`, replace `nutrition_missing_ingredients` with three separate methods:

```ruby
def nutrition_missing_ingredients(nutrition)
  nutrition['missing_ingredients'] || []
end

def nutrition_partial_ingredients(nutrition)
  nutrition['partial_ingredients'] || []
end

def nutrition_skipped_ingredients(nutrition)
  nutrition['skipped_ingredients'] || []
end
```

**Step 2: Update the view**

Replace the existing note block (lines 24-32) in `app/views/recipes/_nutrition_table.html.erb` with three separate notes:

```erb
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
```

Note: skipped ingredients are plain text, not clickable buttons — the fix is to add quantities in the recipe, not in the catalog.

**Step 3: Run the full test suite to check for regressions**

Run: `rake test`
Expected: All pass. There are no existing view tests for the nutrition note, so no test updates needed.

**Step 4: Update `html_safe_allowlist.yml` if needed**

Run: `rake lint:html_safe`
If any line numbers shifted for existing `.html_safe` calls in `recipes_helper.rb`, update `config/html_safe_allowlist.yml`.

**Step 5: Commit**

```
feat: render three distinct nutrition notes (missing, partial, skipped)
```

---

### Task 4: Fix Eggs seed data — add `~unitless` portion

**Files:**
- Modify: `db/seeds/resources/ingredient-catalog.yaml`

**Step 1: Add `~unitless` to Eggs entry**

In the Eggs entry's `portions` block, add `"~unitless": 50` (50g = one large egg, matching the existing `large` portion — the standard assumption for bare "Eggs, 4" in recipes):

```yaml
  portions:
    "~unitless": 50.0
    large: 50.0
    small: 38.0
    medium: 44.0
    extra large: 56.0
    jumbo: 63.0
```

**Step 2: Run `rake catalog:sync` to push change into the database**

Run: `rake catalog:sync`
Expected: Eggs entry updated with new portion

**Step 3: Verify with a quick manual check**

Run: `rails runner "e = IngredientCatalog.find_by(ingredient_name: 'Eggs', kitchen_id: nil); puts e.portions"`
Expected: Shows `~unitless` key with value 50.0

**Step 4: Commit**

```
fix: add ~unitless portion to Eggs seed data (50g = 1 large egg)
```

---

### Task 5: Run full lint and test suite

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses

**Step 2: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: Pass (allowlist up to date)

**Step 3: Run full test suite**

Run: `rake test`
Expected: All pass

**Step 4: Final commit if any fixups needed**

Only commit if lint/test required changes.

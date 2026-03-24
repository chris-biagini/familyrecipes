# Ingredient Tooltips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display per-ingredient gram weight and nutrition as native browser tooltips (`title` attribute) on recipe ingredient list items.

**Architecture:** `NutritionCalculator` captures per-ingredient detail during its existing accumulation loop, stores it in the existing `nutrition_data` JSON column via a new `ingredient_details` field on `Result`. The `RecipesHelper#ingredient_data_attrs` method reads this data and sets the `title` attribute on each ingredient `<li>`. No new JavaScript, CSS, migrations, or Stimulus controllers.

**Tech Stack:** Ruby/Rails, Minitest

**Spec:** `docs/plans/2026-03-18-ingredient-tooltips-design.md`

---

### Task 1: NutritionCalculator — capture per-ingredient details

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb`
- Test: `test/nutrition_calculator_test.rb`

The calculator already iterates ingredients and resolves each to grams. We add
an `IngredientDetail` data class and populate a `details` hash during
accumulation. `Result` gains an `ingredient_details` field.

**Design decisions:**
- Store all 11 nutrients (not just the 6 tooltip ones) — simpler accumulation,
  future-proof, trivial storage cost. Filtering to the 6 display nutrients
  happens in the helper.
- Tooltip nutrient abbreviations (`Cal`, `Pro`, `Fat`, `Carb`) are defined in
  the helper, not derived from `NutritionConstraints::NUTRIENT_DEFS`.

- [ ] **Step 1: Write failing test — resolved ingredient has details**

In `test/nutrition_calculator_test.rb`, add after the existing `test_gram_based_calculation`:

```ruby
def test_ingredient_details_for_resolved_ingredient
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 500 g

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  detail = result.ingredient_details['Flour (all-purpose)']
  refute_nil detail
  assert_in_delta 500, detail.grams, 0.1
  assert_in_delta 1820, detail.nutrients[:calories], 1
  assert_in_delta 51.65, detail.nutrients[:protein], 0.1
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n test_ingredient_details_for_resolved_ingredient`
Expected: FAIL — `Result` doesn't have `ingredient_details` yet.

- [ ] **Step 3: Write failing test — missing/partial/skipped have no details**

```ruby
def test_ingredient_details_excludes_unresolved
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Unicorn dust, 50 g
    - Flour (all-purpose), 2 bushels
    - Olive oil

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  assert_nil result.ingredient_details['Unicorn dust']
  assert_nil result.ingredient_details['Flour (all-purpose)']
  assert_nil result.ingredient_details['Olive oil']
end
```

- [ ] **Step 4: Write failing test — multi-step aggregation in details**

```ruby
def test_ingredient_details_aggregates_across_steps
  recipe = make_recipe(<<~MD)
    # Test


    ## Step 1 (first)

    - Butter, 50 g

    First.

    ## Step 2 (second)

    - Butter, 100 g

    Second.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  detail = result.ingredient_details['Butter']
  refute_nil detail
  assert_in_delta 150, detail.grams, 0.1
  assert_in_delta 1075.5, detail.nutrients[:calories], 1
end
```

- [ ] **Step 5: Write failing test — as_json includes ingredient_details**

```ruby
def test_as_json_includes_ingredient_details
  recipe = make_recipe(<<~MD)
    # Test


    ## Mix (combine)

    - Flour (all-purpose), 100 g

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)
  json = result.as_json

  detail = json['ingredient_details']['Flour (all-purpose)']
  refute_nil detail
  assert_instance_of Float, detail['grams']
  assert_instance_of Float, detail['nutrients']['calories']
end
```

- [ ] **Step 6: Implement IngredientDetail and Result changes**

In `lib/familyrecipes/nutrition_calculator.rb`:

1. Add `IngredientDetail` data class inside the `NutritionCalculator` class:

```ruby
IngredientDetail = Data.define(:grams, :nutrients)
```

2. Add `ingredient_details` to the `Result` definition:

```ruby
Result = Data.define(
  :totals, :serving_count, :per_serving, :per_unit,
  :makes_quantity, :makes_unit_singular, :makes_unit_plural,
  :units_per_serving, :total_weight_grams,
  :missing_ingredients, :partial_ingredients, :skipped_ingredients,
  :ingredient_details
)
```

3. Update `as_json` to serialize `ingredient_details`:

In the `as_json` method on `Result`, add serialization for `ingredient_details`
after the existing transform blocks:

```ruby
h['ingredient_details'] = h['ingredient_details']&.transform_values do |detail|
  { 'grams' => detail.grams.to_f,
    'nutrients' => detail.nutrients.transform_keys(&:to_s).transform_values(&:to_f) }
end
```

4. Update `sum_totals` to build and return the details hash:

```ruby
def sum_totals(recipe, recipe_map)
  active = recipe.all_ingredients_with_quantities(recipe_map)
                 .reject { |name, _| @omit_set.include?(name.downcase) }
  known, unknown = active.partition { |name, _| @nutrition_data.key?(name) }

  totals = NUTRIENTS.index_with { |_n| 0.0 }
  weight = { grams: 0.0 }
  details = {}
  missing, partial, skipped = partition_ingredients(totals, weight, details, known, unknown)
  [totals, weight[:grams], missing, partial, skipped, details]
end
```

5. Update `partition_ingredients` to accept and pass `details`:

```ruby
def partition_ingredients(totals, weight, details, known, unknown)
  known_quantified, known_skipped = split_by_quantified(known)
  unknown_quantified, unknown_skipped = split_by_quantified(unknown)

  partial = known_quantified.each_with_object([]) do |(name, amounts), partials|
    accumulate_amounts(totals, weight, details, partials, name, amounts, @nutrition_data[name])
  end

  skipped = known_skipped.map(&:first).concat(unknown_skipped.map(&:first))
  [unknown_quantified.map(&:first), partial, skipped]
end
```

6. Update `accumulate_amounts` to build `IngredientDetail`:

```ruby
def accumulate_amounts(totals, weight, details, partial, name, amounts, entry) # rubocop:disable Metrics/ParameterLists
  ingredient_grams = 0.0
  ingredient_nutrients = NUTRIENTS.index_with { |_n| 0.0 }

  amounts.each do |amount|
    next if amount.nil? || amount.value.nil?

    grams = UnitResolver.new(entry).to_grams(amount.value, amount.unit)
    if grams.nil?
      partial << name unless partial.include?(name)
      next
    end

    weight[:grams] += grams
    ingredient_grams += grams
    NUTRIENTS.each do |nutrient|
      contribution = nutrient_per_gram(entry, nutrient) * grams
      totals[nutrient] += contribution
      ingredient_nutrients[nutrient] += contribution
    end
  end

  details[name] = IngredientDetail.new(grams: ingredient_grams, nutrients: ingredient_nutrients) if ingredient_grams.positive?
end
```

7. Update `calculate` to thread `details` through:

```ruby
def calculate(recipe, recipe_map)
  totals, total_weight, missing, partial, skipped, details = sum_totals(recipe, recipe_map)
  serving_count = parse_serving_count(recipe)

  Result.new(
    totals: totals,
    serving_count: serving_count,
    per_serving: divide_nutrients(totals, serving_count),
    total_weight_grams: total_weight,
    **per_unit_metadata(recipe, totals, serving_count),
    missing_ingredients: missing,
    partial_ingredients: partial,
    skipped_ingredients: skipped,
    ingredient_details: details
  )
end
```

- [ ] **Step 7: Fix the existing `test_as_json_coerces_numeric_scalars_to_float` test**

This test constructs a `Result` manually and doesn't include `ingredient_details`.
Add `ingredient_details: {}` to the constructor call.

- [ ] **Step 8: Run all NutritionCalculator tests**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: All pass, including the 4 new tests.

- [ ] **Step 9: Run full test suite**

Run: `rake test`
Expected: All green. No other code references `Result.new` directly besides
the test, so the new field with default shouldn't break anything — but verify.

- [ ] **Step 10: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "Add per-ingredient detail capture to NutritionCalculator

NutritionCalculator now builds an IngredientDetail (grams + nutrients)
per resolved ingredient during accumulation. Stored in Result#ingredient_details,
serialized to JSON alongside existing nutrition data."
```

---

### Task 2: Helper — build title attributes from ingredient details

**Files:**
- Modify: `app/helpers/recipes_helper.rb`
- Test: `test/helpers/recipes_helper_test.rb`

The helper gains a private `ingredient_tooltip` method that builds the title
string, and `ingredient_data_attrs` gains an `ingredient_info:` keyword.

**Tooltip nutrient abbreviations** (defined as a constant in the helper):

```ruby
TOOLTIP_NUTRIENTS = [
  [:calories, 'Cal', ''],
  [:protein, 'Pro', 'g'],
  [:fat, 'Fat', 'g'],
  [:carbs, 'Carb', 'g'],
  [:sodium, 'Sodium', 'mg'],
  [:fiber, 'Fiber', 'g']
].freeze
```

- [ ] **Step 1: Write failing test — resolved ingredient gets title with grams and nutrition**

In `test/helpers/recipes_helper_test.rb`:

```ruby
test 'ingredient_data_attrs includes title for resolved ingredient' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
  info = {
    'ingredient_details' => {
      'flour' => { 'grams' => 250.0, 'nutrients' => {
        'calories' => 820.0, 'protein' => 12.0, 'fat' => 2.0,
        'carbs' => 170.0, 'sodium' => 5.0, 'fiber' => 4.0
      } }
    },
    'missing_ingredients' => [],
    'partial_ingredients' => []
  }
  attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

  assert_includes attrs, 'title='
  assert_includes attrs, '250g'
  assert_includes attrs, 'Cal 820'
  assert_includes attrs, 'Pro 12g'
  assert_includes attrs, 'based on original quantities'
end
```

- [ ] **Step 2: Write failing test — missing ingredient gets catalog nudge**

```ruby
test 'ingredient_data_attrs title for missing ingredient' do
  ingredient = Ingredient.new(name: 'Unicorn dust', quantity_low: 1.0, unit: 'cup')
  info = {
    'ingredient_details' => {},
    'missing_ingredients' => ['Unicorn dust'],
    'partial_ingredients' => []
  }
  attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

  assert_includes attrs, 'Not in ingredient catalog'
end
```

- [ ] **Step 3: Write failing test — partial ingredient gets conversion message**

```ruby
test 'ingredient_data_attrs title for partial ingredient' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'bushel')
  info = {
    'ingredient_details' => {},
    'missing_ingredients' => [],
    'partial_ingredients' => ['Flour']
  }
  attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

  assert_includes attrs, "can&#39;t convert this unit"
end
```

- [ ] **Step 4: Write failing test — no ingredient_info means no title**

```ruby
test 'ingredient_data_attrs omits title when ingredient_info is nil' do
  ingredient = Ingredient.new(name: 'Flour', quantity_low: 2.0, unit: 'cup')
  attrs = ingredient_data_attrs(ingredient)

  assert_not_includes attrs, 'title='
end
```

- [ ] **Step 5: Write failing test — skipped ingredient (no quantity) gets no title**

```ruby
test 'ingredient_data_attrs omits title for skipped ingredient' do
  ingredient = Ingredient.new(name: 'Olive oil', quantity: nil)
  info = {
    'ingredient_details' => {},
    'missing_ingredients' => [],
    'partial_ingredients' => []
  }
  attrs = ingredient_data_attrs(ingredient, ingredient_info: info)

  assert_not_includes attrs, 'title='
end
```

- [ ] **Step 6: Run tests to verify they all fail**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: 5 new tests fail (unknown keyword `ingredient_info`).

- [ ] **Step 7: Implement the helper changes**

In `app/helpers/recipes_helper.rb`:

1. Add the `TOOLTIP_NUTRIENTS` constant near the top (after `NUTRITION_ROWS`):

```ruby
TOOLTIP_NUTRIENTS = [
  [:calories, 'Cal', ''],
  [:protein, 'Pro', 'g'],
  [:fat, 'Fat', 'g'],
  [:carbs, 'Carb', 'g'],
  [:sodium, 'Sodium', 'mg'],
  [:fiber, 'Fiber', 'g']
].freeze
```

2. Update `ingredient_data_attrs` signature and add title logic. The current
   signature is `ingredient_data_attrs(item, scale_factor: 1.0)`. Change to:

```ruby
def ingredient_data_attrs(item, scale_factor: 1.0, ingredient_info: nil)
  attrs = {}
  attrs[:title] = ingredient_tooltip(item, ingredient_info) if ingredient_info
  return tag.attributes(attrs) unless item.quantity_low

  attrs[:'data-quantity-low'] = item.quantity_low.to_f * scale_factor
  # ... rest unchanged ...

  tag.attributes(attrs)
end
```

3. Add private helper methods:

```ruby
def ingredient_tooltip(item, info)
  name_key = item.name.downcase
  detail = info['ingredient_details']&.dig(name_key)

  return resolved_tooltip(item, detail) if detail
  return 'Not in ingredient catalog' if info['missing_ingredients']&.include?(item.name)
  return "In catalog, but can't convert this unit" if info['partial_ingredients']&.include?(item.name)

  nil
end

def resolved_tooltip(item, detail)
  grams = detail['grams'].round
  quantity_str = item.quantity_display
  lines = ["#{quantity_str} \u2192 #{grams}g"]
  lines << tooltip_nutrient_line(detail['nutrients'], TOOLTIP_NUTRIENTS[0..3])
  lines << tooltip_nutrient_line(detail['nutrients'], TOOLTIP_NUTRIENTS[4..5])
  lines << '(based on original quantities)'
  lines.join("\n")
end

def tooltip_nutrient_line(nutrients, defs)
  defs.map { |key, label, unit| "#{label} #{nutrients[key.to_s].round}#{unit}" }.join(' | ')
end
```

Note: `ingredient_tooltip` returns `nil` for skipped ingredients (no quantity),
which means no `title` attribute is set — matching the spec.

- [ ] **Step 8: Run helper tests**

Run: `ruby -Itest test/helpers/recipes_helper_test.rb`
Expected: All pass, including existing tests (the new keyword arg defaults to nil).

- [ ] **Step 9: Run full test suite**

Run: `rake test`
Expected: All green. Existing call sites in views pass no `ingredient_info:`
keyword, so they get `nil` and behave identically to before.

- [ ] **Step 10: Commit**

```bash
git add app/helpers/recipes_helper.rb test/helpers/recipes_helper_test.rb
git commit -m "Add ingredient tooltip titles to recipe helper

ingredient_data_attrs now accepts ingredient_info: and sets a title
attribute with gram weight, nutrition summary, or catalog nudge."
```

---

### Task 3: View plumbing — thread ingredient_info to the step partial

**Files:**
- Modify: `app/views/recipes/_recipe_content.html.erb`
- Modify: `app/views/recipes/_step.html.erb`
- Test: `test/controllers/recipes_controller_test.rb`

Pass `ingredient_info` extracted from `@nutrition` down through the partials.
Embedded recipes pass `nil` (no tooltips for cross-referenced steps).

- [ ] **Step 1: Write failing integration test**

In `test/controllers/recipes_controller_test.rb`, add a test that verifies the
title attribute appears on ingredient `<li>` elements. This requires a recipe
with nutrition data. Find the existing pattern for recipe show tests in the file
and add:

```ruby
test 'show renders ingredient tooltip title when nutrition data present' do
  recipe = current_kitchen.recipes.first
  recipe.update_column(:nutrition_data, { # rubocop:disable Rails/SkipsModelValidations
    'ingredient_details' => {
      recipe.steps.first.ingredients.first.name.downcase => {
        'grams' => 250.0,
        'nutrients' => {
          'calories' => 820.0, 'protein' => 12.0, 'fat' => 2.0,
          'carbs' => 170.0, 'sodium' => 5.0, 'fiber' => 4.0
        }
      }
    },
    'missing_ingredients' => [],
    'partial_ingredients' => [],
    'skipped_ingredients' => [],
    'totals' => { 'calories' => 820.0 }
  })

  get recipe_path(recipe.slug)

  assert_response :success
  assert_select '.ingredients li[title]'
end
```

Note: check the existing test file first for the correct setup pattern (likely
uses `create_kitchen_and_user` and `log_in`). Adapt accordingly. The key
assertion is `assert_select '.ingredients li[title]'`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_show_renders_ingredient_tooltip_title_when_nutrition_data_present`
Expected: FAIL — no `title` on `<li>` elements yet.

- [ ] **Step 3: Update `_recipe_content.html.erb`**

Extract `ingredient_info` from `nutrition` and pass to the step partial.
Change the step render loop from:

```erb
<% recipe.steps.each do |step| %>
  <%= render 'recipes/step', step: step, embedded: false, heading_level: 2, scale_factor: 1.0 %>
<% end %>
```

To:

```erb
<% ingredient_info = nutrition&.slice('ingredient_details', 'missing_ingredients', 'partial_ingredients') %>
<% recipe.steps.each do |step| %>
  <%= render 'recipes/step', step: step, embedded: false, heading_level: 2, scale_factor: 1.0, ingredient_info: ingredient_info %>
<% end %>
```

- [ ] **Step 4: Update `_step.html.erb`**

1. Update the locals declaration at the top:

```erb
<%# locals: (step:, embedded: false, heading_level: 2, scale_factor: 1.0, ingredient_info: nil) %>
```

2. Update the `ingredient_data_attrs` call to pass through `ingredient_info`:

```erb
<li <%= ingredient_data_attrs(item, scale_factor: scale_factor, ingredient_info: ingredient_info) %>>
```

- [ ] **Step 5: Verify `_embedded_recipe.html.erb` passes nil (no change needed)**

The embedded recipe partial renders steps without `ingredient_info:`, so the
default `nil` applies. No change needed — just verify it still works by running
the full test suite.

- [ ] **Step 6: Run the integration test**

Run: `ruby -Itest test/controllers/recipes_controller_test.rb -n test_show_renders_ingredient_tooltip_title_when_nutrition_data_present`
Expected: PASS.

- [ ] **Step 7: Run full test suite**

Run: `rake test`
Expected: All green.

- [ ] **Step 8: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses. If the `html_safe_allowlist.yml` line numbers shifted,
update them.

- [ ] **Step 9: Commit**

```bash
git add app/views/recipes/_recipe_content.html.erb app/views/recipes/_step.html.erb test/controllers/recipes_controller_test.rb
git commit -m "Thread ingredient_info to step partial for tooltip rendering

Extracts ingredient_details, missing, and partial lists from nutrition
data and passes through _recipe_content → _step → ingredient_data_attrs."
```

---

### Task 4: Backfill existing recipes and verify end-to-end

**Files:**
- No code changes — this task runs the existing `RecipeNutritionJob` to
  regenerate `nutrition_data` with the new `ingredient_details` field.

Since `RecipeNutritionJob` already calls `result.as_json` and writes the full
result, re-running it for each recipe will populate `ingredient_details`.

- [ ] **Step 1: Write a one-time migration to nullify nutrition_data**

Create a migration file in `db/migrate/` following the sequential numbering
convention. Check the highest-numbered existing migration and increment.

Per CLAUDE.md: never call application models, services, or jobs from migrations.
Instead, nullify the column so the next `RecipeNutritionJob` run repopulates it
with the new `ingredient_details` field.

```ruby
class NullifyNutritionDataForRecompute < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE recipes SET nutrition_data = NULL"
  end

  def down
    # No rollback needed — nutrition_data is recomputed on every recipe save
  end
end
```

- [ ] **Step 2: Run the migration, then recompute via rails runner**

Run: `rails db:migrate`

Then recompute nutrition for all recipes outside the migration context:

Run: `rails runner 'Kitchen.find_each { |k| r = IngredientCatalog.resolver_for(k); next if r.lookup.empty?; k.recipes.find_each { |recipe| RecipeNutritionJob.perform_now(recipe, resolver: r) } }'`

Expected: Success. Recipes now have `ingredient_details` in their
`nutrition_data` JSON.

- [ ] **Step 3: Manual verification**

Start the dev server (`bin/dev`) and open a recipe that has ingredients with
catalog entries. Hover over an ingredient — you should see the tooltip with
grams and nutrition. Check:
- Resolved ingredient: shows `"2 cups → 250g"` + nutrients
- Missing ingredient (if any): shows `"Not in ingredient catalog"`
- Ingredient without quantity: no tooltip

- [ ] **Step 4: Commit the migration**

```bash
git add db/migrate/
git commit -m "Recompute nutrition data to populate ingredient details

Backfills ingredient_details in nutrition_data JSON for all existing
recipes."
```

- [ ] **Step 5: Run full test suite one final time**

Run: `rake`
Expected: All tests pass, no lint offenses.

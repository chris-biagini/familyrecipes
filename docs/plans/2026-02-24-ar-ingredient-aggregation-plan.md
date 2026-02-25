# AR Ingredient Aggregation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate recipe re-parsing in ShoppingListBuilder and RecipeNutritionJob by adding ingredient aggregation methods to AR models.

**Architecture:** Add `own_ingredients_aggregated` and `all_ingredients_with_quantities` to AR `Recipe`, add `expanded_ingredients` to AR `CrossReference`. Both services switch from parser instantiation to AR method calls. `NutritionCalculator` works unchanged via duck typing.

**Tech Stack:** Rails AR models, existing `IngredientAggregator` module, `Quantity` value object.

---

### Task 1: Add `expanded_ingredients` to AR CrossReference

**Files:**
- Modify: `app/models/cross_reference.rb`
- Test: `test/models/cross_reference_test.rb`

**Step 1: Write the failing tests**

Add these tests to `test/models/cross_reference_test.rb`, inside a new test class at the end of the file:

```ruby
class CrossReferenceExpandedIngredientsTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')

    # Target recipe: Poolish with "Flour, 2 cups" and "Water, 1 cup"
    @target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category, markdown_source: "# Poolish\n\nCategory: Bread\n\n## Mix\n\n- Flour, 2 cups\n- Water, 1 cup\n\nMix."
    )
    target_step = @target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Water', quantity: '1', unit: 'cup', position: 2)

    # Parent recipe with a cross-reference to Poolish
    @recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: "# Focaccia\n\nCategory: Bread\n\n## Mix\n\n- @[Poolish]\n\nMix."
    )
    @step = @recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
  end

  test 'expanded_ingredients returns target ingredients with default multiplier' do
    xref = CrossReference.create!(
      step: @step, target_recipe: @target, position: 1,
      target_slug: 'poolish', target_title: 'Poolish'
    )

    result = xref.expanded_ingredients

    assert_equal 2, result.size
    flour = result.find { |name, _| name == 'Flour' }
    assert flour, 'Expected Flour in expanded ingredients'
    assert_in_delta 2.0, flour[1].first.value, 0.01
    assert_equal 'cup', flour[1].first.unit
  end

  test 'expanded_ingredients scales by multiplier' do
    xref = CrossReference.create!(
      step: @step, target_recipe: @target, position: 1,
      target_slug: 'poolish', target_title: 'Poolish', multiplier: 0.5
    )

    result = xref.expanded_ingredients

    flour = result.find { |name, _| name == 'Flour' }
    assert_in_delta 1.0, flour[1].first.value, 0.01
  end

  test 'expanded_ingredients returns empty array when target_recipe is nil' do
    xref = CrossReference.create!(
      step: @step, position: 1,
      target_slug: 'nonexistent', target_title: 'Nonexistent'
    )

    assert_empty xref.expanded_ingredients
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/cross_reference_test.rb -n /expanded_ingredients/`
Expected: FAIL — `NoMethodError: undefined method 'expanded_ingredients'`

**Step 3: Implement `expanded_ingredients` on AR CrossReference**

Add to `app/models/cross_reference.rb`, before the `self.resolve_pending` class method:

```ruby
def expanded_ingredients
  return [] unless target_recipe

  target_recipe.own_ingredients_aggregated.map do |name, amounts|
    scaled = amounts.map do |amount|
      next unless amount

      Quantity[amount.value * multiplier, amount.unit]
    end
    [name, scaled]
  end
end
```

Note: This depends on `Recipe#own_ingredients_aggregated` from Task 2. For now, tests will fail with a different error (undefined method on Recipe). That's expected — Task 2 completes the chain.

**Step 4: Commit work in progress**

```bash
git add app/models/cross_reference.rb test/models/cross_reference_test.rb
git commit -m "feat: add expanded_ingredients to AR CrossReference (#90)"
```

---

### Task 2: Add `own_ingredients_aggregated` and `all_ingredients_with_quantities` to AR Recipe

**Files:**
- Modify: `app/models/recipe.rb`
- Create: `test/models/recipe_aggregation_test.rb`

**Step 1: Write the failing tests**

Create `test/models/recipe_aggregation_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'

class RecipeAggregationTest < ActiveSupport::TestCase
  setup do
    @kitchen = Kitchen.find_or_create_by!(name: 'Test Kitchen', slug: 'test-kitchen')
    ActsAsTenant.current_tenant = @kitchen

    @category = Category.find_or_create_by!(name: 'Bread', slug: 'bread')
  end

  test 'own_ingredients_aggregated groups by name and sums quantities' do
    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: 'placeholder'
    )
    step1 = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step1.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)
    step2 = recipe.steps.find_or_create_by!(title: 'Knead', position: 2)
    step2.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)
    step2.ingredients.find_or_create_by!(name: 'Salt', quantity: '1', unit: 'tsp', position: 2)

    result = recipe.own_ingredients_aggregated

    assert result.key?('Flour')
    flour_cup = result['Flour'].find { |q| q&.unit == 'cup' }
    assert_in_delta 3.0, flour_cup.value, 0.01
    assert result.key?('Salt')
  end

  test 'own_ingredients_aggregated handles unquantified ingredients' do
    recipe = Recipe.find_or_create_by!(
      title: 'Simple', slug: 'simple',
      category: @category, markdown_source: 'placeholder'
    )
    step = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step.ingredients.find_or_create_by!(name: 'Salt', position: 1)

    result = recipe.own_ingredients_aggregated

    assert result.key?('Salt')
    assert_includes result['Salt'], nil
  end

  test 'all_ingredients_with_quantities includes cross-reference ingredients' do
    target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category, markdown_source: 'placeholder'
    )
    target_step = target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)

    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: 'placeholder'
    )
    step = recipe.steps.find_or_create_by!(title: 'Dough', position: 1)
    step.ingredients.find_or_create_by!(name: 'Salt', quantity: '1', unit: 'tsp', position: 1)
    step.cross_references.find_or_create_by!(
      target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
      position: 2
    )

    result = recipe.all_ingredients_with_quantities

    names = result.map(&:first)
    assert_includes names, 'Salt'
    assert_includes names, 'Flour'
  end

  test 'all_ingredients_with_quantities merges duplicate names from own and xref' do
    target = Recipe.find_or_create_by!(
      title: 'Poolish', slug: 'poolish',
      category: @category, markdown_source: 'placeholder'
    )
    target_step = target.steps.find_or_create_by!(title: 'Mix', position: 1)
    target_step.ingredients.find_or_create_by!(name: 'Flour', quantity: '2', unit: 'cups', position: 1)

    recipe = Recipe.find_or_create_by!(
      title: 'Focaccia', slug: 'focaccia',
      category: @category, markdown_source: 'placeholder'
    )
    step = recipe.steps.find_or_create_by!(title: 'Dough', position: 1)
    step.ingredients.find_or_create_by!(name: 'Flour', quantity: '3', unit: 'cups', position: 1)
    step.cross_references.find_or_create_by!(
      target_recipe: target, target_slug: 'poolish', target_title: 'Poolish',
      position: 2
    )

    result = recipe.all_ingredients_with_quantities
    flour = result.find { |name, _| name == 'Flour' }
    flour_cup = flour[1].find { |q| q&.unit == 'cup' }

    assert_in_delta 5.0, flour_cup.value, 0.01
  end

  test 'all_ingredients_with_quantities accepts optional recipe_map for duck typing' do
    recipe = Recipe.find_or_create_by!(
      title: 'Bread', slug: 'bread',
      category: @category, markdown_source: 'placeholder'
    )
    step = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)

    # Should work with or without the argument
    result_without = recipe.all_ingredients_with_quantities
    result_with = recipe.all_ingredients_with_quantities({})

    assert_equal result_without.map(&:first), result_with.map(&:first)
  end

  test 'all_ingredients_with_quantities skips unresolved cross-references' do
    recipe = Recipe.find_or_create_by!(
      title: 'Bread', slug: 'bread',
      category: @category, markdown_source: 'placeholder'
    )
    step = recipe.steps.find_or_create_by!(title: 'Mix', position: 1)
    step.ingredients.find_or_create_by!(name: 'Flour', quantity: '1', unit: 'cup', position: 1)
    step.cross_references.find_or_create_by!(
      target_slug: 'nonexistent', target_title: 'Nonexistent',
      position: 2
    )

    result = recipe.all_ingredients_with_quantities

    names = result.map(&:first)
    assert_equal ['Flour'], names
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/recipe_aggregation_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'own_ingredients_aggregated'`

**Step 3: Implement both methods on AR Recipe**

Add to `app/models/recipe.rb`, in the public section (before `private`):

```ruby
def own_ingredients_aggregated
  ingredients.group_by(&:name).transform_values do |group|
    IngredientAggregator.aggregate_amounts(group)
  end
end

def all_ingredients_with_quantities(_recipe_map = nil)
  cross_references.each_with_object(own_ingredients_aggregated) do |xref, merged|
    xref.expanded_ingredients.each do |name, amounts|
      merged[name] = merged.key?(name) ? IngredientAggregator.merge_amounts(merged[name], amounts) : amounts
    end
  end.to_a
end
```

**Step 4: Run all aggregation tests**

Run: `ruby -Itest test/models/recipe_aggregation_test.rb`
Expected: All 6 tests PASS

**Step 5: Run CrossReference expanded_ingredients tests (from Task 1)**

Run: `ruby -Itest test/models/cross_reference_test.rb -n /expanded_ingredients/`
Expected: All 3 tests PASS (the chain is now complete)

**Step 6: Commit**

```bash
git add app/models/recipe.rb test/models/recipe_aggregation_test.rb
git commit -m "feat: add ingredient aggregation methods to AR Recipe (#90)"
```

---

### Task 3: Update ShoppingListBuilder to use AR methods

**Files:**
- Modify: `app/services/shopping_list_builder.rb`
- Test: `test/services/shopping_list_builder_test.rb` (existing tests must still pass)

**Step 1: Add a cross-reference integration test**

Add to the end of `test/services/shopping_list_builder_test.rb`:

```ruby
test 'includes cross-referenced recipe ingredients in shopping list' do
  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Poolish

    Category: Bread

    ## Mix (combine)

    - Flour, 1 cup
    - Water, 1 cup

    Mix.
  MD

  MarkdownImporter.import(<<~MD, kitchen: @kitchen)
    # Pizza

    Category: Bread

    ## Dough (assemble)

    - Salt, 1 tsp
    - @[Poolish]

    Make dough.
  MD

  IngredientCatalog.find_or_create_by!(kitchen_id: nil, ingredient_name: 'Water') do |p|
    p.basis_grams = 240
    p.aisle = 'Miscellaneous'
  end

  list = GroceryList.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'pizza', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, grocery_list: list).build
  all_names = result.values.flatten.map { |i| i[:name] }

  assert_includes all_names, 'Salt'
  assert_includes all_names, 'Flour'
  assert_includes all_names, 'Water'
end
```

**Step 2: Run the new test to verify it passes with current code**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /cross-referenced/`
Expected: PASS (current re-parsing code handles this — we're confirming the baseline)

**Step 3: Refactor ShoppingListBuilder**

Replace three methods in `app/services/shopping_list_builder.rb`:

1. **Delete** `build_recipe_map` (lines 68-77 — the re-parsing method).

2. **Replace** `selected_recipes` (line 31-33) with enhanced eager loading:

```ruby
def selected_recipes
  slugs = @grocery_list.state.fetch('selected_recipes', [])
  @kitchen.recipes
    .includes(:category, steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
    .where(slug: slugs)
end
```

3. **Replace** `aggregate_recipe_ingredients` (lines 47-58) to use AR methods:

```ruby
def aggregate_recipe_ingredients
  selected_recipes.each_with_object({}) do |recipe, merged|
    recipe.all_ingredients_with_quantities.each do |name, amounts|
      merged[name] = merged.key?(name) ? IngredientAggregator.merge_amounts(merged[name], amounts) : amounts
    end
  end
end
```

**Step 4: Run all ShoppingListBuilder tests**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: All tests PASS (including the new cross-reference test)

**Step 5: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "refactor: ShoppingListBuilder uses AR aggregation instead of re-parsing (#90)"
```

---

### Task 4: Update RecipeNutritionJob to use AR methods

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Test: `test/jobs/recipe_nutrition_job_test.rb` (existing tests must still pass)

**Step 1: Refactor RecipeNutritionJob**

In `app/jobs/recipe_nutrition_job.rb`:

1. **Replace** the `perform` method to pass the AR recipe directly:

```ruby
def perform(recipe)
  recipe = Recipe.includes(steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }])
                 .find(recipe.id)

  nutrition_data = build_nutrition_lookup(recipe.kitchen)
  return if nutrition_data.empty?

  calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
  result = calculator.calculate(recipe, {})

  recipe.update_column(:nutrition_data, serialize_result(result))
end
```

2. **Delete** `parsed_recipe` method (lines 42-48).

3. **Delete** `recipe_map` method (lines 54-58).

**Step 2: Run all RecipeNutritionJob tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All tests PASS (duck typing means NutritionCalculator works identically)

**Step 3: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb
git commit -m "refactor: RecipeNutritionJob uses AR recipe instead of re-parsing (#90)"
```

---

### Task 5: Full regression test and cleanup

**Files:**
- All modified files from Tasks 1-4

**Step 1: Run the full test suite**

Run: `rake test`
Expected: All tests pass, no regressions

**Step 2: Run lint**

Run: `rake lint`
Expected: No new offenses

**Step 3: Verify no remaining parser instantiation in services**

Confirm that `FamilyRecipes::Recipe.new` no longer appears in `app/services/` or `app/jobs/`:

Run: `grep -r "FamilyRecipes::Recipe.new" app/services/ app/jobs/`
Expected: No output (zero matches)

**Step 4: Final commit closing the issue**

```bash
git add -A
git commit -m "chore: close #90 — AR ingredient aggregation eliminates recipe re-parsing"
```

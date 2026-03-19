# Nutrition Pipeline Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make RecipeNutritionJob always write to `nutrition_data` and log failures visibly, eliminating silent nutrition loss.

**Architecture:** Remove the silent early return on empty catalog and add a rescue with logging. The calculator already handles missing ingredients gracefully — we just need to stop short-circuiting before it runs.

**Tech Stack:** Rails 8, Minitest, ActiveJob

**Spec:** `docs/superpowers/specs/2026-03-19-nutrition-pipeline-resilience-design.md`

---

### Task 1: Update existing test — empty catalog writes result instead of nil

**Files:**
- Modify: `test/jobs/recipe_nutrition_job_test.rb:40-50`

- [ ] **Step 1: Update the "handles recipe with no nutrition entries gracefully" test**

The test currently asserts `assert_nil recipe.nutrition_data`. Change it to
assert that nutrition_data is present with zero-value totals and the
ingredient listed in `missing_ingredients`.

```ruby
test 'writes valid result when catalog is empty' do
  IngredientCatalog.destroy_all

  markdown = "# Salad\n\n\n## Toss\n\n- Lettuce, 1 head\n\nToss."
  recipe = import_without_nutrition(markdown)

  RecipeNutritionJob.perform_now(recipe)
  recipe.reload

  assert_predicate recipe.nutrition_data, :present?
  assert_equal 0, recipe.nutrition_data['totals']['calories']
  assert_includes recipe.nutrition_data['missing_ingredients'], 'Lettuce'
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n test_writes_valid_result_when_catalog_is_empty`

Expected: FAIL — the job still returns early and leaves nutrition_data nil.

- [ ] **Step 3: Commit failing test**

```bash
git add test/jobs/recipe_nutrition_job_test.rb
git commit -m "Test: empty catalog should write valid result, not nil"
```

---

### Task 2: Fix RecipeNutritionJob — remove early return, add rescue

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`

- [ ] **Step 1: Update the perform method**

Replace the current `perform` method with:

```ruby
def perform(recipe, resolver: nil)
  loaded = eager_load_recipe(recipe)
  resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)

  if resolver.lookup.empty?
    Rails.logger.warn { "Nutrition: empty catalog for kitchen #{loaded.kitchen_id}, recipe #{recipe.id}" }
  end

  calculator = FamilyRecipes::NutritionCalculator.new(resolver.lookup, omit_set: resolver.omit_set)
  result = calculator.calculate(loaded, {})
  recipe.update_column(:nutrition_data, result.as_json) # rubocop:disable Rails/SkipsModelValidations
rescue StandardError => e
  Rails.logger.error { "Nutrition failed for recipe #{recipe.id}: #{e.message}" }
  raise if Rails.env.test?
end
```

Key changes:
- `return if resolver.lookup.empty?` → log warning and continue
- `rescue StandardError` wraps the whole method, logs error
- `raise if Rails.env.test?` re-raises in test so failures surface

- [ ] **Step 2: Update the header comment**

Update the header comment to reflect the new behavior — the job now always
writes to `nutrition_data` and never silently skips.

- [ ] **Step 3: Run the failing test from Task 1**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n test_writes_valid_result_when_catalog_is_empty`

Expected: PASS

- [ ] **Step 4: Run the full test file**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`

Expected: All tests pass. The existing tests should be unaffected — the
only behavioral change is for the empty-catalog case.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb
git commit -m "Make RecipeNutritionJob always write nutrition_data

Remove silent early return on empty catalog — the calculator handles
missing ingredients gracefully. Add rescue with logging so failures
are visible, not silent. Re-raise in test environment."
```

---

### Task 3: Add test — exception is rescued and logged

**Files:**
- Modify: `test/jobs/recipe_nutrition_job_test.rb`

- [ ] **Step 1: Write the test**

Test that when NutritionCalculator raises, the exception is rescued (in
non-test env) and previous nutrition_data is retained. Since we're in
test env where `raise if Rails.env.test?` re-raises, use
`assert_raises` to verify the exception propagates in test.

```ruby
test 'rescues and re-raises computation errors in test' do
  markdown = "# Bread\n\nServes: 2\n\n## Mix\n\n- Flour, 60 g\n\nMix."
  recipe = import_without_nutrition(markdown)
  recipe.update_column(:nutrition_data, { 'previous' => true }) # rubocop:disable Rails/SkipsModelValidations

  resolver = Minitest::Mock.new
  resolver.expect(:lookup, nil) { raise StandardError, 'calculator boom' }

  assert_raises(StandardError) do
    RecipeNutritionJob.perform_now(recipe, resolver:)
  end

  assert recipe.reload.nutrition_data['previous'],
         'previous nutrition_data should be retained on failure'
end
```

Note: The mock approach above may need adjustment depending on what
`resolver.lookup` returns and how the error is triggered. The key
assertion is that `nutrition_data` retains its previous value. An
alternative approach: stub `FamilyRecipes::NutritionCalculator.new`
to raise. Use whichever approach works cleanly with the codebase's
test patterns.

- [ ] **Step 2: Run test to verify it passes**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb -n test_rescues_and_re_raises_computation_errors_in_test`

Expected: PASS — the rescue catches the error, logs it, then re-raises
in test env. `assert_raises` catches the re-raise.

- [ ] **Step 3: Commit**

```bash
git add test/jobs/recipe_nutrition_job_test.rb
git commit -m "Test: verify nutrition errors are rescued and re-raised in test"
```

---

### Task 4: Update rake task — remove empty-catalog skip

**Files:**
- Modify: `lib/tasks/nutrition.rake`

- [ ] **Step 1: Remove the resolver.lookup.empty? guard**

The rake task currently skips kitchens with empty catalogs. Now that
`RecipeNutritionJob` handles this gracefully, the rake task should
delegate to the job and let it log warnings. Keep only the zero-recipes
skip.

```ruby
namespace :nutrition do
  desc 'Recompute nutrition_data for all recipes in all kitchens'
  task recompute: :environment do
    Kitchen.find_each do |kitchen|
      ActsAsTenant.with_tenant(kitchen) do
        recipes = kitchen.recipes
        count = recipes.size

        if count.zero?
          puts "#{kitchen.name}: no recipes — skipping."
          next
        end

        resolver = IngredientCatalog.resolver_for(kitchen)
        recipes.find_each { |recipe| RecipeNutritionJob.perform_now(recipe, resolver:) }
        puts "#{kitchen.name}: recomputed nutrition for #{count} recipes."
      end
    end
  end
end
```

- [ ] **Step 2: Run the rake task to verify it works**

Run: `bundle exec rake nutrition:recompute`

Expected: Completes successfully, prints recipe count per kitchen.

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/nutrition.rake
git commit -m "Remove empty-catalog skip from nutrition:recompute

RecipeNutritionJob now handles empty catalogs gracefully, so the
rake task should delegate rather than duplicate the guard."
```

---

### Task 5: Run full test suite and lint

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `bundle exec rake test`

Expected: All tests pass.

- [ ] **Step 2: Run lint**

Run: `bundle exec rubocop`

Expected: No offenses. The `rubocop:disable` comment on `update_column`
is preserved.

- [ ] **Step 3: Final commit if any adjustments needed**

If lint or tests required adjustments, commit those fixes.

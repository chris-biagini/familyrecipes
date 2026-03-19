# Nutrition Pipeline Resilience

## Problem

Nutrition data silently disappears from all recipes at once and stays missing
even after re-saving. The root cause: `RecipeNutritionJob` silently returns
early when the ingredient catalog resolver is empty, leaving `nutrition_data`
as NULL with no log output, no error, and no indication of failure. Once NULL,
re-saving hits the same empty resolver and silently skips again.

Secondary fragility: the job has no error handling. If `NutritionCalculator`
raises an exception, it propagates unrescued — the recipe is already committed
(nutrition runs after the save transaction), so the recipe persists with NULL
`nutrition_data` permanently.

## Root Causes

1. **Silent early return.** `RecipeNutritionJob` line 17:
   `return if resolver.lookup.empty?` — skips computation, writes nothing,
   logs nothing. When the catalog is empty (bad seed, migration, tenant
   scoping issue), every recipe in the kitchen is silently skipped.

2. **No error handling.** If `NutritionCalculator#calculate` or
   `update_column` raises, the exception propagates. The recipe was already
   committed by `MarkdownImporter#save_recipe`'s transaction, so it exists
   with NULL `nutrition_data`. The failure may or may not surface to the user
   depending on how the controller handles it.

3. **Nutrition runs after the save transaction.** `MarkdownImporter#run`
   commits the recipe in `save_recipe` (transaction), then calls
   `RecipeNutritionJob.perform_now` outside the transaction. This is
   intentional — nutrition shouldn't block recipe saves — but means a
   recipe can exist without nutrition if the job fails.

## Design

### RecipeNutritionJob: Always write, never silently skip

Two changes to the `perform` method:

**A. Remove silent early return on empty catalog.**

Instead of returning when `resolver.lookup.empty?`, log a warning and proceed.
`NutritionCalculator` already handles missing ingredients gracefully — it
categorizes them as `missing_ingredients` and produces a valid `Result` with
zero totals. The view checks `nutrition['totals']&.values&.any? { |v| v.to_f > 0 }`
before rendering the nutrition table, so an all-zero result won't display
broken data. But `nutrition_data` will be a valid JSON object (not NULL), and
the log line makes the empty-catalog condition visible.

**B. Rescue exceptions.**

Wrap the computation in a `rescue StandardError` that logs the error. On
failure, don't write a garbage marker — let `nutrition_data` retain its
previous value. The critical improvement is the log line: the failure is no
longer invisible. Re-raise in test so failures surface immediately rather
than hiding behind log lines. The rescue covers the full method body
(including `eager_load_recipe` and resolver construction), which is
intentional — any failure in the nutrition path should be contained in
production.

The combined flow:

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

### CascadeNutritionJob: Resilience inherited

`CascadeNutritionJob` iterates parent recipes and calls
`RecipeNutritionJob.perform_now` for each. Previously, if one parent failed,
`find_each` would abort and remaining parents would never be recomputed.

With the rescue now inside `RecipeNutritionJob#perform`, each parent's failure
is self-contained. One bad parent won't abort the cascade. No changes needed
to `CascadeNutritionJob` itself.

### Rake task: Update for consistency

`rake nutrition:recompute` was added earlier in this session. It currently
has its own `resolver.lookup.empty?` guard that skips entire kitchens. Update
it to match the job's new behavior: remove the skip, let the job handle
empty catalogs gracefully (log + write zero-total result). The task should
only skip kitchens with zero recipes.

## What we're NOT doing

- **Not moving nutrition inside the save transaction.** Nutrition is a
  nice-to-have — it shouldn't block saving a recipe. If `NutritionCalculator`
  has a bug, a recipe should save with missing nutrition rather than fail to
  save entirely.

- **Not adding a sweep or background job.** If the write path always writes,
  there's nothing to sweep for. The rake task covers intentional invalidation.

- **Not adding computed-on-read fallback.** Keeps the write-path-only
  architecture clean. Avoids latency and N+1 risk on recipe list pages.

## Files Changed

- `app/jobs/recipe_nutrition_job.rb` — remove early return, add rescue +
  logging
- `lib/tasks/nutrition.rake` — remove empty-catalog skip for consistency

## Testing

- Existing test `skips when catalog is empty` must be updated: the job now
  writes a result with zero totals instead of leaving `nutrition_data` nil.
- Add test: exception during computation is rescued and logged, recipe
  retains previous `nutrition_data`.
- Add test: empty catalog produces valid result with all ingredients in
  `missing_ingredients`.

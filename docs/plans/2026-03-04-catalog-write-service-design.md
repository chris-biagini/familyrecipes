# CatalogWriteService Extraction & IngredientRowBuilder

**Date:** 2026-03-04
**Status:** Approved

## Problem

`NutritionEntriesController` is a fat controller doing three jobs: persistence, post-save orchestration (aisle sync, nutrition recalc, broadcasting), and response rendering. Recipe mutations go through `RecipeWriteService`; catalog mutations have no equivalent service — the pattern is inconsistent. Meanwhile, the `IngredientRows` concern lives in `controllers/concerns/` but is consumed by `RecipeBroadcaster` (a service), with a `current_kitchen` fallback that's dead code in that context.

## Approach

**Approach B — Full extraction.** Two new service classes, one deleted concern.

## Design

### IngredientRowBuilder (replaces IngredientRows concern)

Plain service class with explicit constructor args:

```ruby
class IngredientRowBuilder
  def initialize(kitchen:, recipes: nil, lookup: nil)
    @kitchen = kitchen
    @recipes = recipes || kitchen.recipes.includes(steps: :ingredients)
    @lookup  = lookup || IngredientCatalog.lookup_for(kitchen)
  end

  def rows                          # sorted array of row hashes
  def summary                       # { total:, complete:, missing_nutrition:, missing_density: }
  def next_needing_attention(after:) # String or nil
end
```

Private helpers from the concern (`ingredient_row`, `row_status`, `entry_source`, `canonical_ingredient_name`, `recipes_by_ingredient`) move in as private methods, unchanged.

**Consumers:**
- `IngredientsController` — `IngredientRowBuilder.new(kitchen: current_kitchen)`
- `NutritionEntriesController` — `IngredientRowBuilder.new(kitchen: current_kitchen)`
- `RecipeBroadcaster` — `IngredientRowBuilder.new(kitchen:, recipes:, lookup: catalog_lookup)` (passes pre-computed lookup to avoid a redundant query)

The optional `lookup:` kwarg keeps the builder self-contained for simple callers while letting the broadcaster share its existing lookup.

### CatalogWriteService

Mirrors `RecipeWriteService` — owns persistence and the full post-write pipeline.

```ruby
class CatalogWriteService
  Result = Data.define(:entry, :persisted)

  def self.upsert(kitchen:, ingredient_name:, params:)
  def self.destroy(kitchen:, ingredient_name:)
end
```

**`upsert` pipeline:**
1. `find_or_initialize_by(kitchen:, ingredient_name:)`
2. `assign_from_params(**params, sources: WEB_SOURCE)`
3. `save` — return `Result.new(entry:, persisted: false)` on validation failure
4. Post-write: sync aisle to kitchen (if aisle present and not 'omit'), recalculate nutrition for affected recipes (if nutrition data present), broadcast meal-plan refresh
5. Return `Result.new(entry:, persisted: true)`

**`destroy` pipeline:**
1. `find_by!` then `destroy!`
2. Post-write: recalculate affected recipes, broadcast meal-plan refresh (no aisle sync)
3. Return `Result.new(entry:, persisted: true)`

`WEB_SOURCE` moves from the controller to the service.

Nutrition recalculation stays synchronous (`perform_now`) — dataset is small enough today.

### NutritionEntriesController (slimmed)

Becomes a thin adapter: parse params, call service, render response.

- `include IngredientRows` removed — replaced by `IngredientRowBuilder` instantiation in render helpers
- `after_save`, `sync_aisle_to_kitchen`, `recalculate_affected_recipes`, `broadcast_aisle_change` all removed — owned by CatalogWriteService
- `destroy` reduces from inline orchestration to a single service call + rescue

### RecipeBroadcaster update

`include IngredientRows` removed. `broadcast_ingredients` instantiates `IngredientRowBuilder` with the pre-computed `catalog_lookup` to avoid a redundant query.

## What doesn't change

- `IngredientCatalog` model — no changes
- `IngredientsController` — only changes from `include IngredientRows` to `IngredientRowBuilder.new`
- Param parsing stays in the controller (its job)
- Response rendering stays in the controller (its job)
- Nutrition recalc stays synchronous

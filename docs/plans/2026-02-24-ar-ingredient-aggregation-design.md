# AR Ingredient Aggregation — Eliminate Recipe Re-parsing

**Issue:** #90
**Date:** 2026-02-24

## Problem

`ShoppingListBuilder` and `RecipeNutritionJob` re-parse every recipe's markdown via `FamilyRecipes::Recipe.new` to access `all_ingredients_with_quantities`. This runs the full parser pipeline (LineClassifier, RecipeBuilder, IngredientParser) despite all the underlying data already existing in the database.

`ShoppingListBuilder` is the hot path — it re-parses on every grocery page AJAX request. `RecipeNutritionJob` only runs at save time but still parses every recipe in the kitchen to build a recipe map for cross-reference expansion.

## Approach

Add ingredient aggregation methods to the AR `Recipe` and `CrossReference` models. Services call AR methods instead of instantiating parser classes. `NutritionCalculator` works unchanged via duck typing.

## New AR Methods

### `CrossReference#expanded_ingredients`

Follows the `target_recipe` association, gets its own aggregated ingredients, scales each quantity by `multiplier`. Returns an array of `[name, [Quantity, ...]]` pairs. No recipe map needed — uses associations directly.

### `Recipe#own_ingredients_aggregated`

Groups `ingredients` (through `steps`) by name. Sums quantities per unit via `IngredientAggregator.aggregate_amounts`. Returns `{name => [Quantity, ...]}`.

### `Recipe#all_ingredients_with_quantities(_recipe_map = nil)`

Merges own ingredients + expanded cross-reference ingredients. Accepts an optional `recipe_map` argument for duck-type compatibility with `NutritionCalculator`, but ignores it (uses associations instead).

## Duck Typing

`NutritionCalculator` calls these methods on whatever recipe object it receives:

| Method | Parser `FamilyRecipes::Recipe` | AR `Recipe` |
|--------|-------------------------------|-------------|
| `all_ingredients_with_quantities(map)` | Parser logic | New AR method (ignores map) |
| `serves` | Parsed from front matter | Column |
| `makes` | Parsed from front matter | Existing method |
| `makes_quantity` | Parsed from front matter | Column |
| `makes_unit_noun` | Parsed from front matter | Column |

Zero changes to `NutritionCalculator`.

## Eager Loading

### ShoppingListBuilder

```ruby
selected_recipes.includes(
  :category,
  steps: [:ingredients, { cross_references: { target_recipe: { steps: :ingredients } } }]
)
```

One query with JOINs. No N+1 during cross-reference expansion.

### RecipeNutritionJob

Eager-load on the single recipe record before passing to the calculator.

## Service Changes

### ShoppingListBuilder

- Delete `build_recipe_map` (the method that re-parses all recipes).
- `aggregate_recipe_ingredients` calls `recipe.all_ingredients_with_quantities` (AR method) on each selected recipe.
- Update `selected_recipes` eager loading to include cross-reference targets.

### RecipeNutritionJob

- Delete `parsed_recipe` and `recipe_map` methods.
- Pass the AR `recipe` directly to `NutritionCalculator#calculate`.
- Second argument (`recipe_map`) becomes `nil` or `{}`.

### NutritionCalculator

No changes. Duck typing handles the interface.

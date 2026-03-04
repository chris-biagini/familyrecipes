# CatalogWriteService Variant Matching Fix (#181)

## Problem

`CatalogWriteService#recalculate_affected_recipes` uses `LOWER(ingredients.name) = ?` for exact case-insensitive matching only. If a catalog entry is "Eggs" and a recipe uses "Egg", updating the catalog entry won't trigger recalculation for that recipe.

## Design

Replace the SQL `LOWER()` query with resolver-based variant lookup, matching the pattern already used by `IngredientsController#recipes_for_ingredient`.

Build an `IngredientResolver` via `IngredientCatalog.resolver_for(kitchen)`, use `all_keys_for(ingredient_name)` to get all raw name variants (plurals, aliases, case variants), then query with `WHERE ingredients.name IN (?)`.

```ruby
def recalculate_affected_recipes
  resolver = IngredientCatalog.resolver_for(kitchen)
  raw_names = resolver.all_keys_for(ingredient_name)
  kitchen.recipes
         .joins(steps: :ingredients)
         .where(ingredients: { name: raw_names })
         .distinct
         .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
end
```

Test: catalog entry "Eggs", recipe uses "Egg" — updating catalog triggers recalculation.

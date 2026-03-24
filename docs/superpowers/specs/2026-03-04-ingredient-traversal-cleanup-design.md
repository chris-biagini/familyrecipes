# Ingredient Traversal Cleanup

## Problem

The recipe-ingredient eager-load graph (`steps → ingredients → cross_references → target_recipe → steps → ingredients`) is defined independently in five files, each with slight variations. Two files duplicate an expression that extracts visible ingredient names from a shopping list hash. These are textbook shotgun-surgery risks — a model change or format change requires finding and updating every copy.

### Affected files

**Duplicated eager-load includes:**
- `ShoppingListBuilder#selected_recipes` (line 49)
- `RecipeAvailabilityCalculator#loaded_recipes` (line 62)
- `RecipeNutritionJob#eager_load_recipe` (line 25)
- `RecipeBroadcaster::SHOW_INCLUDES` (line 13)
- `RecipesController#show` (line 11)

**Duplicated visible-names extraction:**
- `MealPlanActions#shopping_list_visible_names` (line 38–39)
- `RecipeWriteService#prune_stale_meal_plan_items` (line 103–104)

## Design

### 1. Canonical eager-load scope on Recipe

Add a single named scope to `Recipe`:

```ruby
scope :with_full_tree, -> {
  includes(:category,
           steps: [:ingredients,
                   { cross_references: { target_recipe: { steps: %i[ingredients cross_references] } } }])
}
```

All five consumers replace their inline includes with `Recipe.with_full_tree` (or chain it onto a kitchen-scoped query). Consumers that previously loaded a subset now load the full tree — the over-fetching is negligible (a handful of extra cross_reference rows at the deepest level).

### 2. `ShoppingListBuilder#visible_names`

Add a public method to `ShoppingListBuilder`:

```ruby
def visible_names
  build.each_value.flat_map { |items| items.map { |i| i[:name] } }.to_set
end
```

Both `MealPlanActions` and `RecipeWriteService` simplify to a single method call instead of reaching into the hash structure.

### What we chose not to do

**Resolver caching.** `IngredientCatalog.resolver_for` is called from multiple independent entry points, but the existing code already threads the resolver through the one hot path (broadcaster → row builder). Adding request-scoped caching would be a new abstraction for a problem that isn't causing real pain.

## Scope

Two changes, zero new classes, zero new abstractions. Existing tests should continue to pass with no modification — these are internal refactors that don't change any public behavior or query results.

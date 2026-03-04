# Unified Ingredient Name Resolution — Design

## Problem

Three services each implement their own `canonical_name` method with divergent behavior:

- **ShoppingListBuilder** — case-insensitive shadow hash + uncataloged first-seen memoization
- **RecipeAvailabilityCalculator** — exact match only, returns raw name on miss
- **IngredientRowBuilder** — exact match + runtime Inflector variants against a peer index

The same ingredient can resolve to different canonical names depending on which code path runs. The availability dots on the menu page can desync from the shopping list — e.g., "parmesan" checked off in groceries but shown as still needed in availability because the calculator lacks the CI fallback.

`IngredientCatalog.lookup_for` does the heavy lifting (pre-registering variants, aliases, case forms), but each consumer wraps it with ad-hoc fallback logic instead of the catalog owning the full resolution question.

## Design Decisions

- **Always case-insensitive.** Every resolve call gets a downcase fallback, even if `lookup_for` missed a variant. Belt-and-suspenders.
- **Resolver owns uncataloged grouping.** For names not in the catalog, the resolver memoizes first-seen capitalization so all casings of the same name collapse.
- **Stateful resolver with variant collapsing.** The resolver accumulates resolved names internally. For uncataloged names, it tries Inflector variants against already-resolved names so "Egg" and "Eggs" collapse even without a catalog entry.
- **New `IngredientResolver` class** produced by `IngredientCatalog.resolver_for(kitchen)`.
- **`lookup_for` stays as-is.** Proven hash-building logic is untouched. The resolver wraps it.

## The `IngredientResolver` Class

A plain Ruby class in `app/services/ingredient_resolver.rb`. Constructed with the `lookup_for` hash.

### Resolution Cascade

1. **Exact match** — `lookup[name]&.ingredient_name`
2. **Case-insensitive fallback** — `ci_lookup[name.downcase]&.ingredient_name`
3. **Uncataloged with variant collapsing** — try `Inflector.ingredient_variants(name)` against already-resolved uncataloged names. If a variant was seen before, collapse to that form. Otherwise, register this name as the canonical for its downcased key.

### API Surface

```ruby
class IngredientResolver
  attr_reader :lookup    # raw lookup_for hash, for callers needing key iteration

  def initialize(lookup)
  def resolve(name)           # => canonical name string (never nil)
  def catalog_entry(name)     # => IngredientCatalog AR object or nil
  def cataloged?(name)        # => boolean
  def all_keys_for(name)      # => array of all raw keys that resolve to this canonical name
end
```

- `resolve(name)` always returns a string — never nil, never raises. Callers can unconditionally use it as a hash key, set member, or display string.
- `catalog_entry(name)` runs the same cascade but returns the AR object. Returns nil for uncataloged ingredients. Used by ShoppingListBuilder for aisle lookups and NutritionCalculator for nutrition data.
- `cataloged?(name)` is sugar over `catalog_entry(name).present?`.
- `all_keys_for(name)` is a reverse lookup — all raw keys in the lookup hash that map to a given canonical name. Replaces `IngredientsController#matching_raw_names`. Hook point for fixing #181 later.

### Factory

```ruby
IngredientCatalog.resolver_for(kitchen)
# => IngredientResolver.new(IngredientCatalog.lookup_for(kitchen))
```

## Caller Migration

| Caller | Before | After |
|---|---|---|
| ShoppingListBuilder | `@profiles`, `@profiles_ci`, `@uncataloged_names`, custom `canonical_name` | `@resolver.resolve(name)`, `@resolver.catalog_entry(name)&.aisle` |
| RecipeAvailabilityCalculator | `@profiles[name]&.ingredient_name \|\| name` | `@resolver.resolve(name)` |
| IngredientRowBuilder | `lookup[name]` + runtime Inflector fallback against peer index | `@resolver.resolve(name)` |
| RecipeNutritionJob | `lookup_for` for nutrition data hash + `extract_omit_set` | Keep `lookup_for` for nutrition maps, use resolver for omit resolution |
| IngredientsController | `catalog_lookup` hash + `matching_raw_names` method | `resolver` + `resolver.all_keys_for(name)` |
| NutritionEntriesController | Constructs IngredientRowBuilder without passing lookup (inconsistency) | Passes resolver, fixing the inconsistency |

Constructor signatures change: `catalog_lookup:` / `lookup:` become `resolver:`.

## Data Flow and Lifecycle

**One resolver per request.** Controller actions memoize it:

```ruby
def resolver
  @resolver ||= IngredientCatalog.resolver_for(current_kitchen)
end
```

Services receive it as a dependency. When multiple services share a resolver in one request, uncataloged names resolved by one are already known to the other.

**Jobs construct their own.** `RecipeNutritionJob` and `RecipeBroadcastJob` each construct a resolver independently — no shared state with the original request, which is fine.

## Testing Strategy

**Unit tests for `IngredientResolver`** — hand-built lookup hashes, no database:
- Exact match, CI fallback, alias resolution, Inflector variant resolution
- Uncataloged first-seen capitalization, uncataloged variant collapsing
- `catalog_entry`, `cataloged?`, `all_keys_for` correctness
- Never returns nil

**Integration tests per caller** — updates to existing test files:
- ShoppingListBuilder: existing tests + differently-cased uncataloged ingredients produce one line
- RecipeAvailabilityCalculator: existing tests + CI resolution test (the original bug)
- IngredientRowBuilder: existing tests + verify runtime Inflector fallback is gone

**Regression test:** Recipe A has "Parmesan", recipe B has "parmesan", both selected. Verify ShoppingListBuilder and RecipeAvailabilityCalculator agree on the canonical name.

## Rollout Order

1. Build and test `IngredientResolver` in isolation
2. Migrate ShoppingListBuilder (most complex, best test coverage)
3. Migrate RecipeAvailabilityCalculator (the bugfix)
4. Migrate IngredientRowBuilder
5. Migrate controllers (IngredientsController, NutritionEntriesController)
6. Update RecipeBroadcaster

Each step is independently shippable.

## Out of Scope

- `IngredientCatalog.lookup_for` internals — untouched
- `Inflector` — no changes
- `NutritionTui::Data` — standalone TUI, separate world
- `BuildValidator` — seed-time validation, own downcased set
- `CatalogWriteService#recalculate_affected_recipes` — tracked in #181

## Related Issues

- #179 — DRY `broadcast_meal_plan_refresh` stream tuple
- #180 — `MealPlan.prune_stale_items` circular model/service dependency
- #181 — `CatalogWriteService#recalculate_affected_recipes` misses Inflector variants

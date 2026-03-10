# Resolver Omit Cleanup Design

**Date:** 2026-03-10
**Status:** Draft

## Problem

Three related code smells in the ingredient catalog pipeline:

1. **Omit-set duplication.** The "is this ingredient omitted from shopping?"
   question is answered independently in `RecipeNutritionJob`,
   `RecipeAvailabilityCalculator`, `ShoppingListBuilder`, `NutritionTui::Data`,
   and `BuildValidator` — each with subtly different implementations (some
   downcase, some don't; some build a Set, one filters inline).

2. **Resolver encapsulation break.** `RecipeAvailabilityCalculator` reaches
   into `@resolver.lookup` to scan for omitted entries. No other consumer
   touches that raw hash — they use `resolve()`, `catalog_entry()`, etc.

3. **N+1 catalog lookups.** When `CatalogWriteService` recalculates nutrition
   for affected recipes, it builds a resolver (1 DB query via `lookup_for`),
   then calls `RecipeNutritionJob.perform_now` for each recipe — and each job
   call hits `lookup_for` again. The catalog hasn't changed between calls.

4. **Sentinel string for omit.** The concept "don't put this on the shopping
   list" is encoded as `aisle: 'omit'` — a magic string pretending to be a
   grocery aisle. `AisleWriteService` special-cases it, the helper special-cases
   it, the aisle sync filters it out, and the editor hard-codes it as a dropdown
   option. An ingredient can't simultaneously have a real aisle and be omitted.

## Solution

Two changes that reinforce each other:

### A. Replace the sentinel string with a boolean column

Add `omit_from_shopping boolean DEFAULT false NOT NULL` to
`ingredient_catalogs`. Migrate existing `aisle: 'omit'` rows to
`omit_from_shopping: true, aisle: nil`. Update seed YAML to use
`omit_from_shopping: true` instead of `aisle: omit`.

This eliminates every `== 'omit'` check, every aisle-sync guard for `'omit'`,
and every UI special-case. The editor gets a checkbox instead of a magic
dropdown option. Ingredients can now have both an aisle and be omitted (e.g.,
salt lives in "Spices" but you always have it).

### B. Make IngredientResolver the single owner of omit knowledge

Add to `IngredientResolver`:

```ruby
def omitted?(name)
  entry = find_entry(name)
  entry&.omit_from_shopping == true
end

def omit_set
  @omit_set ||= @lookup.each_value
                        .select(&:omit_from_shopping)
                        .to_set { |e| e.ingredient_name.downcase }
end
```

`omit_set` exists for `NutritionCalculator`, which needs a pre-built Set of
downcased names for its inner loop. `omitted?` is the clean API for everyone
else.

### C. Thread the resolver through RecipeNutritionJob

Change `RecipeNutritionJob#perform` to accept an optional `resolver:` keyword.
When called from `CatalogWriteService`, the service passes the resolver it
already built. When called from `MarkdownImporter` (no resolver in scope), the
job builds one itself via `IngredientCatalog.resolver_for(kitchen)`.

The job uses `resolver.lookup` for building `nutrition_data` (same data it
currently gets from `lookup_for`) and `resolver.omit_set` instead of its own
`extract_omit_set`. This kills the N+1: one resolver, N recipe calculations.

## Changes by file

### Migration

- Add `omit_from_shopping` boolean column (default false, not null)
- Data migration: `UPDATE ingredient_catalogs SET omit_from_shopping = true,
  aisle = NULL WHERE aisle = 'omit'`

### IngredientResolver

- Add `omitted?(name)` method
- Add `omit_set` memoized method (returns `Set` of downcased names)
- Remove `attr_reader :lookup` — no consumer should reach into the raw hash
- Add `nutrition_data_for(name)` or keep `catalog_entry(name)` as the access
  path for job's `build_nutrition_data` (catalog_entry already exists, so the
  job can use it; but it currently iterates the full hash, so we keep a
  `each_catalog_entry` enumerator or expose `lookup.transform_values` through
  a method)

**Decision: keep `attr_reader :lookup` for now.** `RecipeNutritionJob` needs to
iterate all catalog entries to build the `nutrition_data` hash for
`NutritionCalculator`. Adding a wrapper method that just delegates to the hash
would be ceremony without value. The resolver header comment should document
that `lookup` is for bulk iteration by the nutrition pipeline, not for
ad-hoc access.

### RecipeNutritionJob

- Accept optional `resolver:` keyword in `perform`
- Fall back to `IngredientCatalog.resolver_for(recipe.kitchen)` when not
  provided
- Use `resolver.lookup` instead of `IngredientCatalog.lookup_for`
- Use `resolver.omit_set` instead of `extract_omit_set`
- Delete `extract_omit_set` method

### CascadeNutritionJob

- No change needed — it calls `RecipeNutritionJob.perform_now(dependent)` for
  each referencing recipe. These are different kitchens' recipes potentially,
  so sharing a resolver across them isn't safe. Each call builds its own.

**Wait — actually** `CascadeNutritionJob` operates within a single kitchen
(wrapped in `ActsAsTenant.with_tenant(recipe.kitchen)`), and all dependents
are in the same kitchen. So it could build one resolver and share it. But
cascade jobs are async and infrequent — not worth the complexity.

### CatalogWriteService

- `recalculate_affected_recipes`: build resolver once, pass to each
  `RecipeNutritionJob.perform_now(recipe, resolver:)` call
- `recalculate_all_affected_recipes`: same pattern
- Both methods already build a resolver for `all_keys_for` — reuse it

### RecipeAvailabilityCalculator

- Replace `build_omit_set` with `@resolver.omitted?(name)` in
  `needed_ingredients`
- Delete `build_omit_set` method
- Remove `@omitted` instance variable

### ShoppingListBuilder

- Replace `aisle_for(name) == 'omit'` with `@resolver.omitted?(name)` in
  `organize_by_aisle`

### AisleWriteService

- `sync_new_aisle`: remove `return if aisle == 'omit'` guard
- `sync_new_aisles`: remove `.reject { |a| a == 'omit' }` filter

### Kitchen model

- `all_aisles`: remove `'omit'` from the `.where.not(aisle: ...)` exclusion
  list (keep nil and empty string exclusions)

### IngredientsHelper

- `display_aisle`: remove the `aisle == 'omit' ? 'Omit' : aisle` ternary;
  just return the aisle or dash

### View templates

**`_editor_form.html.erb`:** Remove the hard-coded `<option value="omit">`
from the aisle dropdown. Add a checkbox for "Omit from grocery list" in the
form, outside the aisle fieldset.

**`_aisle_selector.html.erb`:** Remove `<option value="omit">`.

### Stimulus controller (nutrition_editor_controller.js)

- Read the checkbox value and include `omit_from_shopping` in the save payload
- No omit-specific logic currently in JS, so this is additive

### NutritionCalculator (domain, lib/)

- No change. It already accepts `omit_set:` as a plain Set of downcased
  strings. The resolver's `omit_set` method produces exactly that.

### bin/nutrition TUI

- `NutritionTui::Data#build_omit_set`: change from
  `entry['aisle'] == 'omit'` to `entry['omit_from_shopping'] == true`
- `bin/nutrition` coverage report: change count from
  `entry['aisle'] == 'omit'` to `entry['omit_from_shopping']`

### BuildValidator

- Change `IngredientCatalog.where(aisle: 'omit')` to
  `IngredientCatalog.where(omit_from_shopping: true)`

### Seed YAML (ingredient-catalog.yaml)

- Change entries (Ice, Poolish, Water) from `aisle: omit` to
  `omit_from_shopping: true` (remove the aisle key)

### Seeds and catalog sync

- `IngredientCatalog.attrs_from_yaml`: handle `omit_from_shopping` key
- `rake catalog:sync`: no special handling needed — attrs_from_yaml covers it

### Import/Export

- Export: serialize `omit_from_shopping` in YAML output
- Import: `attrs_from_yaml` already covers it once updated
- Backward compat: if an imported file has `aisle: omit` (old format), the
  import should still work. `attrs_from_yaml` can detect this and set the
  boolean. This is a one-time migration path, not permanent compat code.

## Testing

- Existing omit-related tests update to use the boolean
- New resolver tests: `omitted?`, `omit_set`
- Verify N+1 is gone: `CatalogWriteService` test asserting
  `IngredientCatalog.lookup_for` is called once (not N+1 times)
- Verify aisle + omit coexistence: an ingredient with `aisle: 'Spices',
  omit_from_shopping: true` appears in aisle lists but not on shopping list

## What doesn't change

- `NutritionCalculator` interface (still takes `omit_set:`)
- `IngredientAggregator` (doesn't know about omit)
- `MarkdownImporter` (calls job without resolver, job builds its own)
- `CascadeNutritionJob` (infrequent, builds its own)
- `RecipeBroadcaster` (unrelated)
- `MealPlanWriteService` (unrelated)
- `CategoryWriteService` (unrelated)

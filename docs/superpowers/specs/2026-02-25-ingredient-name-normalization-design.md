# Ingredient Name Normalization Design

## Problem

Recipe source files use inconsistent singular/plural forms for the same ingredient:

- "Egg" (3 recipes) vs "Eggs" (7 recipes) — catalog canonical: "Eggs"
- "Egg yolk" (1) vs "Egg yolks" (2)
- "Lemon" (2) vs "Lemons" (1) — catalog canonical: "Lemons"
- "Lime" (1) vs "Limes" (1) — catalog canonical: "Limes"
- "Onion" (10) vs "Onions" (1) — catalog canonical: "Onions"
- "Carrot" (4) — catalog canonical: "Carrots"

All lookups against `IngredientCatalog` use exact string matching, so "Egg" fails
to find the "Eggs" catalog entry. This causes:

1. Nutrition data must be entered for each variant separately
2. Shopping list doesn't merge quantities across variant names
3. Ingredients page shows false "missing" warnings

## Approach: normalize at lookup time

Enhance `IngredientCatalog.lookup_for(kitchen)` to return a hash that resolves both
singular and plural variants to the same catalog entry. One change point, all callers
benefit automatically. No stored data changes, no migrations.

## Existing infrastructure

`FamilyRecipes::Inflector` (`lib/familyrecipes/inflector.rb`) already has everything
needed — it's just only wired up for unit normalization today:

- `singular(word)` / `plural(word)` — standard English rules plus irregulars
- `uncountable?(word)` — "butter", "flour", "garlic", etc.
- Irregular handling: "taco"→"tacos", "leaf"→"leaves", "loaf"→"loaves"
- Case preservation via `apply_case`

No new pluralization logic or mapping tables needed.

## New method: `Inflector.ingredient_variants(name)`

Returns alternate singular/plural forms of an ingredient name.

Behavior:
- `"Eggs"` → `["Egg"]`
- `"Egg"` → `["Eggs"]`
- `"Butter"` → `[]` (uncountable)
- `"Tomatoes (canned)"` → `["Tomato (canned)"]` (inflects base word, preserves qualifier)
- `"Flour (all-purpose)"` → `[]` (uncountable base word)

Parenthetical qualifiers are split off, the base word is inflected, and the qualifier
is reattached. This handles cases like "Egg yolks" → "Egg yolk" where only the last
word needs inflection.

## Changes to `IngredientCatalog.lookup_for`

After building the exact-match hash (global entries merged with kitchen overrides),
iterate entries and add variant keys. Explicit entries always win — variant keys
never overwrite an existing key.

```
Before: { "Eggs" => entry, "Butter" => entry }
After:  { "Eggs" => entry, "Egg" => entry, "Butter" => entry }
```

All callers of `lookup_for` benefit automatically:
- `RecipeNutritionJob#build_nutrition_lookup`
- `ShoppingListBuilder`
- `IngredientsController` (nutrition status + missing detection)
- `Kitchen#all_aisles`

## Changes to `BuildValidator`

Currently builds a downcase set of known names and checks recipe ingredients against
it. Update to also generate singular/plural variants for each known name, so "Carrot"
in a recipe matches "Carrots" in the catalog.

## Out of scope

- Recipe source file cleanup (names stay as-is)
- Non-plural variants: "Parmesan cheese" vs "Parmesan", "Flour (All purpose)" vs
  "Flour (all-purpose)" — these are separate naming inconsistencies
- Schema changes or migrations

## Files changed

- `lib/familyrecipes/inflector.rb` — add `ingredient_variants`
- `app/models/ingredient_catalog.rb` — enhance `lookup_for` with variant keys
- `lib/familyrecipes/build_validator.rb` — variant-aware known-name set
- Tests for all three

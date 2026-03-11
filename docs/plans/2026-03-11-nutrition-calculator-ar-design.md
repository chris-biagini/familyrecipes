# NutritionCalculator: Consume IngredientCatalog Records

## Problem

`NutritionCalculator` consumes hand-built string-keyed hashes — a YAML
artifact from when ingredient data lived in flat files. Every caller
(`RecipeNutritionJob`, `BuildValidator`, `NutritionTui::Data`) must translate
catalog data into this intermediate format. This taxes every new consumer and
blocks the upcoming web-based ingredient editor from doing things like "preview
nutrition with these changes" without constructing throwaway hashes.

## Change

Make `NutritionCalculator` consume `IngredientCatalog` records (or any object
that quacks like one) directly. The lookup hash it receives becomes
`{ ingredient_name => IngredientCatalog }` — the same shape
`IngredientResolver#lookup` already holds.

## What Changes

**`NutritionCalculator`** — rewrite internals to call AR-style accessors:
- `entry.dig('nutrients', 'basis_grams')` → `entry.basis_grams`
- `entry.dig('nutrients', nutrient.to_s)` → `entry.public_send(nutrient)`
- `entry['density']` hash → `entry.density_grams`, `entry.density_volume`,
  `entry.density_unit`
- `entry['portions']` → `entry.portions`
- Constructor takes `{ name => catalog_record }` instead of
  `{ name => string_hash }`
- Drop nested-hash validation in constructor — just check
  `entry.basis_grams.present?`

**`RecipeNutritionJob`** — delete `build_nutrition_data`, `nutrients_hash`,
and `density_hash`. Pass `resolver.lookup` directly to the calculator.

**`BuildValidator`** — same treatment; pass lookup directly instead of
building hashes.

**`NutritionTui::Data`** — will break. The TUI is being replaced by the web
ingredient editor; no effort spent maintaining compatibility.

**Tests** — update calculator tests to use `IngredientCatalog` records (or
stubbed objects with the same interface) instead of hand-built hashes.

## What Doesn't Change

- `IngredientCatalog` model — already has all the right accessors
- `IngredientResolver` — already produces `{ name => IngredientCatalog }`
- `CatalogWriteService`, controllers, views — untouched
- `NutritionCalculator::Result` — same shape, same serialization
- The `omit_set` parameter — stays as-is (tracked in adjacent cleanup issue)

## Risk

Low. The calculator is a pure computation class with good test coverage. The
change is mechanical — swap hash access for method calls. `RecipeNutritionJob`
gets simpler. The TUI breaks but we don't care.

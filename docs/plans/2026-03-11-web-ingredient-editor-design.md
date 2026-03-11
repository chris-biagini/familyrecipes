# Web Ingredient Editor Data Layer

**Date:** 2026-03-11

## Overview

Move USDA search/import capabilities out of the TUI into Rails services and
controllers, and add unit resolution analysis to the editor form. This gives
the future web editor all the data infrastructure it needs so implementation
can focus purely on UX.

## 1. `UsdaImportService`

New service at `app/services/usda_import_service.rb`. Takes raw USDA detail
(from `UsdaClient#fetch`) and returns a structured result:

- **Suggested form values**: nutrients mapped to our schema, auto-picked
  density (via `UsdaPortionClassifier.pick_best_density`), source metadata
- **Informational data**: classified portion candidates (density candidates,
  named portions like "medium onion = 110g"), filtered entries

```ruby
UsdaImportService.call(detail) → Result
  .nutrients           # { basis_grams: 100, calories: 52.0, ... }
  .density             # { grams: 236.0, volume: 1.0, unit: "cup" } or nil
  .source              # { type: "usda", dataset: "SR Legacy", fdc_id: 9003, description: "Apples, raw" }
  .portions            # [{ name: "medium", grams: 182.0 }, ...] — informational
  .density_candidates  # full classified list — informational
```

Pure data transformation — no persistence, no side effects. Consumes
`UsdaClient` (already extracted) and `UsdaPortionClassifier` (already
extracted). Auto-picks density via `pick_best_density` (largest per-unit
grams minimizes rounding error).

## 2. `UsdaSearchController`

New controller at `app/controllers/usda_search_controller.rb`. Two JSON
actions behind `require_membership`:

**`GET /usda/search?q=cream+cheese&page=0`** — calls `UsdaClient#search`,
returns paginated results with nutrient previews. Returns 422 with
`{ error: "no_api_key" }` if `current_kitchen.usda_api_key` is blank.

**`GET /usda/:fdc_id`** — calls `UsdaClient#fetch`, pipes through
`UsdaImportService.call`, returns suggested values + informational portions.
Same API key guard.

Both actions rescue `UsdaClient::Error` subclasses and return appropriate
error JSON (auth errors, rate limits, network failures).

Routes (inside the existing kitchen scope):

```ruby
get "usda/search", to: "usda_search#search"
get "usda/:fdc_id", to: "usda_search#show"
```

## 3. Unit Resolution in Editor

Add a `needed_units` method to `IngredientRowBuilder` that, given an
ingredient name:

1. Walks the kitchen's recipes collecting all units used with that ingredient
2. Checks each against `NutritionCalculator#resolvable?` with the current
   catalog entry
3. Returns an array of `{ unit:, resolvable:, method: }` hashes

`IngredientsController#edit` includes this data in the editor form response
so the template can render a "Recipe Units" reference section.

## 4. `UsdaClient` Cleanup

- Remove `load_api_key` and `parse_env_file` (TUI-only `.env` reading; Rails
  reads from `Kitchen#usda_api_key`)
- Update header comment collaborators to reference `UsdaSearchController`
  instead of `bin/nutrition`

## Files

| File | Action |
|------|--------|
| `app/services/usda_import_service.rb` | New |
| `app/controllers/usda_search_controller.rb` | New |
| `config/routes.rb` | Add 2 routes |
| `app/services/ingredient_row_builder.rb` | Add `needed_units` |
| `app/controllers/ingredients_controller.rb` | Pass needed_units to edit |
| `app/views/ingredients/_editor_form.html.erb` | Render recipe units section |
| `lib/familyrecipes/usda_client.rb` | Remove `load_api_key`, update comment |
| `test/services/usda_import_service_test.rb` | New |
| `test/controllers/usda_search_controller_test.rb` | New |
| `test/services/ingredient_row_builder_test.rb` | Add needed_units tests |

## Not in scope

- JS/Stimulus work for the USDA search UI (that's UX, deferred)
- Changes to `CatalogWriteService` (upsert path is already correct)
- TUI fixes or migration (being abandoned)
- Coverage report features (index summary bar already covers this)

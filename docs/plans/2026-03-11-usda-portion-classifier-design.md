# USDA Portion Classifier Extraction

## Problem

USDA portion classification logic is trapped in `NutritionTui::Data`, a
TUI-specific module. `UsdaClient` does a throwaway first-pass classification
(volume vs non_volume) that the TUI immediately recombines and re-classifies
into three richer buckets. Volume-unit detection is duplicated between both.
This blocks clean web USDA integration — the web editor will need the same
classification logic but can't reach it without pulling in the TUI.

## Solution

Extract `FamilyRecipes::UsdaPortionClassifier` as a shared domain class in
`lib/familyrecipes/`. The client fetches, the classifier classifies.

## New Class: `UsdaPortionClassifier`

File: `lib/familyrecipes/usda_portion_classifier.rb`

Public API:

- `classify(portions)` — takes flat array of `{modifier:, grams:, amount:}`
  hashes, returns `Result` with `density_candidates`, `portion_candidates`,
  `filtered`. Each entry includes computed `:each` (per-unit grams). Portion
  candidates get `:display_name`, filtered entries get `:reason`.
- `pick_best_density(density_candidates)` — returns candidate with highest
  per-unit grams.
- `normalize_volume_unit(modifier)` — extracts normalized volume unit string
  from a modifier.
- `volume_modifier?(modifier)` / `weight_modifier?(modifier)` — public
  predicates for classification rules. Exposed for direct testing.

Owns `VOLUME_PREFIXES` and `WEIGHT_PREFIXES` constant sets (derived from
`NutritionCalculator` and `Inflector`, currently duplicated in
`NutritionTui::Data`).

`Result = Data.define(:density_candidates, :portion_candidates, :filtered)`

## Changes to `UsdaClient`

- Delete `classify_portions` and `volume_unit?` private methods.
- `format_fetch_response` returns `portions:` as a flat array of raw portion
  hashes (output of `build_portion_entry` for each food portion).
- Response shape changes from
  `portions: { volume: [...], non_volume: [...] }` to `portions: [...]`.
- Client becomes a pure HTTP adapter.

## Changes to `NutritionTui::Data`

Delete ~60 lines of USDA classification methods and constants:

- `classify_usda_modifiers`, `pick_best_density`, `normalize_volume_unit`
- `strip_parenthetical`, `volume_modifier?`, `weight_modifier?`,
  `regulatory_modifier?`, `unit_prefix_match?`, `modifier_bucket`,
  `per_unit_grams`
- `VOLUME_PREFIXES`, `WEIGHT_PREFIXES`

The `rubocop:disable Metrics/ModuleLength` annotation can be removed.

What stays: I/O, variant lookup, context loading, coverage analysis — all
TUI-specific concerns with no web equivalent.

## Changes to TUI Ingredient Screen

`classify_and_apply_density` changes from:

```ruby
all_modifiers = detail[:portions][:volume] + detail[:portions][:non_volume]
@usda_classified = Data.classify_usda_modifiers(all_modifiers)
best = Data.pick_best_density(@usda_classified[:density_candidates])
```

to:

```ruby
@usda_classified = FamilyRecipes::UsdaPortionClassifier.classify(detail[:portions])
best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(@usda_classified.density_candidates)
```

`apply_density` calls `UsdaPortionClassifier.normalize_volume_unit` instead of
`Data.normalize_volume_unit`.

## Testing

- **New:** `test/usda_portion_classifier_test.rb` — moves classification tests
  from `data_test.rb`, retargeted at `FamilyRecipes::UsdaPortionClassifier`.
  Uses `Minitest::Test` (no Rails dependency). Predicates tested directly.
- **Updated:** `test/usda_client_test.rb` — adjusted for flat portions array.
- **Trimmed:** `test/nutrition_tui/data_test.rb` — USDA classification tests
  removed.

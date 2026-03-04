# Nutrition Constants Consolidation Design

**Date:** 2026-03-04
**Status:** Approved
**Problem:** Nutrient metadata is defined in 5 places with different structures. Volume unit lists are fragmented across 4 files. `fl oz`, `pt`, `qt`, and `gal` are missing from the nutrition calculator.

## Fix 1: Nutrient List — Single Source of Truth

### Problem

Adding a nutrient requires updating 5 independent constants, each with a different data structure:

| Location | Structure |
|----------|-----------|
| `NutritionTui::Data::NUTRIENTS` | `[{key:, label:, unit:, indent:}]` |
| `NutritionCalculator::NUTRIENTS` | `%i[...]` |
| `IngredientCatalog::NUTRIENT_COLUMNS` | `%i[...]` |
| `IngredientCatalog::NUTRIENT_DISPLAY` | `[['Label', :key, 'unit']]` |
| `RecipesHelper::NUTRITION_ROWS` | `[['Label', 'key', 'unit', indent]]` |

### Solution

Add `NutrientDef` and `NUTRIENT_DEFS` to `NutritionConstraints` (already loaded by both TUI and Rails). All consumers derive their constants from it.

```ruby
NutrientDef = Data.define(:key, :label, :unit, :indent)

NUTRIENT_DEFS = [
  NutrientDef.new(key: :calories,      label: 'Calories',     unit: '',   indent: 0),
  NutrientDef.new(key: :fat,           label: 'Total Fat',    unit: 'g',  indent: 0),
  NutrientDef.new(key: :saturated_fat, label: 'Saturated Fat', unit: 'g', indent: 1),
  NutrientDef.new(key: :trans_fat,     label: 'Trans Fat',    unit: 'g',  indent: 1),
  NutrientDef.new(key: :cholesterol,   label: 'Cholesterol',  unit: 'mg', indent: 0),
  NutrientDef.new(key: :sodium,        label: 'Sodium',       unit: 'mg', indent: 0),
  NutrientDef.new(key: :carbs,         label: 'Total Carbs',  unit: 'g',  indent: 0),
  NutrientDef.new(key: :fiber,         label: 'Fiber',        unit: 'g',  indent: 1),
  NutrientDef.new(key: :total_sugars,  label: 'Total Sugars', unit: 'g',  indent: 1),
  NutrientDef.new(key: :added_sugars,  label: 'Added Sugars', unit: 'g',  indent: 2),
  NutrientDef.new(key: :protein,       label: 'Protein',      unit: 'g',  indent: 0)
].freeze

NUTRIENT_KEYS = NUTRIENT_DEFS.map(&:key).freeze
```

### Derivations

Each consumer replaces its hardcoded constant:

- **`NutritionCalculator::NUTRIENTS`** → `NutritionConstraints::NUTRIENT_KEYS`
- **`IngredientCatalog::NUTRIENT_COLUMNS`** → `NutritionConstraints::NUTRIENT_KEYS`
- **`IngredientCatalog::NUTRIENT_DISPLAY`** → derived from `NUTRIENT_DEFS`, adding whitespace-indented labels
- **`RecipesHelper::NUTRITION_ROWS`** → derived from `NUTRIENT_DEFS`
- **`NutritionTui::Data::NUTRIENTS`** → derived from `NUTRIENT_DEFS`, converting keys to strings

### Label handling

`NutrientDef#label` uses the full canonical form ("Saturated Fat"). Consumers that need abbreviated labels (e.g., "Sat. Fat" in the web nutrition table) handle abbreviation at the display layer. The `indent` field drives visual hierarchy — consumers that need whitespace-indented labels (like `NUTRIENT_DISPLAY`) prepend spaces based on indent level.

## Fix 2: Volume Units — Single Source of Truth + New Units

### Problem

Volume unit lists are defined independently in 4 places:

- `NutritionCalculator::VOLUME_TO_ML` — 5 units (cup, tbsp, tsp, ml, l)
- `NutritionTui::Data::VOLUME_UNITS` — 9 entries including 'fl oz' and long forms
- `UsdaClient::VOLUME_UNITS` — 8 entries, long forms only, missing 'fl oz'
- `_editor_form.html.erb` — hardcoded `%w[cup tbsp tsp ml l]`

`fl oz`, `pt`, `qt`, and `gal` are missing from the calculator despite the Inflector already knowing how to normalize them.

### Solution

**Expand `VOLUME_TO_ML`** as the single source of truth for volume conversions:

```ruby
VOLUME_TO_ML = {
  'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
  'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
  'gal' => 3785.41, 'ml' => 1, 'l' => 1000
}.freeze
```

**Add `fl oz` to `Inflector::ABBREVIATIONS`:**

```ruby
'fl oz' => 'fl oz', 'fluid ounce' => 'fl oz', 'fluid ounces' => 'fl oz'
```

### Consumer changes

- **`NutritionTui::Data::VOLUME_UNITS`** — delete, derive from `VOLUME_TO_ML.keys`
- **`NutritionTui::Data::WEIGHT_UNITS`** — delete, derive from `WEIGHT_CONVERSIONS.keys`
- **`UsdaClient::VOLUME_UNITS`** — delete, replace `volume_unit?` with Inflector-based normalization: normalize the first word of the modifier, check if result is in `VOLUME_TO_ML`
- **`_editor_form.html.erb`** — replace hardcoded list with `NutritionCalculator::VOLUME_TO_ML.keys`

### Parser compatibility

Already verified: `Ingredient.split_quantity` uses `split(' ', 2)` which keeps `"fl oz"` as a single unit token. The full pipeline works: parser → Inflector normalization → NutritionCalculator conversion.

### USDA modifier matching

`UsdaClient.volume_unit?` currently does prefix matching against a local list. After this change, it normalizes the first word of the USDA modifier via `Inflector.normalize_unit` and checks if the result is a key in `VOLUME_TO_ML`. This uses the existing normalization pipeline instead of maintaining a separate list.

`NutritionTui::Data.volume_modifier?` and `weight_modifier?` get the same treatment — build a set of recognized prefixes from `VOLUME_TO_ML.keys` + long-form aliases from `Inflector::ABBREVIATIONS`, then check against that.

## Fixes 3 & 4: Documentation Only

**#3 — Omit-set construction:** Add comments to `NutritionTui::Data.build_omit_set` and `RecipeNutritionJob#extract_omit_set` noting they implement the same `aisle == 'omit'` business rule and should be updated in tandem.

**#4 — Lookup/variant matching:** The existing comment at `Data.build_lookup` ("mirrors IngredientCatalog.lookup_for") is sufficient. No additional documentation needed.

## Files Changed

| Category | Files | Nature |
|----------|-------|--------|
| `NutrientDef` source of truth | `lib/familyrecipes/nutrition_constraints.rb` | Add ~15 lines |
| Derive nutrient constants | `lib/familyrecipes/nutrition_calculator.rb`, `app/models/ingredient_catalog.rb`, `app/helpers/recipes_helper.rb`, `lib/nutrition_tui/data.rb` | Replace hardcoded constants |
| Expand volume conversions | `lib/familyrecipes/nutrition_calculator.rb` | Add fl oz, pt, qt, gal |
| Inflector `fl oz` support | `lib/familyrecipes/inflector.rb` | 3 new ABBREVIATIONS entries |
| Delete TUI unit constants | `lib/nutrition_tui/data.rb` | Derive from calculator |
| Simplify USDA volume check | `lib/familyrecipes/usda_client.rb` | Use Inflector normalization |
| Update editor dropdown | `app/views/ingredients/_editor_form.html.erb` | Derive from VOLUME_TO_ML |
| Documentation | `lib/nutrition_tui/data.rb`, `app/jobs/recipe_nutrition_job.rb` | ~2 lines each |
| Tests | Existing test files | Update as needed for new derivations |

## Risk Assessment

Low risk. No behavioral changes to existing functionality — the nutrient list and existing volume units are unchanged. The only new behavior is `fl oz`/`pt`/`qt`/`gal` support in recipes and nutrition calculations. Existing tests should continue passing since the underlying values don't change, only where they're defined.

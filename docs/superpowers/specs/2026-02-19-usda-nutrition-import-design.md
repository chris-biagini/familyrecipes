# USDA Nutrition Import with Density-First Data Model

## Problem

The project needs nutrition data for ~100+ recipe ingredients. Manual entry from package labels (`bin/nutrition-entry`) works but is tedious for staple ingredients (flour, sugar, butter, produce) that have well-characterized data in the USDA FoodData Central database. A previous attempt at USDA integration was abandoned because search results were too noisy (searched all databases) and the data was opaque.

## Solution

A new `bin/nutrition-usda` script that searches the USDA SR Legacy dataset via the FoodData Central API, with user-controlled search queries and an interactive pick-and-confirm workflow. Alongside this, refactor the nutrition data model to a density-first design that stores raw measurements and derives all intermediate values at build time.

## Data Model

### Principle

Store three things:
1. **Nutritional density** -- raw nutrient values + the gram mass they correspond to
2. **Volumetric density** -- a single raw volume-mass pairing (the largest reliable measurement)
3. **Non-standard unit mappings** -- portions that can't be derived from density (stick, pat, ~unitless, clove)

All volume unit conversions (cup, tbsp, tsp, ml, l) are derived from density at build time. No intermediate values are stored.

### Format

```yaml
Flour (all-purpose):
  nutrients:
    basis_grams: 100.0          # these values are per 100g (USDA)
    calories: 364.0
    fat: 0.98
    saturated_fat: 0.155
    trans_fat: 0.0              # not in USDA, default 0
    cholesterol: 0.0
    sodium: 2.0
    carbs: 76.31
    fiber: 2.7
    total_sugars: 0.27
    added_sugars: 0.0           # not in USDA, default 0
    protein: 10.33
  density:
    grams: 125.0                # raw USDA measurement
    volume: 1.0
    unit: cup
  source: "USDA SR Legacy: Wheat flour, white, all-purpose,
    enriched, bleached (FDC 168894)"
```

```yaml
Butter:
  nutrients:
    basis_grams: 100.0
    calories: 717.0
    fat: 81.11
    saturated_fat: 50.489
    trans_fat: 0.0
    cholesterol: 215.0
    sodium: 11.0
    carbs: 0.06
    fiber: 0.0
    total_sugars: 0.06
    added_sugars: 0.0
    protein: 0.85
  density:
    grams: 227.0
    volume: 1.0
    unit: cup
  portions:
    stick: 113.0
    pat: 5.0
  source: "USDA SR Legacy: Butter, without salt (FDC 173430)"
```

```yaml
Eggs:
  nutrients:
    basis_grams: 100.0
    calories: 143.0
    # ...
  portions:
    ~unitless: 50.0             # 1 large egg = 50g
  source: "USDA SR Legacy: Egg, whole, raw, fresh (FDC 171287)"
```

```yaml
# Manual label entry -- same format, different basis
Cream cheese:
  nutrients:
    basis_grams: 29.0           # label serving is 29g
    calories: 100.0
    fat: 10.0
    # ...
  density:
    grams: 29.0                 # 2 tbsp = 29g (from label)
    volume: 2.0
    unit: tbsp
  source: Philadelphia Original
```

### Build-time derivation

- Nutrient per gram: `nutrients[key] / nutrients['basis_grams']`
- Density (g/mL): `density['grams'] / (density['volume'] * ml_per_unit(density['unit']))`
- Volume to grams: `density_g_per_ml * ml_per_unit(unit) * amount`

## bin/nutrition-usda Script

### Workflow

1. Accept ingredient name (CLI argument or interactive prompt)
2. Resolve via grocery-info.yaml alias map
3. Prompt for search query (default: ingredient name with parentheticals stripped)
4. POST to `https://api.nal.usda.gov/fdc/v1/foods/search` with `dataType: ["SR Legacy"]`
5. Display numbered results (description + FDC ID)
6. User picks a result or types 's' to search again with new terms
7. GET full detail from `https://api.nal.usda.gov/fdc/v1/food/{fdcId}`
8. Extract 11 nutrients via USDA nutrient number mapping
9. Classify USDA portions: volume (cup/tbsp/tsp) vs non-volume (stick/pat/etc)
10. Pick largest volume portion for density; collect non-volume portions
11. Show which recipe units are needed and whether they resolve
12. Display full entry for review
13. Confirm to save to nutrition-data.yaml

### --missing mode

Iterate through all ingredients lacking nutrition data (reusing find_missing_ingredients logic from nutrition-entry). For each, enter the search-pick-confirm loop. User can skip ingredients.

### USDA nutrient ID mapping

| USDA Number | USDA Name                    | Our Key        |
|-------------|------------------------------|----------------|
| 208         | Energy (kcal)                | calories       |
| 204         | Total lipid (fat)            | fat            |
| 606         | Fatty acids, total saturated | saturated_fat  |
| 605         | Fatty acids, total trans     | trans_fat      |
| 601         | Cholesterol                  | cholesterol    |
| 307         | Sodium, Na                   | sodium         |
| 205         | Carbohydrate, by difference  | carbs          |
| 291         | Fiber, total dietary         | fiber          |
| 269         | Total Sugars                 | total_sugars   |
| --          | (not in SR Legacy)           | added_sugars   |
| 203         | Protein                      | protein        |

Trans fat (605) and added sugars default to 0 when absent.

### USDA portion classification

Volume units recognized: cup, tbsp, tsp (matched against start of USDA modifier string, ignoring parenthetical descriptions like "cup (4.86 large eggs)").

Everything else is a non-volume portion.

## NutritionCalculator Changes

Three methods change their data access paths:

1. **`initialize`** -- validate `nutrients['basis_grams']` and `nutrients` hash (was `serving.grams` and `per_serving`)
2. **`nutrient_per_gram`** -- `nutrients[key] / nutrients['basis_grams']` (was `per_serving[key] / serving.grams`)
3. **`derive_density`** -- read from `entry['density']` hash (was `entry['serving']` volume fields)

The 5-tier resolution cascade in `to_grams` is unchanged:
1. Bare count -> `portions[~unitless]`
2. Weight unit (g/oz/lb/kg) -> direct conversion
3. Named portion -> `portions[stick]`, etc.
4. Volume unit -> density from `density` hash
5. Fail (partial)

## nutrition-entry Changes

Update output format to match new data model:
- `per_serving` + `serving` -> `nutrients` with `basis_grams`
- `serving.volume_amount/volume_unit` -> `density` hash
- Stop storing derived volume portions (cup/tbsp/tsp)
- Only store non-volume, non-derivable portions

## Data Migration

Two existing entries (Flour, Sugar) converted to new format.

## Files Changed

- `bin/nutrition-usda` (new)
- `lib/familyrecipes/nutrition_calculator.rb` (data access paths)
- `bin/nutrition-entry` (output format)
- `resources/nutrition-data.yaml` (new format + migration)
- `test/nutrition_calculator_test.rb` (fixture format)
- `CLAUDE.md` (document new script)

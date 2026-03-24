# Nutrition Reporting Improvements

## Problem

The nutrition table's "missing data" reporting conflates three distinct situations
into one generic message, making it hard for users to know what's wrong or how to
fix it:

1. **Missing** — ingredient not in catalog at all. User needs to add it.
2. **Partial** — ingredient has catalog data but the recipe's unit can't be
   resolved to grams (e.g., `Eggs, 4` when `~unitless` portion isn't defined).
   User needs to add a portion size.
3. **Skipped** — "to taste" ingredients with no quantity. Expected behavior, but
   currently invisible to the user.

Additionally, the Eggs seed data is missing a `~unitless` portion entry, causing
silent calculation failures for bare-count egg recipes.

## Design

### Calculator Changes (`NutritionCalculator`)

Add `skipped_ingredients` to the `Result` struct. During `sum_totals`, when an
amount is `nil` (unquantified), record the ingredient name in the skipped list
instead of silently ignoring it. Filter out omit-set ingredients (water, ice)
from the skipped list.

### Job Changes (`RecipeNutritionJob`)

Serialize the new `skipped_ingredients` field into `nutrition_data` JSON alongside
`missing_ingredients` and `partial_ingredients`.

### View Changes (`_nutrition_table.html.erb` + `RecipesHelper`)

Replace the single merged note with three distinct notes, ordered by severity:

- **Missing:** `*Approximate. No nutrition data for: X, Y`
- **Partial:** `*Approximate. Could not calculate: X (unknown portion size)`
- **Skipped:** `Not included (no quantity specified): Salt, Black pepper`

Each ingredient in missing/partial remains a clickable button (for members) to
open the nutrition editor. Skipped ingredients are plain text (no action needed
unless the user wants to add quantities to the recipe).

Stop merging missing + partial in `nutrition_missing_ingredients` — render each
list separately.

### Seed Data Fix

Add `~unitless: 50` to the Eggs entry in `ingredient-catalog.yaml` (50g = one
large egg, the standard assumption matching the existing `large` portion).

## Out of Scope

- Changing how the omit set works (water/ice silently excluded — no note needed).
- Changing the nutrition calculation math itself.
- UI redesign of the nutrition table.

# Merged Nutrition Entry Script

Replaces `bin/nutrition-entry` and `bin/nutrition-usda` with a single `bin/nutrition` script.

## Invocation

```
bin/nutrition                        # Interactive prompt for ingredient name
bin/nutrition "Cream cheese"         # Enter new or edit existing data
bin/nutrition --missing              # Report + batch iterate
bin/nutrition --manual "Flour"       # Force manual entry (skip USDA)
bin/nutrition --help                 # Usage info
```

API key auto-detection: USDA-first when `USDA_API_KEY` is present (env or `.env`), manual when absent with a one-line explanatory message. `--manual` forces manual mode even when key is available.

## New Ingredient Flow

1. Accept ingredient name (CLI arg or interactive prompt)
2. Resolve via grocery-info.yaml alias map
3. Find needed recipe units (for coverage display later)

### USDA mode (default when API key present)

4. Prompt for USDA search query (default: name with parentheticals stripped)
5. Search SR Legacy, display numbered results
6. User picks a result, searches again, or presses `q` to fall back to manual
7. Fetch full detail, extract nutrients/density/portions
8. Display full entry with unit coverage (OK/MISSING for each recipe unit)
9. Prompt: Save (s) / Edit (e) / Discard (d)

### Manual mode (default when no API key, or `--manual`, or `q` from USDA search)

4. Prompt for serving size (parsed via NutritionEntryHelpers)
5. Prompt for 11 nutrients in FDA label order (Enter = 0)
6. Show per-100g cross-check for eyeballing correctness
7. Prompt for brand/source
8. Prompt for portions (auto-portions from label, ~unitless, needed recipe units, custom)
9. Build density from serving size volume info
10. Display full entry with unit coverage
11. Prompt: Save (s) / Edit (e) / Discard (d)

Pressing `q` during USDA search gracefully falls back to manual entry (not abort).

## Edit Existing Ingredient

When an ingredient already has data, show the current entry and drop into the edit menu:

```
--- Flour (all-purpose) ---
  Nutrients (per 100g):
    calories: 364.0, fat: 0.98, ...
  Density: 125.0g per 1.0 cup
  Portions: (none)
  Source: USDA SR Legacy (FDC 168894)

  Unit coverage for recipes:
    cup: OK

  1. Re-import from USDA
  2. Nutrients
  3. Density
  4. Portions
  5. Source
  s. Save (no changes)
  d. Discard and start fresh
```

- **1** runs the USDA search-and-pick flow, replacing the entire entry, then returns to this menu
- **2** walks through 11 nutrients with current values as defaults (Enter to keep)
- **3** prompts for serving size, replacing the density block
- **4** enters the portions prompt (existing portions, needed recipe units, add/remove)
- **5** prompts for new source string
- **s** saves current state
- **d** discards existing entry and starts the new-ingredient flow from scratch

## `--missing` Mode

### Phase 1: Report

Two groups, each sorted by recipe count descending:

```
Missing nutrition data (3):
  - Butter (4 recipes: Pizza Dough, Croissants, ...)
  - Heavy cream (2 recipes: ...)
  - Parsley (1 recipe: ...)

Missing unit conversions (1):
  - Cream cheese: 'stick' (2 recipes: ...)
```

### Phase 2: Batch iterate

Prompts `Enter data? (y/n)`. If yes, iterates starting with the most-used ingredient. Missing entries get the new-ingredient flow. Unresolvable-unit entries go straight to the edit menu. User can press `q` to stop.

## Technical Cleanup

- **Load once**: recipes and alias map loaded once at startup, passed through (currently re-parsed per ingredient)
- **Cosmetic rounding**: extend `save_nutrition_data` to also round `density.volume` (prevents float artifacts like `0.333333`)
- **Unit coverage everywhere**: show OK/MISSING for recipe units before every save, regardless of entry mode
- **Shared code stays in-script**: `load_nutrition_data`, `save_nutrition_data`, `resolve_name`, etc. live in `bin/nutrition`; `NutritionEntryHelpers` stays in `lib/` since it's used by other code

## Files Changed

- `bin/nutrition` (new, merges both scripts)
- `bin/nutrition-entry` (deleted)
- `bin/nutrition-usda` (deleted)
- `CLAUDE.md` (update script references)

## Prior Design

The density-first data model, USDA API integration, nutrient ID mapping, and portion classification are unchanged from the [USDA nutrition import design](2026-02-19-usda-nutrition-import-design.md). This document covers only the script merge and UX improvements.

# Import Write Path Fix

## Problem

ImportService has two bugs that compound each other on fresh-install imports:

**Bug 1: Catalog entries bypass CatalogWriteService.** `ImportService#upsert_catalog_entry`
does a raw `find_or_initialize_by` + `save!`, skipping the side effects that
`CatalogWriteService.upsert` provides: aisle sync to `kitchen.aisle_order` and
nutrition recalculation for affected recipes.

**Bug 2: ZIP import ordering guarantees stale nutrition.** `ExportService` writes
recipes before custom ingredients. `ImportService` processes entries in stream
order, so recipes are imported first. Each recipe fires `RecipeNutritionJob` at
save time via `MarkdownImporter`, but the custom catalog entries haven't been
imported yet — nutrition is computed against the global seed catalog only and
never corrected.

**Bug 3: Kitchen preferences not exported.** `aisle_order` (grocery aisle
sequence) and category positions (homepage ordering) are not included in the
export. A fresh install loses the user's custom ordering for both.

## Approach

Reorder import phases so catalog entries are in place before recipes, route
catalog imports through a new `CatalogWriteService.bulk_import` method, and
add aisle/category ordering to the export format.

## Export Format Changes

Three new files in the ZIP:

| File | Format | Content |
|------|--------|---------|
| `aisle-order.txt` | Newline-delimited | `kitchen.aisle_order` |
| `category-order.txt` | Newline-delimited | Category names in position order |
| `custom-ingredients.yaml` | YAML (unchanged) | Kitchen catalog overrides |

Both `.txt` files are one name per line; order is the data. On import, missing
files (older exports) are gracefully skipped.

## Import Ordering

Old order (stream-sequential):

    recipes → quick bites → custom ingredients

New order (buffered, phased):

    Phase 1: aisle-order.txt      → restore kitchen.aisle_order
    Phase 2: category-order.txt   → store ordering for Phase 6
    Phase 3: custom-ingredients    → CatalogWriteService.bulk_import
    Phase 4: quick bites           → direct assignment (unchanged)
    Phase 5: recipes               → RecipeWriteService.create (catalog now in place)
    Phase 6: apply category order  → set positions on categories created in Phase 5

Phase 2/6 split: categories are created on-demand by `RecipeWriteService.create`
→ `find_or_create_category`. We read the ordering early but apply positions
after recipes have been imported.

## CatalogWriteService.bulk_import

New class method:

    CatalogWriteService.bulk_import(kitchen:, entries_hash:)

`entries_hash` is the parsed YAML hash (`{ "flour" => { "aisle" => "Baking", ... } }`).

Steps:
1. **Save all entries** — `find_or_initialize_by` + `assign_attributes(attrs_from_yaml)`
   + `save!`. Collect persisted count and validation errors.
2. **Bulk aisle sync** — collect non-nil, non-`'omit'` aisles. Diff against
   `kitchen.parsed_aisle_order`. Append new aisles in one `update!`.
3. **Bulk nutrition recalc** — find existing recipes referencing any imported
   ingredient (via `IngredientResolver` variant matching). Run
   `RecipeNutritionJob.perform_now` for each. On fresh install this is a no-op
   (no recipes yet). On re-import it catches stale recipes.
4. **No broadcast** — ImportService broadcasts once at the end.

Returns a count of persisted entries + an array of error strings.

Uses `attrs_from_yaml` (not `assign_from_params`). The web path and import path
have different input shapes; both are valid. Model validations and `before_save`
callbacks handle normalization regardless of assignment path.

## ImportService Changes

Replace stream-and-process with classify-and-buffer. `process_zip` reads all
entries into a typed hash, then `process_buffered_entries` runs the six phases.
Classification uses existing predicates plus two new ones for `.txt` settings.

`upsert_catalog_entry` and `import_ingredients` are deleted — logic moves to
`CatalogWriteService.bulk_import`.

Non-ZIP imports (individual .md files) are unaffected.

## ExportService Changes

Three new methods: `add_aisle_order`, `add_category_order`, plus updated write
order (settings first for readability). No changes to existing methods.

## Testing

**CatalogWriteService:**
- `bulk_import` creates entries from YAML hash
- `bulk_import` syncs new aisles in one pass, skips 'omit'
- `bulk_import` recalculates nutrition for existing affected recipes
- `bulk_import` returns count + errors for invalid entries
- `bulk_import` is a no-op for empty hash

**ImportService:**
- Existing ingredient import tests updated to verify aisle sync and nutrition
- Round-trip: export kitchen with catalog + aisle order + category order, import
  into empty kitchen, assert all restored
- Import with `aisle-order.txt` restores kitchen.aisle_order
- Import with `category-order.txt` restores category positions
- Import without settings files (old format) works — graceful degradation

**ExportService:**
- Export includes `aisle-order.txt` and `category-order.txt` when data present
- Export omits settings files when data is blank

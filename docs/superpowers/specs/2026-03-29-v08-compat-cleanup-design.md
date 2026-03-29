# v0.8 Alpha: Backward-Compatibility Cleanup — Design Spec

## Context

The app is approaching v0.8 alpha. No one else uses it yet; the production
instance will be nuked and rebuilt from scratch before alpha. There is no
backward compatibility to maintain with any prior version. This cleanup
establishes the current schema and data formats as the absolute baseline.

## Scope

### A. Consolidate database migrations

Replace all 15 migration files (`001_create_schema.rb` through
`015_normalize_quick_bites.rb`) with a single `001_create_schema.rb` that
creates the current schema. The new migration reproduces `db/schema.rb`
exactly — no data migration logic, no format conversion, no inline parsers.
`schema_migrations` version resets to `1`.

### B. Remove model/service compat code

**`IngredientCatalog.aisle_attrs_from_yaml`** (line 75-80): The old
`aisle: 'omit'` YAML format no longer exists — all entries use
`omit_from_shopping: true`. Remove the `aisle == 'omit'` detection and
simplify the method to read both fields directly.

**`Kitchen::MAX_AISLE_NAME_LENGTH`** (line 33): This constant is a thin alias
for `FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH`, added originally
for backward compat. Inline the canonical constant at the two call sites
(`AisleWriteService`) and delete the alias from Kitchen.

### C. Remove JS localStorage/sessionStorage compat code

**`grocery_ui_controller.js`:**
- `cleanupOldStorage()` (line 200-204) and its call in `connect()` (line 24):
  removes a deprecated `grocery-aisles-*` localStorage key that no longer
  exists.
- `cleanupCartStorage()` (line 297-301) and its call in `connect()` (line 25):
  removes a deprecated `grocery-in-cart-*` sessionStorage key.
- Boolean-to-object collapse format conversion (line 264-266): converts old
  boolean collapse state to the current `{ to_buy, on_hand }` object format.

**`recipe_state_controller.js`:**
- String-to-number `scaleFactor` coercion (line 103): `typeof scaleFactor ===
  'string' ? parseFloat(scaleFactor) : scaleFactor`. The `saveRecipeState()`
  method (line 67) already writes a number, so the string path is dead code.

**`nutrition_editor_controller.js`:**
- Stale sessionStorage key cleanup (line 640-641): removes old
  `editor:section:*` keys from a naming scheme that no longer exists.

### D. Clean up compat-specific tests

**`catalog_write_service_test.rb`** (line 375-384): Delete the test
`bulk_import converts old aisle omit to omit_from_shopping` — the format
it tests no longer exists.

**`vulgar_fractions_test.rb`** (line 156-158): Rename
`test_backward_compatible_without_unit` to `test_format_without_unit` — the
test exercises a valid default-argument path, not backward compat.

**`search_match_test.mjs`** (line 31): Remove the comment
`// Single token — backward compatible` — the behavior is just normal
functionality, not compat.

## Out of scope

- Feature work, new tests, or refactoring unrelated to compat cleanup.
- Changes to `db/seeds.rb` or seed data files — they're already current.
- The `VulgarFractions.format` method signature itself — the default argument
  is normal API design, not compat.

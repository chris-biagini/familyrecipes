# Alias Cross-Collisions in Ingredient Catalog — Design

GitHub Issue: #193
Date: 2026-03-07

## Problem

Ingredient catalog aliases (JSON arrays on individual entries) have no
cross-entry collision detection. Three collision types exist:

1. **Alias vs alias** — two entries declare the same alias (confirmed:
   "Kosher salt" on both `Salt (Table)` and `Salt (Kosher)`).
2. **Alias vs canonical name** — partially protected by `add_alias_keys`
   but doesn't check the extras hash or do full case-insensitive matching.
3. **No write-time validation** — `CatalogWriteService#upsert` accepts
   aliases that shadow other entries.

## Approach

Hybrid: lightweight write-time checks + collision reporting at sync time.
Warn on existing data; block new bad data.

## Changes

### 1. Fix seed data

Remove "Kosher salt" alias from `Salt (Table)`. Keep it on `Salt (Kosher)`
where it semantically belongs.

### 2. `add_alias_keys` collision logging

When `extras[v]` already maps to a different entry, log a warning via
`Rails.logger.warn` and skip (first-wins, but now visible). Current silent
`||=` behavior is preserved but collisions are no longer invisible.

### 3. Write-time validation in `CatalogWriteService#upsert`

Before save, check proposed aliases against:

- **Canonical names**: query `IngredientCatalog` (global + kitchen scope)
  for entries whose `ingredient_name` matches an alias (NOCASE collation).
- **Other aliases**: collect aliases from other entries in scope, check for
  case-insensitive overlap.

Collisions produce ActiveRecord validation errors — the save is blocked and
the controller renders standard error messages.

### 4. `catalog:sync` collision reporting

After building entries from YAML, build the full alias map and detect
alias-vs-alias and alias-vs-canonical collisions. Print warnings to stdout
but don't abort the sync.

### 5. Test coverage

- **YAML catalog integrity test**: load full YAML, assert no alias appears
  on multiple entries and no alias matches a canonical name.
- **`CatalogWriteService` validation tests**: upsert rejects aliases
  colliding with canonical names and with other entries' aliases.
- **`add_alias_keys` collision test**: overlapping aliases → first wins,
  warning logged.

## Design decisions

- **Warn at sync, block at write**: seed data issues shouldn't prevent app
  boot; interactive saves should be strict.
- **First-wins for runtime**: deterministic because YAML ordering is stable.
  Logging makes collisions visible without crashing.
- **No schema change**: aliases stay as JSON column. Write-time queries are
  cheap enough for an admin operation.

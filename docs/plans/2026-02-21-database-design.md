# Database Design: ActiveRecord Schema for Recipe Storage

**Date:** 2026-02-21
**Status:** Approved

## Context

The family recipes project is a static site generator that parses Markdown recipe files into HTML. We're adding a PostgreSQL database alongside the existing static build to support a future Rails-based web editor, Docker deployment, and multi-user access. The Markdown files remain the source of truth for now; the database is a runtime artifact populated by seeds.

## Decisions

- **Approach:** Rails-managed schema with ActiveRecord models, separate from the existing pure-Ruby domain classes. No mixing of persistence into domain classes.
- **Database:** PostgreSQL everywhere (dev and production). No SQLite.
- **Normalization:** Fully normalized from the start — separate tables for recipes, steps, ingredients, and cross-references. Enables cross-recipe queries (ingredient index, grocery builder) without deserializing JSON.
- **Source of truth:** `source_markdown` column is canonical. Structured columns are derived from it via the parser. This will flip to structured-data-as-canonical when we build the web editor.
- **Nutrition data:** Moved into the database as a `nutrition_entries` table, replacing `resources/nutrition-data.yaml` at runtime.
- **Quick Bites:** Stored in the `recipes` table with `quick_bite: true`. No steps; ingredients have `step_id: null`.
- **Cross-references:** Live resolution via foreign key to target recipe. No snapshotting.
- **Categories:** Plain string column, not a lookup table.

## Schema

### recipes

| Column | Type | Constraints |
|---|---|---|
| id | bigint | PK (Rails default) |
| title | string | not null |
| slug | string | not null, unique index |
| description | text | nullable |
| category | string | not null, index |
| makes | string | nullable (raw "12 pancakes") |
| serves | integer | nullable |
| footer | text | nullable |
| source_markdown | text | not null |
| version_hash | string | not null (SHA256 of source_markdown) |
| quick_bite | boolean | not null, default: false |
| created_at | datetime | |
| updated_at | datetime | |

`slug` is the unique business key (URLs, seed idempotency). `id` is the surrogate key for foreign keys. `makes` is stored as a raw string; `makes_quantity` and `makes_unit_noun` are parsed at the application level.

### steps

| Column | Type | Constraints |
|---|---|---|
| id | bigint | PK |
| recipe_id | bigint | not null, FK → recipes, index |
| position | integer | not null |
| tldr | string | not null |
| instructions | text | nullable |
| created_at | datetime | |
| updated_at | datetime | |

`position` preserves step order (set from array index during seeding). Validation that a step must have ingredients or non-empty instructions is application-level.

### ingredients

| Column | Type | Constraints |
|---|---|---|
| id | bigint | PK |
| step_id | bigint | nullable, FK → steps, index |
| recipe_id | bigint | not null, FK → recipes, index |
| position | integer | not null |
| name | string | not null |
| quantity | string | nullable (raw "75 g", "1/2 cup") |
| prep_note | string | nullable |
| created_at | datetime | |
| updated_at | datetime | |

`recipe_id` denormalized for direct cross-recipe queries. `step_id` nullable for Quick Bites. `quantity` stored as raw string; parsing into value/unit happens in Ruby. `name` is the raw name as written; alias resolution and singularization happen at query time.

### cross_references

| Column | Type | Constraints |
|---|---|---|
| id | bigint | PK |
| step_id | bigint | not null, FK → steps, index |
| recipe_id | bigint | not null, FK → recipes, index |
| target_recipe_id | bigint | not null, FK → recipes, index |
| position | integer | not null |
| multiplier | decimal | not null, default: 1.0 |
| prep_note | string | nullable |
| created_at | datetime | |
| updated_at | datetime | |

`recipe_id` denormalized from step for direct "what references this recipe?" queries. `position` shares sequence with ingredients within a step — merged and sorted in Ruby at render time. `multiplier` is decimal to avoid float precision issues. Quick Bites never have cross-references, so `step_id` is not nullable.

### nutrition_entries

| Column | Type | Constraints |
|---|---|---|
| id | bigint | PK |
| ingredient_name | string | not null, unique index |
| basis_grams | decimal | not null |
| calories | decimal | not null |
| fat | decimal | not null |
| saturated_fat | decimal | not null |
| trans_fat | decimal | not null |
| cholesterol | decimal | not null |
| sodium | decimal | not null |
| carbs | decimal | not null |
| fiber | decimal | not null |
| total_sugars | decimal | not null |
| added_sugars | decimal | not null |
| protein | decimal | not null |
| density_grams | decimal | nullable |
| density_volume | decimal | nullable |
| density_unit | string | nullable |
| portions | jsonb | nullable |
| sources | jsonb | nullable |
| created_at | datetime | |
| updated_at | datetime | |

Replaces `resources/nutrition-data.yaml`. The 11 FDA-label nutrients are explicit columns for aggregate queries. `density_*` columns are nullable as a group (all-or-none enforced at application level). `portions` and `sources` are JSONB for variable-structure data. `ingredient_name` is the lookup key, not a foreign key to the ingredients table — nutrition data is reference data joined by canonical name after alias resolution.

## Relationships

```
recipes 1──N steps
recipes 1──N ingredients (denormalized, also through steps)
steps   1──N ingredients
steps   1──N cross_references
recipes 1──N cross_references (denormalized, also through steps)
recipes 1──N cross_references (as target, via target_recipe_id)
```

## Seed Strategy

- `db/seeds.rb` reads `recipes/**/*.md` and `recipes/Quick Bites.md`
- Parses using the existing domain classes (`Recipe.parse`, `QuickBite`)
- Maps parsed structures into ActiveRecord model inserts
- Idempotent on slug (`find_or_create_by`)
- Also loads `resources/nutrition-data.yaml` into `nutrition_entries`
- Category derived from front matter, same as today

## Parser Refactor

`Recipe.parse` is refactored to accept a raw Markdown string with path/category as optional metadata. The same parser works for:
1. Static site generation (reading from filesystem)
2. Seed loading (reading from filesystem into database)
3. Future web editor (Markdown stored in database)

This is a pure refactor — existing tests and `bin/generate` must continue to work identically.

## Dual Path

- `bin/generate` continues unchanged: Markdown → HTML → `output/web/`
- `rails db:create db:migrate db:seed` populates the database from the same Markdown files
- The two paths share the same parser and source files but are otherwise independent

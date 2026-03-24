# Normalize Quick Bites into AR Models

**Date:** 2026-03-24
**Status:** Draft
**GitHub:** #286

## Problem

Quick Bites are first-class data objects — selected on the menu page,
referenced by ID in meal plan selections, their ingredients flow into the
shopping list and ingredient catalog — but they're stored as raw plaintext in
`Kitchen#quick_bites_content` and parsed on-the-fly by
`FamilyRecipes.parse_quick_bites_content`.

Their IDs are derived from title slugification, making them fragile (rename
breaks selections). Six consumers re-parse the blob on every request. QB
ingredients participate in the catalog ecosystem (`IngredientResolver`
canonicalizes them, `ShoppingListBuilder` merges them with recipe ingredients)
but aren't queryable via SQL.

Additionally, Quick Bites have their own parallel category system (subcategory
strings like "Snacks", "Breakfasts") that duplicates the recipe `categories`
table. On the menu page, this forces users to look in two separate places for
related items — homemade spaghetti under recipes, jarred-sauce spaghetti under
Quick Bites.

## Design

### Data Model

Two new tables, one modified table, one dropped column.

**`quick_bites` table:**

| Column        | Type    | Constraints                |
|---------------|---------|----------------------------|
| `id`          | integer | PK                         |
| `kitchen_id`  | integer | FK → kitchens, not null    |
| `category_id` | integer | FK → categories, not null  |
| `title`       | string  | not null                   |
| `position`    | integer | not null (global display order)  |
| `created_at`  | datetime| not null                   |
| `updated_at`  | datetime| not null                   |

Indexes: `[kitchen_id, category_id]` for scoped queries,
`[kitchen_id, title]` unique for write service title matching.

**`quick_bite_ingredients` table:**

| Column          | Type    | Constraints                  |
|-----------------|---------|------------------------------|
| `id`            | integer | PK                           |
| `quick_bite_id` | integer | FK → quick_bites, not null   |
| `name`          | string  | not null                     |
| `position`      | integer | not null (preserves order)   |

Index: `[quick_bite_id]` for eager loading.

**`meal_plan_selections` change:** QB rows switch from slug strings
(`"hummus-with-pretzels"`) to stringified integer PKs (`"42"`). The column
remains string-typed since recipe selections still use slugs.

**String-vs-integer boundary:** `selectable_id` is a string column, so
`MealPlanSelection.quick_bite_ids_for` returns string values. Consumers that
compare against integer `QuickBite#id` must coerce — either `ids.map(&:to_i)`
at the query boundary or `.to_s` at the comparison point. The view layer
(`@selected_quick_bites.include?(item.id)`) must use consistent types.
Standardize on integer IDs: `quick_bite_ids_for` returns `.map(&:to_i)`.

**Dropped:** `Kitchen#quick_bites_content` text column.

### AR Models

**`QuickBite`** — `belongs_to :kitchen`, `belongs_to :category`,
`has_many :quick_bite_ingredients, dependent: :destroy`.
`acts_as_tenant :kitchen`. Validates presence of title and category.

Provides duck-type interface matching what consumers expect:

- `#ingredients_with_quantities` → `[["Bread", [nil]], ["Peanut Butter", [nil]]]`
- `#all_ingredient_names` → `["Bread", "Peanut Butter"]`

These methods read from the `quick_bite_ingredients` association, maintaining
compatibility with `ShoppingListBuilder` and `RecipeAvailabilityCalculator`.

**`QuickBiteIngredient`** — `belongs_to :quick_bite`. Minimal model: `name`
and `position`. No catalog FK (names resolve through `IngredientResolver` at
query time, same as recipe ingredients).

**`Category`** — gains `has_many :quick_bites` alongside existing
`has_many :recipes`. No schema change needed.

**`Kitchen`** — gains `has_many :quick_bites, dependent: :destroy`. Drops
`parsed_quick_bites`, `quick_bites_by_subsection`, and the
`clear_parsed_quick_bites_cache` hook.

### Migration

Single migration that:

1. Creates `quick_bites` and `quick_bite_ingredients` tables.
2. For each kitchen, parses `quick_bites_content` using the existing parser.
   Maps each subcategory name (e.g., "Snacks") to an existing `Category` by
   name — creates the category if it doesn't exist.
3. Inserts `QuickBite` and `QuickBiteIngredient` rows from parsed data.
4. Rewrites `meal_plan_selections` QB rows: matches old slug IDs against
   migrated QuickBite titles (re-slugify to match), replaces with the new
   integer PK.
5. Drops `quick_bites_content` from `kitchens`.

Uses raw SQL and inline model stubs — no application model references per
project conventions.

### Consumer Updates

**`ShoppingListBuilder`** — Replace `@kitchen.parsed_quick_bites.select { ... }`
with `QuickBite.where(id: ids).includes(:quick_bite_ingredients)`. The
duck-type interface means aggregation logic (`ingredients_with_quantities`,
`merge_ingredient`) stays the same.

**`RecipeAvailabilityCalculator`** — Replace `@kitchen.parsed_quick_bites`
with `@kitchen.quick_bites.includes(:quick_bite_ingredients)`. Availability
computation unchanged — still iterates all QBs, calls `all_ingredient_names`.

**`MenuController#show`** — Remove `@quick_bites_by_subsection`. QB data
loads per-category since QBs now belong to categories. Selected QB IDs
become integer sets.

**`MealPlanWriteService`** — `apply_select` passes integer IDs for QB
toggles instead of slugs.

**`Kitchen.reconcile_meal_plan_tables`** — Prune stale QB selections using
`kitchen.quick_bite_ids` (simple PK pluck) instead of parsing text to
extract slugs.

**`SearchDataHelper#ingredient_corpus`** — Enhancement: include QB ingredient
names in the corpus so search overlay covers the full grocery vocabulary.

**`IngredientRowBuilder`** — Replace `kitchen.parsed_quick_bites` with
`kitchen.quick_bites.includes(:quick_bite_ingredients)`. The duck-type
interface (`all_ingredient_names`, `title`, `id`) means logic stays the same,
but `qb.id` changes from string slug to integer (affects dedup keys).

**`ExportService`** — Currently writes `kitchen.quick_bites_content` as
`quick-bites.txt`. After the column is dropped, serialize from AR models via
`QuickBitesSerializer` to produce the same plaintext format. Export format
stays compatible.

**`ImportService`** — Currently calls `QuickBitesWriteService.update` with
raw content. This continues to work since the write service's plaintext path
parses first then saves to AR. No format change needed — existing exports
remain importable.

**`db/seeds.rb`** — Currently loads `Quick Bites.md` into
`kitchen.quick_bites_content`. Update to use `QuickBitesWriteService.update`
(which parses plaintext and saves to AR).

**`Category.cleanup_orphans`** — Must check for both recipes and quick bites
before destroying: `where.missing(:recipes).where.missing(:quick_bites)`.
Without this, categories with only QBs would be destroyed on every
`Kitchen.finalize_writes` call.

### Editor

The dual-mode editor (plaintext + graphical) continues to work. The
persistence layer changes underneath.

**`QuickBitesWriteService`:**
- `update_from_structure(kitchen:, structure:)` — Maps IR categories/items
  to AR creates/updates/deletes. Matches existing QBs by title for updates,
  removes absent ones, creates new ones. Saves `quick_bite_ingredients` as
  nested children.
- `update(kitchen:, content:)` — Parses plaintext via
  `FamilyRecipes.parse_quick_bites_content` first, then saves via the same
  AR path. The parser remains for editor use (plaintext → IR conversion) but
  is no longer the storage mechanism.

**`QuickBitesSerializer`:**
- `to_ir` gains an AR-backed variant: reads from `kitchen.quick_bites` grouped
  by category, produces the same IR hash the editor expects.
- `serialize` unchanged — still needed for plaintext mode display.

**`MenuController` editor endpoints:**
- `quick_bites_content` / `quickbites_editor_frame` — Build IR from AR models
  via `QuickBitesSerializer.to_ir`.
- `/parse` and `/serialize` — Unchanged, still needed for mode-switching
  within the editor session.

### Menu Page Rendering

Categories now contain both recipes and quick bites. Each category section
on the menu page renders:

1. Recipes (existing behavior)
2. A compact QB subsection at the bottom — same selection checkboxes and
   availability badges, but visually diminutive

Availability badges work the same way, keyed by QB id (now integer).

### Removed Code

- `FamilyRecipes::QuickBite` value object (replaced by AR model)
- `FamilyRecipes.parse_quick_bites_content` — **retained** for editor
  plaintext parsing, but no longer used for storage/retrieval
- `Kitchen#parsed_quick_bites` and `#quick_bites_by_subsection`
- `Kitchen#clear_parsed_quick_bites_cache`
- `Kitchen#quick_bites_content` column

### What This Doesn't Change

- The plaintext format and parser (still used by the editor's plaintext mode)
- The graphical editor UI and IR structure
- The `/parse` and `/serialize` endpoints for mode-switching
- `QuickBitesSerializer#serialize` (IR → plaintext)
- The availability badge computation logic (keys change from string slugs
  to integer PKs, but the computation itself is unchanged)
- The shopping list aggregation logic (duck-type interface preserved)

## Testing

- Migration test: round-trip data integrity (parse → insert → read back
  matches original)
- `QuickBite` model: validations, duck-type interface methods,
  `acts_as_tenant` scoping
- `QuickBitesWriteService`: structure save, plaintext save, delete/reorder
- `ShoppingListBuilder`: QB ingredient aggregation with AR models
- `RecipeAvailabilityCalculator`: availability with AR-backed QBs
- `MenuController`: category-grouped display, selection toggle with integer IDs
- `MealPlanSelection`: prune stale with integer PKs
- `ExportService`/`ImportService`: round-trip with AR-backed QBs
- `Category.cleanup_orphans`: QB-only categories preserved
- Seeds: `Quick Bites.md` loads into AR models

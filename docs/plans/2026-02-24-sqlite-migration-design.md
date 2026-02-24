# SQLite Migration Design

GitHub Issue: #80

## Summary

Migrate from PostgreSQL to SQLite, clean up the database schema, retool seeds, and wire up the Rails 8 multi-database pattern with Solid Cable and Solid Queue.

## Three-Database Architecture

Rails 8 multi-database with three SQLite files, each with its own write lock:

| Database | File | Purpose |
|----------|------|---------|
| **primary** | `storage/<env>.sqlite3` | App data (recipes, kitchens, users, etc.) |
| **cable** | `storage/<env>_cable.sqlite3` | Solid Cable messages (ephemeral pub/sub) |
| **queue** | `storage/<env>_queue.sqlite3` | Solid Queue jobs (background work) |

SQLite tuning pragmas: WAL journal mode, relaxed sync, memory-mapped I/O, 64MB page cache.

Solid Queue runs inside the Puma process (no separate worker). Jobs continue to use `perform_now` — the infrastructure is in place for `perform_later` when needed.

## Schema Changes

### Fresh migration

Delete all existing migrations. Replace with a single migration defining the clean schema for SQLite. Solid Cable and Solid Queue get their own migration directories (`db/cable_migrate/`, `db/queue_migrate/`).

### Dropped tables

- **`recipe_dependencies`** — redundant with `cross_references`. The dependency graph is derivable via `CrossReference.joins(:step).select('steps.recipe_id AS source_recipe_id, cross_references.target_recipe_id')`.
- **`site_documents`** — only stored `quick_bites`, `nutrition_data`, and `site_config`. Each moves elsewhere (see below).
- **`solid_cable_messages`** — moves to the cable database (managed by Solid Cable's own migrations).

### Renamed tables

- **`ingredient_profiles` → `ingredient_catalog`** — better communicates its role as the comprehensive reference for everything known about an ingredient (nutrition, density, portions, aisle). The global/kitchen overlay pattern (kitchen_id NULL = global, non-null = kitchen override) is unchanged.

### New columns

- **`kitchens.quick_bites_content`** (text) — Quick Bites markdown content, formerly a SiteDocument row. Web-editable via the groceries page.

### Column type changes

- `jsonb` → `json` on: `grocery_lists.state`, `recipes.nutrition_data`, `ingredient_catalog.portions`, `ingredient_catalog.sources`. SQLite stores JSON as TEXT; Rails handles serialization transparently.

### Preserved tables (unchanged)

`kitchens`, `users`, `memberships`, `sessions`, `connected_services`, `categories`, `recipes`, `steps`, `ingredients`, `cross_references`, `grocery_lists`

## Site Config

Replace the `site_config` SiteDocument with `config/site.yml`, loaded at boot via a Rails initializer:

```ruby
Rails.configuration.site = config_for(:site)
```

Accessed as `Rails.configuration.site.site_title`, etc. No database query, no fallback logic.

## Seed Cleanup

### Merged ingredient file

Merge `nutrition-data.yaml` and `grocery-info.yaml` into a single `db/seeds/resources/ingredient-catalog.yaml`. One entry per ingredient, all properties together:

```yaml
Eggs:
  aisle: Refrigerated
  nutrients:
    basis_grams: 100.0
    calories: 143.0
    # ... remaining FDA nutrients
  density:
    grams: 243.0
    volume: 1.0
    unit: cup
  portions:
    medium: 44.0
    large: 50.0
    "~unitless": 50.0
  sources:
    - type: usda
      dataset: SR Legacy
      fdc_id: 171287
      description: "Egg, whole, raw, fresh"

Bread:
  aisle: Fresh Bakery
```

Aisle-only entries have just `aisle:`. Drop alias support (no longer needed).

### Deleted seed files

- `db/seeds/resources/nutrition-data.yaml` — merged into ingredient-catalog.yaml
- `db/seeds/resources/grocery-info.yaml` — merged into ingredient-catalog.yaml
- `db/seeds/resources/site-config.yaml` — replaced by config/site.yml

### Revised seed flow

1. Create kitchen + user + membership
2. Import recipes via `MarkdownImporter`
3. Load Quick Bites content onto the kitchen record
4. Seed `ingredient_catalog` from `ingredient-catalog.yaml` (single pass)

## Gem Changes

- Remove `pg`
- Add `sqlite3`
- Add `solid_queue`
- Keep `solid_cable`

## Docker Simplification

No more PostgreSQL container. One container, one volume:

```yaml
services:
  app:
    image: ghcr.io/chris-biagini/familyrecipes:latest
    environment:
      RAILS_ENV: production
      SECRET_KEY_BASE: CHANGE_ME
    ports:
      - "3030:3030"
    volumes:
      - app_storage:/rails/storage

volumes:
  app_storage:
```

Dockerfile: remove `libpq-dev`, ensure `libsqlite3-dev` is present. Entrypoint still runs `db:prepare` and `db:seed`.

Environment variables dropped: `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`.

## Model and Code Changes

### Models

- `IngredientProfile` → `IngredientCatalog` (rename everywhere)
- `SiteDocument` → delete
- `RecipeDependency` → delete
- `Kitchen` — add `quick_bites_content` text column

### Controllers

- `HomepageController` — site config from `Rails.configuration.site`
- `GroceriesController` — Quick Bites via `current_kitchen.quick_bites_content`
- `RecipesController` — dependency tracking derived from `CrossReference` joins

### Services

- `MarkdownImporter` — remove `RecipeDependency` rebuild logic
- `ShoppingListBuilder` — rename `IngredientProfile` → `IngredientCatalog`

### Jobs

- `RecipeNutritionJob`, `CascadeNutritionJob` — rename references, keep `perform_now`

### CLI

- `bin/nutrition` — read/write `ingredient-catalog.yaml` instead of `nutrition-data.yaml`

### CI / GitHub Actions

- Remove PostgreSQL service container from test workflow
- Update Dockerfile build deps

## Risks

- **Decimal precision**: SQLite stores decimals as REAL (floating point). Acceptable for recipe-scale arithmetic.
- **Partial indexes**: SQLite 3.30+ supports WHERE clauses in indexes. The `ingredient_catalog` global uniqueness index works as-is.
- **`acts_as_tenant`**: Pure ActiveRecord scoping, fully database-agnostic.
- No PostgreSQL-specific SQL exists in application code (only in old migrations being deleted).

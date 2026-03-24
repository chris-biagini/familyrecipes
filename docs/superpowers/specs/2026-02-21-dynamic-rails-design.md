# Fully Dynamic Rails App — Design Document

**Date:** 2026-02-21
**Branch:** `rails-development`
**Status:** Approved

## Goal

Replace the static site generator with a fully dynamic Rails 8 application. All four pages (homepage, recipes, ingredient index, groceries) render live from a PostgreSQL database. The static pipeline (`bin/generate`, `SiteGenerator`, `output/web/`) is retired. GitHub Pages continues serving from `main` until this branch is ready to ship.

This is the foundation for a web-based recipe editor and Docker-packaged homelab deployment.

## Data Model

### Tables

**categories** — `id`, `name`, `slug`, `position` (homepage ordering), timestamps

**recipes** — `id`, `category_id` (FK), `title`, `slug`, `description`, `makes_quantity`, `makes_unit_noun`, `serves`, `footer` (text), `markdown_source` (text), timestamps

**steps** — `id`, `recipe_id` (FK), `title`, `summary`, `instructions` (text), `position`, timestamps

**ingredients** — `id`, `step_id` (FK), `name`, `quantity`, `unit`, `prep_note`, `position`, timestamps

**recipe_dependencies** — `id`, `source_recipe_id` (FK), `target_recipe_id` (FK), timestamps

### Key decisions

- **`markdown_source`** on Recipe stores the original markdown. The editor will show this; on save, it's re-parsed into structured columns. Structured data renders the page; markdown is the editing format.
- **`recipe_dependencies`** is a thin join table tracking which recipes reference which. No multiplier, no position, no semantics. The *meaning* of a cross-reference lives in the markdown and is resolved at render time by the parser. This keeps cross-references flexible — they can evolve from "faux ingredient" to "inline import" or anything else without schema changes.
- **Ingredients table stores only real ingredients.** Cross-references (`@[Recipe Name]`) are not modeled as ingredients; they stay in markdown and are resolved at render time.
- **Nutrition stays in YAML.** `NutritionCalculator` reads `nutrition-data.yaml` at render time. No nutrition tables in the DB yet.
- **No Quick Bites table in v1.** Seed them as simplified recipes or add in a fast follow.

## Import Pipeline

When markdown is saved (seed, file import, or future editor):

1. **Parse** using existing classes: `LineClassifier` → `RecipeBuilder` → `Step`/`Ingredient` objects
2. **Upsert structured data** — Recipe, Steps, Ingredients rows from parsed output
3. **Resolve dependencies** — scan for `@[Recipe Name]` references, look up targets by slug, rebuild `recipe_dependencies` rows
4. **Cross-references do not become Ingredient rows** — they stay in markdown

The existing parser classes become the importer's engine. The current `Recipe` domain class (in `lib/familyrecipes/`) stays as a parser/value object, renamed to avoid collision with the ActiveRecord model (e.g., `FamilyRecipes::RecipeParser` or `FamilyRecipes::MarkdownImporter`).

## Routes

```ruby
root 'homepage#show'
resources :recipes, only: [:show], param: :slug
get 'index', to: 'ingredients#index'
get 'groceries', to: 'groceries#show'
```

Recipes move from `/:slug` to `/recipes/:slug` — conventional Rails routing, frees the root namespace for future routes (`/collections/vegetarian`, `/cuisine/thai`, `/settings`, etc.).

## Controllers

All controllers are thin — load from ActiveRecord, pass to views:

- **`HomepageController#show`** — recipes grouped by category → homepage view
- **`RecipesController#show`** — recipe by slug with eager-loaded steps/ingredients → recipe view
- **`IngredientsController#index`** — all ingredients grouped/sorted by name with their recipes → index view
- **`GroceriesController#show`** — all recipes with ingredients + aisle mappings → groceries view

## Views

```
app/views/
  layouts/
    application.html.erb       ← doctype, meta, stylesheet, nav, yield
  shared/
    _nav.html.erb
  homepage/
    show.html.erb
  recipes/
    show.html.erb
    _step.html.erb
    _ingredient.html.erb
    _nutrition_table.html.erb
  ingredients/
    index.html.erb
  groceries/
    show.html.erb
```

- Templates ported from `templates/web/` to proper Rails partials/layouts/helpers.
- `<base href>` replaced by Rails route helpers (`_path`/`_url`).
- Helper methods replace lambda-based rendering (`slugify`, `scalable_numbers`, `render_markdown`).
- Visual identity unchanged — same HTML structure, CSS classes, gingham tablecloth.

## Assets (Propshaft)

Files move from `resources/web/` to `app/assets/`:

- `stylesheets/` — `style.css`, `groceries.css`
- `javascripts/` — `recipe-state-manager.js`, `groceries.js`, `notify.js`, `wake-lock.js`
- `images/` — favicons, icons

Propshaft provides fingerprinting and cache-busting. Views use `stylesheet_link_tag`, `javascript_include_tag`, `image_path`. No build step, no bundling, no node.

## Seeding

A seed task (`db:seed` or custom rake task) populates the DB from `recipes/*.md`:

1. Scan `recipes/` subdirectories for `.md` files
2. Parse each with the parser pipeline
3. Create/update Category, Recipe, Step, Ingredient records
4. Build `recipe_dependencies` from `@[Recipe Name]` references
5. Handle Quick Bites separately

**Idempotent** — match on slug, upsert everything else. Safe to re-run.

The `recipes/` directory stays in the repo as canonical seed data. Once the editor exists, the database becomes the source of truth.

## What Gets Retired

- `bin/generate` — deleted
- `bin/serve` — deleted
- `SiteGenerator` — deleted
- `PdfGenerator` — deleted (PDF generation is not a Rails feature)
- `templates/web/` — deleted (replaced by `app/views/`)
- `output/` — deleted (nothing generates into it)
- `StaticOutputMiddleware` — deleted (Propshaft serves assets)
- `resources/web/` — emptied (assets move to `app/assets/`)
- `recipe_watcher.rb` initializer — deleted (no static site to regenerate)
- `bin/dev` simplified — just Puma, no WEBrick dual-server

## What Stays in `lib/familyrecipes/`

- `LineClassifier`, `RecipeBuilder`, `IngredientParser` — parser pipeline (import engine)
- `CrossReference` — resolves `@[Recipe Name]` at render time
- `IngredientAggregator` — groceries page ingredient summing
- `VulgarFractions`, `Inflector` — utility classes for views
- `ScalableNumberPreprocessor` — scaling feature
- `NutritionCalculator` — reads YAML, calculates at render time
- `Quantity` — value object for ingredient quantities

## Not In Scope

- Web editor (next project)
- Authentication (add with editor)
- Nutrition in the database (stays in YAML)
- Docker packaging (after app works)
- CI changes (main keeps deploying static site)
- Caching (not needed yet — render live, optimize later)

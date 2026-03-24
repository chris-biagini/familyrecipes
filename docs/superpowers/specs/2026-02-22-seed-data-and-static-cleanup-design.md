# Seed Data Reorganization & Static Build Cleanup

_2026-02-22_

## Problem

Seed data is spread across two top-level directories (`recipes/`, `resources/`) — a holdover from the static site generator era. Some YAML resources (site-config, nutrition-data) are still read from disk at runtime instead of the database. The GitHub Actions workflow references a deleted `bin/generate` script. The README describes a static site that no longer exists.

## Decisions

1. **Seed files move to `db/seeds/`** with one level of structure: `recipes/` (keeping category subdirs) and `resources/` (YAML files). This is standard Rails practice — seed data lives near `db/seeds.rb`.
2. **All YAML resources become SiteDocuments** in the database, seeded from the files on disk. This makes site-config, nutrition-data, grocery-aisles, and quick-bites all database-driven and web-editable.
3. **`bin/nutrition` continues editing the seed file on disk.** Run the tool, then `db:seed` to push changes to the DB. Same workflow as editing recipe markdown.
4. **GitHub Actions workflow**: comment out build/deploy steps, keep lint + test as CI.
5. **Disk fallbacks stay** in controllers for graceful degradation (if SiteDocument missing, read from seed file) but paths update to `db/seeds/`.

## New Directory Layout

```
db/seeds/
  recipes/
    Bread/
      Bagels.md
      ...
    Mains/
      ...
    Quick Bites.md
  resources/
    grocery-info.yaml
    nutrition-data.yaml
    site-config.yaml
```

Top-level `recipes/` and `resources/` directories are deleted after the move.

## SiteDocument Table

| SiteDocument name | Content format | Seed source | Runtime consumers |
|---|---|---|---|
| `site_config` | YAML | site-config.yaml | HomepageController, application layout |
| `grocery_aisles` | Markdown (converted from YAML at seed) | grocery-info.yaml | GroceriesController, IngredientsController |
| `nutrition_data` | YAML | nutrition-data.yaml | RecipesController |
| `quick_bites` | Markdown | Quick Bites.md | GroceriesController |

## Controller Changes

- **HomepageController**: load site config from `SiteDocument('site_config')` instead of disk YAML.
- **RecipesController**: load nutrition data from `SiteDocument('nutrition_data')` instead of disk YAML.
- **All controllers with disk fallbacks**: update fallback paths from `resources/` to `db/seeds/resources/`.

## Other Changes

- `db/seeds.rb` — new paths, seed `site_config` and `nutrition_data` documents.
- `bin/nutrition` — update YAML path to `db/seeds/resources/nutrition-data.yaml`.
- `.github/workflows/deploy.yml` — comment out build/deploy, keep lint+test.
- `README.md` — rewrite for Rails app reality.
- `CLAUDE.md` — update path references throughout.
- `.gitignore` — remove `output/` entry if present.

## Not Changing

- Parser classes (seed/import infrastructure, not static build code).
- The parsed-recipe bridge pattern in RecipesController.
- Test files (unless hardcoded paths need updating).

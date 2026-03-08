# Slug Collision Detection — Design

GitHub Issue: #197

## Problem

Two recipes with different titles can slugify to the same value (e.g.
"Cookies!" and "Cookies?" both → `cookies`). Currently the second silently
overwrites the first via `find_or_initialize_by(slug:)` in MarkdownImporter.

## Approach: Block + Skip-and-Report

**Rule:** If `slug` matches an existing recipe but the `title` differs, it's a
collision. Same-title re-import remains idempotent (intentional overwrite).

## Detection

`MarkdownImporter#find_or_initialize_recipe` raises
`MarkdownImporter::SlugCollisionError` when the found recipe's title doesn't
match the incoming title. The error message includes both titles so callers can
surface it. `SlugCollisionError < RuntimeError`.

## Caller Behavior

- **`RecipesController#create`** — already rescues `RuntimeError`; collision
  error gets caught, returns 422 JSON with the error message. User sees it in
  the editor.
- **`RecipesController#update`** — same handling. Rename "Cookies?" to
  "Cookies!" when "Cookies!" exists would be caught.
- **`ImportService#import_recipe_content`** — already rescues `StandardError`
  into `@errors`. Collision errors land there automatically, show up in the
  toast summary.

## Result Summary

`ImportsController#import_summary` already appends `Failed: ...` for errors.
No change needed — collisions appear as e.g. *"Imported 8 recipes. Failed:
Cookies.md: A recipe with a similar name already exists: 'Cookies?'"*

## What Doesn't Change

- `RecipeWriteService#update` with the *same* slug (editing an existing
  recipe) — MarkdownImporter finds the same record, title gets overwritten, no
  collision.
- ZIP re-import of an unchanged recipe — slug matches, title matches,
  idempotent overwrite.

## Tests

- Single import: slug collision raises error, returns 422
- Single import: same-title re-import still works
- ZIP import: collision skipped, reported in errors array
- ZIP import: internal collision (two files in same ZIP) — second file skipped
- Update: rename to colliding slug raises error
- Update: normal edit of existing recipe still works

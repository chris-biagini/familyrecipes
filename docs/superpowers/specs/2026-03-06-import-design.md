# Import Feature Design

## Overview

A single "Import" button on the homepage (next to "Export All Data") that accepts
ZIP files or individual recipe files (`.md`, `.txt`, `.text`). Import is
additive/upsert — it never deletes existing data.

## File Handling

**Input:** One or more files selected via a hidden `<input type="file" multiple>`
triggered by a styled Import button.

**Accepted extensions:** `.zip`, `.md`, `.txt`, `.text`.

**Routing logic:**

- If any selected file has `.zip` extension, process as a full backup import
  (only the first ZIP; ignore other files).
- Otherwise, treat all files as individual recipe files, import each to the
  "Miscellaneous" category.

**ZIP structure** (mirrors export format):

```
CategoryName/RecipeTitle.md    -> recipe with category
quick-bites.txt                -> replaces Kitchen#quick_bites_content
custom-ingredients.yaml        -> upsert IngredientCatalog entries
everything else                -> silently skipped
```

For recipe files inside a ZIP, the parent folder name determines the category.
Files at the ZIP root (no folder) go to "Miscellaneous."

### Quick Bites filename matching

Accept any of these basenames (case-insensitive): `quick-bites`, `quickbites`,
`quick bites`. Accept any of these extensions: `.txt`, `.md`, `.text`. Examples:
`Quick-Bites.md`, `quickbites.text`, `quick bites.txt`.

### Recipe file extensions

Inside a ZIP or as individual uploads, accept `.md`, `.txt`, and `.text` as
recipe files. Skip all other file types silently.

## Merge Behavior

| Data type          | Conflict key                | On conflict                                          |
|--------------------|-----------------------------|------------------------------------------------------|
| Recipes            | slug (kitchen-wide)         | Overwrite: update markdown_source, category, all fields |
| Quick Bites        | n/a (single blob)           | Full replace of `quick_bites_content`                |
| Custom ingredients | `ingredient_name`           | Upsert: overwrite all fields on match, create if new |

Import never deletes existing data not present in the import file.

## Service Architecture

### ImportService

`ImportService.call(kitchen:, files:)` — new service, sole entry point.

- `files` is an array of `ActionDispatch::Http::UploadedFile`.
- Detects ZIP vs individual files.
- For ZIP: extracts entries, routes each to the appropriate handler.
- For individual files: imports each as a recipe into "Miscellaneous" category.
- Returns a result struct with counts and errors:
  `{ recipes: 12, quick_bites: true, ingredients: 5, errors: ["Soup.md: parse error"] }`
- Calls `Kitchen#broadcast_update` once at the end (not per-recipe).

**Delegates to existing services:**

- `RecipeWriteService` for recipe create/update (which calls `MarkdownImporter`).
- `CatalogWriteService` for ingredient upserts.
- Direct assignment for `Kitchen#quick_bites_content`.

### ImportsController

`ImportsController#create` — POST endpoint, guarded by `require_membership`.

- Receives uploaded files from multipart form.
- Calls `ImportService.call`.
- Sets flash with summary: "Imported 12 recipes, 5 ingredients, and Quick Bites."
- On errors: "Imported 10 of 12 recipes. Failed: Soup.md (parse error)."
- Redirects to `home_path`.

## UI

A second button added to the `#export-actions` div on the homepage:

```
[Export All Data] [Import]
```

**Interaction flow:**

1. User clicks styled "Import" button.
2. Stimulus controller programmatically clicks the hidden file input.
3. Native file picker opens (accepts `.zip`, `.md`, `.txt`, `.text`, `multiple`).
4. User selects files; Stimulus controller catches the `change` event.
5. Controller submits the form (POST to `/import`).
6. Server processes, sets flash, redirects to homepage.

No confirmation dialog — import is non-destructive (upsert/additive only).

## Error Handling

- **Malformed recipe files:** catch parse errors, collect in errors array, continue
  with remaining files.
- **Malformed YAML:** report as error, skip ingredient import entirely.
- **Empty ZIP / no importable files:** flash "No importable files found."
- **Non-recipe files in ZIP:** silently skipped (handles `.DS_Store`,
  `__MACOSX/`, images, etc.).

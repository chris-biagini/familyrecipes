# Data Export Design

## Overview

Members-only feature to download all user data as a ZIP file. A button on the homepage triggers a `confirm()` dialog, then initiates the download.

## UI

Button at the bottom of `homepage/show.html.erb`, between an `<hr>` and the existing footer. Styled like the Select All button on the menu page.

```
  ...last category section...
  <hr>
  <div id="export-actions">
    <button class="btn">Export All Data</button>
  </div>
  <footer>
    <p>For more information, visit our project page on GitHub.</p>
  </footer>
```

On click: `confirm("Export all recipes, Quick Bites, and custom ingredients?")` — if OK, navigates to the download endpoint.

## Backend

**Route:** `GET /export` (scoped under the optional kitchen prefix).

**Controller:** `ExportsController#show` — members only. Generates a ZIP in-memory and sends it as a download.

**Service:** `ExportService` assembles the ZIP to keep the controller thin.

## ZIP Structure

```
ours-2026-03-05/
  recipes/
    Breads/
      Bagels.md
      Focaccia.md
    Mains/
      Detroit Pizza.md
  quick-bites.txt
  custom-ingredients.yaml
```

- **Recipes:** `markdown_source` written to `recipes/{category.name}/{recipe.title}.md`
- **Quick Bites:** `kitchen.quick_bites_content` verbatim — omitted if blank
- **Custom ingredients:** `IngredientCatalog.for_kitchen(kitchen)` serialized to YAML matching seed format — omitted if none exist

## Implementation Details

- `rubyzip` gem for ZIP generation
- No Stimulus controller — simple `confirm()` + navigation
- ZIP generated in-memory via `StringIO`
- `send_data` with `disposition: :attachment`
- Filename: `{kitchen-slug}-{YYYY-MM-DD}.zip`

## Access Control

Members only (`require_membership`), consistent with write-guarded operations.

## Testing

- Controller test: members-only access, ZIP contains expected files
- Service test: ZIP structure, category folder organization, YAML format

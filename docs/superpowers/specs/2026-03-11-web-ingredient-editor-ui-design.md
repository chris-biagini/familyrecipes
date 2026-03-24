# Web Ingredient Editor UI — USDA Import & Coverage

**Date:** 2026-03-11

## Context

The data layer is complete: `UsdaImportService`, `UsdaSearchController`,
`IngredientRowBuilder#coverage`, and `CatalogWriteService` all exist. The editor
form, table, and Stimulus controllers work. This design covers the remaining UI
gaps from GH #210.

## Decisions

- **Single dialog** — USDA search lives as an inline collapsible section within
  the existing editor form. No modal-on-modal.
- **Auto-populate, not review step** — USDA import auto-selects the best density
  and populates portions directly into form fields. Density alternatives
  available via a disclosure element for override.
- **Filter pill, not dashboard** — Coverage surfaces as a "Resolvable" filter
  pill in the existing summary bar, consistent with the other pills.
- **Compact list, not cards** — USDA results render as a scrollable list within
  the ~550px editor width.

## 1. USDA Import Panel

A `<details>` element at the top of the editor form, above Nutrition Information:

- Collapsed by default; open by default when the ingredient has no nutrition data.
- Contains a search input + "Search" button.
- Results appear as a compact scrollable list (max-height ~250px).
- Each result row: food description (bold, truncated), dataset badge (muted),
  nutrient preview line (`120 cal | 0g fat | 31g carbs | 1g protein`).
- Click a result → fetch full USDA detail → auto-populate all form fields
  (nutrients, density, portions, source metadata).
- Loading state: spinner on the clicked row while fetching.
- After import, the panel collapses and a small "Imported from USDA" badge
  appears next to the section title.
- Pagination via "More results" button at list bottom.

## 2. Density Candidates

After USDA import populates density fields:

- A `<details>` element labeled "Other USDA densities" appears below density
  inputs.
- Contains radio buttons for each candidate (e.g. "118g per 1 cup").
- Auto-selected best density is pre-checked.
- Selecting a different candidate updates the density form fields.
- Hidden when no USDA data or only one candidate.

## 3. Portion Candidates

After USDA import:

- Portions populate as normal editable portion rows (existing UI).
- User deletes unwanted portions, adds custom ones — no new UI pattern.
- The `~unitless` / "each" mapping already works in the existing portion row
  partial.

## 4. Coverage Filter

- Add a "Resolvable" filter pill to the existing summary bar.
- Shows count: e.g. "Resolvable (247/312)".
- When active, filters to show only ingredients with unresolvable units.
- Uses `IngredientRowBuilder#coverage` data via a `resolvable` data attribute on
  each table row.
- Per-ingredient unresolvable unit details already visible in the editor's
  "Recipe Units" section.

## 5. Data Flow

```
User opens editor → clicks "Import from USDA" details
  → types query, clicks Search
  → GET /usda/search?q=...&page=0 (JSON)
  → render result list in panel
  → user clicks a result
  → GET /usda/:fdc_id (JSON → UsdaImportService::Result)
  → auto-populate: nutrients, density, portions, source
  → show density candidates in <details> if multiple
  → user adjusts, saves normally via existing flow
```

## 6. Changes Required

No new endpoints needed. All backend APIs exist.

- **Views**: USDA panel in `_editor_form.html.erb`, coverage pill in
  `_summary_bar.html.erb`, `resolvable` data attribute in `_table_row.html.erb`.
- **Stimulus**: Extend `nutrition_editor_controller.js` with USDA
  search/import/density-candidate methods.
- **Stimulus**: Extend `ingredient_table_controller.js` with resolvable filter.
- **CSS**: USDA result list, density candidates, import badge.
- **Controller**: Pass coverage data to index view for filter pill count.

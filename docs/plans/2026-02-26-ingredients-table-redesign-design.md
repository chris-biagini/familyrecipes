# Ingredients Table Redesign

## Problem

The ingredients page has UX friction: summary counts are disconnected from filters, table headers are abbreviated and unsortable, row expansion adds a click before reaching the editor, and recipe display takes up a column without adding much value.

## Design

### Filter buttons with integrated counts

Replace the summary bar + filter pills with a single row of toggle buttons that double as the summary:

```
[All (129)]  [Complete (27)]  [Missing Nutrition (90)]  [Missing Density (12)]
```

- "All" active by default.
- Selecting a filter highlights it and filters the table.
- Search bar remains (above filter buttons).
- Old summary bar, "Needs Attention" pill, and "Showing X of Y" footer removed.
- Counts update dynamically as search narrows results.

### Table

**Columns:** Ingredient, Nutrition, Density, Aisle. No Recipes column.

**Headers:** Full words in Futura (site heading font). Clickable for sorting. A small arrow (▲/▼) indicates active sort column and direction. Default: Ingredient A-Z. Clicking the same header toggles direction. Clicking a different header sorts ascending by that column. Sorting is client-side in the Stimulus controller.

**Sort logic per column:**
- Ingredient: alphabetical (case-insensitive)
- Nutrition: ✓ first or ✗ first
- Density: ✓ first or ✗ first
- Aisle: alphabetical, empty last

**Row click → open editor:** No row expansion. Clicking anywhere on a row opens the nutrition editor dialog for that ingredient. The existing `nutrition_editor_controller` already handles dialog open — wire row click to trigger it directly.

**Status indicators:** Nutrition and Density columns show ✓ (green) or ✗ (red). No "—", "N/A", or tristate. Binary: data present or not.

**Source badges:** The source badge (built-in / custom / missing) renders next to the ingredient name in the first column.

### Editor dialog changes

**Reset to built-in:** Moves from the (now-removed) detail panel into the editor dialog. Only shown when a custom kitchen override exists for the ingredient.

**Used in (recipes):** New section at the bottom of the editor dialog listing recipe names as links. Format: "Used in: Focaccia, Pizza Dough, Sandwich Bread". Data fetched with the editor form (already a turbo-frame lazy load).

### Removed

- Row expansion (`ingredient-expand` rows, detail panel, lazy turbo-frame per row)
- `IngredientsController#show` action (served detail panels)
- Recipes column from table
- "Needs Attention" filter (replaced by two specific filters)
- Separate summary bar partial
- "Showing X of Y" count footer

## Files affected

| Area | Files |
|------|-------|
| View | `index.html.erb`, `_table_row.html.erb`, `_summary_bar.html.erb` (remove or inline), `_editor_form.html.erb` |
| Controller | `ingredients_controller.rb` (remove show action, pass recipe data to editor) |
| JS | `ingredient_table_controller.js` (sorting, filter rewrite, row click → editor) |
| CSS | `style.css` (ingredients section) |
| Helper | `ingredients_helper.rb` (simplify density helpers, remove expansion helpers) |
| Routes | Remove ingredient detail route if dedicated |
| Tests | Update controller + integration tests |

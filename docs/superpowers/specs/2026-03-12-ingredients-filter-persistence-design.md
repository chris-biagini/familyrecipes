# Ingredients Page Filter State Persistence

## Problem

After saving an ingredient in the nutrition editor, `CatalogWriteService` calls
`kitchen.broadcast_update`, which fires `broadcast_refresh_to`. This triggers a
Turbo morph that replaces table row DOM but preserves the `ingredient-table`
controller element — so Stimulus `connect()` never re-fires. Filters, sort, and
search appear lost even though sessionStorage still holds the values.

The search input text is also cleared by the morph since the server renders it
empty.

## Solution

Three changes to `ingredient_table_controller.js`:

1. **Persist search text** to sessionStorage (`ingredients:search`). Save on
   each keystroke in `search()`, restore in `connect()`.

2. **Listen for `turbo:morph`** in `connect()` (clean up in `disconnect()`).
   The handler calls `restore()` to re-apply all UI state to the new DOM.

3. **Extract `restore()`** — shared logic between `connect()` and the morph
   handler: restore search text, re-apply filter pill active states, update
   sort indicators, re-sort rows, re-apply visibility filters.

No other files change. Existing sessionStorage keys for filter and sort are
unchanged.

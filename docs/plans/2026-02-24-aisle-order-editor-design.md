# Aisle Order Editor

## Problem

Grocery aisles sort alphabetically, but users want to order them to match their physical store layout so they can shop in a logical path (e.g., Produce first because it's by the entrance, Frozen last because it's in the back).

## Data Model

New `aisle_order` text column on `Kitchen`. Stores an ordered list of aisle names as newline-delimited text (same storage pattern as `quick_bites_content`).

```
Produce
Bread
Refrigerated
Frozen
Pantry
Baking
Spices
Condiments
Snacks
Miscellaneous
```

Why a text column, not a separate table? This is a simple ordered list of strings with no metadata or relationships. A join table would be over-engineering. The text column is the same format the user sees in the textarea and matches the Quick Bites precedent.

Per-kitchen: each kitchen stores its own order, consistent with the overlay model where kitchens customize their ingredient catalog.

## Sorting Logic

`ShoppingListBuilder#organize_by_aisle` changes from alphabetical to position-based:

1. Parse `kitchen.aisle_order` into an ordered array.
2. Aisles in the array sort by index (0 = first).
3. Aisles **not** in the array sort after all ordered aisles, alphabetically among themselves.
4. "Miscellaneous" sorts last by default (after both ordered and unordered), unless explicitly positioned in the order list.
5. `omit` sentinel behavior unchanged.
6. Empty order list falls back to current alphabetical sort.

## Editor UI

A button in the groceries page navbar opens an `<dialog>` with a `<textarea>`, using the existing `editor-dialog` system (`recipe-editor.js`). Each line is one aisle name in order. Users reorder by cutting and pasting lines. Only visible to kitchen members.

### Pre-populating the textarea

When the editor opens, the textarea contains all distinct aisle names currently in use for the kitchen (from `IngredientCatalog.lookup_for`), ordered by the kitchen's existing `aisle_order` with new aisles appended alphabetically at the end.

## Endpoint

`PATCH /kitchens/:kitchen_slug/groceries/aisle_order` on `GroceriesController`, guarded by `require_membership`. Accepts the textarea body, saves to `Kitchen#aisle_order`.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| New aisle added to an ingredient | Appears at end of shopping list (not in order list) |
| Aisle removed from order list | Still appears in shopping list, after ordered aisles |
| Aisles with no ingredients yet | Allowed in the order list; sit silently until referenced |
| Blank lines / extra whitespace | Stripped on save |
| Duplicate aisle names | Deduplicated on save (keep first occurrence) |
| `omit` in the list | Ignored — sentinel, not a real aisle |
| "Miscellaneous" in the list | Respected position; otherwise defaults to last |
| Empty order list | Falls back to alphabetical sort |

## Future

The order list doubles as a source for an aisle picker dropdown on the ingredients page, so users can select from known aisles rather than typing freeform.

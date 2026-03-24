# Aisle Order Editor v2 — Design

GitHub: #178

## Problem

The current Aisle Order editor is a plain textarea where users type aisle names separated by newlines. It's functional but has no affordances for reordering, renaming, or deleting aisles — and renames/deletes don't cascade to catalog entries.

## Goals

1. Replace the textarea with a rich list-based UI that matches the grocery page's aisle header styling.
2. Support reorder (chevron buttons), inline rename, add, and delete — all as a staged changeset that commits on Save.
3. Cascade renames and deletes to `IngredientCatalog` entries on save.
4. Begin splitting the shared editor infrastructure into a dialog shell (reusable) and editor-specific controllers.

## Non-Goals

- Drag-and-drop reordering (buttons only for now).
- Changes to the Recipe, Quick Bites, or Nutrition editors (future work per #178).
- Retrofitting the Nutrition Editor onto the shared dialog shell (future).

## Shared Editor Infrastructure

The `shared/editor_dialog` layout stays as the **dialog chrome** — header, footer, error display, and content yield. No changes to the layout partial itself.

The existing `editor` Stimulus controller continues to serve Recipe and Quick Bites editors unchanged. The Aisle Order editor gets a new `aisle-order-editor` Stimulus controller that handles its list-based UI and reuses `editor_utils.js` for CSRF, error display, save requests, and beforeunload guards.

Net effect: no disruption to existing editors. Shared utilities remain shared; each editor owns its content area.

## Aisle Order Editor UI

### Row States

Each aisle row is a stateful object with three possible states, all client-side until Save:

**Unchanged** — default appearance, matching grocery page aisle header styling (uppercase, Futura font, 0.8rem, 0.1em letter-spacing, `--surface-alt` background):

```
│ PRODUCE                         [^] [v] [×]  │
```

**Renamed** — warm amber/yellow background tint. Shows the new name prominently with a small "was [original]" annotation below. Editing the name back to its original clears the rename state automatically:

```
│ FRUITS & VEGETABLES             [^] [v] [×]  │
│ ← was "Produce"                               │
```

**Deleted** — faded to ~40% opacity, strikethrough text. Reorder buttons hidden. The × button transforms into an ↩ undo button. Clicking ↩ restores the row to its previous state:

```
│ P̶R̶O̶D̶U̶C̶E̶                               [↩]  │
```

### Controls

- **Inline rename:** Clicking an aisle name converts it to a text input styled with a subtle underline. Enter or blur confirms. Typing the original name back clears rename state.
- **Reorder:** Small circular chevron buttons (^ v), styled like the grocery page's custom-item "+" button. Up disabled on first row, down disabled on last row. Swaps rows in the DOM.
- **Delete:** Small circular × button, same style family. Transitions row to deleted state.
- **Add:** Text input + "+" button at the bottom of the list, same style as the grocery page custom item entry. Inserts new aisle at the bottom.

### Dirty Checking

The internal data model tracks each aisle as `{ originalName, currentName, deleted }`. The unsaved-changes guard compares the full state array against the initial snapshot loaded from the server. Any rename, reorder, add, or delete marks the editor as dirty.

## Data Flow

### Loading

Dialog open triggers a fetch to the existing `groceries_aisle_order_content_path`. Returns `{ aisle_order: "Produce\nDairy\n..." }`. The controller splits on newlines and builds the initial state array.

### Saving

On Save, the controller serializes:

```json
{
  "aisle_order": "Fruits & Vegetables\nDairy\nMeat & Seafood",
  "renames": { "Produce": "Fruits & Vegetables" },
  "deletes": ["Bakery"]
}
```

- `aisle_order`: the final ordered list (excludes deleted aisles), newline-separated
- `renames`: old name → new name map for catalog cascading
- `deletes`: aisle names whose catalog entries should have their aisle cleared

PATCHes to the existing `groceries_aisle_order_path`. On success, dialog closes.

## Server-Side Changes

### `GroceriesController#update_aisle_order`

Extended to accept optional `renames` and `deletes` params alongside the existing `aisle_order`.

Flow (transaction-wrapped):
1. Parse `aisle_order`, `renames` (hash), `deletes` (array)
2. Apply renames: for each old→new pair, `IngredientCatalog.where(kitchen:, aisle: old_name).update_all(aisle: new_name)`
3. Apply deletes: for each deleted aisle, `IngredientCatalog.where(kitchen:, aisle: name).update_all(aisle: nil)`
4. Save new `aisle_order` on the kitchen (existing `normalize_aisle_order!` + validation)
5. Broadcast meal plan refresh via ActionCable (existing)

Steps 2-3 use bulk updates scoped to the kitchen. `CatalogWriteService` isn't the right fit here since it operates on individual entries — bulk aisle operations belong in the controller or a dedicated service method.

### No New Endpoints

The existing load and save endpoints are sufficient. The save endpoint is extended with optional params.

## Styling

- Aisle rows match the grocery page's `<summary>` styling: uppercase, Futura, `--surface-alt` background
- Circular buttons (chevrons, ×, +) match the custom-item "+" button pattern
- Renamed state: `background: var(--renamed-bg)` (new CSS variable, warm amber ~`#fff3cd`)
- Deleted state: `opacity: 0.4`, `text-decoration: line-through`
- The dialog uses the existing `.editor-dialog` dimensions and scroll behavior

## Testing

- **Controller tests:** Extend `GroceriesController` tests for rename and delete params, verifying catalog cascades and validation
- **System tests (Playwright):** Open editor, verify list loads, reorder via buttons, rename inline, delete with undo, save and verify grocery page reflects changes
- **Edge cases:** Rename to an existing aisle name (should that merge or error?), delete all aisles, add duplicate name

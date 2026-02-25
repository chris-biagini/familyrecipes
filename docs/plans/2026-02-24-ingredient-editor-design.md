# Unified Ingredient Editor Design

**Date:** 2026-02-24
**GitHub Issue:** #82

## Problem

The ingredient catalog stores nutrition data, density, portions, and grocery aisle assignments. The web editor on the ingredients page only handles nutrition — aisle assignments can only be changed via the Rails console or seed data. Meanwhile, aisle names live in two places (`Kitchen#aisle_order` and `IngredientCatalog#aisle`) with no unified API and no sync between them.

## Design

### Aisle Unification

Add `Kitchen#all_aisles` — the canonical, ordered list of aisle names for a kitchen:

1. Start with `parsed_aisle_order` (preserves user-specified ordering)
2. Append any aisles from `IngredientCatalog.lookup_for(self)` not already in the list (sorted alphabetically)
3. Exclude `omit` (sentinel for "exclude from grocery list", not a real aisle)

This formalizes the merge logic already inline in `GroceriesController#build_aisle_order_text`. The groceries controller's `aisle_order_content` endpoint refactors to call `all_aisles`.

**Auto-sync on writes:** When the ingredient editor saves a new aisle (via "Other..."), the controller appends it to `Kitchen#aisle_order` if not already present. The aisle immediately appears in the groceries page's aisle order editor with no separate step.

### Shared JS Module

Extract common editor behaviors from `nutrition-editor.js` and `recipe-editor.js` into `editor-utils.js`, exposed as `window.EditorUtils` (no bundler, no import maps — Propshaft serves it directly).

**What moves into `editor-utils.js`:**
- CSRF token lookup
- Unsaved-changes detection
- Error display/clear
- Close-with-confirmation logic
- Save fetch (POST/PATCH/DELETE with CSRF, Content-Type, status handling)
- `beforeunload` listener setup

**What stays in each editor:**
- `nutrition-editor.js` — open-button wiring (reads `data-ingredient`, `data-nutrition-text`, `data-aisle`), reset-button logic, aisle dropdown behavior, save payload construction
- `recipe-editor.js` — data-attribute-driven dialog discovery, dynamic content loading, delete confirmation

No behavioral changes to `recipe-editor.js` — this is a pure refactor for it.

### Unified Editor Dialog

The existing nutrition editor dialog in `ingredients/index.html.erb` gains an aisle `<select>` in the footer:

```
+------------------------------------------+
|  Flour (all-purpose)                  x  |
|------------------------------------------|
|                                          |
|  Serving size: 0.25 cup (30g)            |
|                                          |
|  Calories            110                 |
|  Total Fat           1.5g               |
|  ...                                     |
|                                          |
|------------------------------------------|
|  [Aisle: Baking v]      Cancel    Save   |
+------------------------------------------+
```

**The `<select>` element:**
- Options populated from `@available_aisles` (via `Kitchen#all_aisles` in the controller)
- First option: blank `(none)` for no aisle assignment
- Last real option: `omit` (exclude from grocery list)
- Separator, then "Other..." sentinel
- Selecting "Other..." swaps the `<select>` for a text `<input>`; clearing it or pressing Escape swaps back

**Data flow on open:**
- Edit buttons carry `data-ingredient`, `data-nutrition-text`, and `data-aisle`
- JS reads `data-aisle` and sets the dropdown's selected value on open
- Unsaved-changes detection tracks both textarea content and dropdown value

### Controller Changes

Extend `NutritionEntriesController#upsert` to accept an optional `aisle` parameter alongside `label_text`. Three save scenarios:

1. **Aisle + nutrition** — label text has real data, aisle is set. Parse label, assign aisle, save everything.
2. **Aisle only** — label text is blank/skeleton. Skip `NutritionLabelParser`. Find-or-initialize an `IngredientCatalog` entry, set only the aisle. No nutrition recalculation.
3. **Nutrition only** — label text has data, no aisle change. Existing behavior, backward compatible.

Detection: if the label text stripped of whitespace matches the blank skeleton or is empty, treat it as aisle-only.

**After save:**
- If aisle changed: `GroceryListChannel.broadcast_content_changed(current_kitchen)`
- If aisle is new (not in `Kitchen#aisle_order`): append to `aisle_order` and save the kitchen
- If nutrition changed: `RecipeNutritionJob.perform_now` for affected recipes (existing behavior)

The `destroy` action stays unchanged — deletes the kitchen override, reverting to global.

**Payload from JS:**
```json
{ "label_text": "Serving size: 30g\n...", "aisle": "Produce" }
```

### View & Data Changes

**`IngredientsController#index`** — add `@available_aisles = current_kitchen.all_aisles`.

**`ingredients/index.html.erb`:**
- Edit/add buttons gain `data-aisle="<%= entry&.aisle %>"` attribute
- Dialog footer gains a `<select>` rendered once from `@available_aisles`; JS sets selected value per-ingredient on open

**`GroceriesController#aisle_order_content`** — refactor to use `Kitchen#all_aisles` instead of inline merge logic.

**No migration needed.** The `aisle` column already exists on `ingredient_catalog`. `Kitchen#aisle_order` already exists.

**No new routes needed.** The existing `POST nutrition/:ingredient_name` endpoint handles the new `aisle` param.

### Broadcast Behavior

- **Aisle save:** `GroceryListChannel.broadcast_content_changed(current_kitchen)` — existing mechanism, shows "Reload" notification on open grocery tabs
- **Nutrition-only save:** No broadcast (doesn't affect grocery layout)
- **New aisle auto-sync:** Appending to `Kitchen#aisle_order` is additive, no conflict with concurrent reordering

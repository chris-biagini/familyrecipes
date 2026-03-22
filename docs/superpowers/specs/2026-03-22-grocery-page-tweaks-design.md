# Grocery Page Tweaks — Design Spec

**Date:** 2026-03-22

## Goal

Several UX improvements to the groceries page: make Inventory Check
collapsible and prominent, restructure aisle sections to reduce layout shift,
and add missing tooltips.

## Changes

### 1. Inventory Check — collapsible, first on page, with tooltips

The Inventory Check already renders first within `_shopping_list.html.erb`,
but it appears below the "Shopping List" `<h2>` header. Move it above the
header so it's the very first thing the user sees.

Wrap it in the standard collapse pattern (`<details class="collapse-header">`
+ `collapse-body` / `collapse-inner`).

- **Summary line:** "Inventory Check" with item count, e.g.
  `▸ Inventory Check (3)`
- **Default state:** open. Collapse state persisted in localStorage under
  the same `grocery-on-hand-{slug}` key with a dedicated
  `_inventory_check` key (e.g. `{ "_inventory_check": true, ... }`).
- Add "Needed for: Recipe1, Recipe2" tooltip (`title` attribute) to each
  inventory check `<li>`, using the `sources` data already present in each
  item hash (currently unused in this section).

### 2. Aisle sections — separate "to buy" and "on hand" collapsibles

Remove the `aisle-complete` variant entirely. Every aisle always renders its
`<h3>` header, then up to two collapsible sections:

- **"X to buy"** — unchecked shopping items. Hidden when empty.
- **"X on hand"** — checked/stocked items. Hidden when empty.

Both default to **open**. Collapse state for both is persisted per-aisle in
localStorage (see §4).

When the to-buy section is empty (all items on hand), append a checkmark
**after** the aisle name: `PRODUCE ✓`. This avoids layout shift since the
checkmark doesn't displace the aisle name.

#### DOM structure — collapse sibling selector isolation

The base.css collapse animation uses `collapse-header[open] + .collapse-body`
and `collapse-header[open] ~ .collapse-body`. With two details+body pairs
per aisle, the `~` general sibling selector would cause the first `<details>`
to match both `collapse-body` elements when open.

**Solution:** wrap each details+body pair in a `<div>` to isolate siblings:

```html
<section class="aisle-group" data-aisle="Produce">
  <h3 class="aisle-header">Produce</h3>

  <div class="aisle-section">              <!-- isolates sibling selectors -->
    <details class="collapse-header to-buy-section" open>
      <summary>3 to buy</summary>
    </details>
    <div class="collapse-body">
      <div class="collapse-inner">
        <ul class="to-buy-items">...</ul>
      </div>
    </div>
  </div>

  <div class="aisle-section">              <!-- isolates sibling selectors -->
    <details class="collapse-header on-hand-section" open>
      <summary>5 on hand</summary>
    </details>
    <div class="collapse-body on-hand-body">
      <div class="collapse-inner">
        <ul class="on-hand-items">...</ul>
      </div>
    </div>
  </div>
</section>
```

Each `<div class="aisle-section">` contains exactly one details+body pair,
so the `+` adjacent sibling selector works correctly.

### 3. Layout shift behavior

The existing behavior already keeps checked items in the to-buy DOM list with
strikethrough until the next server morph — no changes needed to the check-off
flow. The new structure preserves this: because "to buy" and "on hand" are
separate collapsible sections, the aisle container doesn't resize when an
item gets checked.

The `applyInCartState` mechanism (sessionStorage, shopping trip boundary)
continues to work unchanged — it moves on-hand items into to-buy visually
during a shopping trip.

### 4. localStorage schema change

Current schema (`grocery-on-hand-{slug}`):
```json
{ "Produce": true, "Dairy": false }
```

New schema:
```json
{
  "Produce": { "to_buy": true, "on_hand": true },
  "Dairy": { "to_buy": true, "on_hand": false }
}
```

Backwards-compatible: if the old boolean format is detected for an aisle,
treat as `{ to_buy: true, on_hand: <boolean> }`.

**Restore logic change:** the current `restoreOnHandState()` only opens
sections where stored value is truthy (because `<details>` defaults to
closed). With the new default-open behavior, restore must also *close*
sections where stored value is `false`.

### 5. Print styles

Print styles need updates for the new structure:

- Remove `.aisle-complete` from the print hide list (class no longer exists)
- Hide on-hand `<details>` and `.on-hand-body` in print
- Force to-buy `<details>` open in print (already open by default, but
  ensure `details.to-buy-section` is visible even if collapsed)
- The `.aisle-section` wrapper divs need no special print treatment

## Files to modify

| File | Change |
|---|---|
| `app/views/groceries/_shopping_list.html.erb` | Restructure: inventory check collapsible + tooltips above header, aisle sections with wrapper divs and separate to-buy/on-hand `<details>` |
| `app/assets/stylesheets/groceries.css` | Remove `aisle-complete` styles, add `to-buy-section`/`on-hand-section` collapse styles, update print styles |
| `app/javascript/controllers/grocery_ui_controller.js` | Update localStorage schema to track both sections, restore logic handles closing, persist on toggle for both section types |

## Out of scope

- Changes to the check/have-it/need-it server endpoints
- Changes to ShoppingListBuilder or MealPlan
- Changes to `groceries_helper.rb` (tooltip data already available in template)

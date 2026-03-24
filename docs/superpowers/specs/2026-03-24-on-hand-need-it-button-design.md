# On Hand: "Need It" Button + Optimistic Zone Transitions

**Issue:** [#291](https://github.com/chris-biagini/familyrecipes/issues/291)
**Date:** 2026-03-24

## Problem

Two UX issues on the grocery page:

1. **On Hand items all have checkboxes** regardless of when they were confirmed.
   Unchecking something you bought last week doesn't feel right — you didn't
   "un-buy" it, you ran out. Bold styling on "confirmed today" items is the
   only visual distinction, and it's subtle.

2. **Zone transitions feel slow.** When a checkbox is toggled, the item fades
   out (250ms), then there's a dead gap while the server round-trips and
   broadcasts a Turbo morph, then the item bloops into its new zone. The
   perceived latency makes the list feel sluggish.

## Design

Split On Hand items into two visual treatments based on `confirmed_at`:

| Condition | UI | Action on click |
|---|---|---|
| `confirmed_at == today` | Checkbox (pre-checked) | `uncheck!` (existing behavior) |
| `confirmed_at != today` | "Need It" button | `need_it!` (SM-2 blending) |

### What changes

1. **Remove bold styling** from `.confirmed-today`. Today items are now
   distinguished by having checkboxes; non-today items have a "Need It" button.

2. **View split** in `_shopping_list.html.erb`: the on-hand `<li>` renders
   either a checkbox or a "Need It" button based on `confirmed_today?`.

3. **"Need It" button fires `need_it` action**, not `uncheck`. This is a
   behavioral improvement: `need_it!` performs SM-2 interval blending
   (records observed consumption period), while `uncheck!` is a simpler
   revert. For items on hand for days/weeks, blending is more accurate.

4. **JS handler** in `grocery_ui_controller.js`: "Need It" buttons in on-hand
   use the same `data-grocery-action="need-it"` as Inventory Check buttons.
   The existing `sendAction` dispatcher already handles this — no new JS
   needed.

5. **CSS**: delete `.confirmed-today` bold rule. The `.on-hand-fresh/mid/aging`
   opacity classes remain unchanged for non-today items.

### What stays the same

- Three-zone model (Inventory Check / To Buy / On Hand) — unchanged.
- Today items keep checkbox + `uncheck!` behavior — if you just bought
  something and realize you didn't, unchecking is the right semantic.
- On Hand section headers, collapse behavior, freshness opacity — all unchanged.
- Inventory Check zone — unchanged.
- To Buy zone — unchanged.

### Markup sketch

Non-today on-hand item (new):
```erb
<li class="<%= freshness_class %>" data-item="<%= item[:name] %>">
  <button class="btn btn-sm btn-need-it" data-grocery-action="need-it"
          data-item="<%= item[:name] %>">Need It</button>
  <span class="item-text"><%= item[:name] %> <span class="item-amount">...</span></span>
</li>
```

Today on-hand item (unchanged except no bold):
```erb
<li data-item="<%= item[:name] %>">
  <label class="check-off">
    <input class="custom-checkbox" type="checkbox" data-item="<%= item[:name] %>" checked>
    <span class="item-text">...</span>
  </label>
</li>
```

### Optimistic zone transitions

Current flow (checkbox toggle):
1. Exit animation (250ms collapse+fade)
2. `sendAction` fires (fire-and-forget)
3. Dead gap — waiting for server broadcast morph
4. Morph arrives, `applyPendingMoves` bloops item into new zone

New flow (all zone moves — checkbox and button):
1. Exit animation (collapse+fade) or instant `li.remove()` for buttons
2. **Optimistically insert a minimal `<li>` in the destination zone** with
   bloop entry animation — no waiting for server
3. `sendAction` fires
4. Morph arrives — idiomorph matches by `data-item`, patches attribute
   differences (freshness class, tooltip) as a near-no-op

**How it works:** after the exit animation completes, construct a destination
`<li>` with the item name, the right structure (checkbox or button depending
on destination zone), and the correct `data-item` attribute. Insert it into
the appropriate `<ul>` and apply the `check-off-enter` bloop animation.

Idiomorph matches DOM elements by attributes. As long as the optimistic `<li>`
has the right `data-item`, the morph updates it in place rather than
duplicating. The optimistic markup doesn't need to be pixel-perfect — the
morph patches any differences (tooltips, freshness classes, amounts).

**Which transitions get optimistic moves:**

| Action | Exit | Optimistic destination |
|---|---|---|
| To Buy checkbox checked | collapse+fade | On Hand `<ul>` (checkbox, checked) |
| On Hand today checkbox unchecked | collapse+fade | To Buy `<ul>` (checkbox, unchecked) |
| On Hand non-today "Need It" button | instant remove | To Buy `<ul>` (checkbox, unchecked) |
| IC "Have It" button | instant remove | On Hand `<ul>` (checkbox, checked) |
| IC "Need It" button | instant remove | To Buy `<ul>` (checkbox, unchecked) |

**Destination zone or aisle doesn't exist yet:** when the target `<ul>`
doesn't exist in the DOM (e.g., checking off the last to-buy item in an aisle
creates the first on-hand item), skip the optimistic insert and fall back to
the current behavior — the morph will create the section. This keeps the JS
simple; the edge case is rare and the morph is fast enough.

**Error/rejection fallback:** if the server rejects the action (stale record,
etc.), the morph moves the item back to its correct zone — the right behavior.

**Builder function:** a single `buildOptimisticItem(name, zone)` function in
`grocery_ui_controller.js` constructs the destination `<li>`. It only needs
the item name and target zone — no amounts, tooltips, or freshness classes.
The morph fills those in.

### Animation

Non-today "Need It" clicks use instant `li.remove()` (same as IC buttons).
Today checkbox toggles keep the existing collapse+fade exit. Both get an
optimistic insert + bloop in the destination zone.

### Print

No change needed — print CSS already hides on-hand sections entirely.

## Files touched

| File | Change |
|---|---|
| `app/views/groceries/_shopping_list.html.erb` | Split on-hand rendering by `confirmed_today?` |
| `app/assets/stylesheets/groceries.css` | Delete `.confirmed-today` rule; add layout for button-style on-hand items |
| `app/helpers/groceries_helper.rb` | No change — `confirmed_today?` already exists |
| `app/javascript/controllers/grocery_ui_controller.js` | `buildOptimisticItem`, optimistic insert after exit for all zone moves |
| `test/helpers/groceries_helper_test.rb` | Verify existing `confirmed_today?` coverage |
| `test/controllers/groceries_controller_test.rb` | Add test for need_it on on-hand item |

## Out of scope

- Visual freshness indicators beyond existing opacity (future consideration)
- SM-2 algorithm changes
- Optimistic inserts when the destination zone/aisle section doesn't exist yet
  (fall back to morph in that edge case)

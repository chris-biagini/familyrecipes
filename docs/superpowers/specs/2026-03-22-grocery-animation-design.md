# Grocery Item Check-Off Animation

## Problem

When a grocery item is checked off in "To Buy," it stays in place until a
Turbo morph arrives and silently relocates it to "On Hand." This is
disorienting — the user doesn't see the item move and may not realize it
landed in On Hand. The reverse (unchecking from On Hand) has the same
problem.

## Solution

Animate items between zones with a two-phase visual:

1. **Exit**: Item collapses out of its current section (height shrink + fade)
2. **Entry**: After Turbo morph renders the item in its new section, it bloops
   into place using the existing `bloop` keyframes

Additionally, items confirmed today (`confirmed_at == Date.current`) render
with bold text so recently-purchased items are easy to spot in On Hand.

## Scope

This spec covers **checkbox-driven moves** between To Buy and On Hand only.
Inventory Check buttons ("Have It" / "Need It") already remove items from the
DOM immediately — they don't need an exit animation. Their post-morph entry
into To Buy or On Hand will get the bloop treatment via the same
`pendingMoves` mechanism.

## Animation Phases

### Phase 1 — Exit (client-side, immediate)

When the user checks a To Buy checkbox or unchecks an On Hand checkbox:

1. Record the item name in a `pendingMoves` Set
2. Wrap the `<li>` content in a CSS grid collapse pattern (consistent with
   the existing `collapse-body`/`collapse-inner` pattern used for section
   collapses): set `grid-template-rows` from `1fr` to `0fr` with opacity
   fade, ~250ms
3. The item remains in the DOM — the Turbo morph will remove it

For "Have It" / "Need It" buttons: add the item name to `pendingMoves`
before removing the `<li>` from the DOM (existing behavior). No exit
animation needed — the instant removal is appropriate for button clicks.

### Phase 2 — Entry (client-side, post-morph)

In the existing `preserveOnHandStateOnRefresh` render-wrapper (which wraps
`originalRender` and runs code after `await originalRender(...args)`):

1. After collapse state and `applyInCartState` have both run, iterate
   `pendingMoves`
2. For each item, find the `<li>` by `data-item` using `CSS.escape(name)`
   for safe attribute selectors
3. Skip items that have the `in-cart` class (their position is managed by
   cart logic, not zone animations)
4. Apply a `check-off-enter` CSS class that triggers the `bloop` animation
   (scale 0.95→1.02→0.992→1 + opacity, 250ms)
5. Remove the class after animation completes (via `animationend` listener)
6. Clear `pendingMoves`

### Bold for Today

Server-side: when rendering On Hand items, compare the item's `confirmed_at`
value to `Date.current.iso8601` (string comparison — `confirmed_at` is stored
as an ISO 8601 string like `"2026-03-22"`). Guard against nil and the
`ORPHAN_SENTINEL` value. If they match, add a `confirmed-today` CSS class to
the `<li>`.

CSS rule: `.confirmed-today .item-text { font-weight: 600; }`.

This naturally expires at midnight — no client-side timer needed. The next
morph or page load drops the class.

## File Changes

### `app/assets/stylesheets/groceries.css`

New classes:

```css
.check-off-exit {
  display: grid;
  grid-template-rows: 0fr;
  opacity: 0;
  transition: grid-template-rows 250ms ease, opacity 250ms ease;
  overflow: hidden;
}

.check-off-exit > * {
  min-height: 0;
}

.check-off-enter {
  animation: bloop 250ms cubic-bezier(0.16, 0.75, 0.40, 1);
}

.confirmed-today .item-text {
  font-weight: 600;
}
```

The exit uses CSS grid `grid-template-rows: 0fr` (matching the existing
collapse pattern in `base.css`) instead of `max-height`, which avoids the
classic `max-height` timing mismatch on variable-height items.

### `app/javascript/controllers/grocery_ui_controller.js`

- Add `this.pendingMoves = new Set()` in `connect()`
- In the checkbox change handler: add item name to `pendingMoves`, wrap
  `<li>` content for grid collapse and apply `check-off-exit` class
- In inventory check button handler: add item name to `pendingMoves` before
  the existing `li.remove()` call
- In `preserveOnHandStateOnRefresh`: after `applyInCartState()` completes,
  iterate `pendingMoves`, find each item's `<li>` by
  `[data-item="${CSS.escape(name)}"]`, skip `in-cart` items, apply
  `check-off-enter` class, listen for `animationend` to remove it, then
  clear the set

### `app/views/groceries/_shopping_list.html.erb`

- On Hand `<li>` elements: add `confirmed-today` class when
  `confirmed_today?(item[:name], on_hand_data)` returns true
- The class goes on the `<li>` element alongside the existing `data-item`
  and `title` attributes

### `app/helpers/groceries_helper.rb`

- Add `confirmed_today?(name, on_hand_data)` helper:
  - Looks up the item's entry via case-insensitive key match (same pattern
    as `restock_tooltip`)
  - Returns false if entry is nil, `confirmed_at` is nil, or `confirmed_at`
    equals `MealPlan::ORPHAN_SENTINEL`
  - Returns `entry['confirmed_at'] == Date.current.iso8601`

## Edge Cases

- **Morph arrives before exit animation finishes**: The morph removes the old
  DOM node mid-animation — this is fine, the item simply disappears and
  bloops in at its destination. No visual glitch since both happen fast.
- **Multiple items checked rapidly**: Each gets its own exit animation and
  entry in `pendingMoves`. The post-morph hook handles all of them.
- **Item moves to a new aisle group**: The `data-item` selector is
  page-wide, so it finds the item regardless of which aisle group it
  lands in.
- **On Hand section created by the morph**: If the aisle had no On Hand
  section before, the morph creates one. The item is found there normally.
- **Cross-device sync**: Another device's morph won't have `pendingMoves`
  entries, so items appear without animation — correct behavior, since
  that user didn't perform the action.
- **In-cart items**: Items tracked in sessionStorage cart are excluded from
  bloop animations — their visual position is managed by `applyInCartState`.
- **Print styles**: No change needed — print already hides On Hand and
  checked items.
- **`ORPHAN_SENTINEL` confirmed_at**: The `confirmed_today?` helper guards
  against sentinel values that aren't real dates.

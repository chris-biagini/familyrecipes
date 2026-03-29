# Dinner Picker Redesign — Design Spec

## Summary

Redesign the dinner picker dialog from a multi-page flow (tag selection →
slot animation → result card) into a single-page experience with a
physics-based slot machine animation and faux-cylinder visual treatment.
The user can keep spinning without leaving the view.

## Current State

The dinner picker has three distinct states that toggle visibility:

1. **tagState** — tag preference pills + spin button
2. **slotDisplay** — slot machine animation (setTimeout-based text swap)
3. **resultArea** — result card with recipe details + action buttons

"Try again" navigates back to state 1, resetting the view. The animation
cycles recipe names via `textContent` swaps with linear deceleration
(stepped delays per cycle). The dialog jumps between sizes as content
changes.

## Redesigned Layout

Everything lives on one page. No state transitions, no hidden containers.

**Top to bottom:**

1. **Heading** — "What's for Dinner?" + subtitle
2. **Tag pills** — always visible, 3-state toggle (neutral/up/down)
3. **Slot drum** — always visible, compact window (76px tall)
4. **Result details** — slides in below the drum after landing (description + recipe link)
5. **Buttons** — spin button (always visible) + "Add to Menu" (appears after first landing)

The spin button shows a random quip on each spin ("I'm feeling lucky",
"Let it ride", etc.). After landing, the quip changes to re-spin language
("Spin again", "One more time", "Not feeling it").

## Slot Machine Animation

### Physics Model

The animation uses a blended friction model with pre-computed keyframes,
inspired by the Price is Right wheel — fast initial bleed, long graceful
coast at the end.

**Two friction components blended together:**

- **Constant friction** — fixed deceleration (like a brake pad). Produces
  linear velocity decay and an abrupt stop.
- **Proportional drag** — deceleration proportional to velocity (like air
  resistance). Sheds speed quickly when fast, coasts at low speed.
  Exponential decay.

**Locked-in parameters:**

| Parameter | Value | Effect |
|-----------|-------|--------|
| Spin force (v₀) | 1200 px/s | Initial velocity |
| Total friction | 275 | Overall drag amount |
| Drag blend | 75% proportional | Character of slowdown |

With 75% blend, friction splits into:
- `constFric = 275 × 0.25 = 68.75` px/s²
- `dragCoeff = 275 × 0.75 / 1200 × 3 = 0.515625` 1/s

**Per-frame physics:** `decel = constFric + dragCoeff × velocity`

### Pre-Computed Keyframes (No Snap Landing)

The animation is pre-simulated at 240fps using Euler integration before
the first frame renders. This produces an array of `{t, pos, v}` keyframes
representing the complete trajectory. The natural stopping distance is
calculated, rounded to the nearest item boundary, and the winner is
placed at that position. All keyframe positions are uniformly scaled so
the physics naturally reaches zero velocity exactly when the winner is
centered. No snap correction needed.

**Playback:** `requestAnimationFrame` reads the pre-computed curve via
binary search on elapsed time. Position is linearly interpolated between
the two nearest keyframes. This is cheaper than running physics per-frame
and guarantees deterministic, smooth playback.

### Reel Construction

Recipes loop to fill the reel: if the kitchen has recipes A, B, C, D,
the reel is A, B, C, D, A, B, C, D, ... with the winner placed at the
calculated landing index. Extra buffer items extend past the winner so the
reel doesn't run out during the coast.

### Faux-Cylinder Visual Treatment

Items warp vertically based on their distance from the center of the
slot window, simulating text printed on a spinning drum.

**Foreshortening curve:** `foreshorten = 1 - |dist|^1.3` (where `dist` is
normalized 0–1 from center to edge). This power curve compresses items
immediately from center, unlike `cos()` which stays flat near 0° and
creates an unrealistic "sharp corner" effect.

**Per-item transform (applied each frame):**
- `scaleY = 0.15 + 0.85 × foreshorten` — ranges from 15% at edges to
  100% at center
- `translateY` shift toward center to close gaps created by compression
- No horizontal scaling (drums don't shrink in X as the surface recedes)
- No opacity changes (the gradient overlay handles depth)

**Items more than 1.5× the container height off-screen skip transforms**
for performance.

**CSS gradient overlay** reinforces the curved look:
- Top/bottom edges darken (rgba(45,42,38, 0.35) → transparent)
- Center highlight lines (subtle red-tinted borders) mark the read point
- The gradient is purely cosmetic and layered via `::before` / `::after`
  pseudo-elements with `pointer-events: none`

### Slot Window Dimensions

| Property | Value |
|----------|-------|
| Container height | 76px |
| Item height | 30px |
| Reel padding-top | 22px (centers active item) |
| Font size | 1rem, weight 600 |
| Highlight height | 30px (matches item) |
| Border radius | 8px |
| Background | `var(--surface-alt)` |

### Accessibility

- `prefers-reduced-motion: reduce` — skip animation entirely, show
  result immediately (existing behavior, preserved)
- All text rendered via `textContent`, no `innerHTML`
- Buttons and links have clear labels

## Behavioral Changes from Current Implementation

| Aspect | Before | After |
|--------|--------|-------|
| Layout | 3 mutually exclusive states | Single page, all elements always present |
| Animation | setTimeout text swap, 15 cycles | requestAnimationFrame physics simulation |
| Deceleration | Linear staircase (80ms + i×15ms) | Blended constant + proportional friction |
| Landing | Text swap to winner + scale(1.15) CSS | Physics naturally stops on winner position |
| "Try again" | Returns to tag state, rebuilds UI | Immediately re-spins, tags stay visible |
| Result display | Replaces slot with result card | Result details slide in below the drum |
| Dialog sizing | Jumps between content sizes | Stable height, result details expand below |

## What Doesn't Change

- **Weight computation** — `computeFinalWeights` and `weightedRandomPick`
  in `dinner_picker_logic.js` are unchanged
- **Tag preference system** — 3-state toggle (neutral/up/down) with
  multipliers (1/2/0.25)
- **Decline penalties** — each "spin again" applies 0.3× penalty to the
  previous winner
- **Cook history weights** — server-side `CookHistoryWeighter` unchanged
- **Accept flow** — dispatches checkbox change event, closes dialog
- **Data source** — recipes and tags loaded from shared search data JSON

## Files to Modify

- `app/javascript/controllers/dinner_picker_controller.js` — rewrite
  animation and layout logic
- `app/assets/stylesheets/menu.css` — update dinner picker styles
- `app/views/menu/show.html.erb` — simplify dialog markup (single
  container instead of three targets)
- `test/javascript/dinner_picker_test.mjs` — update tests for new
  animation approach

## Files to Create

- `app/javascript/utilities/spin_physics.js` — physics simulation,
  keyframe generation, and cylinder warp functions (extracted from
  controller for testability)

## Reference Prototype

Interactive prototype with tunable parameters:
`.superpowers/brainstorm/141793-1774831771/content/scroll-physics-v8.html`

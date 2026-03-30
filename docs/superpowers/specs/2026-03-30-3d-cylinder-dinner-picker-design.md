# 3D Cylinder Dinner Picker Design

Replace the faux-3D drum effect with a real CSS 3D spinning cylinder.
Pre-populate with weighted-random recipes on load; let the spin land naturally.

## Cylinder Geometry & Rendering

12 slots at 30° apart, rendered with CSS 3D transforms. The drum container
gets `perspective`; the cylinder wrapper gets `transform-style: preserve-3d`.
Each recipe label is a `div` positioned with
`rotateX(N * 30deg) translateZ(radius)`, where radius is calculated from the
item height and slot count to produce natural spacing at the chosen perspective
distance.

Narrow viewport (~3 items visible) — tight slot-machine feel. Back-face items
use `backface-visibility: hidden`. The existing vignette gradient overlay stays
(darkens top/bottom edges for depth). The faux scaleY warp code and the
`::after` indicator lines are deleted.

Two static red chevron markers (▶ ◀) sit on the left and right edges of the
drum viewport, pointing inward to frame the winner slot. These are part of the
drum container, not the cylinder.

The cylinder rotates on its X axis via a single `rotateX(Ndeg)` transform on
the wrapper — no per-item warp calculations.

## Population & Weighting

On dialog open, the cylinder's 12 slots are filled with recipes chosen by
weighted random sampling without replacement. Weights come from:

- Cook history recency weights (from `CookHistoryWeighter`, passed as JSON)
- Tag preferences (all neutral on first open)
- Decline penalties (empty on first open)

Reuse `computeFinalWeights` and `weightedRandomPick` from
`dinner_picker_logic.js`. Call `weightedRandomPick` 12 times, removing each
pick from the pool, to fill the slots. If the kitchen has fewer than 12
recipes, slots repeat cyclically.

On spin, the 12 slots are re-populated with fresh weighted picks reflecting
current tag preferences and decline penalties. The cylinder swaps its labels
then immediately begins spinning — new names blur past as it accelerates.

No "—" placeholder. The cylinder is populated from the moment it opens.

## Spin Physics

Physics simulation moves from pixel-space to angular-space. Same structure.

On spin:

1. Fill 12 slots with fresh weighted-random recipes.
2. Pick a random initial angular velocity within a range that guarantees 720°+
   of travel (minimum 2 full rotations).
3. Simulate deceleration:
   `angular_decel = const_friction + drag_coeff * angular_velocity`
   (same hybrid friction model as current code).
4. Find the natural resting angle.
5. Calculate the nearest 30° boundary and scale the entire simulation
   proportionally so it lands there exactly — same technique as current
   `buildKeyframes`. No visible snap correction.
6. The winner is whichever recipe sits at the final slot index.

Animation loop: single `requestAnimationFrame` sets
`transform: rotateX(-${angle}deg)` on the cylinder wrapper each frame.
Rotation direction is top-rolling-toward-viewer (negative X rotation).
`positionAtTime` binary-search interpolation is reused, operating on degrees
instead of pixels.

Reduced motion: `prefers-reduced-motion` skips animation and shows the result
instantly.

## Idle Rotation

On dialog open, after populating slots, the cylinder begins slow continuous
rotation toward the viewer. Simple `requestAnimationFrame` loop incrementing
angle by ~0.3°/frame (roughly one full rotation every 4 seconds).

When the user hits Spin, the idle loop is cancelled and spin physics takes over
from the cylinder's current angle. No jarring reset.

After spin completes, idle does not resume. The cylinder sits still on the
winner. Result details are visible; user can accept or re-spin. Re-spin starts
from the current resting position.

## File Changes

### Modified

- **`dinner_picker_controller.js`** — Major rewrite: cylinder DOM construction,
  idle rotation loop, spin-from-current-angle, remove `warpItems()`. Targets
  stay the same.
- **`spin_physics.js`** — Rewrite to angular space: `buildKeyframes` works in
  degrees. `simulateCurve` unchanged (unit-agnostic). Delete `buildReelItems`
  and `applyCylinderWarp`.
- **`menu.css`** — Replace drum styles: `perspective` on container,
  `transform-style: preserve-3d` on reel, position items with
  `rotateX`/`translateZ`, chevron markers, delete faux-warp styles.
- **`show.html.erb`** — Remove the single placeholder reel item div (cylinder
  built entirely in JS).
- **`spin_physics_test.mjs`** — Update to match new function signatures
  (degrees instead of pixels, removed deleted functions).

### Deleted code

- `applyCylinderWarp()` — replaced by native CSS 3D.
- `buildReelItems()` — replaced by weighted sampling into fixed slots.
- `warpItems()` controller method — no longer needed.

### Unchanged

- `dinner_picker_logic.js` — `computeFinalWeights` and `weightedRandomPick`
  reused as-is.
- `search_data.js` — recipe/tag loading unchanged.
- All server-side code — no controller, model, or helper changes.

# Recipe Scaling Overhaul Design

Replace the `prompt()`/`alert()` scaling UI with an inline collapsible panel.
Fix two bugs: duplicate scaling from multiple controller instances, and static
cross-reference multiplier badges.

## Current State

Scaling is client-side only, driven by `recipe_state_controller`. The
controller reads `data-quantity-value` on ingredient `<li>` elements and
`data-base-value` on scalable `<span>` elements in instructions, multiplies
by the user's factor, and formats output with vulgar fractions. State persists
to localStorage keyed by recipe slug and markdown version hash (48-hour TTL).

### Bugs

**Two attempts to stick.** Every `recipe-state` controller instance
(`<article>` on the main recipe AND each embedded cross-reference) calls
`setupScaleButton()`, which binds a click handler to the same
`#scale-button`. Multiple `prompt()` dialogs fire in sequence. Worse: the
embedded controller's `applyScale()` pass (with its own independent scale
factor, defaulting to 1) overwrites the parent's scaling on reconnect.

**Cross-reference multiplier badge static.** The `× 2` badge in embedded
recipe headers is server-rendered and never updated by JavaScript. When the
user scales by 3×, embedded ingredient quantities correctly show 6× values
(because `data-quantity-value` already includes the base multiplier), but the
badge still reads `× 2`.

## UI Design

### Collapsed State

A "Scale" link appended to the recipe-meta line: `BASICS · SERVES 4 · Scale`.
Styled identically to the category link. When scale ≠ 1, shows the factor:
"Scale (×2)". Clicking toggles the panel open/closed.

### Expanded State

A compact centered strip that animates open between the header and the first
step using the `grid-template-rows: 0fr → 1fr` pattern (same as grocery aisle
expand/collapse). Layout:

```
[½×] [1×] [2×] [3×]  |  [___3/2___] ×   Reset
```

- Preset buttons and free-form input on one line.
- Active preset highlighted in `--red`.
- Input and presets stay in sync: typing `2` highlights the 2× preset;
  clicking ½× updates the input to `1/2`.
- Live validation on the input — red border on invalid, clears when valid.
- Reset link right-aligned, only visible when scale ≠ 1.
- On mobile (≤720px): same single line — presets + input fit within 390px.

### Animation

`grid-template-rows` transition on a wrapper div with `overflow: hidden` on
the inner content during transition, matching the grocery aisle pattern.

## Controller Architecture

### New: `scale_panel_controller`

Owns the panel UI. Lives on a `<div>` inside the main recipe `<article>`.

- **Targets:** preset buttons, text input, reset button, collapse wrapper,
  "Scale" toggle link in recipe-meta.
- **Values:** `factor` (Number, default 1).
- **Responsibilities:** toggle open/close, preset clicks, input
  parsing/validation, sync between input and presets.
- **On factor change:** dispatches `scale-panel:change` event (bubbles) with
  `{ detail: { factor } }`.
- **Restoration:** listens for `recipe-state:restored` event dispatched by
  `recipe_state_controller` after loading from localStorage. Updates its
  input/presets to match the restored factor.

### Refactored: `recipe_state_controller`

Scaling + cross-off. The `setupScaleButton()` method and all `prompt()`/
`alert()` code is deleted.

- **New value:** `embedded` (Boolean, default false). Embedded articles set
  `data-recipe-state-embedded-value="true"`.
- **Embedded instances** skip all scaling: no `applyScale`, no scale factor
  in localStorage. They only handle cross-off state.
- **Top-level instance** listens for `scale-panel:change` on its element,
  calls `applyScale(factor)`.
- **`applyScale()`** unchanged for ingredients and scalable spans — it queries
  `this.element.querySelectorAll(...)` which covers the full subtree including
  embedded recipes. Gains one new step: updating embedded multiplier badges.

### Event Flow

1. User clicks preset or types in input.
2. `scale_panel_controller` validates, dispatches `scale-panel:change`.
3. Event bubbles to `<article data-controller="recipe-state">`.
4. `recipe_state_controller` calls `applyScale(factor)`, saves to
   localStorage.
5. Embedded `recipe-state` controllers are never involved in scaling.

## Cross-Reference Multiplier Updates

Each embedded recipe `<article>` gets a `data-base-multiplier` attribute
(the server-rendered cross-reference multiplier). `applyScale()` updates
`.embedded-multiplier` elements:

- `effective = baseMultiplier × userFactor`
- `effective == 1.0` → hide the badge.
- Otherwise → show `× {effective}` (formatted with `formatVulgar`).

At 1× user scale with 2× base: `× 2` (unchanged).
At 3× user scale with 2× base: `× 6`.
At ½× user scale with 2× base: `× 1` → hidden.
At 2× user scale with 1× base: `× 2` (newly visible).

## State Persistence & Turbo Morphs

**localStorage saves `scaleFactor` as a number** (not raw input string).
The raw input text is ephemeral UI state.

**Panel open/closed state is not persisted.** Starts collapsed every time.
The "Scale (×2)" label in recipe-meta signals a non-default factor.

**Version hash check stays.** Stale or mismatched state is discarded.

**On Turbo morph:**

1. Both controllers reconnect via Stimulus lifecycle.
2. `recipe_state_controller` loads factor from localStorage, re-applies
   scaling, dispatches `recipe-state:restored` event.
3. `scale_panel_controller` receives restoration event, updates input/presets.
4. Cross-off state restored from localStorage (existing behavior).

**Cross-reference content changes** (e.g., someone edits Simple Tomato Sauce):
Morph delivers fresh HTML with updated `data-quantity-value` attributes.
`applyScale()` re-runs on the new DOM — consistent automatically.

**Cross-reference multiplier changes** (e.g., `>>>@[Sauce], 2` changed to 3):
Morph updates `data-base-multiplier`. `applyScale()` reads the new value on
next run.

## Removed

- `#scale-button` from the nav bar (`show.html.erb` extra_nav).
- `setupScaleButton()` and `prompt()`/`alert()` from `recipe_state_controller`.
- Independent scaling in embedded `recipe-state` controller instances.

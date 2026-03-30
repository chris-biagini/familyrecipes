# Dinner Picker CSS Polish — Design Spec

Elevate the 3D spinning cylinder from functional to showcase. Five
enhancements, all pure CSS/JS — no new dependencies, no markup changes to the
server-rendered template.

## Current State

- 12 recipe labels arranged on a CSS 3D cylinder (rotateX / translateZ)
- `backface-visibility: hidden` recently changed to `visible` — fixes
  late-pop label timing but exposes upside-down rear labels through the
  transparent drum
- Flat vignette gradient (`::before`) darkens top/bottom edges
- Chevrons float inside the drum viewport
- No motion blur during spin

## 1. Cylinder Wall Panels — Real 3D Occlusion

### Geometry

24 child elements inside `.dinner-picker-reel`:

| Type  | Count | Angles                          | translateZ        |
|-------|-------|---------------------------------|-------------------|
| Panel | 12    | 15°, 45°, 75° … 345° (midpoints) | `cylinderRadius`  |
| Label | 12    | 0°, 30°, 60° … 330° (existing)   | `cylinderRadius + 1.5px` |

Panels are offset 15° from labels — they sit *between* adjacent label slots,
forming the walls of a 12-sided prism. Labels float 1.5px above the panel
surface so text doesn't z-fight.

### Panel sizing

- Height: 28px (vs 26px labels) — eliminates hairline gaps between adjacent
  panels at the seam
- Width: 100% of reel

### Alternating colors

Even panels (0, 2, 4 …): `--surface-alt` (#f7f5f1 light / #2a2724 dark)
Odd panels (1, 3, 5 …): `--rule-faint` (#eee9e3 light / #2e2a26 dark)

New CSS custom properties on `.dinner-picker-reel-panel`:
```css
.dinner-picker-reel-panel { --panel-color: var(--surface-alt); }
.dinner-picker-reel-panel.alt { --panel-color: var(--rule-faint); }
```

### Visibility rules

- Panels: `backface-visibility: hidden` — only the front-facing hemisphere
  renders. The front panels occlude the rear labels naturally.
- Labels: `backface-visibility: visible` (current) — they exist on both
  sides but are hidden behind solid panels on the back half.

### Build logic (`populateCylinder`)

Single loop 0–11. For each index `i`:
1. Create panel div (class `dinner-picker-reel-panel`, plus `alt` if `i` is
   odd). Transform: `rotateX(${i * 30 + 15}deg) translateZ(${radius}px)`.
2. Create label div (existing logic). Transform:
   `rotateX(${i * 30}deg) translateZ(${radius + 1.5}px)`.

Both appended to the reel in the same loop.

## 2. Inset Metallic Bezel

The drum container becomes a slot-machine faceplate — a physical surface with
a rectangular window into the spinning mechanism.

### Drum container changes (`.dinner-picker-drum`)

Remove the current `border: 1px solid var(--rule)` and
`background: var(--surface-alt)`.

Replace with:
```css
background: linear-gradient(
  to bottom,
  #d8d4d0 0%,
  #c8c4c0 50%,
  #b8b4b0 100%
);
border: 1px solid #a8a4a0;
box-shadow:
  inset 0 2px 6px rgba(0, 0, 0, 0.25),
  inset 0 -1px 3px rgba(0, 0, 0, 0.1),
  0 1px 2px rgba(0, 0, 0, 0.1);
```

This creates a brushed-metal look — lighter at top (catching light), darker
at bottom, recessed via inset shadows.

### Dark mode

```css
background: linear-gradient(to bottom, #4a4540 0%, #3a3530 50%, #2a2724 100%);
border-color: #1e1b18;
box-shadow:
  inset 0 2px 6px rgba(0, 0, 0, 0.4),
  inset 0 -1px 3px rgba(0, 0, 0, 0.2),
  0 1px 2px rgba(0, 0, 0, 0.2);
```

### Vignette replacement

Delete the existing `::before` vignette gradient entirely. Edge shading
(section 4) replaces it.

### `::before` repurposed as inner bevel

The `::before` pseudo-element becomes a subtle inner-edge highlight:
```css
.dinner-picker-drum::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
  border-radius: 7px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.3);
}
```

This adds a single-pixel highlight along the inside top edge — the "lip" of
the recessed window.

## 3. Bezel-Mounted Chevrons

Chevrons move from floating inside the drum to sitting on the bezel surface.

### Positioning

Same absolute positioning as today, but `z-index: 4` (above the `::before`
bevel at z-index 2 and any drum content). They read as stamped/engraved into
the metal faceplate.

### Engraved look

```css
.dinner-picker-chevron {
  color: #8a8580;
  text-shadow:
    0 1px 0 rgba(255, 255, 255, 0.4),
    0 -1px 0 rgba(0, 0, 0, 0.2);
  opacity: 1; /* remove the current 0.6 opacity */
}
```

The dual text-shadow (light below, dark above) creates an engraved/debossed
effect — light catches the bottom edge of the stamp, shadow at the top.

### Dark mode

```css
color: #5a5550;
text-shadow:
  0 1px 0 rgba(255, 255, 255, 0.15),
  0 -1px 0 rgba(0, 0, 0, 0.4);
```

## 4. Cosine Edge Shading (Lambert Lighting)

Per-panel shading that follows 3D geometry, replacing the flat vignette.

### Shade calculation

Each panel and label gets an inline `--shade` custom property set during
`populateCylinder()`:

```javascript
const shade = 1 - Math.abs(Math.cos(angleInRadians))
```

- Front face (0°): `cos(0) = 1` → shade = 0 (no darkening)
- Side face (90°): `cos(90°) = 0` → shade = 1 (maximum darkening)

Note: we use `Math.abs` because panels span the full 360° — a panel at 180°
should shade the same as one at 0° (both face directly toward/away from
viewer). But panels at 180° are `backface-visibility: hidden` anyway, so
this mainly affects the 60°–90° range.

### CSS application

Panels:
```css
.dinner-picker-reel-panel {
  background-color: color-mix(in srgb, var(--panel-color), black calc(var(--shade) * 35%));
}
```

Labels: shade applied as reduced opacity on the text:
```css
.dinner-picker-reel-item {
  opacity: calc(1 - var(--shade) * 0.6);
}
```

### Per-frame shade update

The `--shade` must be recalculated each frame because elements rotate with
the cylinder — a panel created at 15° moves to 105° when the cylinder
rotates 90°. The shade depends on each element's *current* facing angle,
not its creation angle.

```javascript
updateShading() {
  const panels = this.reelTarget.querySelectorAll('.dinner-picker-reel-panel')
  const labels = this.reelTarget.querySelectorAll('.dinner-picker-reel-item')

  panels.forEach((panel, i) => {
    const angle = (i * 30 + 15 + this.currentAngle) % 360
    const rad = angle * Math.PI / 180
    const shade = 1 - Math.abs(Math.cos(rad))
    panel.style.setProperty('--shade', shade.toFixed(3))
  })

  labels.forEach((label, i) => {
    const angle = (i * 30 + this.currentAngle) % 360
    const rad = angle * Math.PI / 180
    const shade = 1 - Math.abs(Math.cos(rad))
    label.style.setProperty('--shade', shade.toFixed(3))
  })
}
```

Called once per rAF frame — 24 `setProperty` calls per frame is negligible.

## 5. Spin Blur

Velocity-proportional `filter: blur()` during spin animation.

### Blur formula

```javascript
const blurPx = Math.min(velocity / 300, 4)
```

| Velocity | Blur   | Visual effect                     |
|----------|--------|-----------------------------------|
| 1200°/s  | 4px    | Labels smear into colored bands   |
| 600°/s   | 2px    | Labels soft but recognizable      |
| 150°/s   | 0.5px  | Sub-pixel, effectively sharp      |
| 0°/s     | 0px    | Crisp landing                     |

### Application

Applied to `this.reelTarget.style.filter` during `animateSpin()`. The
velocity is available from the `positionAtTime()` return value (`.vel`
property).

```javascript
this.reelTarget.style.filter = blurPx > 0.3 ? `blur(${blurPx.toFixed(1)}px)` : 'none'
```

The 0.3px threshold avoids setting a blur filter for imperceptible values
(saves a compositing pass).

### Cleanup

On spin complete: `this.reelTarget.style.filter = 'none'`
On idle: no blur applied (22°/s is well below threshold).

### Reduced motion

Already handled — `spin()` skips animation entirely for
`prefers-reduced-motion: reduce`, so blur never applies.

### Performance

`filter: blur()` on an element with `will-change: transform` is
GPU-composited. No layout/paint cost. The reel already has `will-change`.

## Files Changed

| File | Changes |
|------|---------|
| `app/javascript/controllers/dinner_picker_controller.js` | `populateCylinder()` builds panels + labels; `updateShading()` method; blur in `animateSpin()` |
| `app/assets/stylesheets/menu.css` | Panel styles, bezel gradient/shadows, chevron engraving, shade/opacity rules, delete vignette |

## Not in Scope

- Reflection below drum (decided against — keep it restrained)
- Embossed label text (decided against — cosine shading already adds depth)
- New Stimulus targets or values
- Markup changes to `show.html.erb` (all new elements built in JS)

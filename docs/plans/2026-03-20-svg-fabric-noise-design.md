# SVG Fabric Noise Design

Add organic grain to the gingham tablecloth background using a procedural
SVG `feTurbulence` filter. The noise breaks up the clinical regularity of
the pure-CSS gradient checks, making the fabric feel hand-woven rather than
digitally generated.

## Current State

`body::before` renders the gingham pattern using four layered
`repeating-linear-gradient`s (two red check layers at 135°/45°, two fine
gray weave lines). The result is clean but perfectly regular.

A `#paper-texture` SVG filter (diffuse-lit noise) already exists in the
layout for the content card's `main::before` overlay.

## Chosen Approach: Flat Grayscale Noise

Desaturated `feTurbulence` — neutral grain without directional lighting.
Unlike the paper texture's diffuse-lit filter, flat noise doesn't bias
toward white, so it won't wash out the red gingham stripes. It simply adds
organic irregularity.

### Filter definition

Add a second filter inside the existing `<svg>` block in the layout:

```xml
<filter id="fabric-texture">
  <feTurbulence type="fractalNoise" baseFrequency="0.65"
                numOctaves="4" stitchTiles="stitch" />
  <feColorMatrix type="saturate" values="0" />
</filter>
```

Key parameter differences from `#paper-texture`:
- `baseFrequency="0.65"` (vs 0.5) — tighter grain that reads as fabric
  weave rather than paper fiber
- No `feDiffuseLighting` — flat speckle, no directional light artifacts
- `feColorMatrix saturate=0` — desaturates the noise to neutral gray

### CSS changes

New custom property in `:root`:

```css
--gingham-noise-opacity: 0.07;
```

Dark mode override:

```css
--gingham-noise-opacity: 0.04;
```

New `body::after` pseudo-element layered over the gingham:

```css
body::after {
  content: '';
  position: fixed;
  inset: 0;
  z-index: -1;
  pointer-events: none;
  filter: url(#fabric-texture);
  opacity: var(--gingham-noise-opacity);
}
```

### Stacking context

`body::before` (gingham gradients) and `body::after` (noise overlay) both
use `position: fixed` with `z-index: -1`. The `::after` pseudo-element
naturally paints after `::before` in the same stacking context, so the
noise sits on top of the checks. All page content (`<main>`, `<nav>`, etc.)
has higher stacking context and remains above both layers.

### Print

Suppress the noise overlay in `print.css`:

```css
body::after {
  display: none;
}
```

### Dark mode

Same filter, lower opacity (0.04 vs 0.07). The desaturated noise is
inherently neutral — it works on both the warm off-white
(`rgb(249, 246, 243)`) and dark brown (`#1e1b18`) gingham bases without
color-shifting.

### Performance

Same cost profile as the paper texture filter: renders once on a static
fixed pseudo-element, no reflow triggers, cached after first paint. Window
resize is the only repaint trigger.

### CSP

No impact. The filter is inline markup — same-document fragment reference.

## Files Changed

| File | Change |
|------|--------|
| `app/views/layouts/application.html.erb` | Add `#fabric-texture` filter inside existing `<svg>` block |
| `app/assets/stylesheets/base.css` | Add `--gingham-noise-opacity` token, add `body::after` rule |
| `app/assets/stylesheets/print.css` | Add `body::after { display: none; }` |

## Alternatives Considered

- **Reuse `#paper-texture`** (diffuse-lit): simpler (no new filter), but
  the white-biased lighting output washes out the red gingham stripes.
- **Multiply-blended noise**: most organic (noise darkens into stripes),
  but `mix-blend-mode: multiply` on a fixed pseudo-element can trigger
  compositing quirks in Safari and doesn't work well in dark mode where
  multiply would make the already-dark background even darker.

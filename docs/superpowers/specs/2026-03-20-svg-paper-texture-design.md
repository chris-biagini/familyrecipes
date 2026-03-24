# SVG Paper Texture Design

Replace the tiling PNG paper texture on the content card with a procedural
SVG filter using `feTurbulence` + `feDiffuseLighting`. Eliminates an image
asset, adds tunability via CSS custom properties, and produces a richer
tactile effect that adapts to dark mode.

## Current State

`main::before` tiles `paper-noise.png` (34 KB) at 200×200px with 5% opacity.
`fabric-weave.png` (82 bytes) exists but is unused — the weave effect is
already CSS gradients.

## Chosen Approach: Diffuse-Lit Noise (4 octaves)

`feTurbulence` generates fractal noise; `feDiffuseLighting` treats the noise
alpha channel as a height map and simulates light reflecting off peaks and
valleys. The result looks like actual paper fiber rather than flat speckle.

### Filter definition

Inline SVG in the application layout, placed inside `<body>` but outside
`<main>` (after the closing `</main>` tag) so it does not become a child of
the content card. Include `aria-hidden="true"` since it is purely decorative
infrastructure:

```xml
<filter id="paper-texture">
  <feTurbulence type="fractalNoise" baseFrequency="0.5"
                numOctaves="4" stitchTiles="stitch" />
  <feDiffuseLighting lighting-color="white" surfaceScale="1.2">
    <feDistantLight azimuth="45" elevation="55" />
  </feDiffuseLighting>
</filter>
```

Key parameters:
- `baseFrequency="0.5"` — grain scale
- `numOctaves="4"` — detail layers (each octave doubles compute; 4 is the
  sweet spot between quality and cost)
- `surfaceScale="1.2"` — height exaggeration for the lighting
- `azimuth="45" elevation="55"` — light direction (top-left, moderate angle)
- `stitchTiles="stitch"` — seamless tiling at element edges

### CSS changes

New custom property in `:root`:

```css
--paper-opacity: 0.08;
```

Dark mode override:

```css
--paper-opacity: 0.04;
```

`main::before` replacement:

```css
main::before {
  content: "";
  position: absolute;
  inset: 0;
  filter: url(#paper-texture);
  opacity: var(--paper-opacity);
  pointer-events: none;
}
```

### Stacking context

The existing `main > * { position: relative; }` rule ensures all content
children sit above the absolutely-positioned `::before` overlay. This rule
must be preserved for the texture to stay behind interactive content.

### Print

Suppress the texture overlay in `print.css`:

```css
main::before {
  display: none;
}
```

### Dark mode

Same filter, lower opacity. The diffuse lighting produces near-white output
that works as a subtle overlay on both light (`rgb(255, 252, 249)`) and dark
(`rgb(30, 27, 24)`) card backgrounds.

### Performance

The filter renders once on a static pseudo-element. No reflow triggers — the
overlay is absolutely positioned with `pointer-events: none`. The browser
rasterizes on first paint and caches. Comparable cost to the current PNG
tiling approach. Window resize is the only repaint trigger.

### CSP

No impact. The SVG filter is inline markup in the layout, not an external
resource. No new `<script>` or `<style>` tags.

## Files Changed

| File | Change |
|------|--------|
| `app/views/layouts/application.html.erb` | Add inline `<svg>` with filter definition |
| `app/assets/stylesheets/base.css` | Replace `main::before` styles, add `--paper-opacity` token |
| `app/assets/images/paper-noise.png` | Delete |
| `app/assets/images/fabric-weave.png` | Delete (already unused) |
| `app/assets/stylesheets/print.css` | Add `main::before { display: none; }` |

## Alternatives Considered

- **Flat noise grain** (desaturated `feTurbulence` only): simpler, but
  produces uniform speckle without the tactile depth of lighting.
- **Fine film grain** (high frequency, low octaves): fast but reads as
  photographic grain, not paper.
- **5 octaves**: marginally richer detail, but the difference is invisible
  at 8% opacity and costs an extra noise computation pass.

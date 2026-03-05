# Dark Mode Design

## Summary

Add automatic dark mode via `prefers-color-scheme: dark`. No toggle UI — respects OS setting. Warm charcoal palette that preserves the cookbook feel. Subtle/faded gingham texture. Adaptive favicon and dual-set PWA icons.

## Color Palette

### Light Mode (current, unchanged)

| Role | Value |
|------|-------|
| Gingham base | `rgb(249, 246, 243)` |
| Gingham stripe | `rgba(190, 12, 30, 0.5)` |
| Overscroll | `rgb(205, 71, 84)` |
| Content card | `rgb(255, 252, 249)` |
| Frosted glass | `rgba(255, 252, 249, 0.75)` |
| Text | `rgb(50, 50, 50)` |
| Border (dark) | `rgb(25, 25, 25)` |
| Accent | `rgb(155, 10, 25)` |
| Hover bg | `#f5efe8` |
| Surface alt | `#fafafa` |
| Muted text | `#666` |
| Muted text light | `#888` |
| Border light | `#ccc` |
| Border muted | `#999` |
| Separator | `#ddd` |
| Danger | `#c00` |
| Scaled highlight | `rgba(255, 243, 205, 0.6)` |
| Input bg | `white` |

### Dark Mode (new)

Warm charcoal tint throughout — slightly brown-black, not blue-black or pure neutral. The red accent brightens slightly for contrast on dark surfaces.

| Role | Value | Rationale |
|------|-------|-----------|
| Gingham base | `rgb(24, 22, 20)` | Warm near-black |
| Gingham stripe | `rgba(140, 20, 30, 0.15)` | Barely visible — texture, not pattern |
| Weave | `rgba(100, 100, 100, 0.04)` | Even subtler than light mode |
| Overscroll | `rgb(30, 24, 22)` | Dark warm tone for rubber-band |
| Content card | `rgb(38, 35, 32)` | Elevated warm surface |
| Frosted glass | `rgba(38, 35, 32, 0.8)` | Translucent dark nav |
| Text | `rgb(220, 215, 210)` | Warm off-white, not harsh pure white |
| Border (dark) | `rgb(65, 60, 55)` | Visible but not glaring |
| Accent | `rgb(200, 55, 60)` | Slightly brighter red for dark bg contrast |
| Accent hover | `rgb(170, 45, 50)` | Darkened accent for hover states |
| Hover bg | `rgb(48, 44, 40)` | Subtle lift on hover |
| Surface alt | `rgb(32, 30, 28)` | Slightly darker than card for inset areas |
| Muted text | `rgb(140, 135, 130)` | Readable but clearly secondary |
| Muted text light | `rgb(110, 106, 102)` | Tertiary text |
| Border light | `rgb(60, 56, 52)` | Subtle borders |
| Border muted | `rgb(85, 80, 75)` | Medium borders |
| Separator | `rgb(50, 47, 44)` | Dividers |
| Danger | `rgb(220, 60, 50)` | Brighter red for visibility on dark |
| Checked color | `rgb(200, 55, 60)` | Matches accent |
| Scaled highlight | `rgba(180, 140, 60, 0.2)` | Warm amber tint, subtler |
| Input bg | `rgb(30, 28, 26)` | Slightly darker than card surface |
| Shadow opacity | Reduced ~50% | Shadows are less effective on dark; rely more on border/lightness |
| Dialog backdrop | `rgba(0, 0, 0, 0.65)` | Slightly more opaque to differentiate from dark bg |

### Semantic/Status Colors (dark mode adjustments)

| Role | Light | Dark | Notes |
|------|-------|------|-------|
| Source badge bg | `#cce5ff` | `rgba(50, 100, 160, 0.25)` | Desaturated, translucent |
| Source badge text | `#004085` | `rgb(130, 170, 220)` | Light blue on dark |
| Aisle renamed bg | `#fff8e1` | `rgba(180, 140, 40, 0.15)` | Warm amber tint |
| Aisle renamed border | `#ffe082` | `rgba(180, 140, 40, 0.3)` | Subtle amber |
| Aisle new bg | `#e8f5e9` | `rgba(60, 140, 70, 0.15)` | Muted green |
| Aisle new border | `#a5d6a7` | `rgba(60, 140, 70, 0.3)` | Subtle green |
| Broken reference bg | `#fdf6f0` | `rgb(42, 36, 32)` | Warm dark tint |
| Custom item border | `#eee` | `rgb(50, 47, 44)` | Matches separator |
| Custom item remove | `#bbb` | `rgb(110, 106, 102)` | Matches muted-text-light |
| Aisle group border | `#e0e0e0` | `rgb(55, 52, 48)` | Warm mid-dark |

## CSS Architecture

### Variable Consolidation

Currently ~30 hard-coded color values are scattered across the three stylesheets. All of these become CSS variables in `:root`, then overridden in a `@media (prefers-color-scheme: dark)` block.

New variables to add (replacing hard-coded values):

```
--input-bg                  white -> var in dark
--shadow-color              rgba(0,0,0,*) -> lower opacity in dark
--dialog-backdrop           rgba(0,0,0,0.5) -> more opaque in dark
--accent-hover              rgb(135,8,20) -> brighter in dark
--scaled-highlight          rgba(255,243,205,0.6) -> amber in dark
--source-badge-bg           #cce5ff
--source-badge-text         #004085
--aisle-renamed-bg          #fff8e1
--aisle-renamed-border      #ffe082
--aisle-new-bg              #e8f5e9
--aisle-new-border          #a5d6a7
--broken-reference-bg       #fdf6f0
--aisle-row-border          #e0e0e0
--custom-item-border        #eee
--custom-item-remove        #bbb
--overscroll-color          rgb(205,71,84)
```

The dark override block lives at the top of `style.css`, right after the light `:root` block. The other two stylesheets (`menu.css`, `groceries.css`) reference variables from `style.css` — no duplication of the dark palette.

Remaining hard-coded `white` values for text-on-accent (checkbox checkmarks, btn-primary text, btn-danger hover text) stay as `white` — they're always white regardless of mode.

### Structure

```css
:root {
  /* All light-mode variables */
}

@media (prefers-color-scheme: dark) {
  :root {
    /* Override every variable that changes */
  }
}
```

### Print

Print styles already force `background: white` and `color: black`. No dark mode changes needed for print.

## Favicon

### Current

Simple SVG with hard-coded cream + red:
```xml
<svg width="16" height="16" ...>
  <rect fill="rgb(249,246,243)" />
  <rect fill="rgb(190,12,30)" fill-opacity="0.5" />
  <rect fill="rgb(190,12,30)" fill-opacity="0.5" />
</svg>
```

### Dark-Adaptive

Add a `<style>` block with `prefers-color-scheme` media query. CSS classes control the fill colors:

```xml
<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
  <style>
    .base { fill: rgb(249,246,243); }
    .check { fill: rgb(190,12,30); fill-opacity: 0.5; }
    @media (prefers-color-scheme: dark) {
      .base { fill: rgb(38,35,32); }
      .check { fill: rgb(200,55,60); fill-opacity: 0.35; }
    }
  </style>
  <rect width="16" height="16" class="base" />
  <rect width="8" height="16" class="check" />
  <rect width="16" height="8" class="check" />
</svg>
```

Browser tabs will auto-adapt. The dark favicon uses the card surface color as its base and a brighter but lower-opacity red for the check pattern.

## PWA Icons

### Dual Icon Sets

`rake pwa:icons` generates both light and dark PNG sets from the same `favicon.svg`. To force the media query during rsvg-convert, we create a temporary modified SVG that hard-codes the dark colors (since rsvg-convert doesn't respect `prefers-color-scheme`).

**Generated files:**

| Filename | Size | Mode |
|----------|------|------|
| `icon-192.png` | 192x192 | Light |
| `icon-512.png` | 512x512 | Light |
| `apple-touch-icon.png` | 180x180 | Light |
| `favicon-32.png` | 32x32 | Light |
| `icon-192-dark.png` | 192x192 | Dark |
| `icon-512-dark.png` | 512x512 | Dark |
| `apple-touch-icon-dark.png` | 180x180 | Dark |
| `favicon-32-dark.png` | 32x32 | Dark |

### Manifest Changes

`PwaController#manifest_data` includes both icon sets:

```ruby
icons: [
  { src: versioned_icon_path('icon-192.png'), sizes: '192x192', type: 'image/png' },
  { src: versioned_icon_path('icon-512.png'), sizes: '512x512', type: 'image/png' },
  { src: versioned_icon_path('icon-192-dark.png'), sizes: '192x192', type: 'image/png',
    purpose: 'any', media: '(prefers-color-scheme: dark)' },
  { src: versioned_icon_path('icon-512-dark.png'), sizes: '512x512', type: 'image/png',
    purpose: 'any', media: '(prefers-color-scheme: dark)' }
]
```

Where `media` isn't supported, the browser falls back to the first matching size (light icons) — identical to today's behavior.

### Layout Changes

Add a dark-mode `apple-touch-icon` link:

```erb
<link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon.png') %>">
<link rel="apple-touch-icon" sizes="180x180" href="<%= versioned_icon_path('apple-touch-icon-dark.png') %>" media="(prefers-color-scheme: dark)">
```

Similarly for the PNG favicon:

```erb
<link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32.png') %>">
<link rel="icon" type="image/png" sizes="32x32" href="<%= versioned_icon_path('favicon-32-dark.png') %>" media="(prefers-color-scheme: dark)">
```

The SVG favicon adapts automatically via its internal `<style>` — no extra `<link>` needed.

### Theme Color

The `<meta name="theme-color">` in the layout and `theme_color` in the manifest need dark variants:

```erb
<meta name="theme-color" content="rgb(205, 71, 84)" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="rgb(30, 24, 22)" media="(prefers-color-scheme: dark)">
```

Manifest `theme_color` stays as the light value (it's a single value; the meta tag takes precedence at runtime).

## Scope

### In Scope

1. CSS variable consolidation — replace all hard-coded colors with variables
2. Dark mode `@media (prefers-color-scheme: dark)` override block
3. Adaptive favicon SVG
4. Dual PNG icon generation in `rake pwa:icons`
5. Manifest and layout updates for dark icons + theme-color
6. Tests for manifest dark icons and theme-color meta tags

### Out of Scope

- Toggle UI (can add later)
- Nav icon SVGs (they use `currentColor`, so they adapt automatically)
- Service worker changes (icon URLs are new but follow existing caching patterns)

## Risk

- **rsvg-convert and CSS media queries**: rsvg-convert likely ignores `prefers-color-scheme` in SVG `<style>` blocks. The rake task will need to generate a temporary SVG with dark colors baked in, or use a simpler approach like a separate dark SVG template string.
- **Contrast ratios**: The warm muted palette needs WCAG AA checking, especially muted text on dark surfaces. We'll verify during implementation.
- **Frosted glass on dark**: `backdrop-filter: blur()` on dark translucent surfaces can look muddy. May need to adjust opacity or blur radius.

# Menu Page Visual Refresh

**Date:** 2026-03-04
**Status:** Approved

## Problem

The menu page's availability indicators have several visual issues:
- Green/gray colors feel disconnected from the warm cream/red gingham palette
- Serif font in expanded ingredient detail is ornate and hard to scan at small sizes
- Expanded view uses italic comma-separated text with tight spacing — noisy
- Have and Missing sections are visually indistinguishable
- Hover state (`#fafafa` on `#fffcf9`) is nearly invisible, especially for CVD users
- Unicode ✓/✗ glyphs have a calligraphic look that clashes with the Futura UI elements

## Direction

1960s cookbook aesthetic — warm, earthy, slightly faded tones. No clinical greens. Harvest gold as the positive indicator color.

## Design

### Color Palette

| Role | Old | New |
|------|-----|-----|
| Checkbox checked | `#2a5a3a` (green) | `rgb(155, 10, 25)` (accent red) |
| On-hand / Have | `#2a5a3a` | `#b8860b` (harvest gold / darkgoldenrod) |
| Missing / Need | `#666` / `#999` | `#996` (warm dusty brown-gray) |
| Hover background | `#fafafa` | `#f5efe8` (warm cream tint) |

### SVG Indicators

Replace Unicode ✓/✗ with clean geometric inline SVGs:
- **On-hand:** Filled circle (10px) — solid, "complete"
- **Missing:** Open circle ring (10px) — hollow, "not yet"
- Shape difference (filled vs hollow) is CVD-safe — no color-only encoding

### Typography & Layout

**Badge (summary pill):** Switch from serif to Futura. Keep pill shape, update colors.

**Expanded ingredient detail:**
- Font: Futura regular 0.8rem (was serif italic 0.75rem)
- Two separate labeled lines instead of comma-separated dump
- Labels ("HAVE" / "MISSING") in Futura bold uppercase 0.65rem
- Have line in harvest gold; Missing line in warm muted
- Padding bumped to 0.4rem for breathing room

### Hover State

- Background: `#f5efe8` (clearly visible warm cream)
- Left border: 2px solid `rgb(155, 10, 25)` — non-color-dependent shape cue
- Applies to both recipe and quick bite rows

## Files

- `app/assets/stylesheets/style.css` — checkbox color variable
- `app/assets/stylesheets/menu.css` — all availability and hover styles
- `app/views/menu/_recipe_selector.html.erb` — SVG markup, expanded detail structure

## Not Changing

Page structure, `<details>/<summary>` pattern, responsive grid, print styles, Stimulus controller, Quick Bites layout.

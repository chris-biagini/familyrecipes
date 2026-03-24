# Typography Cleanup Design

## Problem

The site's body font is Bodoni 72 — a display serif with hairline strokes,
designed for magazine covers at large sizes. At 18px on screen it's fatiguing
to read and pushes the whole design into ornate-retro territory that clashes
with the dynamic, interactive app the site has become. Meanwhile, Futura is
declared individually 30+ times across three CSS files instead of via custom
properties, and fallback stacks vary between declarations.

## Decision

**Keep Futura** for display/UI: headings (h1–h3), nav links, category headers,
uppercase labels. It's geometric, bold, and part of the brand alongside the
gingham.

**Replace Bodoni with Source Sans 3** for body text: recipe prose, ingredients,
instructions, descriptions, paragraphs — everything that's meant to be *read*.
Also use Source Sans for all user inputs and buttons, since those are body-level
interactive text, not display elements.

**Self-host the font** as WOFF2 files to satisfy the strict CSP (no external
resources). Include the SIL Open Font License alongside the files. Source Sans 3
is SIL OFL 1.1 — fully compatible with AGPL.

## Font Files

Download from Google Fonts. We need:

- `SourceSans3-Regular.woff2` (400)
- `SourceSans3-Italic.woff2` (400 italic)
- `SourceSans3-SemiBold.woff2` (600) — for emphasis in body contexts
- `SourceSans3-Bold.woff2` (700) — for strong tags, bold body text

Place in `app/assets/fonts/source-sans-3/` with an `OFL.txt` license file.

Total payload: ~60–80KB for four weights, loaded once and cached.

## CSS Architecture

### Custom Properties

Define three font variables in `:root`:

```css
:root {
  --font-display: "Futura", "Trebuchet MS", sans-serif;
  --font-body: "Source Sans 3", "Source Sans Pro", sans-serif;
  --font-mono: ui-monospace, "Cascadia Code", "Source Code Pro", Menlo, Consolas, monospace;
}
```

### @font-face Declarations

Add to the top of `style.css`, after `:root` variables:

```css
@font-face {
  font-family: "Source Sans 3";
  src: url("source-sans-3/SourceSans3-Regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
/* ... repeat for italic, 600, 700 */
```

### Replacement Rules

1. `body { font-family: ... }` → `var(--font-body)` (replaces Bodoni)
2. All 30+ `font-family: "Futura", sans-serif` → `var(--font-display)`
3. All monospace declarations → `var(--font-mono)`
4. Nutrition label keeps `"Helvetica Neue"` (FDA compliance, not a brand choice)
5. Search overlay switches from Helvetica Neue to `var(--font-body)` (consistency)
6. Buttons and form inputs get explicit `font-family: var(--font-body)`
7. Delete the commented-out `quigleywigglyregular` reference

### Fallback Stack Rationale

- `"Trebuchet MS"` is the best geometric-sans system fallback for Futura
  (available on macOS and Windows, similar proportions)
- `"Source Sans Pro"` is the previous name for Source Sans 3 — catches systems
  that have the older version installed

## What Stays the Same

- Gingham background (untouched)
- Weave overlay (untouched)
- All font sizes, weights, letter-spacing, text-transform values
- Color palette
- Dark mode
- Monospace for editors
- Helvetica Neue for FDA nutrition label
- Overall layout and spacing

## Scope Boundary

This is a font swap and CSS cleanup only. No changes to HTML structure, no
changes to font sizes or spacing, no changes to the gingham or color palette.
If Source Sans 3 reveals that some sizes or weights need tuning, that's a
follow-up.

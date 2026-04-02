# Help Site Dark Mode Design

**Date:** 2026-04-01

## Goal

Add dark mode support to the Jekyll help site (`docs/help/`) using pure CSS
`prefers-color-scheme` media queries. No JavaScript, no manual toggle — the
site follows the user's OS preference automatically.

---

## Activation

A single `@media (prefers-color-scheme: dark)` block at the end of
`docs/help/assets/style.css`. Every hardcoded light-mode color gets an
override in this block.

No CSS custom properties — the site is small enough (one stylesheet, no
theming variants) that direct overrides in one media query block are simpler
and more readable than converting everything to variables.

No markup or layout changes. The favicon SVG already handles
`prefers-color-scheme` independently.

---

## Color Palette

Zinc neutral scale — true neutral with no blue or brown cast. Lets the
terracotta accent stand out cleanly.

### Backgrounds

| Role              | Light          | Dark           |
|-------------------|----------------|----------------|
| Page              | `#f9fafb`      | `#18181b`      |
| Surface (sidebar, topbar, cards, callouts, table headers) | `#fff` | `#27272a` |
| Borders           | `#e5e7eb`      | `#3f3f46`      |
| Dividers (sidebar)| `#f3f4f6`      | `#3f3f46`      |

### Text

| Role              | Light          | Dark           |
|-------------------|----------------|----------------|
| Primary (h1, h2)  | `#111827`      | `#fafafa`      |
| Body (p, li, td)  | `#374151`      | `#d4d4d8`      |
| Secondary (lead, breadcrumb, sidebar labels) | `#6b7280` / `#9ca3af` | `#a1a1aa` |
| Topbar name       | `#111827`      | `#fafafa`      |
| Topbar subtitle   | `#9ca3af`      | `#a1a1aa`      |

### Accent

Terracotta `#c0522a` stays the same for links, active nav, callout left
borders, and card hover borders. The inline code text color may need a slight
warm lift (e.g. `#d4835a`) for WCAG contrast on the dark background — verify
during implementation.

### Components

**Sidebar:**
- Background: `#27272a`
- Border-right: `#3f3f46`
- Link text: `#a1a1aa` (default), `#c0522a` (active)
- Hover/active background: `rgba(192, 82, 42, 0.1)`

**Inline code:**
- Background: `#27272a`
- Text: terracotta (same or lifted)

**Code blocks:**
- Background: `#2e2b28` (slight lift from current `#1e1b18` so blocks stand
  out from the `#18181b` page)
- Text: `#e5e0d8` (unchanged)

**Callouts:**
- Background: `#27272a`
- Border: `#3f3f46`
- Left border: `#c0522a`
- Text: `#d4d4d8`

**Section cards:**
- Background: `#27272a`
- Border: `#3f3f46`
- Hover: border `#c0522a`, shadow `rgba(192, 82, 42, 0.15)`
- Card heading: `#fafafa`
- Card description: `#a1a1aa`

**Tables:**
- Header background: `#27272a`
- Header border-bottom: `#3f3f46`
- Row border: `#3f3f46`

**Page nav (prev/next):**
- Border-top: `#3f3f46`

**Mobile nav backdrop:**
- `rgba(0, 0, 0, 0.5)` (slightly more opaque than light mode's 0.3)

**Mobile nav toggle hover:**
- Background: `#3f3f46`

---

## Scope

Only one file changes: `docs/help/assets/style.css`.

All overrides live in a single `@media (prefers-color-scheme: dark)` block
appended to the end of the file. The block mirrors the structure of the
existing stylesheet for easy cross-reference.

---

## Out of Scope

- Manual dark/light toggle (no JS)
- CSS custom properties refactor
- Changes to layout HTML or Jekyll templates
- Favicon SVG (already handles dark mode)

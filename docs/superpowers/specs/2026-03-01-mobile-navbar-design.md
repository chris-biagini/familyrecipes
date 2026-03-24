# Mobile Navbar Design

**Issue:** #119 — Make navbar adapt to mobile
**Date:** 2026-03-01

## Problem

The navbar overflows to two lines on mobile. Renaming "Home" to "Recipes" (desired) would make it worse. Four nav links plus up to two action buttons don't fit at narrow widths.

## Solution: Icon+Text Nav Links

Add inline SVG icons to each nav link. Desktop shows icon + text label. Mobile (≤600px) hides text and shows icon only, freeing space for action buttons.

No hamburger menu. No new Stimulus controller. Pure HTML + CSS.

## Icon Set

| Page | Icon | Shape | Distinguishing trait |
|------|------|-------|---------------------|
| Recipes | Open book | Wide/landscape | Two splayed pages with center spine |
| Ingredients | Pantry jar | Upright cylinder | Lid on top, rounded body |
| Menu | Folded menu card | Tall/portrait | Single fold on left, text lines on right |
| Groceries | Shopping cart | Standard cart | Wheels, handle, basket |

Book vs menu card distinguished by orientation: book is landscape, menu card is portrait.

## Behavioral Changes

- Rename "Home" link to "Recipes" (text label and title attribute).
- Drop mid-dot separators between links (awkward between icon-only items on mobile).
- Icons inherit `currentColor` — existing hover/focus color transitions apply automatically.
- `aria-label` on each link for accessibility when text is hidden.

## Breakpoints

- **Desktop (>600px):** Icon + text label, side by side within each link.
- **Mobile (≤600px):** Icon only. Text hidden via CSS. Action buttons remain visible.

Aligns with the existing `@media screen and (max-width: 600px)` breakpoint already in `style.css`.

## What Stays the Same

- Sticky frosted-glass bar, backdrop blur, box shadow.
- Underline hover animation on links (via `::after`).
- Extra nav buttons (Edit, Scale, + New, Edit Quick Bites, Edit Aisle Order) untouched.
- No changes to Stimulus controllers, importmap, or CSP.

## Files Changed

- `app/views/shared/_nav.html.erb` — add inline SVGs, rename Home to Recipes, add `aria-label`.
- `app/assets/stylesheets/style.css` — icon sizing, text hide at mobile breakpoint, remove mid-dot separator.
- `app/helpers/application_helper.rb` — possibly extract a `nav_link` helper if the ERB gets repetitive (optional).
- Tests — update any assertions on nav link text ("Home" → "Recipes").

# Typography Redesign Spec

**Status:** Ready for implementation
**Baseline:** `public/typography/redesign/v4-quiet-lux.html`
**Target:** All three stylesheets (`style.css`, `menu.css`, `groceries.css`)

## Design Language

The redesign replaces the current gingham-check aesthetic with a quieter,
more refined look. The gingham favicon remains — it's the logo, not the
background. The new design is warm, restrained, and typographically rich.

### Fonts

**Display:** Instrument Serif (regular 400 + italic), via Google Fonts.
Elegant, modern serif. Used for: page titles (`h1`), step headers (`h2` on
recipes), the site name in nav, recipe description text.

**Body:** Outfit (300, 400, 500, 600), via Google Fonts. Geometric sans with
warmth and great legibility. Used for: everything else — body text, nav links,
category headers, buttons, form labels, ingredient lists.

**Mono:** Keep the current `--font-mono` stack for editor textareas.

Both fonts must be loaded via the layout (`application.html.erb`), not
`@import` in CSS, so they work with the strict CSP. Use `<link>` tags with
`preconnect`.

The existing Source Sans 3 `@font-face` declarations and woff2 files can be
removed once the migration is complete.

### Color Tokens (Light Mode)

```
--ground:       #faf8f5     (page background — warm near-white)
--text:         #2d2a26     (primary text — warm almost-black)
--text-soft:    #706960     (secondary text — descriptions, meta)
--text-light:   #a09788     (tertiary text — timestamps, counts, muted labels)
--red:          #b33a3a     (accent — one precise red, used sparingly)
--red-light:    rgba(179, 58, 58, 0.08)  (hover backgrounds, focus rings)
--rule:         #e4dfd8     (standard divider lines)
--rule-faint:   #eee9e3     (subtle dividers — ingredient/instruction border)
```

### Color Tokens (Dark Mode)

Dark mode needs a full mapping. Guiding principle: invert the luminance, keep
the warmth. The ground should be a warm dark brown (not pure black), and the
accent red should be slightly lighter/more saturated to read well on dark.

```
--ground:       #1e1b18     (warm dark brown)
--text:         #dcd7d0     (warm light gray)
--text-soft:    #a09788     (mid-warm gray)
--text-light:   #706960     (darker gray — swaps with light mode text-soft)
--red:          #c85050     (slightly lighter/warmer red for dark backgrounds)
--red-light:    rgba(200, 80, 80, 0.12)
--rule:         #3a3530     (dark divider)
--rule-faint:   #2e2a26     (subtle dark divider)
```

Additional dark-mode mappings for existing semantic variables:
```
--content-background-color  → var(--ground)  (no separate card background)
--frosted-glass-bg          → rgba(30, 27, 24, 0.8)
--accent-color              → var(--red)
--checked-color             → var(--red)
--hover-bg                  → rgba(255, 255, 255, 0.04)
--separator-color           → var(--rule)
--border-color              → var(--rule)
--border-light              → var(--rule-faint)
--border-muted              → var(--rule)
--surface-alt               → #252220
--input-bg                  → #1a1816
--danger-color              → #d05050
--shadow-*                  → reduce opacity further
```

### Background

**No pattern.** The `--ground` color is the entire background. Remove:
- The gingham repeating-linear-gradient layers
- The weave overlay
- The `--overscroll-color` (replace with `--ground`)
- All `--gingham-*` and `--weave-*` variables

The `<html>` element gets `background-color: var(--ground)` and nothing else.

### The Red Line

A single 2px red line at the very top of the page. This is the **only** bold
color gesture. Implemented as `body::before` with `height: 2px; background:
var(--red)`.

### Content Card → No Card

The current design wraps `<main>` in a bordered, shadowed card on a patterned
background. The new design removes the card entirely:

```css
main {
  max-width: 35rem;    /* keep the same measure */
  margin: 0 auto;
  padding: 3rem 1.5rem 5rem;
  border: none;
  background: none;
  box-shadow: none;
  border-radius: 0;
}
```

The current `--breathing-room` variable (3rem, shrinks to 1.5rem/0.75rem on
mobile) controls body side-padding AND the nav's negative margin
(`margin: 0 calc(-1 * var(--breathing-room))`) that makes the nav span
edge-to-edge despite the body padding. With the card removed, the body no
longer needs side-padding — the `main` element's own padding provides the
content inset. But the nav still needs to span full-width, so the
breathing-room + negative-margin pattern can be replaced: give `body` zero
side-padding and let `main` handle its own horizontal padding (1.5rem on
wide, 1rem on narrow). The nav can then use `margin: 0` with no negative
offset.

On narrow screens, horizontal padding never hits zero — maintain at least
`1rem` on `main`.

### Typography Scale

```
h1 (page titles):     font-display, 3.8rem, weight 400, line-height 1.05
h1 (narrow):          2.6rem
h2 (step headers):    font-display, 1.4rem, weight 400, line-height 1.35
h2 (category heads):  font-body, 0.68rem, weight 600, uppercase, ls 0.2em
Body (base):          font-body, line-height 1.65 (current site has NO explicit line-height — set one)
Body text:            font-body, 0.95rem, weight 400, line-height 1.75
Ingredients:          font-body, 0.84rem, weight 400, line-height 2
Meta/labels:          font-body, 0.72rem, weight 500, uppercase, ls 0.12em
Nav site name:        font-display, 1.1rem
Nav links:            font-body, 0.72rem, weight 500, uppercase, ls 0.1em
```

### Rules & Dividers

Every rule is a single thin line in `var(--rule)` or `var(--rule-faint)`. No
doubled lines, no colored accent on rules. The only red accent in dividers is
the 40px-wide `var(--red)` dash used as a centered divider under page titles.

The `footer::before` dingbat (`❇︎`) should be removed. Replace the recipe
footer with a centered source note: italic display font, `var(--text-light)`,
with a 40px centered rule above it.

### Section Breaks

Between major sections (e.g., between the TOC and a recipe on the same page),
use a simple centered dot: `var(--rule-faint)` lines left and right, a 4px
red dot in the center. This is already implemented in V4.

## Component Mapping

### Nav

**Current:** Sticky frosted-glass bar, hamburger menu on mobile, Futura
uppercase links with animated underlines.

**New:** Same sticky behavior, same hamburger mechanics, but rethemed:
- Background: `var(--ground)` solid (no frosted glass)
- Border-bottom: `1px solid var(--rule)` (not `--gingham-stripe-color`)
- Site name: Instrument Serif, 1.1rem, normal weight
- Nav links: Outfit 0.72rem, weight 500, uppercase, `var(--text-light)`
- Hover/active: `color: var(--red)`, no animated underline (drop it)
- Shadow: keep `--shadow-nav` but tune for the quieter palette

The hamburger icon, drawer animation, and Stimulus controller stay unchanged.
Only the colors, fonts, and border treatment change.

### Recipe Page

**Header:** Centered. Title in display font at 3.8rem. Description in italic
display font. Meta line (category, makes, serves) in small uppercase body font.
40px red divider centered below.

**Step headers:** Display font at 1.4rem, no border-bottom, no background-image
accent. Just the text, with generous whitespace above (3.5rem margin-top between
steps).

**Ingredient/instruction grid:** Keep `grid-template-columns: 10rem 1fr` with
`gap: 0 2.5rem`. Instructions get a `border-left: 1px solid var(--rule-faint)`
and `padding-left: 2rem`.

On mobile (`max-width: 720px` — matching the existing breakpoint), collapse
the grid to single column. Ingredients stack above instructions with a
`border-top` instead of `border-left`. Note: the current site also switches
ingredient lists to two `column-count` columns at this breakpoint — preserve
that behavior.

**Ingredient list items:** Currently `<li>` with `<b class="ingredient-name">`
and `<span class="quantity">`. Style the name at normal weight (400) in body
text color; the quantity in `--text-light` at weight 300. Generous line-height
(2) for easy scanning while cooking.

**Cross-off interaction:** Keep line-through + muted color. Update
`--muted-text-light` to use `var(--text-light)`.

### Homepage / Table of Contents

**Header:** Same as recipe header — centered, display font, subtitle in italic.

**Category nav:** Centered inline list, `var(--text-light)` with middot
separators. Hover color: `var(--red)`.

**Category headers:** Outfit, 0.68rem, weight 600, uppercase, wide letter-spacing,
`color: var(--text-light)`, bottom border `1px solid var(--rule-faint)`.

**Recipe lists:** Two columns at desktop (`column-count: 2`), staying at two
columns at the 720px mobile breakpoint. Links in `var(--text)`, hover
`var(--red)`.

### Menu Page

Retheme only — same layout. Update:
- Category `h2` headers to match new category header style
- Checkbox colors: `--checked-color` → `var(--red)`
- Hover backgrounds: `--hover-bg` → new warm hover
- Quick Bites section separator: `var(--rule)` not `--separator-color`
- Availability badges: inherit from `--red` / `--text-light`

### Groceries Page

Retheme only — same layout. Update:
- Aisle group borders/backgrounds to use new `--surface-alt`, `--rule`
- Checkbox colors
- Summary font: use `--font-body` (Outfit) for aisle headers, not `--font-display`

Wait — actually the category and aisle headers currently use `--font-display`
(Futura). The new `--font-display` is Instrument Serif. Aisle/category section
headers styled as `uppercase letter-spaced` should use `--font-body` (Outfit),
since a serif font in uppercase small caps looks wrong. Update all instances of
`font-family: var(--font-display)` in section headers, labels, and UI chrome
to `var(--font-body)`.

**Rule:** `var(--font-display)` is for *display text* only — large titles,
site name, recipe descriptions, step headers. Everything else (section headers,
labels, nav links, buttons, form elements, editor chrome) uses
`var(--font-body)`.

### Ingredient Table

Retheme colors and fonts. The table structure stays the same.

### Editor Dialogs

Retheme. The dialog border, background, and shadow use the new tokens. Header
`h2` uses `var(--font-body)` uppercase (not display). The editor textarea
keeps `--font-mono`.

### Search Overlay

Retheme. The panel background, border-radius, shadow stay. Update colors to
new tokens. Selected result highlight: `background: var(--red); color: white`.

### Notification Toast

Retheme. Use `var(--ground)` frosted glass, `var(--rule)` border instead of
`--gingham-stripe-color`.

### FDA Nutrition Label

**Do not retheme.** The nutrition label intentionally uses Helvetica/Arial and
hard-coded black-on-white styling to match FDA regulations. It should look like
a real nutrition label regardless of site theme. The dark-mode override that
inverts its colors should stay.

### Settings Page, Login Page

Retheme colors and fonts. No layout changes.

### Embedded Recipe Cards

Keep the "paper on paper" effect but update to new tokens. Border
`var(--rule)`, background `var(--ground)` (or maybe slightly different —
consider `#fdfbf8` to create subtle contrast against the ground).

### Print Styles

Keep as-is. Print already strips backgrounds, shadows, borders. May need minor
font-family updates.

### App Version Footer

Keep the small muted version text. Remove `footer::before { content: "❇︎"; }`
globally (it currently appears before every `<footer>`, including the recipe
source footer and the app version).

## Responsive Strategy

**Breakpoints to preserve:**
- `720px` — mobile layout (ingredient grid → single column, ingredient
  lists → two `column-count` columns, recipe index lists → two columns,
  `main` padding reduced, editors go fullscreen)
- `720px + pointer: coarse` — small mobile (reduced base font size to 16px)
- `768px` — ingredient table: hide aisle and recipes columns
- `840px` — menu page two-column grid

**Key mobile behaviors to preserve:**
- Ingredient/instruction grid collapses to single column at 720px
- Ingredient `<ul>` switches to `column-count: 2` at 720px
- Recipe index lists (`section > ul`) switch to `column-count: 2` at 720px
- Editor dialogs go fullscreen at 720px
- Hamburger nav drawer replaces inline links (controlled by JS, not breakpoint)

**Note:** The current site has NO breakpoint at 600px. The V4 mockup used 600px
for its responsive rules, but the implementation should use the existing 720px
breakpoint to stay consistent. Add a new 600px breakpoint only if there's a
clear reason (e.g., title font size scaling).

**New responsive behavior:**
- `h1` scales down to 2.6rem at the 720px breakpoint (not 600px)
- Horizontal padding stays `1.5rem` on wide, `1rem` on narrow (never zero)

## Variable Migration

The current CSS has many ad-hoc color values. Map them all to the new tokens:

```
--border-color          → --rule (or --text for high-contrast borders)
--text-color            → --text
--muted-text            → --text-soft
--muted-text-light      → --text-light
--border-light          → --rule-faint
--border-muted          → --rule
--separator-color       → --rule
--accent-color          → --red
--accent-hover          → darken(--red) or explicit darker red
--checked-color         → --red
--on-hand-color         → --red
--missing-color         → --red
--surface-alt           → slightly off-ground for grouped elements
--hover-bg              → rgba warm hover
--content-background-color → --ground
--frosted-glass-bg      → rgba(--ground, 0.85) + backdrop-filter
--danger-color          → keep distinct (#c00 light / #d05050 dark)
```

## Implementation Order

1. **`:root` variables and base typography** — swap fonts, colors, remove gingham
2. **`body` and `html`** — remove gingham background, add red line, remove card from `main`
3. **Nav** — retheme sticky bar, keep hamburger mechanics
4. **Recipe content** — headers, step grid, ingredients, footer
5. **Homepage/TOC** — category headers, recipe lists, toc nav
6. **Menu page** (`menu.css`) — retheme checkboxes, categories, Quick Bites
7. **Groceries page** (`groceries.css`) — retheme aisles, check-off items
8. **Ingredients page** — retheme table, toolbar, filter pills
9. **Editor dialogs** — retheme all editor chrome
10. **Search overlay** — retheme panel and results
11. **Settings, login, notifications** — retheme forms and toasts
12. **Embedded recipe cards** — retheme borders and shadows
13. **Dark mode** — full pass through all dark-mode overrides
14. **Print** — verify, fix any font-family issues
15. **Cleanup** — remove dead variables, Source Sans files, unused rules

## What NOT to Change

- HTML structure of any template
- Stimulus controller behavior
- Hamburger animation keyframes/transforms
- Editor dialog open/close mechanics
- Scroll preservation, Turbo morphing, ActionCable
- FDA nutrition label styling (except dark-mode border inversion)
- Print layout logic
- Any JavaScript

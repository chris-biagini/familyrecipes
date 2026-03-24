# Typography Redesign — Implementation Prompt

Use this prompt to kick off the redesign implementation in a fresh context
window with 1M context and high effort enabled.

---

## Prompt

I'm redesigning the typography and visual style of my recipe site. The design
spec is at `docs/plans/2026-03-12-typography-redesign-spec.md` — read it
carefully before doing anything. The reference HTML mockup is at
`public/typography/redesign/v4-quiet-lux.html`.

This is a **retheme, not a rewrite.** The site is a working Rails app with
Stimulus controllers, Turbo, ActionCable, and carefully-tuned responsive
behavior. Do not change any HTML templates or JavaScript. Only modify CSS
files: `app/assets/stylesheets/style.css`, `menu.css`, and `groceries.css`.

### Setup

Before writing any code:

1. Read the design spec (`docs/plans/2026-03-12-typography-redesign-spec.md`)
2. Read the V4 reference mockup (`public/typography/redesign/v4-quiet-lux.html`)
3. Read all three CSS files completely (`style.css`, `menu.css`, `groceries.css`)
4. Read `CLAUDE.md` for project conventions
5. Read `app/views/layouts/application.html.erb` — you'll need to add font
   `<link>` tags here (this is the ONE template change allowed)

### How to work

Work through the spec's implementation order (steps 1–15), one section at a
time. After each section:

1. Make the CSS changes
2. Verify visually by checking the site in the browser (use Playwright
   screenshots if available, or just navigate to key pages)
3. Run `rake lint` to check for any issues
4. Commit the section with a descriptive message

**Do not try to do everything at once.** The spec is carefully ordered so each
step builds on the previous one. If you make a mistake, it's easier to catch
in a small diff than a 2000-line change.

### Key gotchas

- **`--font-display` usage:** The old `--font-display` was Futura (a geometric
  sans). The new one is Instrument Serif. Many existing uses of
  `var(--font-display)` are for uppercase section headers, labels, and UI
  chrome — these must be changed to `var(--font-body)`. Only large display
  text (h1 titles, site name, recipe descriptions, step headers) should use
  `var(--font-display)`.

- **Font loading:** Add Google Fonts `<link>` tags to `application.html.erb`.
  The CSP allows Google Fonts (`fonts.googleapis.com` and `fonts.gstatic.com`).
  Check `config/initializers/content_security_policy.rb` to verify — if these
  domains aren't allowed, add them to the CSP before adding the links.

- **The `footer::before` dingbat:** `footer:before { content: "❇︎"; }` adds
  a sparkle before every `<footer>`, including the app version footer. Remove
  it entirely.

- **Gingham cleanup:** Delete all `--gingham-*` and `--weave-*` variables and
  the 30+ lines of `background-image` gradients on `html`. Replace with
  `background-color: var(--ground)`.

- **Notification toast border:** Currently uses `--gingham-stripe-color`. Must
  be updated to `var(--rule)`.

- **FDA nutrition label:** Do NOT retheme. It's styled to match FDA regulations.
  Only ensure the dark-mode override still works.

- **Dark mode:** Must be done as a complete pass. Every light-mode color
  variable needs a dark-mode counterpart. The spec provides the full mapping.

- **The `body::before` red line** must sit above the sticky nav. Currently
  `body::before` is `display: block`, which pushes content down. The nav is
  `position: sticky; top: 0`. This means the red line scrolls away naturally —
  that's fine, it's a nice touch. But make sure the line width spans the full
  viewport, not just the content column.

- **`main` card removal:** The current `main` has `border`, `background-color`,
  `box-shadow`, and `border-radius`. All four must be removed. The `max-width`
  and `margin: auto` stay.

- **Source Sans cleanup:** After the retheme is verified working, remove the
  `@font-face` declarations for Source Sans 3 at the top of `style.css`. The
  woff2 files in `public/fonts/` can stay for now (removing them is a separate
  cleanup task).

- **`--breathing-room` and nav negative margin:** The current body has
  `padding: env(safe-area-inset-top) var(--breathing-room) 0` and the nav uses
  `margin: 0 calc(-1 * var(--breathing-room))` to span edge-to-edge despite
  the body padding. With the card removed, body no longer needs side-padding.
  Remove body side-padding, let `main` handle its own horizontal padding, and
  drop the nav's negative margin hack.

- **Responsive breakpoints — use 720px, not 600px:** The V4 mockup uses
  `@media (max-width: 600px)` but the actual site uses `720px` for ALL mobile
  breakpoints. Use 720px in the implementation. There is also a
  `720px + pointer: coarse` breakpoint for small mobile font size reduction.

- **Mobile column counts — two, not one:** At the 720px breakpoint, ingredient
  lists switch to `column-count: 2` (not single column) and recipe index lists
  also switch to `column-count: 2`. The ingredient/instruction *grid* collapses
  to single column, but the ingredient *list within* uses two text columns.
  Preserve this behavior.

- **Desktop recipe list columns:** Currently three columns (`column-count: 3`)
  at desktop. The V4 mockup shows two. The spec notes this as a design
  decision to make during implementation.

- **Body line-height:** The current site has NO explicit `line-height` on
  `body` (it inherits browser default ~1.2). The new design should set
  `line-height: 1.65` on `body`.

### What success looks like

- The site looks like the V4 mockup across all pages
- Dark mode works and feels warm, not cold
- All existing interactions (cross-off, scale, search, editors) work unchanged
- Print styles still produce clean output
- Mobile layouts are correct at all breakpoints
- `rake lint` passes
- `rake test` passes (no CSS-related test failures expected, but verify)

### Fonts license note

Instrument Serif: SIL Open Font License (compatible with AGPL)
Outfit: SIL Open Font License (compatible with AGPL)
Both loaded from Google Fonts, not vendored.

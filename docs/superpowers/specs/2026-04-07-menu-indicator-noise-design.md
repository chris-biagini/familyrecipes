# Menu Availability Indicator Redesign — GH #351

## Problem

The #347 fix made availability indicators always visible (opacity floor 0.3)
so mobile users could see and tap them. This solved the accessibility problem
but made the menu page visually noisy: every recipe shows a red X/Y pill at
varying opacity, with no clear visual distinction between "fully stocked,"
"almost there," and "no chance."

Three interrelated problems:
1. **Too many numbers** — "4/8", "0/4", "2/11" next to every recipe is
   overwhelming
2. **Everything looks the same** — varying opacity of identical red pills
   doesn't create meaningful visual hierarchy
3. **Low-availability items add noise** — pills on hopeless items (0/9)
   take up visual space without providing useful information

## Design

Replace the current X/Y fraction + 10-step opacity system with a three-tier
model that uses distinct visual treatments and human-readable text.

### Three tiers

| Tier  | Condition    | Pill text | Style                          |
|-------|------------- |-----------|--------------------------------|
| Ready | 0 missing    | ✓         | Green pill, full opacity       |
| Close | 1–2 missing  | Need N    | Amber pill, full opacity       |
| Far   | 3+ missing   | Need N    | Amber pill, reduced opacity    |

**Threshold is a fixed count (1–2 missing), not percentage-based.** The
missing count is the practical signal — whether 2 out of 3 or 2 out of 12,
you need to get 2 things.

### Pill styling

Three CSS classes replace the current `.opacity-0` through `.opacity-10`
scale:

- `.availability-ready` — green text, green border, light green background.
  Color tokens: similar to `#4a8c3f` for text/border, `rgba(74,140,63,0.08)`
  for background. Exact values to be finalized during implementation against
  the existing design token palette.
- `.availability-close` — amber text, amber border, light amber background.
  Color tokens: similar to `#946b1a` for text, `rgba(200,160,32,0.25)` for
  border, `rgba(200,160,32,0.08)` for background.
- `.availability-far` — same markup and base style as `.availability-close`
  but with reduced opacity (e.g. `opacity: 0.45`). This keeps the pill
  visually present and tappable without competing with ready/close items.

**Hover behavior preserved.** `@media (hover: hover)` snaps all pill opacity
to 1 on row hover, same as today. This lets desktop users see full detail on
any item by hovering.

**CVD accessibility.** The text itself carries all meaning — "✓", "Need 1",
"Need 5" are unambiguous without color. Color is supplementary, not the
sole differentiator.

### Tap behavior (detail drill-down)

The pill itself is the tap target. Tapping expands an inline breakdown below
the row — same content as the current `<details>` expand, but without the
disclosure triangle.

| Tier  | Expand content                                      |
|-------|-----------------------------------------------------|
| Ready | "Have" list (full ingredient list)                  |
| Close | "Have" list + "Missing" list                        |
| Far   | "Have" list + "Missing" list                        |

The current `<details>`/`<summary>` HTML pattern is retained — the summary
is styled as the pill with the disclosure marker hidden
(`summary::marker { display: none }`). This gives native expand/collapse
without additional JavaScript. The existing morph-preservation logic in
`menu_controller.js` already handles `<details>` elements.

### Scope

- **Recipes and Quick Bites use the same system.** No special treatment for
  QBs — consistency wins over marginal simplification.
- **Single-ingredient items** get the same pill treatment (typically "✓" or
  "Need 1").

### What's removed

- X/Y fraction display (replaced by missing count text)
- `.opacity-0` through `.opacity-10` CSS classes
- `.availability-pill` class (replaced by tier-specific classes)
- Disclosure triangle marker (hidden via CSS, `<details>`/`<summary>` retained)
- The opacity calculation formula in the partial
  (`[(fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round, 3].max`)

### What's preserved

- Inline expand with "Have" / "Missing" breakdown
- `@media (hover: hover)` opacity snap to 1 on row hover
- `menu_controller.js` detail-preservation across Turbo morphs (adapted for
  new expand mechanism)
- Print styles hiding indicators

## Files affected

- `app/views/menu/_recipe_selector.html.erb` — pill rendering, expand markup
- `app/assets/stylesheets/menu.css` — tier classes, remove opacity scale
- `app/javascript/controllers/menu_controller.js` — detail preservation
  across morphs (existing logic, minor selector updates if needed)
- `test/` — controller and integration tests for new pill rendering

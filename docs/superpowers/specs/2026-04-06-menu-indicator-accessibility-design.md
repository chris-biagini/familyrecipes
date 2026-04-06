# Menu Indicator Accessibility — Design Spec

**Issue:** GH #347 — On mobile, can't access ingredients on menu page when
indicator is hidden

**Date:** 2026-04-06

## Problem

Menu items show availability indicators (pills like "3/5") whose opacity is
proportional to ingredient availability. Below 50% availability the indicator
is invisible (`opacity: 0`). On desktop, hovering the row snaps the indicator
to full opacity. On mobile (no hover), invisible indicators are unfindable.

Secondary issue: single-ingredient items use a filled/empty circle instead of
the "have/total" pill. The circle's meaning is easy to forget, especially for
quick bites (which are just grocery bundles, not recipes).

## Changes

### 1. Opacity floor at 0.25

The Ruby formula in `_recipe_selector.html.erb` that computes `opacity_step`
currently yields 0–10. Clamp the minimum to 3 (`opacity: 0.3`, the nearest
step above 0.25 on the existing 0.1-increment scale). This applies universally
— desktop and mobile.

**Current formula:**
```ruby
opacity_step = (fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round
```

**New formula:**
```ruby
opacity_step = [(fraction <= 0.5 ? 0 : (fraction - 0.5) * 20).round, 3].max
```

The `@media (hover: hover)` rule that snaps to full opacity on row hover
stays as-is — it's still useful for the gradient range above the floor. The
`.opacity-0` through `.opacity-2` CSS classes stay in case anything else uses
them.

### 2. Uniform pill indicators — no more circles

Remove the single-ingredient circle special case entirely. All items (recipes
and quick bites) render a "have/total" pill. When `total == 1`, the pill is a
static `<span>` (not `<details>`) with no disclosure triangle — there's nothing
to expand.

When `total > 1`, the `<details>` collapse continues to work as before.

### 3. Remove `.availability-single` CSS

The `.availability-single` class and its styles in `menu.css` become dead code.
Remove them. The `.on-hand` / `.not-on-hand` modifier classes also go away.

## Files touched

- `app/views/menu/_recipe_selector.html.erb` — formula change, replace circle
  rendering with static pill for `total == 1`
- `app/assets/stylesheets/menu.css` — remove `.availability-single` block and
  `.on-hand` / `.not-on-hand` references

## Out of scope

- No JS changes, no Stimulus controller changes
- No changes to the hover-reveal media query
- No changes to the collapse-body ingredient breakdown

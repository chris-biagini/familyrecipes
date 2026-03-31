# Cookbook Index — Recipe Page Redesign

**Date:** 2026-03-31
**Status:** Draft
**Goal:** Give the Recipe page (homepage) a distinct identity as a browsable
cookbook index with tag filtering and visible descriptions, differentiating it
from the Menu page's interactive meal-planning role.

## Problem

The Recipe page is a flat list of recipe title links grouped by category — the
same basic structure as the Menu page, minus checkboxes and availability info.
It doesn't justify its own page. Meanwhile, recipe descriptions and tags exist
in the data model but are invisible (description is a hover tooltip; tags only
appear in the dinner picker and tag editor).

## Design

### Page Structure

The existing `HomepageController#show` page keeps its header (kitchen title,
subtitle, admin actions) and gains a richer recipe listing area:

1. **Sticky tag filter bar** — all tags used across the kitchen's recipes,
   rendered as pill buttons, sorted alphabetically. Tags with zero recipes
   excluded.
2. **Table of contents** — category jump links (same as today). TOC entries
   for categories with no filter matches dim when a filter is active.
3. **Category sections** — heading with "↑ top" anchor link, plus a 2-column
   CSS grid of recipe cards. Responsive: 2 columns desktop (≥600px),
   1 column mobile. Mobile tag bar scrolls horizontally.
4. **Admin actions** — Add Recipe, Edit Categories, Edit Tags, Import/Export
   stay in the page header, unchanged.

### Recipe Cards

Each recipe renders as a card within its category grid:

- **Red left border** when the recipe matches the active tag filter. When
  no filter is active, all cards show the red left border.
- **Title** — serif font, links to the recipe detail page.
- **Description** (optional) — body font, muted color. Omitted entirely when
  the recipe has no description; the card stays compact.
- **Tag pills** — small, muted, info-only (not clickable). Flat background
  (`#f0ebe4`), muted text (`#706960`). Visually distinct from the interactive
  filter bar pills.

### Tag Filtering

- **Activation:** Click an inactive filter-bar pill to activate it. Active
  pills get a thick border and red background. Click again to deactivate.
- **Multi-tag:** AND semantics — recipe must have *all* active tags to match.
- **Visual treatment when filtering:**
  - Matching recipes: full opacity, red left border.
  - Non-matching recipes: dimmed (reduced opacity), no left border. Still
    visible and clickable.
  - Empty categories: entire section dims, shows "No recipes match the
    current filter" message.
  - TOC links: dim for empty categories.
- **Client-side only.** No URL state, no persistence, resets on page load.

### Tag Pill Styles

Two distinct visual treatments to separate interactive from informational:

| Location | Background | Text | Border | Cursor |
|----------|-----------|------|--------|--------|
| Filter bar (inactive) | `--tag-bg` (`#e8e3db`) | `--tag-text` (`#4a4540`) | none | pointer |
| Filter bar (active) | `--red` (`#b33a3a`) | white | thick (2px solid) | pointer |
| Recipe card | `#f0ebe4` | `#706960` | none | default |

## Backend

**No new models or tables.** Uses existing `Tag`/`RecipeTag` and
`Recipe#description`.

**Controller:** `HomepageController#show` adds `recipes: :tags` to the
eager-load chain. Collects unique tags from loaded recipes for the filter bar.

**No new endpoints.** Filtering is entirely client-side via a Stimulus
controller.

## View Changes

- `_recipe_listings.html.erb` partial replaced with the new card layout.
- Each recipe card carries `data-recipe-filter-tags-value` with a
  comma-separated tag list for client-side filtering.
- Tag filter bar rendered from collected unique tags.
- CSS goes in `base.css` alongside existing `.toc_nav` and `section` rules.

## Stimulus Controller

**`recipe_filter_controller`** — mounted on the `#recipe-listings` container.

**Targets:**
- `tag` — each pill in the filter bar
- `card` — each recipe card
- `category` — each category section wrapper
- `tocLink` — each TOC entry

**State:** A `Set` of active tag names in memory.

**Actions:**
- `toggle` — on tag pill click: add/remove from active set, then `apply`.
- `apply` — iterate cards, compare tags against active set, toggle CSS
  classes.

**CSS classes:**
- `.filtered-out` on cards — reduced opacity, no left border.
- `.filtered-empty` on category sections — dims section, reveals a hidden
  "no matches" `<p>`.
- `.active` on filter bar pills — thick border + red fill.

No debouncing needed — CSS class toggling is instant.

## Responsive Behavior

| Breakpoint | Columns | Tag bar |
|-----------|---------|---------|
| ≥600px | 2 | wraps |
| <600px | 1 | horizontal scroll |

## Out of Scope

- Tag persistence in URL or session (can add later if wanted).
- Search/text filtering (separate feature).
- Changes to the Menu page.
- Changes to admin actions or editor dialogs.

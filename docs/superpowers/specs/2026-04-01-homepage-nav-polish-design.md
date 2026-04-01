# Homepage Navigation Polish

Three focused improvements to the homepage categories/tags navigation area.

## 1. Smart Tag Decoration on Homepage

The homepage currently ignores `Kitchen#decorate_tags`. Two tag render sites
need the `smart_tag_pill_attrs` helper:

**Tag filter pills** (`_recipe_listings.html.erb`, line 16–21). Currently
plain `.tag-filter-pill` buttons. When `decorate_tags` is enabled, add the
smart tag CSS classes (color variant, crossout) and emoji data attribute
alongside the existing filter-pill class. When disabled, render as today.

**Recipe card tags** (`_recipe_listings.html.erb`, line 46–48). Currently
plain `<span class="recipe-tag">`. When `decorate_tags` is enabled, render
with the same full decoration as the recipe detail page — colored pill
background and emoji prefix. When disabled, render as today.

Both sites use the existing `SmartTagHelper#smart_tag_pill_attrs` helper,
which already gates on `kitchen.decorate_tags`.

The controller (`HomepageController`) already exposes `current_kitchen` via
the authentication concern, so no new data plumbing is needed.

### CSS considerations

- Filter pills need smart tag color classes to coexist with `.tag-filter-pill`
  (which handles hover, active, cursor, and sizing). The color classes override
  only `background` and `color`. The `.active` state (red background on click)
  should still win — smart tag colors are base state only.
- Recipe card tags (`.recipe-tag`) currently have minimal styling. When
  decorated, they should render as `.tag-pill .tag-pill--tag` with the smart
  color variant, matching the recipe detail page. When undecorated, they keep
  the existing plain style.

## 2. Relocate Edit Buttons

Move "Edit Categories" and "Edit Tags" out of the header `.recipe-actions`
div. The header keeps only "Add Recipe" and (optionally) "AI Import".

New positions:
- **"Edit Categories"**: centered below the category links, inside the
  `.index-nav-categories` container (or a new wrapper around it).
- **"Edit Tags"**: centered below the tag filter pills, inside the
  `.index-nav-tags` container (or a new wrapper around it).

Buttons keep `btn-ghost` class, same `id` attributes (since the editor
dialogs reference them via `editor_open`), same icon + label text.

Only visible to members (`current_member?`), same as today.

## 3. Decorative Section Dividers

The existing `header::after` draws a short 40px red decorative line
(`background: var(--red); width: 40px; height: 1px; margin: 1.5rem auto 0`).

Add the same decorative rule after the categories section and after the tags
section, creating a visual rhythm:

```
header (heading + subtitle + action buttons)
  ── red rule ──  (existing header::after)
categories links + Edit Categories button
  ── red rule ──
tag filter pills + Edit Tags button
  ── red rule ──
recipe card grid
```

Implementation: a reusable CSS class (e.g. `.section-rule::after`) that
mirrors the `header::after` pattern. Applied to the categories and tags
section wrappers. The existing `header::after` can optionally be refactored
to use the same class, or left as-is — either way, the visual result is
identical.

## Files Changed

- `app/views/homepage/show.html.erb` — move edit buttons out of header
  actions, into the listings partial (or add wrapper markup)
- `app/views/homepage/_recipe_listings.html.erb` — add smart tag attrs to
  filter pills and card tags, add edit button markup, add section wrapper
  elements for the decorative rules
- `app/assets/stylesheets/base.css` — add `.section-rule::after` class,
  adjust `.index-nav` layout for new structure, ensure smart tag color
  classes work alongside `.tag-filter-pill`
- Tests: update homepage controller/integration tests to verify decorated
  tags render when `decorate_tags` is enabled

## 4. Tag Filter Active State

The current `.tag-filter-pill.active` uses a solid red background with
`border-color: currentColor` (white) — the white border is invisible against
the cream page background.

New active state: light red background (`--red` at ~15% opacity or a
dedicated token like `--red-light`) with a solid `var(--red)` border and
`var(--red)` text color. This inverts the emphasis — light fill, dark
border — making the selection clear without being heavy, and pairing well
with the smart tag colors nearby.

## Out of Scope

- Changing the recipe detail page tag rendering (already works correctly)
- Search overlay tag decoration (separate concern)
- Tag decoration in editor dialogs
- Mobile-specific layout changes (the centered layout already wraps)

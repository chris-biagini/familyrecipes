# Frontend Cleanup: Unify Interaction Patterns

**GitHub Issue:** #261
**Date:** 2026-03-20

## Overview

Unify collapse/expand, input fields, buttons, and error display across the app.
Six collapse implementations converge on one animated `<details>` + grid pattern.
Twelve-plus input classes collapse into `.input-base` + modifiers. Ten-plus button
classes reorganize under a consistent `.btn` modifier system. Two trivial
controllers are eliminated; error display conventions are documented.

## 1. Collapse/Expand Unification

### Canonical Pattern

```html
<div class="collapse">
  <details class="collapse-header">
    <summary>Section Title</summary>
  </details>
  <div class="collapse-body">
    <div class="collapse-inner">
      <!-- content -->
    </div>
  </div>
</div>
```

CSS: `.collapse-body` uses `grid-template-rows: 0fr` transitioning to `1fr` on
`details[open] + .collapse-body` with `--duration-normal`. Inner div has
`min-height: 0; overflow: hidden`. Use the adjacent sibling combinator (`+`)
when the `<details>` and `.collapse-body` are direct siblings. Use the general
sibling combinator (`~`) when intervening elements sit between them (e.g., the
menu availability pattern has a link between `<details>` and the ingredient
list).

**Why a sibling pattern?** Content placed inside `<details>` cannot be animated
with `grid-template-rows` — the browser toggles it instantly. Placing the
animated body as a sibling and selecting via `details[open]` is the workaround.

Arrow indicator: `summary::before` CSS triangle, rotates 90° on `[open]`.

### Migrations

**Grocery on-hand** (currently `hidden` attr via Stimulus):
- `.on-hand-divider` button becomes a `<summary>` inside `<details>`
- `.on-hand-items` wraps in `.collapse-body > .collapse-inner`
- `grocery_ui_controller` still manages localStorage persistence and
  `aria-expanded`, but collapse/expand is CSS-driven via toggling the `open`
  attribute on `<details>` instead of `hidden` on the target div
- localStorage key format (`grocery-on-hand-{slug}`) and data shape
  (`{aisle: boolean}`) stay the same — only the DOM manipulation changes
  (set/read `details.open` instead of `target.hidden`)
- `preserveOnHandStateOnRefresh()` adapts to read/write `open` attr
- Aisle-complete headers (`.aisle-complete-header`) follow the same migration

**Graphical editor accordion** (currently `accordion.js` toggling `hidden`):
- Step/category cards become `<details class="collapse-header">` +
  `.collapse-body` siblings
- Delete `accordion.js` utility entirely
- `recipe_graphical_controller` and `quickbites_graphical_controller` toggle
  the `open` attribute on `<details>` instead of calling accordion functions
- `buildToggleButton()` goes away — `<summary>` is the native click target

**Rename to canonical classes:**
- `.editor-collapse-header` → `.collapse-header`
- `.editor-collapse-body` → `.collapse-body`
- `.editor-collapse-inner` → `.collapse-inner`
- `.availability-detail` → `.collapse-header`
- `.availability-ingredients` → `.collapse-body`

**JS references to update:** `menu_controller.js` queries
`details.availability-detail` for morph state preservation (lines ~38, ~47).
Update these selectors to `details.collapse-header` and update corresponding
assertions in `test/controllers/menu_controller_test.rb`.

### Keep As-Is

- **Nav hamburger**: Already uses grid-template-rows. Has bespoke behavior
  (ResizeObserver for drawer height, icon rotation, click-outside dismiss)
  that doesn't fit the `<details>` pattern.
- **Scale panel**: Already uses grid-template-rows. Tightly coupled to scale
  state management.

## 2. Input Base Styles

### `.input-base` Class

```css
.input-base {
  font-family: var(--font-body);
  font-size: 0.85rem;
  padding: 0.3rem 0.5rem;
  border: 1px solid var(--rule-faint);
  border-radius: 3px;
  background: var(--input-bg);
  color: var(--text);
  box-sizing: border-box;
  outline: none;
}
.input-base:focus {
  outline: 2px solid var(--red);
  outline-offset: -1px;
  border-color: var(--red);
}
```

### Modifiers

| Modifier | Purpose | Key overrides |
|----------|---------|---------------|
| `.input-mono` | CodeMirror mount / plaintext editors | `font-family: var(--font-mono)`, larger padding |
| `.input-lg` | Full-width search fields | `font-size: 1rem`, `padding: 0.5rem 0.75rem` |
| `.input-sm` | Narrow numeric fields | `width: 4.5rem`, `text-align: right` |
| `.input-inline` | Fields inside tight layouts | Minimal padding tweaks |

### Normalization

- **Border-radius**: Standardize on `3px` (most common value)
- **Focus ring**: Standardize on `outline: 2px solid var(--red)` with `-1px`
  offset (replaces inconsistent `border-color`-only focus styles)
- **Background**: All use `var(--input-bg)`

### Migration Table

| Old class | New class(es) | Notes |
|-----------|---------------|-------|
| `.graphical-input` | `.input-base` | |
| `.graphical-input-title` | `.input-base .input-title` | Larger font-size + weight for title field |
| `.graphical-input--short` | `.input-base .input-short` | Narrow width variant |
| `.graphical-textarea` | `.input-base` | Add `resize: vertical`, `min-height`, `max-height` |
| `.graphical-select` | `.input-base` | Selects share the same base |
| `.settings-input` | `.input-base .input-lg` | |
| `.ingredients-search` | `.input-base .input-lg` | |
| `.usda-search-input` | `.input-base .input-lg` | |
| `.scale-input` | `.input-base .input-sm` | Keep center alignment |
| `.nf-input` | `.input-base .input-sm` | |
| `.field-narrow` | `.input-base .input-sm` | |
| `.portion-name-input` | `.input-base` | |
| `.aisle-add-input` | `.input-base .input-inline` | |
| `.aisle-input` | `.input-base .input-inline` | |
| `.field-unit-select` | `.input-base` | Selects share the same base |
| `.aisle-select` | `.input-base .input-inline` | |
| `#custom-input` | `.input-base .input-lg` | Keep explicit `font-size: 16px` (not `1rem`) for iOS zoom prevention |

**Exception**: `.editor-textarea` stays unique — it's the CodeMirror mount
with `min-height: 60vh`, no border, monospace font. Too different to share
`.input-base`.

**JS touch point:** `dom_builders.js` creates inputs programmatically via
`buildInput()` and `buildTextareaGroup()`. These factories need to inject
`.input-base` alongside any modifier classes. Currently `buildInput` takes a
single `className` parameter — update it to prepend `input-base` automatically,
so callers pass only the modifier (e.g., `"input-sm"` instead of
`"input-base input-sm"`).

## 3. Button Consolidation

### Modifier System

Base `.btn` stays as-is. Formalized modifiers:

| Modifier | Purpose | Key properties |
|----------|---------|----------------|
| `.btn-primary` | Keep | Red bg, white text |
| `.btn-danger` | Keep | Danger color, hover fills |
| `.btn-sm` | Rename from `.btn-small` | Smaller padding/font |
| `.btn-icon` | Keep | Minimal padding, icon-sized |
| `.btn-icon-round` | Circular icon buttons | `border-radius: 50%`, fixed dimensions |
| `.btn-link` | Rename from `.btn-inline-link` | `all: unset`, underline, link color |
| `.btn-ghost` | No border/bg, hover reveals | For toggle-style buttons |
| `.btn-pill` | Pill-shaped | `border-radius: 999px` |

### Migration Table

| Old class | New class(es) | Notes |
|-----------|---------------|-------|
| `.btn-small` | `.btn-sm` | Standard naming |
| `.btn-inline-link` | `.btn-link` | Shorter, clearer |
| `.edit-toggle` | `.btn-ghost` | Same visual behavior |
| `.scale-preset` | `.btn-sm` | Keep pop animation + `.active` filled state as `.scale-preset` overrides |
| `.scale-reset` | `.btn-ghost .btn-sm` | Preserve `[hidden]` layout-reservation override (visibility: hidden, display: block) to prevent layout shift |
| `.aisle-btn` | `.btn-icon-round` | Variants use contextual modifiers |
| `.aisle-btn--delete` | `.btn-icon-round` + danger hover | |
| `.aisle-btn--undo` | `.btn-icon-round` + accent hover | |
| `.aisle-btn--add` | `.btn-icon-round` (larger variant) | |
| `.filter-pill` | `.btn-pill` | Rename + unify |
| `#custom-add` | `.btn-icon-round` | Circular add on groceries |
| `.dinner-picker-spin-btn` | `.btn .btn-primary` | Standard primary action |
| `.result-accept-btn` | `.btn .btn-primary` | Intentional visual change: green → red (placeholder styling) |
| `.result-retry-btn` | `.btn` | Standard secondary |

### CSS Organization

Group all button styles together in `style.css`:
base → color modifiers → size modifiers → shape modifiers → state modifiers.

## 4. Controller Elimination

### Delete: `export_controller.js`

The export link has `data-turbo="false"` (file download), so `data-turbo-confirm`
will not fire. Replace with `onclick="return confirm('...')"` on the link in
`homepage/show.html.erb`. Remove registration from `application.js`.

### Delete: `accordion.js`

Covered by Section 1's collapse migration. Step/category cards use native
`<details>` elements. Remove import from `application.js`.

### Keep: `reveal_controller.js`

18 lines, used in 2 places (USDA key, Anthropic key in settings). No
declarative HTML/Turbo equivalent for toggling input type between `password`
and `text`. Earns its existence.

### Keep: `toast_controller.js`

Architecturally necessary for server-initiated notifications via Turbo
Streams. No alternative.

## 5. Error Display Documentation

No code changes. Document the convention with short comment blocks:

- **Inline errors** (`editor_utils.showErrors`): For dialog/form validation.
  Contextual, displayed next to the form, cleared on re-open.
- **Toast notifications** (`notify.show`): For page-level mutations. Ephemeral,
  auto-dismiss after 5s, non-blocking.

Add a brief header note in `editor_utils.js` and `notify.js` explaining when
to use which pattern.

## Acceptance Criteria

- [ ] All collapse/expand uses animated `<details>` + grid-template-rows
      (grocery on-hand, graphical editor accordion)
- [ ] `.editor-collapse-*` and `.availability-*` renamed to `.collapse-*`
- [ ] `accordion.js` deleted
- [ ] `.input-base` + modifiers extracted; old input classes replaced
- [ ] Border-radius normalized to 3px, focus ring standardized
- [ ] Button modifiers formalized (`.btn-sm`, `.btn-icon-round`, `.btn-link`,
      `.btn-ghost`, `.btn-pill`)
- [ ] One-off button classes migrated to modifier combinations
- [ ] Dinner picker buttons use standard `.btn` / `.btn-primary`
- [ ] `export_controller.js` deleted, replaced with `onclick` confirm
- [ ] Error display conventions documented in `editor_utils.js` and `notify.js`
- [ ] All existing tests pass
- [ ] No visual regressions (manually verify: recipe, menu, groceries,
      ingredients, settings, dinner picker)

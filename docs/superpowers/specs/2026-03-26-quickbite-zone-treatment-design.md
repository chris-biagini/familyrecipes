# QuickBite Zone Treatment on Menu Page

## Problem

QuickBites on the menu page are nearly indistinguishable from recipes — same
row structure, same checkbox/label layout, differing only by slightly smaller
font. Categories with only QuickBites show a distracting double-line (the
category `<h2>` border-bottom stacked with `.quick-bites-list` border-top).
There is no visible affordance for editing individual QuickBites — the only
path is the global "Edit QuickBites" button in the page header.

## Design

### Visual Treatment — Indented Zone with Label

QuickBites within each category are wrapped in a distinct zone:

- **Left border**: 2px solid `--rule-faint` with `0.75rem` left padding,
  creating a visual indent that sets the zone apart from the recipe list above.
- **Sub-header row**: A small "QUICK BITES" label (uppercase, `--text-light`,
  0.65rem, 600 weight) left-aligned, with an edit button right-aligned.
- **Items**: Rendered at 0.9em font size, same checkbox + availability
  structure as recipes, but without the `→` recipe link.
- **Spacing**: `0.5rem` top margin separates the zone from recipes above.
  No border-top — the left-border + indent provides sufficient separation.
- **QB-only categories**: The zone sits directly under the `<h2>`, eliminating
  the double-line problem. The category header's border-bottom is the only
  horizontal rule.

### Edit Affordance — Zone Button Opens Focused Editor

Each zone's sub-header includes a small edit button (pencil icon + "edit"
text, styled like `--text-light`, hover `--red`). Clicking it opens the
existing Quick Bites editor dialog with a **category focus**:

- **Graphical mode**: All category `<details>` cards start collapsed; the
  target category auto-expands. The graphical controller iterates its
  `<details>` cards, finds the one whose title input matches the category
  name, and sets `open` on it.
- **Plaintext mode**: On editor mount, `foldAll` (from `@codemirror/language`)
  is called first to collapse all sections. Then the document is scanned for
  the line matching `## <category>` to get its line number. The cursor is
  positioned on that line and `unfoldCode` (also from `@codemirror/language`)
  is dispatched as a command to unfold just that section.
- The global "Edit QuickBites" header button remains and opens the editor
  without category focus (all sections expanded, as today).

**Category focus data flow:**

1. Zone edit buttons carry `data-category="<%= category.name %>"`.
2. `editor_controller` changes its `openSelectorValue` to match both the
   header button and zone buttons (e.g., `.qb-edit-trigger` class on all).
3. In the click handler, `editor_controller` reads
   `event.target.closest('[data-category]')?.dataset.category` and stashes
   it as `this.focusCategory`.
4. `editor:content-loaded` dispatch includes `{ category: this.focusCategory }`
   in its detail. `this.focusCategory` is cleared after dispatch.
5. `dual_mode_editor_controller.handleContentLoaded()` reads
   `event.detail.category` and forwards it to the active child controller
   (graphical or plaintext) via a `focusCategory(name)` method on each.
6. The header button has no `data-category`, so `focusCategory` is null —
   all sections stay expanded (no change from today).

### Implementation Details

**CSS changes** (`menu.css`):
- New `.qb-zone` class: left border, padding, top margin.
- New `.qb-zone-header`: flex row for label + edit button.
- New `.qb-zone-label`: uppercase micro-label.
- New `.qb-zone-edit`: ghost-style edit button.
- Remove `.quick-bites-list` border-top (replaced by zone treatment).
- Keep `.quick-bite-item` font-size rule (0.9em).
- Print CSS: hide `.qb-zone-edit` (edit buttons not relevant in print).

**Partial changes** (`_recipe_selector.html.erb`):
- Wrap the QB `<ul>` in a `<div class="qb-zone">` containing the sub-header
  and the item list.
- Edit button includes `data-category="<%= category.name %>"` and the shared
  `.qb-edit-trigger` class.
- Pass `editable: current_member?` as a local to the partial. Conditionally
  render the edit button only when `editable` is true.

**JS changes**:
- `editor_controller`: Change `openSelectorValue` for the QB editor to
  `.qb-edit-trigger`. In the click handler, read `data-category` from the
  clicked element and stash as `this.focusCategory`. Include it in the
  `editor:content-loaded` detail. Clear after dispatch.
- `dual_mode_editor_controller`: Read `event.detail.category` in
  `handleContentLoaded` and forward to the active child via
  `focusCategory(name)`.
- `quickbites_graphical_controller`: Add `focusCategory(name)` — iterate
  `<details>` cards, collapse all, expand the one whose title matches.
- `plaintext_editor_controller`: Add `focusCategory(name)` — call
  `foldAll(view)`, scan for the `## <name>` line, position cursor there,
  dispatch `unfoldCode(view)`. Both `foldAll` and `unfoldCode` are commands
  from `@codemirror/language`.

**No new files**: All changes are to existing CSS, ERB, and JS files.

**No model/controller changes**: This is purely a view-layer concern.

## Testing

- **Visual**: Verify zone appearance in mixed categories (recipes + QBs) and
  QB-only categories. Confirm no double-line.
- **Edit button**: Click zone edit → editor opens with correct category
  focused in both graphical and plaintext modes.
- **Header button**: Click global "Edit QuickBites" → editor opens with all
  sections expanded (no regression).
- **Non-members**: Zone renders without edit button; no JS errors.
- **Availability pills**: Confirm availability display still works within the
  zone wrapper.

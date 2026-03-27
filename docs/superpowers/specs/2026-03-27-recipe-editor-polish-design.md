# Recipe Editor Visual Polish

CSS and minor JS improvements to the graphical recipe editor. No structural
changes to the data model or editor lifecycle — purely visual refinements.

## Changes

### 1. New Category Input — Below, Not Replacing

**Current:** Selecting "New category..." hides the `<select>` and shows an
`<input>` in the same position. On narrow viewports the input gets clipped.

**Proposed:** The `<select>` stays visible (locked to "New category..."). A
new row appears below it with the text input and a "cancel" link. Pressing
Escape or clicking cancel hides the row and resets the select to "None".

**Touch points:**
- `recipe_graphical_controller.js`: `categoryChanged()`,
  `showNewCategoryInput()`, `categoryInputKeydown()` — show/hide the new row
  instead of swapping visibility on the select.
- `_editor_frame.html.erb` or `_graphical_editor.html.erb`: add the below-row
  container with `hidden` attribute.
- `editor.css`: style `.graphical-new-category-row` as flex row with gap.

### 2. Compact Front Matter Fields

**Current:** Serves, Makes, and Category all have `flex: 1` with
`min-width: 120px`, so they stretch equally. Serves/Makes fields are mostly
whitespace.

**Proposed:** Serves and Makes get `flex: 0 0 auto; width: 5.5rem`. Category
gets `flex: 1; min-width: 10rem` to fill remaining space. The row uses
`align-items: flex-end` so baselines align when the new-category row is
visible.

**Touch points:**
- `editor.css`: update `.graphical-front-matter-row` alignment; add
  width-constrained modifier classes for Serves/Makes fields.

### 3. Tag Editor Add Button

**Current:** Tags are added only by pressing Enter in the input field. No
visible affordance.

**Proposed:** A round `btn-icon-round` "+" button appears to the right of the
tag input. Clicking it calls the same `addTag()` logic as pressing Enter. The
input and button are wrapped in a flex row.

**Touch points:**
- `tag_input_controller.js`: `connect()` builds the "+" button; wire a click
  handler that calls `commitTag()`.
- `editor.css`: `.tag-input-row` flex container.

### 4. Subtle Ingredient Count in Step Header

**Current:** `.graphical-ingredient-summary` uses `opacity: 0.4` and
`font-size: 0.8em` — same visual weight as the step title.

**Proposed:** Shrink to `font-size: 0.7rem`, use `color: var(--text-light)`,
drop the opacity rule. The count reads as secondary metadata, not a peer of
the title.

**Touch points:**
- `editor.css`: update `.graphical-ingredient-summary` (or rename to
  `.graphical-ingredient-count`).

### 5. Better Buttons — Round Icons and Pills

**Current:** All editor buttons (move up/down, remove, add) use
`.graphical-btn` — a small rectangle with text characters (↑ ↓ × +). They're
tiny and visually inconsistent with the `btn-icon-round` buttons used in the
aisle and category editors.

**Proposed:** Two button styles:

- **Action buttons** (up, down, remove): use `btn-icon-round` with SVG icons
  from `buildIcon()` in `icons.js`. Existing icons: `chevron` (flip with
  `.aisle-icon--flipped` for down), `delete` (× shape). Same 1.75rem circles
  used in aisle/category editors. Danger variant for remove.
- **Add buttons** (+ Add ingredient, + Add Step): use `btn-pill` style —
  rounded capsule with text label. Consistent with pill buttons used elsewhere
  in the app.
- **Tag add button**: `btn-icon-round` with a new `plus` icon added to the
  icon registry in `icons.js`.

**Touch points:**
- `icons.js`: add `plus` icon to the registry.
- `recipe_graphical_controller.js`: `buildIngredientRow()` — replace
  `buildButton()` calls with `btn-icon-round` elements using `buildIcon()`.
- `graphical_editor_utils.js`: `buildCardActions()` — same replacement for
  step action buttons.
- `dom_builders.js`: add a `buildIconButton()` helper that creates a
  `btn-icon-round` with an icon inside.
- `editor.css`: remove `.graphical-btn` if no longer used; add
  `.graphical-add-btn` as a pill variant if `btn-pill` doesn't cover it.

### 6. Ingredient Row Cards with Proportional Widths

**Current:** Three inputs (`name`, `qty`, `prep_note`) all have `flex: 1` —
identical widths. No visual grouping.

**Proposed:**
- Each row gets a card treatment: `background: var(--surface-alt)`,
  `border: 1px solid var(--rule-faint)`, `border-radius: 6px`,
  `padding: 6px 8px`.
- Name input: `flex: 3` (widest — it's the primary field).
- Qty input: `flex: 1; min-width: 4.5rem; max-width: 6rem; text-align: center`.
- Prep note input: `flex: 2; font-style: italic; border-color: var(--rule-faint)`
  — visually lighter since it's optional.

**Touch points:**
- `recipe_graphical_controller.js`: `buildIngredientRow()` — wrap fields in a
  card container div, apply proportional classes.
- `editor.css`: `.graphical-ingredient-card` card styles;
  `.graphical-ing-name`, `.graphical-ing-qty`, `.graphical-ing-prep` with
  proportional flex and visual treatment.

## Out of Scope

- Editor dialog sizing and layout (header, footer, body scroll)
- Plaintext/CodeMirror editor
- Mobile-specific responsive changes (beyond ensuring nothing breaks)
- Step card expand/collapse behavior
- Cross-reference step cards
- Description/Title/Footer/Instructions field styling

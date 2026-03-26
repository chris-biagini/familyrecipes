# Ingredient Editor Redesign

**Date:** 2026-03-26
**Status:** Draft

## Problem

The ingredient editor presents density, portions, and recipe units as three
separate concepts. In reality they all answer one question: "when a recipe says
'2 X of this ingredient', how many grams is that?" The current section names
and labels leak implementation detail (`~unitless`, "via density") that is
inscrutable to anyone unfamiliar with the data model.

## Goals

1. Reorganize the editor so related conversion concepts feel unified.
2. Replace developer jargon with recipe-language terminology.
3. Promote grocery-relevant fields (aisle, aliases) to top-level visibility.
4. Keep the data model unchanged — this is a UI/language refactor only.

## Design

### Layout

The editor dialog gets a new section order:

1. **Grocery Aisle** — always visible (not collapsible). Rendered as plain
   `<div>` with a styled label — no `<details>/<summary>` wrapper. Select +
   "Omit from grocery list" checkbox. Behavior unchanged.
2. **Aliases** — always visible (not collapsible). Same plain `<div>` with
   label. Chip list + add input. Behavior unchanged.
3. **Divider**
4. **Nutrition & Conversions** — single collapsible meta-section containing:
   - **USDA Import** — search bar + results (only when kitchen has API key)
   - **Nutrition Facts** — compact inline summary (calories, fat, carbs,
     protein, basis grams) with an "Edit all nutrients" link that expands the
     full nutrient form
   - **Volume Conversions** — replaces "Density". Same single-row input
     (`1 [cup] = [227] g`), plus derived conversions shown below (tbsp, tsp,
     fl oz computed from the density ratio). Collapsible "Other USDA
     densities" detail underneath when candidates exist.
   - **Unit Weights** — replaces "Portions". Same editable rows
     (`[name] = [grams] g`) with add/remove. `~unitless` displayed as "each"
     in all user-facing contexts.
   - **Recipe Check** — replaces "Recipe Units". Same diagnostic listing every
     unit found across recipes for this ingredient, with human-readable
     resolution labels. Unresolved units highlighted with actionable prompt.

### Collapsed state

When "Nutrition & Conversions" is collapsed, the summary line shows:

- Compact nutrition summary: e.g. "100 cal / 14 g"
- Resolution status icon: checkmark SVG (all resolved) or warning SVG
  (unresolved units exist)

Icons are clean monochrome SVGs registered in `IconHelper`.

The summary line is rendered server-side in ERB from the entry data and
`needed_units`. It does not update live as the user edits — the user must
open the section to edit, and closing it re-renders via Turbo on next save.
This avoids complex client-side state tracking for the collapsed summary.

### Section key changes

The `data-section-key` attribute drives `restoreSectionStates` persistence.
New key map:

- `grocery-aisle` and `aliases` keys are removed (sections are no longer
  collapsible)
- `nutrition-conversions` — the new meta-section `<details>` element
- Inner sub-sections (USDA, Nutrition Facts, Volume, Unit Weights, Recipe
  Check) are **not** individually collapsible — they are always-visible
  content within the meta-section. The "Edit all nutrients" expand is
  managed by Stimulus, not `<details>`, and does not need a section key.

### Terminology

| Current | New |
|---------|-----|
| Density | Volume Conversions |
| Portions | Unit Weights |
| Recipe Units | Recipe Check |
| `(bare count)` (nil unit display) | each |
| `~unitless` (portion name in form) | each (already translated in `_portion_row`) |
| `via ~unitless` (resolution method) | unit weight (N g) |
| via density | volume conversion |
| via [portion name] | unit weight (N g) |
| weight | standard weight |
| no density | no volume conversion |
| no portion | no matching unit — add one above? |

Help text changes:

- Volume Conversions: "When a recipe measures this ingredient by volume (cups,
  tablespoons, etc.), how much does it weigh?"
- Unit Weights: "When a recipe calls for this ingredient by name or count —
  like '2 sticks' or '3 eggs' — how much does one weigh?"
- Recipe Check: "How your recipes use this ingredient, and whether each usage
  can be converted to grams."

### Derived volume conversions

When a density is defined, the Volume Conversions section shows computed
equivalents for all standard volume units below the input row. These are
display-only — computed client-side from the density inputs using the
`UnitResolver::VOLUME_TO_ML` conversion factors. Formula:
`density_grams * (target_unit_ml / selected_unit_ml)`.

Example: if 1 cup = 227 g, show "1 tbsp ≈ 14.2 g", "1 tsp ≈ 4.7 g",
"1 fl oz ≈ 28.4 g".

**Client-side behavior:**
- Derived values recompute live as the user edits density grams, volume, or
  unit select.
- When density inputs are empty or incomplete (missing grams or unit), the
  derived list is hidden.
- When the user picks a density candidate radio button, derived values update
  immediately.
- Exclude the currently selected unit from the derived list (no "1 cup =
  227 g" repeated).

### Compact nutrition summary

The full FDA-label-style nutrient form (11 fields) is behind an "Edit all
nutrients" link. The default view shows an inline summary of the four key
values: calories, fat, carbs, protein, plus the basis grams. This keeps the
expanded meta-section scannable.

**Expand/collapse mechanics:**
- Implemented as a Stimulus-managed visibility toggle (not `<details>`), since
  the compact summary and the full form are two alternate views of the same
  data.
- Default state: compact (summary only). "Edit all nutrients →" link expands
  the full form and hides the summary. A "Done" or collapse link in the full
  form returns to compact view.
- The compact summary updates to reflect the current form values (read from
  the input fields, not just the server-rendered values) so unsaved edits are
  visible in the summary.
- After USDA import populates nutrient fields, stay in compact view — the
  summary shows the imported values and the user can expand to review details
  if desired.

### USDA import behavior change

When the user clicks a USDA search result, only the most recently clicked
result gets the "already imported" dim treatment. Previously, all
previously-imported results stayed dimmed. Since clicking a new result
replaces the form data, dimming old selections is misleading.

### Recipe Check resolution labels

Label rewriting happens in a **view helper** (not in `IngredientRowBuilder`).
The service continues to return its current method strings unchanged — this
preserves the "Not Resolvable" filter pill and avoids service-layer changes.

A new helper method (e.g. `format_resolution_method`) in `IngredientsHelper`
maps method strings to display labels:

- `"via density"` → "volume conversion"
- `"via [name]"` → "unit weight (N g)" — the helper looks up `entry.portions[name]`
  to get the gram weight. This requires passing the `entry` to the helper.
  When `name` is `~unitless`, the lookup works but the display reads
  "unit weight (N g)" — the `~unitless` key is never shown.
- `"weight"` → "standard weight"
- `"no density"` → "no volume conversion"
- `"no portion"` → "no matching unit — add one above?"
- `"no ~unitless portion"` → "no 'each' weight — add one above?"
- `"no nutrition data"` → unchanged (already human-readable)

For nil units (bare counts), the display name changes from `(bare count)` to
`each`.

Unresolved units get a highlighted background and the actionable prompt.

## Data model

No changes. The `IngredientCatalog` schema stays as-is:

- `density_grams`, `density_volume`, `density_unit` → Volume Conversions
- `portions` JSON hash (with `~unitless` key) → Unit Weights
- All nutrient columns → Nutrition Facts

The `~unitless` ↔ "each" translation remains in the view/controller layer.

## Scope

**In scope:**

- Editor dialog layout restructuring (section order, collapsibility)
- Terminology and help text changes throughout the editor
- Derived volume conversion display
- Compact nutrition summary with expand link
- Collapsed meta-section summary line with status icons
- USDA import dim behavior fix (only last-clicked result)
- New SVG icons for resolved/unresolved status

**Out of scope:**

- Unit conversion preference system (future)
- Convert-on-import (future)
- Ingredients list page changes
- "Not Resolvable" filter pill behavior
- Data model or migration changes
- Parser or service layer changes

## Files likely affected

- `app/views/ingredients/_editor_form.html.erb` — main restructuring
- `app/views/ingredients/_portion_row.html.erb` — may rename partial
- `app/assets/stylesheets/nutrition.css` — section styling updates
- `app/javascript/controllers/nutrition_editor_controller.js` — section
  collapse logic, compact nutrition toggle, USDA dim fix, derived volume
  computation
- `app/helpers/icon_helper.rb` — new checkmark/warning SVG icons
- `app/models/ingredient_catalog.rb` — reference only (existing `each` ↔
  `~unitless` translation in `normalize_portions`), no changes expected
- `app/helpers/ingredients_helper.rb` — new `format_resolution_method` helper
- `test/helpers/ingredients_helper_test.rb` — label formatting assertions
- Controller/integration tests that assert on editor HTML (section headings,
  labels)
- Playwright tests for ingredient editor interactions

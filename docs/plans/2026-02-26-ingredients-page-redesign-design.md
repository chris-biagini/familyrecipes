# Ingredients Page Redesign

## Summary

Replace the current flat alphabetical ingredient list with a compact, filterable table that shows data completeness at a glance. Replace the textarea-based nutrition editor with a structured form. Add Turbo Frames for lazy-loaded detail panels, Turbo Streams for in-place updates after save, and a "Save & Next" flow for efficient batch entry.

## Goals

- Show ingredient data completeness (nutrition, density, aisle) at a glance in a scannable table
- Replace the textarea editor with structured form fields that are mobile-friendly and keyboard-navigable
- Support fast batch entry via "Save & Next" without closing the dialog
- Lazy-load detail panels via Turbo Frames to keep initial page load lightweight
- Use Turbo Streams to update the table in place after edits (no full reload)
- Responsive design that works well on mobile without zoom-on-focus issues
- Make the density system intuitive through serving size integration and plain-language explanations

## Non-Goals

- Public access (page stays members-only)
- Changing the underlying `IngredientCatalog` model or migrations
- Modifying `NutritionLabelParser` (CLI path stays intact)
- Inline editing directly in the table rows (edit always opens a dialog)

## Page Layout

### Summary Bar

A status line at the top: "101 ingredients — 87 complete, 9 missing nutrition, 5 missing density". Each count is a clickable filter shortcut that activates the corresponding filter pill.

### Search & Filter Toolbar

A text input for instant client-side name filtering. Below it, pill-shaped toggle buttons:

- **All** — shows everything
- **Needs Attention** — ingredients missing nutrition OR density
- **Complete** — ingredients with both nutrition and density populated

Filter pills show count badges that update as the search narrows results. A "Showing 14 of 101 ingredients" label sits below the table.

All filtering is client-side — no server round-trips. Status data lives in `data-*` attributes on each table row.

### Table Columns

| Column    | Desktop                          | Mobile (<640px)                    |
|-----------|----------------------------------|------------------------------------|
| Name      | Full name, clickable to expand   | Same                               |
| Nutrition | Check/cross icon                 | Combined "Status" column           |
| Density   | Check/cross/dash icon            | Merged into Status                 |
| Aisle     | Text or dash                     | Hidden, shown in expand panel      |
| Recipes   | Count                            | Hidden, shown in expand panel      |

On mobile, nutrition and density collapse into a single "Status" column showing stacked indicator icons (compact dot cluster).

### Row Expand Panel

Clicking a row expands an inline detail panel below it (Turbo Frame, lazy-loaded on first expand). Only one row expanded at a time. Contents:

- **Nutrition summary**: "110 cal · 0g fat · 23g carbs · 3g protein" (key macros)
- **Density explanation**: "1 cup = 120g" in plain English, or "No density data — volume measurements can't be converted"
- **Portions list** if any: "1 stick = 113g", "1 each = 50g"
- **Recipe links**: inline comma-separated list linking to each recipe
- **Source badge**: built-in / custom / missing
- **Action buttons**: `[Edit]` and `[Reset to built-in]` (only if custom entry exists)

## Structured Nutrition Editor

Replaces the textarea with a dialog containing structured form fields organized in collapsible sections.

### Dialog Header

"Edit Cardamom" — ingredient name prominently displayed.

### Section 1: Nutrition Facts (always open)

```
Serving size     [ 30 ] g
  measured as    [  1 ] [ tsp ▾ ]     ← optional

Calories         [ 110 ]
Total Fat        [   0 ] g
  Saturated Fat  [   0 ] g
  Trans Fat      [   0 ] g
Cholesterol      [   0 ] mg
Sodium           [   0 ] mg
Total Carbs      [  23 ] g
  Dietary Fiber  [   3 ] g
  Total Sugars   [   0 ] g
    Added Sugars [   0 ] g
Protein          [   3 ] g
```

All inputs are `type="number"` with `inputmode="decimal"` and `step="any"`. Font size >= 16px on all inputs to prevent iOS zoom-on-focus. Tab order flows top-to-bottom. Sub-nutrient indentation is CSS-based, mirroring the FDA label hierarchy.

**Serving size with density derivation**: The "measured as" row captures the volume portion of a serving size (e.g., "1 tsp" from a label that reads "Serving size: 1 tsp (4g)"). When filled in, the Density section auto-populates with the derived relationship and becomes read-only with a note: "Derived from serving size". Clearing the serving volume fields unlocks the density section for manual entry.

### Section 2: Density (collapsible)

Opens automatically if data exists or if nutrition is populated.

Header explanation: "Density lets the app convert volume measurements (cups, tablespoons) to grams for nutrition calculation."

```
[ 1 ] [ cup ▾ ] = [ 120 ] g
```

Unit dropdown: cup, tbsp, tsp, ml, l.

When no density is set and no recipes use volume measurements for this ingredient, shows a muted note: "None of your recipes use volume measurements for this ingredient." Still editable.

When density is derived from the serving size, fields are read-only with a note: "Derived from serving size above."

### Section 3: Portions (collapsible)

Opens automatically if data exists.

Header explanation: "Portions define named units like 'stick' or 'slice' so the app knows their gram weight."

```
[ stick     ] = [ 113 ] g   [✕]
[ each      ] = [  50 ] g   [✕]
[+ Add portion]
```

Each row is a name/gram-weight pair with a delete button. `[+ Add portion]` appends a blank row. "each" is the UI label for the `~unitless` key in the data model — tooltip reads: "Weight of one unit when listed by count alone (e.g., 'Eggs, 3')". The controller maps "each" ↔ `~unitless` at the display boundary.

### Section 4: Aisle (always visible, compact)

The existing aisle selector relocated from the footer into the dialog body. Same dropdown: existing aisles, "(none)", "Omit from Grocery List", "New aisle..." with text input.

### Dialog Footer

```
[Cancel]     [Save]  [Save & Next ▸]
```

"Save & Next" saves, then loads the next ingredient needing attention (alphabetical order matching current filter). Below the buttons: "Next: Cilantro" label. If nothing needs attention, Save & Next behaves as Save and closes.

Sticky footer on mobile so buttons are always reachable without scrolling.

### Validation

Inline, per-field:

- Serving size / basis_grams: must be > 0
- Nutrient values: 0 to 10,000
- Density grams: must be > 0 if volume is set (and vice versa)
- Portion names: non-empty, no duplicates
- Portion grams: must be > 0

Errors appear adjacent to the offending field, not in a top banner.

## Mobile Responsiveness

**Table**: Collapses to Name + Status columns below 640px. Aisle and recipe count move to expand panel.

**Touch targets**: All clickable rows have min-height 44px. Filter pills are large tap targets.

**Numeric inputs**: All form inputs use `font-size: 1rem` (>= 16px) to prevent iOS Safari zoom-on-focus. `inputmode="decimal"` brings up the numeric keyboard.

**Dialog**: Full-screen on mobile (`width: 100%; height: 100%; max-height: 100dvh`). Collapsible sections stack naturally. Sticky footer. Desktop: centered modal, max-width ~500px.

**Search input**: `position: sticky` above the table, always visible while scrolling. Filter pills wrap on narrow screens.

**Expand panel**: Full-width. Recipe links wrap. Edit button is full-width on mobile.

## Keyboard Navigation

- Tab flows through all numeric fields top-to-bottom in the editor
- Escape closes the dialog (with dirty-check confirmation if modified)
- After "Save & Next", focus lands on the serving size field of the next ingredient
- Search input: typing filters instantly, no submit needed

## Hotwire Architecture

### Turbo Frames

**Expand panels**: Each row's detail panel is a `<turbo-frame>` with `loading="lazy"`:

```erb
<turbo-frame id="ingredient-detail-butter" src="/ingredients/Butter" loading="lazy">
```

First expand triggers the fetch; subsequent toggles show/hide the cached frame.

**Editor form**: The dialog content is a `<turbo-frame>` loaded from `/ingredients/:name/edit`. Server renders the pre-populated form — no JSON in data attributes.

### Turbo Streams (after save)

The save response returns Turbo Streams that:

1. Replace the table row (updated status icons, aisle text)
2. Replace the expand panel with fresh detail content
3. Update the summary bar counts
4. For "Save & Next": replace the editor form frame with the next ingredient's form

### Stimulus Controllers

**`ingredient_table_controller`** (new): Manages the table page.

- Client-side search filtering (input event, hides/shows rows via `hidden` attribute)
- Filter pill toggling (updates active pill, filters rows by `data-status`)
- Row expand/collapse (toggles Turbo Frame visibility, one-at-a-time)
- Count label updates ("Showing N of M")
- Targets: searchInput, row, expandPanel, filterButton, countLabel

**`nutrition_editor_controller`** (major refactor): Manages the structured form dialog.

- Dialog open/close lifecycle (independent from generic `editor_controller`)
- Serving-volume ↔ density derivation sync (auto-populate and lock/unlock)
- Dynamic portion row add/remove
- Client-side field validation before submit
- Form data collection into structured JSON
- Save via fetch, handle Turbo Stream response
- "Save & Next" flow (replace form content, update next-ingredient label)
- Dirty-check on close
- Imports shared utilities from `editor_utils.js` (CSRF, saveRequest, error display)

The generic `editor_controller` is untouched — still used by quick bites and other textarea-based dialogs.

## Routes

New routes inside the existing kitchen scope:

```ruby
get  'ingredients/:ingredient_name', to: 'ingredients#show', as: :ingredient_detail
get  'ingredients/:ingredient_name/edit', to: 'ingredients#edit', as: :ingredient_edit
```

The existing `POST nutrition/:ingredient_name` endpoint is updated to accept structured JSON (Content-Type: application/json) and respond with Turbo Streams. The old `label_text` path is preserved for CLI compatibility.

## Server Changes

### IngredientsController

- `index`: Builds ingredient summary data for the table — name, status flags (has_nutrition?, has_density?), aisle, recipe count. Keeps the view template thin.
- `show` (new): Returns the detail partial for a Turbo Frame — nutrition summary, density explanation, recipe links, action buttons.
- `edit` (new): Returns the structured form partial pre-populated with ingredient data, inside a Turbo Frame.

### NutritionEntriesController

Updated `upsert` action:

- Accepts structured JSON: `{ nutrients: { basis_grams, calories, ... }, density: { volume, unit, grams }, portions: { each: 50, stick: 113 }, aisle: "Spices" }`
- Maps "each" → `~unitless` before persisting
- Responds with Turbo Streams (replace row, detail panel, summary bar; optionally load next editor form)
- Returns field-keyed error JSON for inline validation display
- Old `label_text` + `aisle` path preserved for `bin/nutrition` CLI

### "Save & Next" Logic

The save endpoint accepts a `save_and_next` param. When true, the response includes the next ingredient needing attention (next alphabetical name matching the active filter with incomplete data). The Turbo Stream replaces the editor form with the next ingredient's pre-populated form.

## Data Flow

No new models or migrations. `IngredientCatalog` already has all necessary columns including `portions` (JSON), density fields, and all nutrient columns. The `~unitless` convention in the `portions` hash is preserved — only the UI maps it to "each".

# Ingredient Filter Cleanup

**Date:** 2026-04-07
**Issue:** Improve ingredient page filter pills for clarity and accuracy

## Problem

The ingredients page has seven filter pills, two of which are confusing:
- "No Density" vs "Not Resolvable" — unclear distinction, overlapping concerns
- QuickBite-only ingredients inflate issue counts (No Nutrition, Not Resolvable)
  even though QBs don't use nutrition or unit resolution
- Apple and scale icons in the table are noise — only the pencil (custom) icon
  carries actionable information

## Changes

### 1. Drop "No Density" filter pill

Remove the No Density pill. Six pills remain: **All, Complete, Custom, No Aisle,
No Nutrition, Not Resolvable.** Not Resolvable is the actionable filter — it
shows ingredients with units that *actually* can't convert to grams in current
recipes. No Density was a catalog-entry property that flagged hypothetical future
problems.

### 2. Context-aware status for QB-only ingredients

Add a `qb_only` boolean to each ingredient row (true when all sources are
`QuickBiteSource`, false otherwise). This drives three behavioral changes:

**`row_status` becomes context-aware:**
- Recipe ingredients (unchanged): `missing` → `incomplete` → `complete` based
  on nutrition + density
- QB-only: `complete` if aisle is present or omitted from shopping,
  `incomplete` if neither

**Summary counts exclude QB-only from irrelevant issues:**
- `missing_nutrition`: excludes QB-only rows
- `missing_density`: removed entirely (pill is gone)
- `complete`, `custom`, `missing_aisle`, `total`: unchanged

**Coverage excludes QB-only:**
- `partition_by_resolvability` skips QB-only rows. They have no units and are
  naturally resolvable, but explicitly skipping keeps the unresolvable list clean.

**`next_needing_attention`** delegates to `row_status`, so it gets the new
QB-only behavior for free.

### 3. Simplified editor for QB-only ingredients

When opening the editor for a QB-only ingredient, hide sections that don't
apply:

**Hidden:** Nutrition section (USDA search, nutrient summary, nutrient fields),
Conversions section (recipe check, volume conversions, density candidates,
unit weights).

**Kept:** Grocery Aisle, Aliases, "Used in" list, "Reset to built-in" button.

Pass `qb_only:` to the editor form partial. The controller already has
`sources`, so computing it is trivial. Wrap the two sections in
`<% unless qb_only %>`.

### 4. Remove apple and scale icons from table rows

Remove the apple (has nutrition) and scale (has density) icons from
`_table_row.html.erb`. Keep only the pencil icon for custom entries.

Remove the `data-has-density` attribute from table rows (no longer used by
any filter). Keep `data-has-nutrition` — it's still used by the No Nutrition
JS filter.

### 5. JavaScript filter updates

In `ingredient_table_controller.js`:
- Remove the `no_density` case from `matchesStatus`
- Update `no_nutrition` case: `hasNutrition === "false" && qbOnly !== "true"`
- Add `data-qb-only` to the row data attributes read by the controller
- Update header comment to reflect the new pill set

## Files changed

- `app/services/ingredient_row_builder.rb` — `qb_only` flag, context-aware
  `row_status`, adjusted summary/coverage counts
- `app/views/ingredients/_summary_bar.html.erb` — remove No Density pill
- `app/views/ingredients/_table_row.html.erb` — remove apple/scale icons,
  remove `data-has-density`, add `data-qb-only`
- `app/views/ingredients/_editor_form.html.erb` — conditionally hide
  Nutrition and Conversions sections for QB-only
- `app/controllers/ingredients_controller.rb` — pass `qb_only` to editor
- `app/javascript/controllers/ingredient_table_controller.js` — remove
  `no_density` case, QB-only exclusion from `no_nutrition`

## Tests

**IngredientRowBuilder tests:**
- QB-only ingredient with aisle → status `complete`, `qb_only: true`
- QB-only ingredient omitted from shopping (no aisle) → status `complete`, `qb_only: true`
- QB-only ingredient without aisle and not omitted → status `incomplete`, `qb_only: true`
- Ingredient in both recipe and QB → normal status logic, `qb_only: false`
- `missing_nutrition` summary count excludes QB-only
- Unresolvable coverage list excludes QB-only

**Controller/integration tests:**
- No Density pill absent from rendered HTML
- Apple and scale icons absent from table rows
- Pencil icon still renders for custom entries
- QB-only editor hides Nutrition and Conversions sections

**JS controller tests:**
- Update to remove `no_density` case
- Add QB-only exclusion from `no_nutrition` filter

## Non-changes

- "Complete" definition for recipe ingredients stays the same (nutrition +
  density). There will be a gray area between Complete and the issue pills —
  an ingredient can be non-complete without appearing in any issue pill. This
  is acceptable.
- QB usage still counts toward the recipe count column.
- No schema changes — `qb_only` is computed at row-build time from source data.

# Ingredient Information Display Redesign

GH #213. Refine ingredient badges, move data icons inline with names, add
Custom filter, remove Data column.

## Current State

- **CUSTOM badge**: Blue pill with uppercase text — visually jarring.
- **Data column**: Two SVG icons (apple/scale) in a dedicated 3.5rem column,
  with outline states for missing data.
- **Filter pills**: All, Complete, No Aisle, No Nutrition, No Density, Not
  Resolvable. No Custom filter.

## Design

### Inline icon trail (Approach A)

Move the nutrition (apple) and density (scale) icons from the Data column into
the name cell, rendered inline after the ingredient name. Replace the CUSTOM
text badge with a small pencil SVG icon. Only show icons when the condition is
true — no empty/outline states. This reduces visual noise (most rows are
missing data) and reclaims the Data column width for the ingredient name.

### Row markup

Remove `col-data` `<td>` and `<th>`. The name cell becomes:

```erb
<td class="col-name">
  <%= row[:name] %>
  <span class="ingredient-icons">
    <%# pencil if custom, apple if has_nutrition, scale if has_density %>
  </span>
</td>
```

Icons render at 14px in muted color. The `<span>` wrapper uses inline-flex
with a small gap for consistent spacing.

### New pencil icon

Small pencil SVG at 14px, same style as apple/scale. Indicates a
kitchen-customized catalog entry.

### Filter pill

Add "Custom" pill to `_summary_bar.html.erb`. Count from
`summary[:custom]` — new key in `IngredientRowBuilder#build_summary`:
`rows.count { |r| r[:source] == 'custom' }`.

### Stimulus controller

- Add `data-source` attribute to rows (`"custom"`, `"global"`, `"missing"`).
- Add `"custom"` case to `matchesStatus()`:
  `row.dataset.source === "custom"`.
- Remove `"data"` sort key (column gone).
- SessionStorage persistence unchanged — new filter value just works.

### CSS

- Remove: `.col-data`, `.data-icons`, `.data-icon`, `.data-icon.empty`,
  `.source-badge`, `.source-custom`.
- Add: `.ingredient-icons` (inline-flex, gap, vertical-align middle),
  `.ingredient-icon` (14px, muted color).
- Remove `.col-data` from mobile responsive rules.
- `.col-name` takes remaining width implicitly.

### IngredientRowBuilder

Add to `build_summary`:
`custom: rows.count { |r| r[:source] == 'custom' }`.

## Files Changed

- `app/views/ingredients/_table_row.html.erb`
- `app/views/ingredients/_table.html.erb`
- `app/views/ingredients/_summary_bar.html.erb`
- `app/javascript/controllers/ingredient_table_controller.js`
- `app/services/ingredient_row_builder.rb`
- `app/assets/stylesheets/style.css`
- Tests for IngredientRowBuilder summary, controller, and views

# Nutrition Display Toggle

**GitHub:** #241
**Date:** 2026-03-17

## Problem

Nutrition Facts labels appear on every recipe that has computed nutrition data,
but the nutrition database is often incomplete early in a kitchen's life. Users
want to build up their ingredient catalog over time and flip nutrition display
on when they feel the data is useful — not be distracted by partial results in
the meantime.

## Approach

Display-only toggle on the Kitchen model. All nutrition computation (jobs,
cross-reference cascades, ingredient catalog) continues to run unconditionally.
The toggle controls only whether the Nutrition Facts label renders on recipe
pages.

### Why not skip computation?

- `CascadeNutritionJob` keeps cross-reference parent recipes in sync when a
  child recipe's ingredients change. Disabling it risks stale data.
- `IngredientRowBuilder#coverage` uses `nutrition_data` for the ingredient
  editor — that UI stays visible regardless of the toggle.
- The computation is cheap (synchronous inline, no external API).
- Keeping data warm means toggling display on requires no backfill.

## Design

### Database

Migration `008_add_show_nutrition_to_kitchens.rb`: add `show_nutrition` boolean
column to `kitchens`, default `false`.

### Settings controller

- `show`: include `show_nutrition` in the JSON response.
- `update`: add `show_nutrition` to the `settings_params` whitelist.

### Settings dialog

New "Recipes" fieldset between the existing "Site" and "API Keys" sections:

```html
<fieldset class="editor-section">
  <legend class="editor-section-title">Recipes</legend>
  <div class="settings-field">
    <label class="settings-checkbox-label">
      <input type="checkbox" id="settings-show-nutrition"
             data-settings-editor-target="showNutrition">
      Display nutrition information under recipes
    </label>
  </div>
</fieldset>
```

### Stimulus controller (`settings_editor_controller.js`)

- Add `showNutrition` to `static targets`.
- Wire into `collect`, `provideSaveFn`, `checkModified`, `reset`,
  `storeOriginals`, and `disableFields` — same pattern as existing text fields
  but using `.checked` instead of `.value`.
- Note: both `collect` and `provideSaveFn` independently build the payload
  object — `show_nutrition` must be added to both.
- Load handler uses `this.showNutritionTarget.checked = !!data.show_nutrition`
  (not `|| ""` like the text fields).

### Recipe view (`_recipe_content.html.erb`)

Existing condition:

```erb
<%- if nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
```

Becomes:

```erb
<%- if current_kitchen.show_nutrition && nutrition && nutrition['totals']&.values&.any? { |v| v.to_f > 0 } -%>
```

One guard prepended. No other view or controller changes.

### What stays the same

- `RecipeNutritionJob` and `CascadeNutritionJob` run on every recipe save.
- `NutritionCalculator` is unchanged.
- `RecipesController#show` still assigns `@nutrition = @recipe.nutrition_data`
  unconditionally — the `nutrition` local is also used for `makes_unit_*`
  display in the recipe header, which is independent of the toggle.
- Ingredient editor, coverage badges, and all other nutrition-adjacent UI
  remain unaffected.
- Export endpoints (`show_markdown`, `show_html`) do not include nutrition
  data and are unaffected.

### Documentation updates

- Kitchen model header comment: mention display preferences.
- CLAUDE.md Settings paragraph: add "display preferences" alongside branding
  and API keys.

## Tests

- **Migration:** column exists with default `false`.
- **Settings controller:** `show` returns `show_nutrition`; `update` persists
  the value.
- **Recipe view:** nutrition table renders when `show_nutrition: true` with
  nutrition data present; does not render when `show_nutrition: false` even
  with nutrition data present.

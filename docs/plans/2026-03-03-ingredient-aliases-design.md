# Ingredient Aliases — Design

**Issue:** #157 — Review use of ingredient aliases in web app

## Problem

Ingredient aliases exist in the database (JSON array column on `ingredient_catalog`) and are already resolved during `lookup_for`, but two things are missing:

1. The web editor has no UI for viewing or editing aliases — only the standalone TUI (`bin/nutrition`) can manage them.
2. Inflector variants (singular/plural) are not generated for alias names, so "Spinaches" won't match an alias of "Spinach".

## Design

### Part 1: Aliases Editor in Web UI

Add an "Aliases" fieldset to `_editor_form.html.erb`, placed between the Grocery Aisle section and the "Used in" links. Tag-style chips for existing aliases, with a text input and Enter/button to add new ones.

**View changes:**
- New fieldset with `alias-chip` spans for each existing alias, each with a `×` remove button
- Text input + "Add" button at the bottom of the section
- Existing `entry.aliases` array drives initial rendering

**Stimulus controller changes** (`nutrition_editor_controller.js`):
- New targets: `aliasList`, `aliasInput`
- `addAlias` action — creates a chip DOM element, appends to list
- `removeAlias` action — removes the chip's parent element
- `collectAliases` — reads chip text content into an array
- `collectFormData` includes `aliases` in its return value
- `isModified` and `originalSnapshot` automatically cover aliases since they're part of `collectFormData`

**Controller changes** (`NutritionEntriesController`):
- `catalog_params` gains `aliases:` key from `permitted_aliases` (array of strings, max 20 entries, max 100 chars each)
- `assign_from_params` receives and sets `self.aliases`

**Model changes** (`IngredientCatalog`):
- `assign_from_params` adds `aliases:` keyword parameter, sets `self.aliases` when present
- No validation changes needed — aliases are a simple string array

### Part 2: Inflector Variants for Aliases

In `IngredientCatalog.add_alias_keys`, after generating case variants for each alias, also run `Inflector.ingredient_variants` on the alias name. This registers singular/plural forms so "Spinaches" resolves when "Spinach" is an alias.

The change is additive — existing case-variant logic stays, inflected variants are appended with the same `extras[v] ||= entry` guard to avoid clobbering canonical names.

## Files Changed

| File | Change |
|------|--------|
| `app/models/ingredient_catalog.rb` | `assign_from_params` accepts aliases; `add_alias_keys` adds inflector variants |
| `app/controllers/nutrition_entries_controller.rb` | `catalog_params` includes aliases; `permitted_aliases` method |
| `app/views/ingredients/_editor_form.html.erb` | Aliases fieldset with chips UI |
| `app/javascript/controllers/nutrition_editor_controller.js` | Alias targets, add/remove/collect methods |
| `app/assets/stylesheets/ingredients.css` | Chip styles |
| `test/models/ingredient_catalog_test.rb` | Tests for inflector variants on aliases |
| `test/controllers/nutrition_entries_controller_test.rb` | Tests for saving/loading aliases via web editor |

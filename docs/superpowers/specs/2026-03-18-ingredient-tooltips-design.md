# Ingredient Tooltip Design

Per-ingredient nutrition and gram conversion displayed as native browser
tooltips (`title` attribute) on recipe ingredient list items.

## Motivation

The nutrition pipeline already resolves every ingredient to grams and computes
per-nutrient contributions, but only the aggregated totals are stored. Surfacing
the per-ingredient breakdown lets users see at a glance how much each ingredient
weighs and what it contributes nutritionally — useful during meal planning and
recipe browsing. Missing-catalog nudges encourage filling gaps in the ingredient
editor.

## Scope

**In scope:**
- Per-ingredient gram weight and 6 key nutrients in a `title` tooltip
- Status-aware messages: resolved, partial, missing, skipped
- "Based on original quantities" note (titles are not scaled)
- Data stored in existing `nutrition_data` JSON column (no migration)

**Out of scope (potential future work):**
- Custom styled tooltips (upgrade path if `title` proves too limited)
- Volume equivalents (grams-to-cups reverse conversion)
- Mobile-specific interaction (tooltips are hover-only for now)
- Scaled tooltip values (would require JS updates to `title` attributes)

## Data Layer

### NutritionCalculator changes

`NutritionCalculator#accumulate_amounts` already iterates over each ingredient,
resolves to grams via `UnitResolver`, and multiplies by per-gram nutrient
factors. The change: capture per-ingredient detail alongside the running totals.

New data class:

```ruby
IngredientDetail = Data.define(:grams, :nutrients)
```

- `grams` — total resolved grams for this ingredient (summed across all
  amounts, since an ingredient can appear in multiple steps)
- `nutrients` — hash of the 6 tooltip nutrients:
  `{ calories:, protein:, fat:, carbs:, sodium:, fiber: }`

`accumulate_amounts` builds an `IngredientDetail` per known-and-resolved
ingredient. The hash is keyed by downcased ingredient name to match the
existing `missing_ingredients` / `partial_ingredients` convention.

### Result changes

`Result` gains one new field:

```ruby
Result = Data.define(
  :totals, :serving_count, :per_serving, :per_unit,
  :makes_quantity, :makes_unit_singular, :makes_unit_plural,
  :units_per_serving, :total_weight_grams,
  :missing_ingredients, :partial_ingredients, :skipped_ingredients,
  :ingredient_details  # NEW — { "flour" => { grams: 250.0, nutrients: { ... } }, ... }
)
```

`as_json` serializes `ingredient_details` as a nested hash with string keys and
float values, matching the existing serialization style.

### Storage

Stored in the existing `Recipe#nutrition_data` JSON column — no schema
migration. `RecipeNutritionJob` already calls `result.as_json` and writes the
whole thing. The new field adds a few hundred bytes per recipe at most.

### Ingredient name keying

`NutritionCalculator` works with downcased ingredient names internally. The
tooltip helper needs to match AR `Ingredient#name` to the details hash. Keying
by `name.downcase` in both places ensures a match. If an ingredient appears
in multiple steps, its grams and nutrients are summed into one entry.

## Presentation Layer

### Helper changes

`RecipesHelper#ingredient_data_attrs` currently emits scaling data attributes.
It gains access to the recipe's `ingredient_details` hash (passed down from
the controller/partial) and sets the `title` attribute on each `<li>`.

The helper needs the ingredient details and the lists of missing/partial/skipped
ingredients. These come from the recipe's `nutrition_data` JSON, which is
already available as `@nutrition` in the show action.

### Title format

**Resolved ingredient (grams + nutrition available):**
```
2 cups → 250g
Cal 210 | Pro 7g | Fat 1g | Carb 46g
Sodium 2mg | Fiber 2g
(based on original quantities)
```

Line 1: original quantity display + arrow + gram weight (rounded to nearest
integer). Line 2-3: compact nutrient summary. Line 4: caveat that values
reflect the unscaled recipe.

For range quantities (e.g., `1-2 cups`), use the high value for the tooltip
since `quantity_value` (used for nutrition) returns the high end.

**Missing ingredient (not in catalog):**
```
Not in ingredient catalog
```

**Partial ingredient (in catalog, but unit can't be resolved):**
```
In catalog, but can't convert this unit
```

**Skipped ingredient (no quantity specified):**
No `title` attribute — nothing useful to show.

**No nutrition data at all (e.g., no catalog entries exist yet):**
No `title` attributes rendered.

### Newlines in title

Modern browsers render `&#10;` (Unicode newline) in `title` attributes. The
helper builds the string with `\n` and lets ERB handle encoding. No special
escaping needed — `tag.attributes` handles HTML entity encoding.

### Partial plumbing

The `_step.html.erb` partial needs access to the nutrition ingredient details.
Options:

- Pass the full `nutrition` hash as a local to `_step.html.erb`, then to the
  helper
- Or extract just `ingredient_details`, `missing_ingredients`, and
  `partial_ingredients` into a single hash passed as a local

The simpler path: pass `ingredient_info` (a small hash with the three keys)
as a partial local. `_recipe_content.html.erb` extracts it from `@nutrition`
and threads it through. The helper method signature becomes:

```ruby
def ingredient_data_attrs(item, scale_factor:, ingredient_info: nil)
```

When `ingredient_info` is nil (e.g., embedded recipes without nutrition data),
no titles are rendered — graceful degradation.

### Embedded recipes

Cross-referenced embedded recipes don't have their own `nutrition_data`
computed in the parent's show action. Their ingredients get no tooltips for now.
This is fine — the user can click through to the embedded recipe's own page to
see its tooltips.

## Testing

### Unit tests

- `NutritionCalculator` test: verify `ingredient_details` is populated with
  correct grams and nutrient values for a known recipe
- `NutritionCalculator` test: verify missing/partial/skipped ingredients
  produce no `ingredient_details` entry
- `NutritionCalculator` test: verify `as_json` round-trips `ingredient_details`

### Helper tests

- `ingredient_data_attrs` with resolved ingredient → `title` contains grams
  and nutrient values
- `ingredient_data_attrs` with missing ingredient → `title` says "Not in
  ingredient catalog"
- `ingredient_data_attrs` with partial ingredient → `title` says "can't
  convert"
- `ingredient_data_attrs` with no `ingredient_info` → no `title` attribute

### Integration tests

- Recipe show page renders `title` attributes on ingredient `<li>` elements
  when nutrition data is present

## File Inventory

Files that change:

- `lib/familyrecipes/nutrition_calculator.rb` — `IngredientDetail`, capture
  per-ingredient data in `accumulate_amounts`, add to `Result`
- `app/helpers/recipes_helper.rb` — `ingredient_data_attrs` gains `title`
  building, new private helper for tooltip string formatting
- `app/views/recipes/_recipe_content.html.erb` — extract `ingredient_info`
  from `@nutrition`, pass to step partial
- `app/views/recipes/_step.html.erb` — accept and forward `ingredient_info`
  local to the helper
- `test/nutrition_calculator_test.rb` — new assertions for `ingredient_details`
- `test/helpers/recipes_helper_test.rb` — new assertions for `title` attribute
- `test/controllers/recipes_controller_test.rb` — integration assertion

Files that don't change:

- `UnitResolver` — no new methods needed (no volume equivalents)
- `RecipeNutritionJob` — already passes full `Result` through
- Schema / migrations — data stored in existing JSON column
- CSS — no styling (native browser tooltip)
- JavaScript — no new controllers or changes to existing ones

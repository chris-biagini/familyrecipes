# Ingredient Catalog Improvements — Design

## Motivation

The Ingredient Catalog is one of the highest-value features in the app, supporting nutrition calculation, grocery aisle mapping, and unit conversion. It currently has ~290 entries skewed toward lacto-ovo vegetarian / Italian-American cooking. This design addresses three problems:

1. **No aliasing.** "AP flour" won't resolve to "Flour (all-purpose)." Users write ingredient names in many forms.
2. **Stale curation tooling.** `bin/nutrition` is decoupled from the system and has friction-heavy workflows.
3. **Narrow coverage.** Expanding to meat-eating and broader Western-cuisine users requires more data and validation that the schema can handle what's out there.

## Phase 1: Schema — Aliases

Add an `aliases` JSON column to `ingredient_catalog`, defaulting to `[]`.

### YAML format

```yaml
Flour (all-purpose):
  aliases:
    - AP flour
    - All-purpose flour
    - Flour
    - Plain flour
  aisle: Baking
  nutrients: ...
```

### Lookup behavior

`lookup_for(kitchen)` already builds a name → entry hash with inflection variants. After that step, it iterates each entry's `aliases` array and adds them as additional keys (case-insensitive). Kitchen entries inherit and can extend global aliases.

### Conflict resolution

If two entries claim the same alias, the later one (alphabetically) wins via hash merge. A warning is logged at seed time. Kitchen overrides always take precedence over global entries.

### No other schema changes

The `~unitless` portion with USDA average weights handles meat cuts and countable items. The current portions, density, and nutrient columns are flexible enough. No changes needed.

## Phase 2: bin/nutrition Overhaul

The CLI becomes a dedicated USDA curation tool. Manual/label entry is removed — the web editor covers that use case.

### Richer search results

Each USDA search result shows:
- Nutrient summary (calories, protein, fat, carbs per 100g)
- Available portions with gram weights
- Data type (SR Legacy, Foundation, Survey)

This eliminates the "guess at search strings" problem — you see immediately whether a result is correct.

### Smarter portion import

After selecting a USDA entry:
1. Auto-extract density from the best volume portion (existing behavior).
2. Present non-volume portions with recommendations on which map to our system.
3. Show needed recipe units and flag which are now resolvable.
4. Prompt for `~unitless` weight when the ingredient appears as a bare count.

### Alias prompting

After saving, the tool suggests aliases based on the USDA description (e.g., "Wheat flour, white, all-purpose" suggests "All-purpose flour," "AP flour," "White flour").

### Batch mode

`--missing` keeps priority-by-frequency ordering. Add `--coverage` for a summary of resolution rates. Drop the "enter data?" confirmation — just iterate.

### Removed

- `prompt_serving_size`, `enter_manual`, brand/product prompting
- The `--manual` flag
- All label-entry code

### Retained

- USDA search/fetch, nutrient extraction, portion classification
- Review/edit loop, source tracking (USDA only), unit coverage display

## Phase 3: Trial Runs (~25-30 Ingredients)

Use the revamped tool on diverse ingredients, iterating on tool and schema as friction surfaces. Pause after each batch of ~5 to assess and adjust.

### Ingredient selection

| Category | Examples | Stress-tests |
|---|---|---|
| Meats | Chicken breast, Ground beef, Pork chops, Bacon | Bare counts, weight, cooked-vs-raw |
| Dairy | Milk, Butter, Cheddar cheese, Heavy cream | Volume + weight + sticks, search difficulty |
| Grains/Baking | Rice, Bread, Pasta (dry) | Cooked vs dry density |
| Produce | Onions, Garlic, Bell peppers, Potatoes | Counts, cloves, cups chopped |
| Oils/Fats | Olive oil, Coconut oil | Volume-only |
| Canned/Jarred | Canned tomatoes, Chicken broth, Coconut milk | "1 can" portion, liquid density |
| Spices | Cumin, Paprika, Cinnamon | Tiny quantities, tsp-only |
| Nuts/Seeds | Almonds, Sesame seeds | Volume + weight + count |
| Proteins | Tofu, Lentils (dry) | Block/package portions |
| Compound | Soy sauce, Worcestershire, Honey | Liquid condiments, volume-only |

### Per-ingredient checklist

1. Does USDA search find the right entry within 1-2 queries?
2. Are available portions useful or noisy?
3. Can every reasonable recipe unit be resolved?
4. What aliases would a real user need?
5. Workflow friction?

### Deliverable

~25-30 fully populated catalog entries with aliases, plus a refined `bin/nutrition` tool ready for handoff.

## Phase 4: Forward-Looking Validation (This Session, No Implementation)

Examine 5-10 recipes from popular sites (AllRecipes, Serious Eats, NYT Cooking) spanning American, British, Italian, Mexican, and weeknight-dinner categories.

### Validation checklist

1. **Naming conventions.** Can our catalog + aliases resolve real recipe ingredient names? (e.g., "boneless skinless chicken thighs" → "Chicken thighs")
2. **Quantity expressions.** Can our parser handle "1 (14.5 oz) can diced tomatoes," "2 pounds boneless chicken," "1 bunch cilantro"?
3. **Prep-state ambiguity.** "1 cup chopped onion" vs "1 onion, chopped" — different quantities, same ingredient. Does the system handle both?
4. **Missing categories.** Fish/seafood, lamb, cheeses, herbs, Asian pantry staples?

### Deliverable

A findings report covering schema gaps, parser gaps, a "next 50 ingredients" priority list, and recommendations for what an AI-import tool would need.

# Nutrition TUI: Header Cleanup & Schema Validation

## Problem

The ingredient editor in `bin/nutrition` has three issues:

1. Empty section headers show a trailing em dash on the header line (e.g., `Density [d] ──── —`). The header line should be a pure visual separator with content below.
2. The nutrients `basis_grams` value displays in the header line as `(per 30g)`. It should be on an indented line below like all other content.
3. The TUI editors don't enforce the same validation constraints as the Rails model, allowing invalid data into the YAML.

## Design

### Display Changes

**Header line rule.** `section_header` renders only `Name [key] ────────`. No suffix parameter, no content on the header line.

**Empty sections.** The em dash moves to an indented line below the header:

```
Density [d] ──────────────
    —
```

**Nutrients section.** Basis grams moves from header suffix to indented line:

```
Nutrients [n] ─────────────
    Per 30g
    Calories          110
    Total fat         0.5 g
```

All other sections (density, portions, aisle, aliases, sources) already render content on indented lines below the header. This makes nutrients and empty sections consistent.

### Shared Constraints Module

New file: `lib/familyrecipes/nutrition_constraints.rb`

`FamilyRecipes::NutritionConstraints` provides constants and predicate methods used by both the Rails model and the TUI editors.

**Constants:**

- `NUTRIENT_MAX` — `Hash.new(10_000).merge('sodium' => 50_000).freeze`
- `AISLE_MAX_LENGTH` — `50`

**Predicate methods** (return `[valid, error_message]` tuples):

- `valid_basis_grams?(value)` — numeric, > 0
- `valid_nutrient?(key, value)` — numeric, 0..NUTRIENT_MAX[key]
- `density_complete?(hash)` — all three keys (grams, volume, unit) present or all absent; grams and volume positive numbers; unit non-blank
- `valid_portion_value?(value)` — numeric, > 0
- `valid_aisle?(value)` — length <= AISLE_MAX_LENGTH

**Rails model refactor.** `IngredientCatalog` removes its inline `NUTRIENT_MAX` and delegates to the shared predicates in its custom validators. `Kitchen::MAX_AISLE_NAME_LENGTH` becomes `NutritionConstraints::AISLE_MAX_LENGTH` (Kitchen keeps its constant as an alias for backward compat).

### TUI Editor Validation

Each editor validates on close (Esc). On failure, an error message line appears at the bottom of the overlay. Any keypress dismisses the error and returns to editing.

**DensityEditor.** Calls `density_complete?` on Esc. Rejects partial density (e.g., grams without volume+unit). Allows completely empty density (no fields set).

**NutrientsEditor.** On Esc, validates basis_grams > 0 when nutrients present, and each nutrient value within range via `valid_nutrient?`.

**PortionsEditor.** Validates on input (when committing a portion value). Rejects value <= 0 via `valid_portion_value?`.

**AisleEditor.** Validates the "Other..." free-text path. Rejects length > AISLE_MAX_LENGTH.

**SourcesEditor and AliasesEditor.** No new validation needed — free text fields with no Rails-side constraints beyond blank rejection (already handled).

### Test Coverage

- New `test/nutrition_constraints_test.rb` — unit tests for each predicate with valid, boundary, and invalid inputs.
- Existing `IngredientCatalog` model tests pass unchanged after refactor (proves delegation is correct).
- No TUI editor tests (would require mocking ratatui_ruby event loop; out of scope).

### Documentation Updates

- Architectural header comments on `NutritionConstraints`, updated comments on `IngredientCatalog` and affected TUI editors.
- CLAUDE.md updated if the new module changes any cross-cutting conventions.

# UnitResolver Extraction Design

**Date:** 2026-03-15
**Status:** Approved
**Problem:** Unit conversion tables and resolution logic are trapped inside
`NutritionCalculator`, forcing `UsdaPortionClassifier` and `IngredientRowBuilder`
to depend on a calculator for non-calculation reasons. `IngredientRowBuilder`
reimplements the resolution chain as booleans (~40 lines), creating silent
duplication that can drift.

## Context

The March 4 nutrition constants consolidation unified *where* constants are
defined but kept everything inside `NutritionCalculator`. This extraction is the
structural next step: giving unit resolution its own identity so consumers depend
on it directly.

Future direction: bidirectional volume ↔ mass conversion (on import, on demand,
or live per user preference). Centralizing unit knowledge in one place makes that
a natural extension.

## Approach

**Instance wrapping a catalog entry.** A `FamilyRecipes::UnitResolver` class
where each instance wraps one `IngredientCatalog` entry and answers unit
resolution questions for that ingredient. Conversion tables and unit-type
predicates are class-level constants and methods.

Chosen over a stateless module (which would pass `entry` on every call) and a
hybrid (which splits the API confusingly). The instance approach is the natural
home for future `convert(value, from:, to:)` methods.

## The New Class

**File:** `lib/familyrecipes/unit_resolver.rb`

```ruby
module FamilyRecipes
  class UnitResolver
    # --- Class constants (moved from NutritionCalculator) ---
    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
      'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
      'gal' => 3785.41, 'ml' => 1, 'l' => 1000
    }.freeze

    DENSITY_UNITS = ['cup', 'tbsp', 'tsp', 'fl oz', 'ml', 'l'].freeze

    EXPANDED_VOLUME_UNITS = <built from Inflector, identical to today>
    EXPANDED_WEIGHT_UNITS = <built from Inflector, identical to today>

    # --- Class predicates (no entry needed) ---
    def self.weight_unit?(unit)
    def self.volume_unit?(unit)

    # --- Instance: wraps one IngredientCatalog entry ---
    def initialize(entry)  # entry may be nil (nil-safe)

    def to_grams(value, unit)    # => Float or nil
    def resolvable?(value, unit) # => Boolean
    def density                  # => g/mL or nil
  end
end
```

**Nil entry handling.** `UnitResolver.new(nil)` is valid. Weight units resolve
without an entry (pure table lookup), so `to_grams(100, 'g', nil)` returns
`100.0`. All other resolution paths return nil, and `resolvable?` returns false.
This matches the current behavior in `IngredientRowBuilder#unit_resolvable?`
where `entry&.basis_grams.blank?` guards the non-weight paths.

The resolution chain in `to_grams` is identical to today's
`NutritionCalculator#to_grams`: bare count → weight → named portion →
density → nil. No behavioral change.

## Consumer Changes

### NutritionCalculator — shrinks

**Deletes:** All constants (`WEIGHT_CONVERSIONS`, `VOLUME_TO_ML`,
`DENSITY_UNITS`, `EXPANDED_*`), `to_grams`, `derive_density`, `resolvable?`.

**Keeps:** `calculate`, `sum_totals`, `partition_ingredients`,
`accumulate_amounts`, `divide_nutrients`, `per_unit_metadata`,
`nutrient_per_gram`, `parse_serving_count`, `Result`.

In `accumulate_amounts`, the inline `to_grams` call becomes:

```ruby
resolver = UnitResolver.new(entry)
grams = resolver.to_grams(amount.value, amount.unit)
```

The class-length rubocop disable is removed.

### IngredientRowBuilder — deletes ~50 lines

**Deletes:** `WEIGHT_UNITS`, `VOLUME_UNITS`, `unit_resolvable?`, `weight_unit?`,
`volume_unit?`, `portion_defined?`, `density_defined?`.

Unit resolvability delegates to `UnitResolver`:

```ruby
def unit_resolvable?(unit, entry)
  UnitResolver.new(entry).resolvable?(1, unit)
end
```

`resolution_method` stays (presentation logic), along with its helpers
`unitless_method` and `volume_method`. It uses `UnitResolver` class methods
for unit-type checks instead of the deleted local constants:

```ruby
def resolution_method(unit, resolvable, entry)
  return 'weight' if UnitResolver.weight_unit?(unit)
  return 'no nutrition data' if entry&.basis_grams.blank?
  return unitless_method(resolvable) if unit.nil?
  return volume_method(resolvable) if UnitResolver.volume_unit?(unit)

  resolvable ? "via #{unit}" : 'no portion'
end
```

### UsdaPortionClassifier — fixes semantic dependency

All `NutritionCalculator::` constant references become `UnitResolver::`:

```ruby
# Before
NutritionCalculator::EXPANDED_VOLUME_UNITS
NutritionCalculator::VOLUME_TO_ML

# After
UnitResolver::EXPANDED_VOLUME_UNITS
UnitResolver::VOLUME_TO_ML
```

No logic changes.

### BuildValidator

`@nutrition_calculator.resolvable?` becomes:

```ruby
resolver = UnitResolver.new(entry)
next if resolver.resolvable?(quantity.value, quantity.unit)
```

### Editor form (`_editor_form.html.erb`)

```erb
FamilyRecipes::NutritionCalculator::DENSITY_UNITS
→ FamilyRecipes::UnitResolver::DENSITY_UNITS
```

### RecipeNutritionJob — unchanged

Constructs a `NutritionCalculator` and calls `calculate`. No direct unit
resolution.

## Test Changes

### New: `test/unit_resolver_test.rb`

Plain `Minitest::Test` (no Rails), constructs `IngredientCatalog.new` directly.

**Moved from `nutrition_calculator_test.rb`:**
- `test_resolvable_with_known_unit`
- `test_resolvable_bare_count_with_unitless`
- `test_not_resolvable_with_unknown_unit`
- `test_resolvable_with_density`
- `test_bare_count_not_resolvable_without_unitless`

**New tests:**
- `to_grams` directly: weight, volume+density, named portion, bare count, nil
- `density` method: present, missing fields, zero volume
- Nil entry: weight still resolves, everything else returns nil/false
- Class predicates: `weight_unit?`, `volume_unit?`

### Slimmed: `nutrition_calculator_test.rb`

Five `resolvable?` tests move out. Calculation tests stay — they exercise the
full pipeline and implicitly test the `UnitResolver` integration.

### Unchanged

- `ingredient_row_builder_test.rb` — tests cover behavior, not internal delegation
- `usda_portion_classifier_test.rb` — tests cover classification, not constant source
- `build_validator` tests — tests cover output, not how resolvability is checked

## Files Changed

| File | Nature |
|------|--------|
| `lib/familyrecipes/unit_resolver.rb` | **New** — ~85 lines |
| `lib/familyrecipes/nutrition_calculator.rb` | Remove constants + resolution (~70 lines removed) |
| `app/services/ingredient_row_builder.rb` | Delete reimplemented logic (~40 lines removed) |
| `lib/familyrecipes/usda_portion_classifier.rb` | Repoint 3 constant references, update header comment |
| `lib/familyrecipes/build_validator.rb` | Use `UnitResolver` for `resolvable?` |
| `app/views/ingredients/_editor_form.html.erb` | Repoint 1 constant reference |
| `lib/familyrecipes.rb` | Add `require_relative` for unit_resolver (before nutrition_calculator) |
| `CLAUDE.md` | Update NutritionCalculator description, add UnitResolver bullet |
| `test/unit_resolver_test.rb` | **New** — moved + new tests |
| `test/nutrition_calculator_test.rb` | Remove 5 moved tests |

## Risk Assessment

Low risk. Pure structural extraction with no behavioral changes. The resolution
chain is copied verbatim. All existing calculation tests continue to exercise
the full pipeline end-to-end. The only new code is the class shell and the
`density` public method (which is `derive_density` renamed and made public).

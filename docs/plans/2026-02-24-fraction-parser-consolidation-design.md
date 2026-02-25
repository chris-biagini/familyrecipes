# Fraction Parser Consolidation

Closes #89.

## Problem

Three methods parse fraction strings into floats, each with different robustness:

| Method | Location | `"1/0"` | Garbage |
|--------|----------|---------|---------|
| `IngredientParser.parse_multiplier` | ingredient_parser.rb:60 | `Infinity` | `0.0` |
| `ScalableNumberPreprocessor.parse_numeral` | scalable_number_preprocessor.rb:70 | `Infinity` | `0.0` |
| `NutritionEntryHelpers.parse_fraction` | nutrition_entry_helpers.rb:9 | `nil` | `nil` |

Only the third is robust. The first two produce `Infinity` or silently swallow bad input.

## Solution

Create `FamilyRecipes::NumericParsing` with a single `parse_fraction` method. Replace all three call sites.

### `FamilyRecipes::NumericParsing.parse_fraction(str)`

- `nil` input returns `nil` (nil-in, nil-out).
- Strips whitespace.
- Fractions (`"1/2"`): splits on `/`, validates both parts are numeric via `Float()`, checks denominator is non-zero, returns the float.
- Plain numbers: uses `Float(str, exception: false)`; raises `ArgumentError` if conversion fails.
- Raises `ArgumentError` for division by zero and non-numeric strings.

### Caller changes

**`IngredientParser.parse_multiplier`** — replace body with `NumericParsing.parse_fraction(str) || 1.0`. The regex already constrains input to `\d+(?:/\d+)?(?:\.\d+)?`, so `ArgumentError` only fires on genuine data bugs like `1/0`.

**`ScalableNumberPreprocessor.parse_numeral`** — replace body with `NumericParsing.parse_fraction(str)`. Same regex guarantee.

**`NutritionEntryHelpers.parse_fraction`** — delete. Its caller `parse_serving_size` calls `NumericParsing.parse_fraction` directly, with `rescue ArgumentError` returning `nil` (serving size input comes from user-pasted nutrition labels which can be messy).

### Tests

New `test/numeric_parsing_test.rb` covering: integers, decimals, fractions, nil, empty string, division by zero, garbage input. Each asserts either the correct float or `ArgumentError`.

### File inventory

| File | Action |
|------|--------|
| `lib/familyrecipes/numeric_parsing.rb` | Create |
| `config/initializers/familyrecipes.rb` | Add require |
| `lib/familyrecipes/ingredient_parser.rb` | Replace `parse_multiplier` body |
| `lib/familyrecipes/scalable_number_preprocessor.rb` | Replace `parse_numeral` body |
| `lib/familyrecipes/nutrition_entry_helpers.rb` | Delete `parse_fraction`, update caller |
| `test/numeric_parsing_test.rb` | Create |
| `test/nutrition_entry_helpers_test.rb` | Update `parse_fraction` tests to expect `ArgumentError` |

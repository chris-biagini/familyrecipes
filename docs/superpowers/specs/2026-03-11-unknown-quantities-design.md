# Unknown Quantities Design

**Problem:** Recipes with non-numeric quantities like "a few leaves" crash the
recipe page. Two bugs conspire: (1) `split_quantity` naively splits "a few
leaves" into `quantity: "a"`, `unit: "few leaves"`, then `numeric_value("a")`
returns the string `"a"` instead of nil — downstream `.to_f` silently gives
`0.0`, displaying "0 few leaves"; (2) `NutritionCalculator::Result#as_json`
doesn't coerce `total_weight_grams` (a BigDecimal) to float, so the JSON
stores a string like `"866.0004..."`, and `per_serving_weight` calls
`&.positive?` on that string → `NoMethodError`.

**Architecture:** Make the quantity pipeline honest about what's numeric and
what's not. Non-numeric quantities display verbatim, are excluded from scaling,
and are skipped by nutrition/aggregation — same as unquantified ingredients.
Fix the BigDecimal serialization as a separate but related cleanup.

## Design Decisions

**Freeform quantities display verbatim.** "Basil, a few leaves" renders exactly
as written. No attempt to interpret or normalize informal descriptors.

**No scaling for freeform quantities.** At 2x, "a few leaves" stays "a few
leaves". The user applies judgment.

**Non-numeric = unquantified for math.** Nutrition calculation, ingredient
aggregation, and the ingredient editor all treat freeform quantities the same
as nil — skipped, not errored.

## Changes

### 1. Guard `split_quantity` against non-numeric first tokens

`FamilyRecipes::Ingredient.split_quantity` currently splits on the first space
unconditionally. Add a guard: if the first token isn't numeric-looking (digit,
fraction, vulgar fraction character), return the entire string as the quantity
with nil unit.

```ruby
# Before: split_quantity("a few leaves") → ["a", "few leaves"]
# After:  split_quantity("a few leaves") → ["a few leaves", nil]
```

"Numeric-looking" means: starts with a digit, or starts with a vulgar fraction
character (½, ¾, etc.). This is a simple regex check on the first token.

The stored DB columns become `quantity: "a few leaves"`, `unit: nil`.

### 2. Make `numeric_value` return nil for non-numeric strings

`FamilyRecipes::Ingredient.numeric_value` currently returns the raw string when
it can't parse a number. Add a final guard: `Float(value_str, exception: false)`
— if it returns nil, the value isn't numeric, so return nil.

```ruby
# Before: numeric_value("a") → "a"
# After:  numeric_value("a few leaves") → nil
```

This makes `quantity_value` return nil for freeform text. All downstream
consumers already handle nil correctly (aggregator, nutrition calculator,
view helpers).

### 3. Update view helpers to fall back to `quantity_display`

`scaled_quantity_display` and `format_quantity_display` currently assume
`quantity_value` is numeric when non-nil. After change #2, `quantity_value`
is nil for freeform text, so the existing nil guard returns early. But we
still need to display the original text.

Update: when `quantity_value` is nil but `quantity_display` is present, render
`quantity_display` verbatim (no scaling, no vulgar fraction formatting).

`ingredient_data_attrs` already returns early when `quantity_value` is nil —
no scaling data attributes for freeform quantities. Correct behavior.

### 4. Fix BigDecimal serialization in `Result#as_json`

Add `.to_f` coercion for `total_weight_grams`, `serving_count`,
`makes_quantity`, and `units_per_serving` in `as_json`. These are all numeric
scalars that can be BigDecimal from calculations.

```ruby
def as_json(_options = nil)
  to_h.transform_keys(&:to_s).tap do |h|
    %w[totals per_serving per_unit].each do |key|
      h[key] = h[key]&.transform_keys(&:to_s)&.transform_values(&:to_f)
    end
    %w[total_weight_grams serving_count makes_quantity units_per_serving].each do |key|
      h[key] = h[key]&.to_f
    end
  end
end
```

### 5. Ingredient editor: freeform quantities are unresolvable

The ingredient editor (`IngredientRowBuilder`) already treats ingredients with
nil `quantity_value` as unresolvable for nutrition purposes. No change needed —
the fix in #2 cascades automatically.

## Files Changed

| File | Change |
|------|--------|
| `lib/familyrecipes/ingredient.rb` | Guard `split_quantity`, guard `numeric_value` |
| `app/helpers/recipes_helper.rb` | Fall back to `quantity_display` for freeform |
| `lib/familyrecipes/nutrition_calculator.rb` | Fix `as_json` BigDecimal coercion |
| `test/ingredient_test.rb` | Tests for freeform quantities |
| `test/helpers/recipes_helper_test.rb` | Tests for freeform display |
| `test/nutrition_calculator_test.rb` | Tests for BigDecimal serialization |
| `test/ingredient_aggregator_test.rb` | Tests for freeform in aggregation |

## Not Changed

- **IngredientParser** — it correctly extracts "a few leaves" as the raw
  quantity string. The split happens downstream.
- **MarkdownImporter** — delegates to `split_quantity`, inherits the fix.
- **NutritionCalculator core** — already handles nil quantities correctly.
- **Grocery list / ShoppingListBuilder** — uses aggregator, inherits the fix.

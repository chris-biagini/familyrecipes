# Range-Aware Ingredient Scaling

GitHub issue: #247

## Problem

Ingredient ranges like "2-3 cups" lose their range semantics when scaled.
The current pipeline extracts only the high end for a single numeric value,
so 2× scaling produces "6 cups" instead of "4–6 cups". Hyphens in ranges
are also not upgraded to en-dashes for display.

## Decisions

- **Data model:** Native `quantity_low` / `quantity_high` decimal columns on
  `ingredients`, populated at import time. The existing `quantity` string column
  is retained as a raw fallback for non-numeric values ("a pinch").
- **Nutrition:** Uses `quantity_high` when present (preserves current high-end
  behavior).
- **Display:** En-dash (`–`) between range endpoints on recipe pages. Vulgar
  fraction glyphs for display (e.g., "1½–2¼ cups").
- **Storage & serialization:** ASCII fractions (`1/2`, not `½`), hyphens
  (`2-3`, not `2–3`). Vulgar glyphs in input are normalized to ASCII on import.
- **Scope:** Ingredient quantities only — instruction-text ranges are out of
  scope.

## Data Model

Add two columns to `ingredients`:

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `quantity_low` | decimal | yes | Single value, or low end of range |
| `quantity_high` | decimal | yes | High end of range (nil = not a range) |

Examples:

| Input | `quantity` | `quantity_low` | `quantity_high` | `unit` |
|-------|-----------|---------------|----------------|--------|
| `2-3 cups` | `2-3` | 2.0 | 3.0 | `cup` |
| `2 cups` | `2` | 2.0 | nil | `cup` |
| `½ cup` | `1/2` | 0.5 | nil | `cup` |
| `½-1 sticks` | `1/2-1` | 0.5 | 1.0 | `stick` |
| `Eggs, 2-3` | `2-3` | 2.0 | 3.0 | nil |
| `a pinch` | `a pinch` | nil | nil | nil |

A range is defined as: `quantity_high` is present.

## Parse & Import Pipeline

### `FamilyRecipes::Ingredient` (domain parser class)

New class method `parse_range(value_str)` → `[low, high]`:

- Splits on first hyphen or en-dash: `value_str.split(/[-–]/, 2)`
- Parses each side through `NumericParsing.parse_fraction` to resolve fractions
  and vulgar glyphs to floats.
- Returns `[low, nil]` for single values.
- Returns `[low, high]` for ranges where both sides parse and low ≤ high.
- If low > high (e.g., "1-1/2" misinterpreted as a range), treats as non-range:
  returns `[nil, nil]` and leaves the raw string for `quantity` column only.

The domain-level `FamilyRecipes::Ingredient` class is otherwise unchanged.
Its existing `numeric_value` (high-end extraction from raw strings) continues
to serve the parser pipeline and `IngredientAggregator`. Only the AR model
gets new columns.

### Normalization

Normalization happens in `MarkdownImporter#import_ingredient`, the sole
entry point for user-provided text, before calling `split_quantity`:
- Vulgar fraction glyphs → ASCII fractions (`½` → `1/2`, `¼` → `1/4`, etc.)
- En-dashes → hyphens (`–` → `-`)

A `normalize_quantity` helper on `FamilyRecipes::Ingredient` encapsulates
this. It is idempotent — safe to call on already-normalized strings.

### `MarkdownImporter#import_ingredient`

Normalizes, then splits, then parses range:

```ruby
normalized = FamilyRecipes::Ingredient.normalize_quantity(data[:quantity])
qty, unit = FamilyRecipes::Ingredient.split_quantity(normalized)
low, high = FamilyRecipes::Ingredient.parse_range(qty)

step.ingredients.create!(
  name: data[:name],
  quantity: qty,
  quantity_low: low,
  quantity_high: high,
  unit: unit,
  prep_note: data[:prep_note],
  position: position
)
```

### `RecipeWriteService`

Same flow for `_from_structure` variants — they delegate to
`MarkdownImporter` internals, so the change propagates. The graphical
editor round-trip works without JS changes: `toStructure()` produces a
`quantity` string like `"2-3 cups"`, which flows through the same
normalization and parsing in `import_ingredient`.

## Display & Rendering

### Server-side (`recipes_helper.rb`)

**`ingredient_data_attrs`** emits:
- `data-quantity-low` — always present when ingredient has numeric quantity
- `data-quantity-high` — present only for ranges
- `data-quantity-unit` / `data-quantity-unit-plural` — unchanged

Replaces the current `data-quantity-value`. The JS selector in
`recipe_state_controller.js` changes from `li[data-quantity-value]` to
`li[data-quantity-low]`.

For embedded recipes where `scale_factor != 1.0` (cross-reference multiplier
pre-applied server-side), `data-quantity-low` and `data-quantity-high` are
both pre-multiplied by the cross-reference multiplier, matching the current
behavior for `data-quantity-value`.

**`scaled_quantity_display`** handles ranges alongside the existing
single-value path. When the ingredient has `quantity_high`:

```ruby
def scaled_quantity_display(item, scale_factor)
  return item.quantity_display if !item.quantity_low || scale_factor == 1.0

  if item.quantity_high
    low = VulgarFractions.format(item.quantity_low * scale_factor, unit: item.quantity_unit)
    high = VulgarFractions.format(item.quantity_high * scale_factor, unit: item.quantity_unit)
    ["#{low}–#{high}", item.unit].compact.join(' ')
  else
    formatted = VulgarFractions.format(item.quantity_low * scale_factor, unit: item.quantity_unit)
    [formatted, item.unit].compact.join(' ')
  end
end
```

- Range at 1×: falls through to `quantity_display` → `"2–3 cups"`
- Range at 2×: `"4–6 cups"`
- Non-range: same as today but reads from `quantity_low`

### Client-side (`recipe_state_controller.js`)

`applyScale` reads `data-quantity-low` and optionally `data-quantity-high`:

```javascript
const low = parseFloat(li.dataset.quantityLow)
const high = li.dataset.quantityHigh ? parseFloat(li.dataset.quantityHigh) : null
const scaledLow = low * factor
const scaledHigh = high ? high * factor : null
const display = high
  ? `${formatVulgar(scaledLow, unit)}–${formatVulgar(scaledHigh, unit)}`
  : formatVulgar(scaledLow, unit)
```

Unit pluralization uses the high end when present (since it's always ≥ low).

## Serialization

### Decimal-to-ASCII-fraction conversion

New method `VulgarFractions.to_fraction_string(value)` converts a float to
the most readable ASCII fraction string:

- 0.5 → `"1/2"`
- 1.5 → `"1 1/2"`
- 0.25 → `"1/4"`
- 0.333... → `"1/3"`
- 2.0 → `"2"`
- 1.75 → `"1 3/4"`

Uses the same fraction table as the existing `VulgarFractions.format` (which
maps to Unicode glyphs), but outputs ASCII. Values that don't match a known
fraction round to two decimal places (e.g., 1.37 → `"1.37"`).

Both the Ruby and JavaScript implementations need this method. Ruby:
`VulgarFractions.to_fraction_string`. JS: `toFractionString` in
`app/javascript/utilities/vulgar_fractions.js` (alongside the existing
`formatVulgar` and `isVulgarSingular`). The JS side is used by the
serializer path in the graphical editor.

### `RecipeSerializer#build_ingredient_ir`

Reconstructs the full `quantity` string (including unit) for the IR hash,
matching the existing convention where the IR's `quantity` field is a
combined string like `"2-3 cups"`:

- If `quantity_low` and `quantity_high`:
  `"#{to_fraction(low)}-#{to_fraction(high)} #{unit}".strip`
- If `quantity_low` only: `"#{to_fraction(low)} #{unit}".strip`
- If neither (non-numeric): uses raw `quantity` and `unit` joined as today

### `AR Ingredient#quantity_display`

Updated to render with en-dash for ranges, vulgar fractions for display:

```ruby
def quantity_display
  return [quantity, unit].compact.join(' ').presence unless quantity_low

  if quantity_high
    low = VulgarFractions.format(quantity_low)
    high = VulgarFractions.format(quantity_high)
    ["#{low}–#{high}", unit].compact.join(' ')
  else
    [VulgarFractions.format(quantity_low), unit].compact.join(' ')
  end
end
```

- Range: `"½–1 stick"`
- Non-range: `"½ cup"`
- Non-numeric: falls back to raw `quantity`/`unit`

`VulgarFractions` remains range-unaware — callers assemble the en-dash
string from two separate `format` calls.

## Nutrition

`Ingredient#quantity_value` returns `(quantity_high || quantity_low)&.to_s`
— a string like `"3"` or `"0.5"`, preserving the interface consumed by
`IngredientAggregator` (which calls `Float()` on the result) and
`UnitResolver`. Trailing `.0` is stripped for whole numbers (e.g.,
`3.0.to_s` → `"3.0"` → stripped to `"3"`) to match the current behavior
where `numeric_value` returns `"3"` not `"3.0"`. A helper like
`format_decimal` handles this.

`NutritionCalculator` and `UnitResolver` are unchanged — they consume
`quantity_value` as before.

## Aggregation & Shopping

`IngredientAggregator.aggregate_amounts` sums `quantity_value` across
occurrences of the same ingredient. Since `quantity_value` returns the high
end (`quantity_high || quantity_low`), aggregation collapses ranges: "2-3
cups butter" + "1 cup butter" = "4 cups butter" (3+1). This is correct —
ranges cannot be meaningfully summed into a range. The shopping list
(`ShoppingListBuilder`) consumes aggregated `Quantity` values and is
unchanged.

## Migration

Sequential migration adds `quantity_low` and `quantity_high` columns, then
backfills from existing `quantity` strings using raw SQL with a lightweight
Ruby parsing stub defined inside the migration class (no application model
references per project conventions). The migration stub must handle vulgar
fraction glyphs in existing data (since normalization is being introduced
in this same change — existing rows were stored with whatever the user
typed).

## Edge Cases

- **Non-numeric quantities** ("a pinch", "some"): `quantity_low` and
  `quantity_high` are both nil. Display falls back to raw `quantity` string.
  Scaling is skipped (no `data-quantity-low` emitted).
- **Mixed number ambiguity** ("1-1/2"): `parse_range` checks low ≤ high. Since
  `1 > 0.5`, this fails the check and is treated as non-numeric (nil, nil).
  Users should write "1 1/2" for one-and-a-half.
- **Single-sided fractions** ("1/2-1 sticks"): Parsed correctly as
  low=0.5, high=1.0.
- **Unitless ranges** ("Eggs, 2-3"): Works — unit is nil, name
  singular/plural inflection handles display.
- **Vulgar glyph input** ("½ cup", "½–1 cup"): Normalized to ASCII at import.
  Display re-renders as vulgar glyphs.
- **Seed data:** No existing seed recipes contain ingredient ranges. Add at
  least one range example to a seed recipe for development and testing.

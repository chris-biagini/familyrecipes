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

### `FamilyRecipes::Ingredient`

New class method `parse_range(value_str)` → `[low, high]`:

- Splits on hyphen or en-dash: `/[-–]/`
- Parses each side through `NumericParsing.parse_fraction` to resolve fractions
  and vulgar glyphs to floats.
- Returns `[low, nil]` for single values.
- Returns `[low, high]` for ranges where both sides parse and low ≤ high.
- If low > high (e.g., "1-1/2" misinterpreted as a range), treats as non-range:
  returns `[nil, nil]` and leaves the raw string for `quantity` column only.

### Normalization

`split_quantity` normalizes the raw value string before storage:
- Vulgar fraction glyphs → ASCII fractions (`½` → `1/2`, `¼` → `1/4`, etc.)
- En-dashes → hyphens (`–` → `-`)

This ensures `quantity` column always contains plain ASCII.

### `MarkdownImporter#import_ingredient`

After `split_quantity`, calls `parse_range` on the value portion:

```ruby
qty, unit = FamilyRecipes::Ingredient.split_quantity(data[:quantity])
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
`MarkdownImporter` internals, so the change propagates.

## Display & Rendering

### Server-side (`recipes_helper.rb`)

**`ingredient_data_attrs`** emits:
- `data-quantity-low` — always present when ingredient has numeric quantity
- `data-quantity-high` — present only for ranges
- `data-quantity-unit` / `data-quantity-unit-plural` — unchanged

Replaces the current `data-quantity-value`.

**`scaled_quantity_display`** renders:
- Range at 1×: `"2–3 cups"` (en-dash, vulgar fractions for each side)
- Range at 2×: `"4–6 cups"`
- Non-range: same as today but reads from `quantity_low` column

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

### `RecipeSerializer#build_ingredient_ir`

Reconstructs the `quantity` string from numeric columns:
- If `quantity_low` and `quantity_high`: `"#{format(low)}-#{format(high)} #{unit}"`
- If `quantity_low` only: `"#{format(low)} #{unit}"`
- If neither (non-numeric): uses raw `quantity` and `unit` as-is

Format uses ASCII fractions via `VulgarFractions.to_ascii_fraction` or similar
(e.g., 0.5 → `"1/2"`, 1.5 → `"1 1/2"`). Hyphens for ranges.

### `AR Ingredient#quantity_display`

Updated to render with en-dash for ranges, vulgar fractions for display:
- Range: `"½–1 stick"`
- Non-range: `"½ cup"`

Falls back to raw `quantity`/`unit` when `quantity_low` is nil.

## Nutrition

`Ingredient#quantity_value` returns `quantity_high || quantity_low` (as a
string, preserving the interface). This is a simplification of the current
`FamilyRecipes::Ingredient.numeric_value` string parsing — the range
extraction is now done at import time.

`NutritionCalculator` and `UnitResolver` are unchanged — they consume
`quantity_value` as before.

## Migration

Sequential migration adds `quantity_low` and `quantity_high` columns, then
backfills from existing `quantity` strings using raw SQL with a lightweight
Ruby parsing stub defined inside the migration class (no application model
references per project conventions).

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

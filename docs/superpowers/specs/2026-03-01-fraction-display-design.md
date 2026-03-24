# Fraction Display Design (GH #120)

## Problem

Quantities display inconsistently across the parse → render → scale pipeline:

1. **Scaling bug**: `12.5 g` (Pizza Dough) renders correctly on initial load, but scaling by 1x converts it to `12½ g` because `formatVulgar` doesn't know the unit is metric.
2. **Input gap**: The parser doesn't accept vulgar fraction glyphs (`½`, `¼`) in recipe markdown — only decimals and ASCII fractions (`1/2`).
3. **No unit-aware formatting**: `VulgarFractions.format` always produces glyphs when possible, regardless of whether the unit is metric (where decimals are more natural).

## Decisions

- **Metric units stay decimal; everything else gets vulgar fractions.** The metric set is `g`, `kg`, `ml`, `l` — a small, stable list. US customary (`cup`, `tbsp`, `tsp`, `oz`, `lb`, `pint`, `quart`, `gallon`), unitless quantities, and informal units (`cloves`, `stalks`) all get vulgar fractions.
- **Accept all input forms; store originals.** `0.5`, `1/2`, and `½` all parse to `0.5` for numeric operations, but the DB `quantity` column keeps the string as authored.
- **Format on initial server render.** `scaled_quantity_display` applies unit-aware formatting so there's no flash from raw decimal → vulgar glyph when JS loads.
- **Extend VulgarFractions rather than creating a new class.** Add a `unit:` keyword to `format()`. Metric units bypass glyph lookup and format as decimal.

## Architecture

### Unit Classification

```ruby
# In VulgarFractions
METRIC_UNITS = %w[g kg ml l].to_set.freeze

def metric_unit?(unit)
  METRIC_UNITS.include?(unit&.downcase)
end
```

Inverted logic: metric is the deny-list for vulgar formatting. Everything not in this set (including `nil` for unitless) gets vulgar fractions.

### VulgarFractions.format(value, unit: nil)

```ruby
def format(value, unit: nil)
  return format_decimal(value) if metric_unit?(unit)
  # existing glyph logic unchanged
end
```

JS mirror: `formatVulgar(value, unit = null)` — same `METRIC_UNITS` set, same early return.

### Input Parsing

`NumericParsing.parse_fraction` gains vulgar glyph preprocessing:

```ruby
VULGAR_TO_DECIMAL = {
  '½' => 0.5, '⅓' => 1/3r, '⅔' => 2/3r, '¼' => 0.25,
  '¾' => 0.75, '⅛' => 0.125, '⅜' => 3/8r, '⅝' => 5/8r, '⅞' => 7/8r
}.freeze
```

Before `Float()`, scan for vulgar glyphs. Handle mixed numbers (`2½` → `2.5`).

### Server-Side Rendering

`scaled_quantity_display` passes the normalized unit to `VulgarFractions.format`:

```ruby
def scaled_quantity_display(item, scale_factor)
  return format_quantity(item) if scale_factor == 1.0 || !item.quantity_value
  scaled = item.quantity_value.to_f * scale_factor
  unit = item.quantity_unit
  formatted = VulgarFractions.format(scaled, unit: unit)
  [formatted, item.unit].compact.join(' ')
end

def format_quantity(item)
  return unless item.quantity_value
  formatted = VulgarFractions.format(item.quantity_value.to_f, unit: item.quantity_unit)
  [formatted, item.unit].compact.join(' ')
end
```

### Client-Side Scaling

`applyScale` passes `unitSingular` to `formatVulgar`:

```javascript
const pretty = formatVulgar(scaled, unitSingular)
```

### Data Flow

```
Markdown "½ cup"
  → IngredientParser: { name: ..., quantity: "½ cup" }
  → MarkdownImporter.split_quantity: quantity="½", unit="cup"
  → DB stores: quantity="½", unit="cup"
  → quantity_value: NumericParsing.parse_fraction("½") → 0.5
  → quantity_unit: Inflector.normalize_unit("cup") → "cup"
  → Server render: VulgarFractions.format(0.5, unit: "cup") → "½"
  → HTML: "½ cup" with data-quantity-value="0.5"
  → JS scale by 2: formatVulgar(1.0, "cup") → "1"
  → Display: "1 cup"

Markdown "12.5 g"
  → DB stores: quantity="12.5", unit="g"
  → Server render: VulgarFractions.format(12.5, unit: "g") → "12.5"
  → HTML: "12.5 g" with data-quantity-value="12.5"
  → JS scale by 2: formatVulgar(25.0, "g") → "25"
  → Display: "25 g"
```

## Files Changed

| File | Change |
|------|--------|
| `lib/familyrecipes/vulgar_fractions.rb` | Add `METRIC_UNITS`, `metric_unit?`, `unit:` keyword on `format` |
| `app/javascript/utilities/vulgar_fractions.js` | Add `METRIC_UNITS`, `unit` param on `formatVulgar` |
| `lib/familyrecipes/numeric_parsing.rb` | Add vulgar glyph → decimal preprocessing |
| `app/helpers/recipes_helper.rb` | Unit-aware formatting in `scaled_quantity_display`, new `format_quantity` |
| `app/javascript/controllers/recipe_state_controller.js` | Pass unit to `formatVulgar` calls |
| `test/vulgar_fractions_test.rb` | Unit-aware formatting tests |
| `test/numeric_parsing_test.rb` | Vulgar glyph input tests |
| `test/helpers/recipes_helper_test.rb` | Server-side formatting tests |

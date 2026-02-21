# Nutrition Labels and Yield Inflection

## Problem

The nutrition table header currently shows a generic "Per Serving (1/4)" label. With Makes/Serves front matter now on most recipes, we can show much richer labels like "Per Cookie" and "Per Serving (6 cookies)". The yield line ("Makes: 12 pancakes") also doesn't inflect when scaled — "Makes: 1 pancakes" reads wrong.

## Design

### Nutrition table column logic

The table adapts its columns based on available front matter:

| Makes | Serves | Columns |
|---|---|---|
| 24 cookies | 4 | Per Cookie - Per Serving (6 cookies) - Total |
| 2 pizzas | 4 | Per Pizza - Per Serving (1 pizza) - Total |
| 1 loaf | 4 | Per Serving (1/4 loaf) - Per Loaf |
| 12 bagels | — | Per Bagel - Total |
| 1 loaf | — | Per Loaf |
| — | 4 | Per Serving - Total |
| — | — | Total |

Key rules:
- **Makes qty = 1**: relabel "Total" as "Per [Unit]" (no redundant column). If Serves exists, add "Per Serving (fraction unit)" column.
- **Makes qty > 1**: show "Per [Unit]" column. If Serves exists, add "Per Serving (N units)" with units-per-serving calculated as makes_quantity / serves. Always show "Total" last.
- **No Makes, just Serves**: "Per Serving" + "Total".
- **Neither**: "Total" only.

No filtering by unit type — "Per Cup", "Per Pound" are valid. "Per mL" is rare and harmless.

### Per Serving parenthetical

When both Makes and Serves exist, "Per Serving" gets a parenthetical showing units-per-serving: `(6 cookies)`, `(1 pizza)`, `(1/4 loaf)`. The count is formatted with vulgar fractions when possible and inflected singular/plural.

### Inflection rules

Singular when:
- Exactly 1 (integer)
- A pure vulgar fraction < 1 (1/2, 1/3, 1/4, etc.) — these render as a single glyph and read singular in English

Plural when:
- Any decimal (0.5, 1.0, 0.25)
- Any mixed number (1 1/2, 1.5)
- Any integer > 1 or 0

Uses existing `Inflector.singular` / `Inflector.plural` which already handle irregulars (loaf/loaves, leaf/leaves) and standard rules (cookie/cookies, berry/berries).

### Vulgar fraction formatting

Recognized fractions: 1/2, 1/3, 2/3, 1/4, 3/4, 1/8, 3/8, 5/8, 7/8.

Implemented in both Ruby (nutrition headers) and JS (yield line scaling) as a simple value-to-glyph lookup with float tolerance. Values that don't match fall back to decimal display (and get plural nouns).

Mixed numbers: integer part + fraction glyph (e.g., 1.5 -> "1 1/2"). These are always plural.

### Yield line scaling markup

Current: `Makes <span class="scalable">12</span> pancakes`

New:
```html
Makes <span class="yield"
  data-base-value="12"
  data-unit-singular="pancake"
  data-unit-plural="pancakes">
  <span class="scalable">12</span> pancakes
</span>
```

JS scaling handler for `.yield` spans:
1. Compute scaled value
2. Format number (integer or vulgar fraction)
3. Pick singular or plural form based on rules above
4. Update innerHTML

Serves line has no noun — just the existing scalable number span, unchanged.

### Scaling behavior

Only the Total column scales. Per-unit and per-serving are fixed reference points — per-cookie nutrition doesn't change when you double the recipe.

## Files affected

- `lib/familyrecipes/inflector.rb` — refine singular threshold for vulgar fractions
- `lib/familyrecipes/nutrition_calculator.rb` — expose per-unit values, unit metadata on Result
- `lib/familyrecipes/scalable_number_preprocessor.rb` — new yield-with-unit wrapper method
- `templates/web/recipe-template.html.erb` — dynamic column headers/cells, yield wrapper markup
- `resources/web/recipe-state-manager.js` — yield inflection during scaling, vulgar fraction formatting
- New: vulgar fraction helper (Ruby module, small enough to inline or add to an existing helper)

## Not changed

- Recipe .md file format
- Quick Bites
- Grocery page
- PDF templates
- Per-unit/per-serving columns do not scale (only Total)

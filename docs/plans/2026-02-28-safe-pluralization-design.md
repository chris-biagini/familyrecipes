# Safe Pluralization Design

Addresses GitHub issue #113 (pluralization across scaling, aggregation, and display).

## Problem

Pluralization touches four surfaces — recipe scaling, yield line display, grocery
list aggregation, and ingredient catalog matching — and the current architecture
uses a single rule engine for all of them. The rule engine produces correct
results for common English words but generates nonsense for edge cases:
"oreganoes", "tomatoeses", "smoked paprikas". We've been whack-a-moling these
bugs by growing the UNCOUNTABLE and IRREGULAR sets, but every new ingredient is a
potential regression.

The root issue is that **display and matching have different risk profiles**, but
the code treats them identically.

### Harm taxonomy (from user)

1. **Wrong pluralization** is the worst offense. "Oreganoes" or "Egg yolk" (when
   it should be "Egg yolks") makes the app feel broken. The system should avoid
   this even at the expense of other features.
2. **Missing pluralization** is annoying but forgivable. "5 cup" instead of
   "5 cups" is a paper cut, especially for units and portions we can anticipate.
3. **Inconsistent names** is the least harmful. Showing "Egg, 2" (failing to
   adjust the name to "Eggs") is fine and the first thing to let slide.

### Current bugs

| Surface | Example | Root cause |
|---------|---------|------------|
| Grocery list units | "Bread (4 slice)", "Garlic (12 clove + 40 g)" | Units are stored singular, never re-pluralized for display |
| Recipe scaling (fractions) | "0.5 cups" instead of "½ cup" | JS uses `=== 1` instead of `isVulgarSingular()` for ingredient lines |
| Rule engine edge cases | "oreganoes", "paprikas" | Consonant-o and generic-s rules fire on words that should be uncountable |
| Growing special-case lists | 33 UNCOUNTABLE entries, 4 IRREGULAR entries | Every new ingredient requires triage into the right list |

## Design principle

**Allowlists for display, rules for matching, passthrough for everything else.**

- A word in the allowlist can be safely pluralized/singularized for user-visible
  output.
- A word NOT in the allowlist passes through unchanged — the user's original text
  is never mangled.
- The existing rule engine stays available for internal catalog matching, where a
  false "oreganoes" lookup key is harmless (it simply won't match anything).

## History

This design supersedes:
- `2026-02-20-unified-pluralization-design.md` — introduced the Inflector but
  also migrated YAML keys to singular canonical form, which caused grocery bugs.
- `2026-02-21-revert-grocery-pluralization-design.md` — reverted the YAML
  migration and removed `name_for_grocery()`, but left the rule engine as the
  sole pluralization mechanism.

The current design (GH#113) is the "Phase 2" deferred by the revert design.

## Architecture

### KNOWN_PLURALS: the display-safe allowlist

A single Ruby `Hash` mapping `singular => plural`, covering three domains:

**Units** — the finite set of measurement words the parser recognizes:
```
cup/cups, clove/cloves, slice/slices, can/cans, bunch/bunches,
spoonful/spoonfuls, head/heads, stalk/stalks, sprig/sprigs
```

**Yield nouns** — words that follow "Makes:" in front matter:
```
cookie/cookies, loaf/loaves, roll/rolls, pizza/pizzas, taco/tacos,
pancake/pancakes, bagel/bagels, biscuit/biscuits, gougère/gougères,
quesadilla/quesadillas, pizzelle/pizzelle
```

**Ingredient names** — common countable ingredients:
```
egg/eggs, onion/onions, lime/limes, pepper/peppers, tomato/tomatoes,
carrot/carrots, walnut/walnuts, olive/olives, lentil/lentils,
tortilla/tortillas, bean/beans
```

The inverted map (`plural => singular`) is auto-computed. Both directions are
O(1) lookups.

### What replaces what

| Old | New |
|-----|-----|
| UNCOUNTABLE set (33 entries) | Dropped. Words not in KNOWN_PLURALS pass through unchanged. |
| IRREGULAR_SINGULAR_TO_PLURAL (4 entries) | Subsumed by KNOWN_PLURALS. |
| IRREGULAR_PLURAL_TO_SINGULAR | Subsumed by inverted KNOWN_PLURALS. |
| `singular()` / `plural()` (rule-based) | `safe_singular()` / `safe_plural()` (allowlist-only for display). Rules stay private for matching. |
| ABBREVIATIONS | Stays as-is. Abbreviated units never pluralize. |

### Inflector public API

```ruby
# Display-safe: returns word unchanged if not in KNOWN_PLURALS
Inflector.safe_plural(word)
Inflector.safe_singular(word)

# Unit display: abbreviated units pass through, others use safe_plural
Inflector.unit_display(unit, count)

# Ingredient name display: pluralizes/singularizes last word if known
Inflector.display_name(name, count)

# Matching only (rules-based, never shown to users)
Inflector.ingredient_variants(name)
Inflector.normalize_unit(raw_unit)
```

The old `singular()` and `plural()` methods become private, used only by
`ingredient_variants()` for fuzzy catalog matching.

### KNOWN_PLURALS in JavaScript

The JS never receives the full map. Instead, the server pre-computes the correct
singular and plural forms per HTML element:

- Ingredient `<li>`: `data-quantity-unit` / `data-quantity-unit-plural` (already
  exists), plus new `data-name-singular` / `data-name-plural` for known-safe
  ingredient names.
- Yield `.yield` span: `data-unit-singular` / `data-unit-plural` (already
  exists).

No pluralization logic runs in JavaScript — it only picks between pre-computed
forms based on the scaled quantity.

## Changes by surface

### 1. Grocery list unit display

`ShoppingListBuilder#serialize_amounts` calls `Inflector.unit_display` to
pluralize units before sending JSON:

```ruby
def serialize_amounts(amounts)
  amounts.compact.map { |q| [q.value.to_f, display_unit(q)] }
end

def display_unit(quantity)
  return quantity.unit if quantity.unit.nil?
  FamilyRecipes::Inflector.unit_display(quantity.unit, quantity.value)
end
```

Result: `[5.0, "cups"]` instead of `[5.0, "cup"]`. The JS `formatAmounts()`
needs no changes.

### 2. Grocery list ingredient names

No change. The catalog's canonical form is displayed as-is. If the catalog says
"Eggs", the grocery list says "Eggs" regardless of quantity. This matches the
user's preference: inconsistent names are the least harmful issue, and the
catalog's natural display form is what users expect on a shopping list.

### 3. Recipe scaling — ingredient lines

**Fix fraction singular check.** Use `isVulgarSingular()` (already imported)
instead of `=== 1`. This matches the yield-line scaling behavior.

**Add ingredient name adjustment for known-safe words.** The `_step.html.erb`
partial emits `data-name-singular` / `data-name-plural` when the ingredient
name's last word is in KNOWN_PLURALS. The JS picks the correct form based on
scaled quantity.

**Replace `<b>` with `<span>` for ingredient names.** The `<b>` tag was a legacy
decision. Using `<span class="ingredient-name">` (or similar) gives cleaner
styling hooks. Update CSS to compensate.

Example HTML:
```html
<li data-quantity-value="1"
    data-quantity-unit="cup" data-quantity-unit-plural="cups"
    data-name-singular="Egg" data-name-plural="Eggs">
  <span class="ingredient-name">Egg</span>,
  <span class="quantity">1</span>
</li>
```

Scaled 2x: "Eggs, 2". Scaled ½x: "Egg, ½".

For unknown names (not in KNOWN_PLURALS), no name data attributes are emitted and
the JS leaves the name unchanged. "Oregano, 2 tsp" stays "Oregano, 2 tsp".

### 4. Recipe scaling — yield lines

Add a `.yield-unit` span to hold the unit text, replacing the current bare text
node:

```html
<span class="yield" data-base-value="12"
      data-unit-singular="roll" data-unit-plural="rolls">
  <span class="scalable" data-base-value="12" data-original-text="12">12</span>
  <span class="yield-unit"> rolls</span>
</span>
```

The JS updates `.yield-unit`'s `textContent` instead of manipulating
`nextSibling` text nodes. Simpler and more robust.

### 5. Recipe scaling — instruction numbers

No change. These are bare numbers with no unit context. The `.scalable` pattern
is already clean.

### 6. HTML rationalization

Three scaling patterns, each with a clear role:

| Element | Data attributes | JS behavior |
|---------|----------------|-------------|
| Ingredient `<li>` | `data-quantity-value`, `data-quantity-unit`, `data-quantity-unit-plural`, optional `data-name-singular`/`data-name-plural` | Scale number, pick unit form, optionally pick name form |
| Yield `.yield` | `data-base-value`, `data-unit-singular`, `data-unit-plural` | Scale inner `.scalable`, update `.yield-unit` span |
| Instruction `.scalable` | `data-base-value`, `data-original-text` | Scale number only |

## What stays the same

- Rule-based fuzzy matching for catalog lookups (`ingredient_variants`)
- `normalize_unit` for parsing
- Grocery list ingredient name display (catalog canonical form)
- Nutrition calculation flow
- ABBREVIATIONS constant
- `ScalableNumberPreprocessor` for instruction numbers

## What gets dropped

- UNCOUNTABLE set
- IRREGULAR_SINGULAR_TO_PLURAL / IRREGULAR_PLURAL_TO_SINGULAR
- Public `singular()` / `plural()` methods (become private, match-only)
- `<b>` tag for ingredient names (replaced by `<span>`)
- Text node manipulation for yield unit display

## Migration path

The KNOWN_PLURALS map starts with ~30-40 entries covering all ingredients, units,
and yield nouns currently in the recipe database. When users add new ingredients
or recipes with countable nouns, the nouns pass through unchanged until someone
adds them to the allowlist. This is the correct default — showing "2 persimmon"
is better than showing "2 persimmons" if we're not sure, and far better than
"2 persimmones".

## File changes

### Ruby
- `lib/familyrecipes/inflector.rb` — KNOWN_PLURALS, new API, rules become private
- `lib/familyrecipes/scalable_number_preprocessor.rb` — `.yield-unit` span
- `app/services/shopping_list_builder.rb` — unit display in `serialize_amounts`
- `app/views/recipes/_step.html.erb` — name data attributes, `<b>` → `<span>`
- `app/views/recipes/show.html.erb` — yield line markup if needed
- `app/helpers/recipes_helper.rb` — helper for name data attributes

### JavaScript
- `app/javascript/controllers/recipe_state_controller.js` — `isVulgarSingular`
  for ingredients, `.yield-unit` span, ingredient name adjustment

### CSS
- `app/assets/stylesheets/` — replace `b` selector with `.ingredient-name`

### Tests
- `test/inflector_test.rb` — update for new API, KNOWN_PLURALS
- `test/services/shopping_list_builder_test.rb` — unit display assertions
- `test/lib/scalable_number_preprocessor_test.rb` — `.yield-unit` span

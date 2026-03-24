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

### Harm taxonomy

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
| UNCOUNTABLE set (33 entries) | Dropped entirely. Words not in KNOWN_PLURALS pass through unchanged. |
| IRREGULAR_SINGULAR_TO_PLURAL (4 entries) | Dropped entirely. Subsumed by KNOWN_PLURALS for display. |
| IRREGULAR_PLURAL_TO_SINGULAR | Dropped entirely. Subsumed by inverted KNOWN_PLURALS. |
| `uncountable?()` public method | Dropped. No external callers. |
| `singular()` / `plural()` (rule-based) | `safe_singular()` / `safe_plural()` (allowlist-only for display). Rules stay private for matching. |
| ABBREVIATIONS | Stays as-is. Abbreviated units never pluralize. |

### Why UNCOUNTABLE and IRREGULAR can be dropped entirely

The private rule engine (used only by `ingredient_variants` and
`normalize_unit`) no longer checks UNCOUNTABLE or IRREGULAR. This means:

- `ingredient_variants('Butter')` returns `['Butters']` instead of `[]`.
  The spurious variant is harmless — it's a lookup key, not display text.
  If nothing in the catalog is called "Butters", the key doesn't match.
- `ingredient_variants('Leaf')` returns `['Leafs']` instead of `['Leaves']`.
  The imperfect variant won't match "Leaves" in the catalog, but that's
  acceptable — the direct lookup for "Leaf" handles the common case.

All three callers of `ingredient_variants` were analyzed:

| Caller | Impact of spurious variants |
|--------|---------------------------|
| `BuildValidator` (once per seed) | Harmless — widens the "known" set slightly |
| `IngredientCatalog.lookup_for` (once per request) | Harmless — extra keys point to real entries |
| `IngredientRows` (per ingredient per request) | Harmless — direct lookup succeeds first |

The UNCOUNTABLE set doesn't scale: you can't anticipate every uncountable
ingredient in English, and the list was growing with every new ingredient.
Dropping it eliminates the maintenance burden entirely.

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
`ingredient_variants()` for fuzzy catalog matching. The private rules run
unguarded — no UNCOUNTABLE or IRREGULAR checks.

### KNOWN_PLURALS in JavaScript

The JS never receives the full map. Instead, the server pre-computes the correct
singular and plural forms per HTML element:

- Ingredient `<li>`: `data-quantity-unit` / `data-quantity-unit-plural` (already
  exists), plus new `data-name-singular` / `data-name-plural` for known-safe
  **unitless** ingredient names only.
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
  return quantity.unit unless quantity.unit
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
instead of `=== 1`. This matches the yield-line scaling behavior. Also use
`formatVulgar()` for consistent number display.

**Add ingredient name adjustment for known-safe unitless words.** The
`_step.html.erb` partial emits `data-name-singular` / `data-name-plural` only
when the ingredient has no unit and the name's last word is in KNOWN_PLURALS.
The JS picks the correct form based on scaled quantity.

Name data attributes are restricted to unitless ingredients because unit-bearing
ingredients describe a measured amount, not a count: "Eggs, 2 cups" scaled to
½x should stay "Eggs, 1 cup", not become "Egg, 1 cup".

**Keep `<b>` tag, add class.** Replace `<b>` with `<b class="ingredient-name">`
to add a JS selector hook while preserving semantic HTML. No CSS change needed.

**Use `tag.attributes` for data attributes.** Replace the inline
`ERB::Util.html_escape` + `.html_safe` pattern with a `RecipesHelper` method
that returns all ingredient data attributes via `tag.attributes`. This eliminates
`.html_safe` calls entirely — `tag.attributes` handles escaping internally.

```ruby
# RecipesHelper
def ingredient_data_attrs(item)
  attrs = {}
  return tag.attributes(attrs) unless item.quantity_value

  attrs[:'data-quantity-value'] = item.quantity_value
  attrs[:'data-quantity-unit'] = item.quantity_unit
  if item.quantity_unit
    attrs[:'data-quantity-unit-plural'] =
      FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2)
  end

  unless item.quantity_unit
    singular = FamilyRecipes::Inflector.display_name(item.name, 1)
    plural = FamilyRecipes::Inflector.display_name(item.name, 2)
    if singular != plural
      attrs[:'data-name-singular'] = singular
      attrs[:'data-name-plural'] = plural
    end
  end

  tag.attributes(attrs)
end
```

Template simplifies to:
```erb
<li <%= ingredient_data_attrs(item) %>>
  <b class="ingredient-name"><%= item.name %></b>...
</li>
```

**Initial render uses catalog name as-is.** The server does not call
`display_name` for the initial text content. If the catalog says "Eggs" and the
recipe quantity is 1, the initial render shows "Eggs, 1". After a scale+reset
cycle, the JS might show "Egg, 1". This is the "inconsistent names" tier — the
least harmful, and the simplest approach.

Example HTML (unitless ingredient):
```html
<li data-quantity-value="1"
    data-name-singular="Egg" data-name-plural="Eggs">
  <b class="ingredient-name">Egg</b>, <span class="quantity">1</span>
</li>
```

Example HTML (ingredient with unit — no name data attrs):
```html
<li data-quantity-value="3"
    data-quantity-unit="cup" data-quantity-unit-plural="cups">
  <b class="ingredient-name">Flour</b>, <span class="quantity">3 cups</span>
</li>
```

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
| Ingredient `<li>` | `data-quantity-value`, `data-quantity-unit`, `data-quantity-unit-plural`, optional `data-name-singular`/`data-name-plural` (unitless only) | Scale number, pick unit form, optionally pick name form |
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

- UNCOUNTABLE set (33 entries)
- IRREGULAR_SINGULAR_TO_PLURAL / IRREGULAR_PLURAL_TO_SINGULAR (4 entries)
- `uncountable?` public method
- Public `singular()` / `plural()` methods (become private, match-only)
- `.html_safe` call for unit-plural data attribute (replaced by `tag.attributes`)
- Text node manipulation for yield unit display

## What gets added

- KNOWN_PLURALS / KNOWN_SINGULARS constants (~35 entries)
- `safe_plural`, `safe_singular`, `display_name` public methods
- `ingredient_data_attrs` helper (replaces inline attribute building)
- `.ingredient-name` class on `<b>` tags
- `.yield-unit` span in yield markup

## Migration path

The KNOWN_PLURALS map starts with ~30-40 entries covering all ingredients, units,
and yield nouns currently in the recipe database. When users add new ingredients
or recipes with countable nouns, the nouns pass through unchanged until someone
adds them to the allowlist. This is the correct default — showing "2 persimmon"
is better than showing "2 persimmons" if we're not sure, and far better than
"2 persimmones".

Adding a new word to KNOWN_PLURALS requires re-running nutrition calculation for
affected recipes (or `rake db:seed`) to update stored `makes_unit_singular` /
`makes_unit_plural` in nutrition_data JSON.

## File changes

### Ruby
- `lib/familyrecipes/inflector.rb` — KNOWN_PLURALS, new API, rules become private, drop UNCOUNTABLE/IRREGULAR
- `lib/familyrecipes/scalable_number_preprocessor.rb` — `.yield-unit` span
- `lib/familyrecipes/nutrition_calculator.rb` — `safe_singular`/`safe_plural` calls
- `app/services/shopping_list_builder.rb` — unit display in `serialize_amounts`
- `app/views/recipes/_step.html.erb` — `ingredient_data_attrs` helper, `<b class="ingredient-name">`
- `app/helpers/recipes_helper.rb` — `ingredient_data_attrs` helper method
- `config/html_safe_allowlist.yml` — remove line 19 entry (replaced by `tag.attributes`)

### JavaScript
- `app/javascript/controllers/recipe_state_controller.js` — `isVulgarSingular`
  for ingredients, `formatVulgar` for number display, `.yield-unit` span,
  ingredient name adjustment

### CSS
- No changes needed. `<b>` is bold natively; `.ingredient-name` class is for JS only.

### Tests
- `test/inflector_test.rb` — update for new API, KNOWN_PLURALS, remove UNCOUNTABLE/IRREGULAR tests
- `test/services/shopping_list_builder_test.rb` — unit display assertions
- `test/lib/scalable_number_preprocessor_test.rb` — `.yield-unit` span

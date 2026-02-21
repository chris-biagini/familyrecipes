# Unified Pluralization Design

> **Note:** The singular-canonical YAML key decision was reversed on 2026-02-21.
> See `2026-02-21-revert-grocery-pluralization-design.md` for rationale.
> YAML keys now use natural display forms (the pre-migration convention).

Addresses GitHub issues #54 (localization scaffolding) and #55 (unify pluralization handling).

## Problem

Pluralization is handled by three separate, overlapping systems:

1. **`Ingredient` class** -- `IRREGULAR_PLURALS/SINGULARS` (only leaf/leaves), `UNIT_NORMALIZATIONS` (~20 hardcoded plural-to-singular unit mappings), `pluralize`/`singularize` class methods (regex rules).
2. **`NutritionEntryHelpers`** -- `SINGULARIZE_MAP` (overlapping + unique entries like cookie, patty, ball), `singularize_simple` (nearly identical regex to #1).
3. **`build_alias_map`** in `familyrecipes.rb` -- calls `Ingredient.singularize` to generate singular aliases for grocery items so recipe inputs like "carrot" match canonical "Carrots".

After recipe scaling, units display as "4 clove" and "2 cup" (always singular). Grocery aggregation has the same bug: "12 clove + 3 cup".

## Decisions

### Canonical form: English singular, Title Case

Internal keys use the English singular form: `Carrot`, `Egg`, `Garlic`, `Flour (all-purpose)`. This aligns with i18n standards (CLDR, ICU MessageFormat, Rails i18n) where the singular/lemma is the dictionary headword and base key. Uncountable and qualified names are already singular and don't change.

Rationale: every major i18n framework uses singular as the base form. English has 2 plural categories (one, other); French has 3; Russian has 4; Arabic has 6. All store the singular and derive other forms. Migrating from singular canonical to a UUID-based key later is trivial if needed.

### Two YAML files, shared key space

`grocery-info.yaml` and `nutrition-data.yaml` remain separate files. They serve different edit patterns (human-edited aisle layout vs. tool-edited scientific data) but share the same canonical key space. Both use Title Case singular keys.

### Grocery consolidation stays in grocery-info.yaml

Aliases like "Egg yolk -> Egg" and "Egg white -> Egg" are grocery-specific consolidation rules (different ingredients, same purchase). These stay in `grocery-info.yaml` as aliases. The Inflector handles singular/plural variants, so plural-form aliases are removed.

### Centralized Inflector module

One module replaces all three existing systems. It owns:
- Singular <-> plural morphology (regex rules + irregulars table)
- Countability (uncountable words like "butter", "flour" don't pluralize)
- Unit normalization (abbreviation rules: gram->g, tablespoon->tbsp; full-word units pluralize normally)
- Context-aware display (grocery list = always plural for countables; recipe scaling = quantity-aware)

### Pre-computed data attributes for JavaScript

Ruby Inflector pre-computes both singular and plural unit forms at build time. HTML emits `data-quantity-unit` (singular) and `data-quantity-unit-plural` (plural). JavaScript picks between them based on scaled quantity. No pluralization logic in JS.

## Inflector API

```ruby
module FamilyRecipes
  module Inflector
    # Data constants
    IRREGULARS        # { 'leaf' => 'leaves', 'loaf' => 'loaves', ... }
    UNCOUNTABLE       # Set['asparagus', 'basil', 'butter', 'flour', ...]
    ABBREVIATIONS     # { 'g' => 'g', 'gram' => 'g', 'tbsp' => 'tbsp', ... }

    # Core morphology
    def self.singular(word)         # "carrots" -> "carrot", "leaves" -> "leaf"
    def self.plural(word)           # "carrot" -> "carrots", "leaf" -> "leaves"
    def self.uncountable?(word)     # "butter" -> true, "carrot" -> false

    # Context-aware display
    def self.unit_display(unit, count)        # "cup", 2 -> "cups"  |  "g", 100 -> "g"
    def self.name_for_grocery(name)           # "Carrot" -> "Carrots"  |  "Butter" -> "Butter"
    def self.name_for_count(name, count)      # "carrot", 1 -> "carrot"  |  "carrot", 2 -> "carrots"
  end
end
```

Data (irregulars, uncountables, abbreviations) is stored as Ruby constants. These can be extracted to locale YAML files when localization is added, without changing the API.

## YAML migrations

### grocery-info.yaml

~20 countable-plural keys become singular:

- `Apples` -> `Apple`
- `Carrots` -> `Carrot`
- `Eggs` -> `Egg` (with aliases: Egg yolk, Egg white)
- `Onions` -> `Onion`
- etc.

Alias cleanup:
- Remove plural-form aliases (Inflector handles these)
- Remove false synonyms (Dark chocolate != Chocolate)
- Keep grocery consolidation (Egg yolk -> Egg)
- Keep true synonyms (Parmesan cheese -> Parmesan)

### nutrition-data.yaml

~5-6 key renames to match: `Carrots` -> `Carrot`, `Eggs` -> `Egg`, `Onions` -> `Onion`, `Red bell peppers` -> `Red bell pepper`, `Lemons` -> `Lemon`, `Limes` -> `Lime`.

## File changes

### New
- `lib/familyrecipes/inflector.rb`
- `test/inflector_test.rb`

### Modified (Ruby)
- `lib/familyrecipes/ingredient.rb` -- Remove IRREGULAR_PLURALS, IRREGULAR_SINGULARS, UNIT_NORMALIZATIONS, self.pluralize, self.singularize. quantity_unit delegates to Inflector.
- `lib/familyrecipes/nutrition_entry_helpers.rb` -- Remove SINGULARIZE_MAP and singularize_simple. Use Inflector.singular.
- `lib/familyrecipes.rb` -- build_alias_map uses Inflector.plural (instead of Ingredient.singularize). Require inflector.
- `lib/familyrecipes/site_generator.rb` -- Pass pre-computed display forms to templates.

### Modified (templates)
- `recipe-template.html.erb` -- Emit data-quantity-unit-plural attribute.
- `groceries-template.html.erb` -- Render names via Inflector.name_for_grocery. Include unit plural forms in ingredient JSON.

### Modified (JavaScript)
- `recipe-state-manager.js` -- Read both unit attributes, pick based on scaled quantity.
- `groceries.js` -- Same pattern for aggregated quantity display.

### Modified (data)
- `grocery-info.yaml` -- Key renames + alias cleanup.
- `nutrition-data.yaml` -- Key renames.

### Modified (tests)
- `test/ingredient_test.rb` -- Update for Inflector delegation.
- `test/nutrition_entry_helpers_test.rb` -- Update singularization tests.

## Localization path

When localization is added later:
1. Inflector constants extract to per-locale YAML files (e.g., `locales/en.yml`, `locales/fr.yml`)
2. Each locale provides: plural rules (CLDR categories), irregular forms, countability, gender (if needed)
3. The Inflector API stays the same -- calling code never changes
4. Canonical keys (English singular) become i18n lookup keys
5. Languages that don't pluralize (Japanese, Chinese) provide a single form; the Inflector respects this

## USDA reference

USDA FoodData Central SR Legacy uses a "bulk purchase" naming convention: plural for countable raw items ("Onions, raw", "Carrots, raw", "Strawberries, raw"), singular for single-unit items ("Egg, whole, dried"), singular for mass nouns ("Butter, salted", "Potato flour"). Our singular-canonical approach aligns with the USDA's underlying concept (the item itself is singular; plural is a display/context concern).

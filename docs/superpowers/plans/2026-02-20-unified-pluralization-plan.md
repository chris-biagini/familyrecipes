# Unified Pluralization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace three scattered pluralization systems with one centralized Inflector module, migrate YAML keys to singular canonical form, and fix unit display bugs in recipe scaling and grocery aggregation.

**Architecture:** A new `FamilyRecipes::Inflector` module owns all singular/plural morphology, countability, and unit abbreviation logic. Both YAML data files migrate to Title Case singular keys. HTML templates emit pre-computed singular+plural data attributes so JavaScript can display correct forms without its own pluralization logic.

**Tech Stack:** Ruby (Minitest), ERB templates, vanilla JavaScript

**References:** Design doc at `docs/plans/2026-02-20-unified-pluralization-design.md`. Closes GitHub issues #54 and #55.

---

### Task 1: Create the Inflector module with tests (TDD)

**Files:**
- Create: `lib/familyrecipes/inflector.rb`
- Create: `test/inflector_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

This task builds the complete Inflector module test-first. The module replaces `Ingredient.pluralize`, `Ingredient.singularize`, `Ingredient::UNIT_NORMALIZATIONS`, `NutritionEntryHelpers::SINGULARIZE_MAP`, and `NutritionEntryHelpers.singularize_simple`.

**Step 1: Write failing tests for core morphology**

Create `test/inflector_test.rb`:

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class InflectorTest < Minitest::Test
  # --- singular ---

  def test_singular_regular_s
    assert_equal 'apple', FamilyRecipes::Inflector.singular('apples')
  end

  def test_singular_ies
    assert_equal 'berry', FamilyRecipes::Inflector.singular('berries')
  end

  def test_singular_ses
    assert_equal 'glass', FamilyRecipes::Inflector.singular('glasses')
  end

  def test_singular_ches
    assert_equal 'peach', FamilyRecipes::Inflector.singular('peaches')
  end

  def test_singular_shes
    assert_equal 'dish', FamilyRecipes::Inflector.singular('dishes')
  end

  def test_singular_oes
    assert_equal 'potato', FamilyRecipes::Inflector.singular('potatoes')
  end

  def test_singular_xes
    assert_equal 'box', FamilyRecipes::Inflector.singular('boxes')
  end

  def test_singular_irregular_leaves
    assert_equal 'leaf', FamilyRecipes::Inflector.singular('leaves')
  end

  def test_singular_irregular_loaves
    assert_equal 'loaf', FamilyRecipes::Inflector.singular('loaves')
  end

  def test_singular_already_singular
    assert_equal 'carrot', FamilyRecipes::Inflector.singular('carrot')
  end

  def test_singular_preserves_case
    assert_equal 'Berry', FamilyRecipes::Inflector.singular('Berries')
  end

  def test_singular_nil
    assert_nil FamilyRecipes::Inflector.singular(nil)
  end

  def test_singular_empty
    assert_equal '', FamilyRecipes::Inflector.singular('')
  end

  # --- plural ---

  def test_plural_regular
    assert_equal 'apples', FamilyRecipes::Inflector.plural('apple')
  end

  def test_plural_consonant_y
    assert_equal 'berries', FamilyRecipes::Inflector.plural('berry')
  end

  def test_plural_vowel_y
    assert_equal 'days', FamilyRecipes::Inflector.plural('day')
  end

  def test_plural_sibilant_s
    assert_equal 'glasses', FamilyRecipes::Inflector.plural('glass')
  end

  def test_plural_sibilant_x
    assert_equal 'boxes', FamilyRecipes::Inflector.plural('box')
  end

  def test_plural_sibilant_ch
    assert_equal 'peaches', FamilyRecipes::Inflector.plural('peach')
  end

  def test_plural_sibilant_sh
    assert_equal 'dishes', FamilyRecipes::Inflector.plural('dish')
  end

  def test_plural_consonant_o
    assert_equal 'potatoes', FamilyRecipes::Inflector.plural('potato')
  end

  def test_plural_irregular_leaf
    assert_equal 'leaves', FamilyRecipes::Inflector.plural('leaf')
  end

  def test_plural_irregular_loaf
    assert_equal 'loaves', FamilyRecipes::Inflector.plural('loaf')
  end

  def test_plural_preserves_case
    assert_equal 'Berries', FamilyRecipes::Inflector.plural('Berry')
  end

  def test_plural_nil
    assert_nil FamilyRecipes::Inflector.plural(nil)
  end

  def test_plural_empty
    assert_equal '', FamilyRecipes::Inflector.plural('')
  end

  # --- uncountable? ---

  def test_uncountable_butter
    assert FamilyRecipes::Inflector.uncountable?('butter')
  end

  def test_uncountable_Butter_case_insensitive
    assert FamilyRecipes::Inflector.uncountable?('Butter')
  end

  def test_countable_carrot
    refute FamilyRecipes::Inflector.uncountable?('carrot')
  end

  # --- normalize_unit ---

  def test_normalize_unit_abbreviation_grams
    assert_equal 'g', FamilyRecipes::Inflector.normalize_unit('grams')
  end

  def test_normalize_unit_abbreviation_tablespoons
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('tablespoons')
  end

  def test_normalize_unit_abbreviation_teaspoon
    assert_equal 'tsp', FamilyRecipes::Inflector.normalize_unit('teaspoon')
  end

  def test_normalize_unit_abbreviation_ounces
    assert_equal 'oz', FamilyRecipes::Inflector.normalize_unit('ounces')
  end

  def test_normalize_unit_abbreviation_pounds
    assert_equal 'lb', FamilyRecipes::Inflector.normalize_unit('pounds')
  end

  def test_normalize_unit_abbreviation_lbs
    assert_equal 'lb', FamilyRecipes::Inflector.normalize_unit('lbs')
  end

  def test_normalize_unit_cups_to_cup
    assert_equal 'cup', FamilyRecipes::Inflector.normalize_unit('cups')
  end

  def test_normalize_unit_singular_passthrough
    assert_equal 'cup', FamilyRecipes::Inflector.normalize_unit('cup')
  end

  def test_normalize_unit_discrete_cloves
    assert_equal 'clove', FamilyRecipes::Inflector.normalize_unit('cloves')
  end

  def test_normalize_unit_discrete_singular_passthrough
    assert_equal 'clove', FamilyRecipes::Inflector.normalize_unit('clove')
  end

  def test_normalize_unit_strips_period
    assert_equal 'tsp', FamilyRecipes::Inflector.normalize_unit('tsp.')
  end

  def test_normalize_unit_downcases
    assert_equal 'tbsp', FamilyRecipes::Inflector.normalize_unit('Tbsp')
  end

  def test_normalize_unit_go
    assert_equal 'go', FamilyRecipes::Inflector.normalize_unit('gō')
  end

  def test_normalize_unit_small_slices
    assert_equal 'slice', FamilyRecipes::Inflector.normalize_unit('small slices')
  end

  # --- unit_display ---

  def test_unit_display_abbreviated_never_pluralizes
    assert_equal 'g', FamilyRecipes::Inflector.unit_display('g', 100)
  end

  def test_unit_display_abbreviated_singular
    assert_equal 'g', FamilyRecipes::Inflector.unit_display('g', 1)
  end

  def test_unit_display_cup_plural
    assert_equal 'cups', FamilyRecipes::Inflector.unit_display('cup', 2)
  end

  def test_unit_display_cup_singular
    assert_equal 'cup', FamilyRecipes::Inflector.unit_display('cup', 1)
  end

  def test_unit_display_clove_plural
    assert_equal 'cloves', FamilyRecipes::Inflector.unit_display('clove', 4)
  end

  def test_unit_display_clove_singular
    assert_equal 'clove', FamilyRecipes::Inflector.unit_display('clove', 1)
  end

  # --- name_for_grocery ---

  def test_name_for_grocery_countable
    assert_equal 'Carrots', FamilyRecipes::Inflector.name_for_grocery('Carrot')
  end

  def test_name_for_grocery_uncountable
    assert_equal 'Butter', FamilyRecipes::Inflector.name_for_grocery('Butter')
  end

  def test_name_for_grocery_qualified
    assert_equal 'Flour (all-purpose)', FamilyRecipes::Inflector.name_for_grocery('Flour (all-purpose)')
  end

  # --- name_for_count ---

  def test_name_for_count_singular
    assert_equal 'carrot', FamilyRecipes::Inflector.name_for_count('carrot', 1)
  end

  def test_name_for_count_plural
    assert_equal 'carrots', FamilyRecipes::Inflector.name_for_count('carrot', 2)
  end

  def test_name_for_count_uncountable
    assert_equal 'butter', FamilyRecipes::Inflector.name_for_count('butter', 5)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Ilib -Itest test/inflector_test.rb`
Expected: Failures — `FamilyRecipes::Inflector` does not exist yet.

**Step 3: Implement the Inflector module**

Create `lib/familyrecipes/inflector.rb`. The module consolidates data from:
- `Ingredient::IRREGULAR_PLURALS/SINGULARS` (line 11-12 of `lib/familyrecipes/ingredient.rb`)
- `Ingredient::UNIT_NORMALIZATIONS` (lines 24-52 of `lib/familyrecipes/ingredient.rb`)
- `NutritionEntryHelpers::SINGULARIZE_MAP` (lines 7-15 of `lib/familyrecipes/nutrition_entry_helpers.rb`)
- `Ingredient.pluralize` / `Ingredient.singularize` regex rules (lines 65-98 of `lib/familyrecipes/ingredient.rb`)
- `NutritionEntryHelpers.singularize_simple` (lines 83-95 of `lib/familyrecipes/nutrition_entry_helpers.rb`)

```ruby
# frozen_string_literal: true

module FamilyRecipes
  module Inflector
    # Irregular singular <-> plural not handled by standard rules.
    # Keys and values are lowercase.
    IRREGULAR_SINGULAR_TO_PLURAL = {
      'leaf' => 'leaves',
      'loaf' => 'loaves'
    }.freeze

    IRREGULAR_PLURAL_TO_SINGULAR = IRREGULAR_SINGULAR_TO_PLURAL.invert.freeze

    # Words that do not change between singular and plural.
    UNCOUNTABLE = Set[
      'asparagus', 'baby spinach', 'basil', 'bread', 'broccoli', 'butter',
      'buttermilk', 'celery', 'cheddar', 'chocolate', 'cornmeal', 'cornstarch',
      'cream cheese', 'flour', 'garlic', 'gouda', 'gruyère', 'heavy cream',
      'honey', 'hummus', 'milk', 'mozzarella', 'muesli', 'muenster',
      'oil', 'oregano', 'parmesan', 'parsley', 'pecorino', 'rice', 'ricotta',
      'salt', 'sour cream', 'sugar', 'thyme', 'watermelon', 'whipped cream',
      'water', 'yeast', 'yogurt'
    ].freeze

    # Units that always display as abbreviations (never pluralized).
    # Maps all input variants to canonical abbreviated form.
    ABBREVIATIONS = {
      'g' => 'g', 'gram' => 'g', 'grams' => 'g',
      'tbsp' => 'tbsp', 'tablespoon' => 'tbsp', 'tablespoons' => 'tbsp',
      'tsp' => 'tsp', 'teaspoon' => 'tsp', 'teaspoons' => 'tsp',
      'oz' => 'oz', 'ounce' => 'oz', 'ounces' => 'oz',
      'lb' => 'lb', 'lbs' => 'lb', 'pound' => 'lb', 'pounds' => 'lb',
      'l' => 'l', 'liter' => 'l', 'liters' => 'l',
      'ml' => 'ml'
    }.freeze

    # Multi-word unit mappings and special characters.
    UNIT_ALIASES = {
      'small slices' => 'slice',
      'gō' => 'go'
    }.freeze

    # --- Core morphology ---

    def self.singular(word)
      return word if word.nil? || word.empty?

      lower = word.downcase
      return word if UNCOUNTABLE.include?(lower)
      return apply_case(word, IRREGULAR_PLURAL_TO_SINGULAR[lower]) if IRREGULAR_PLURAL_TO_SINGULAR.key?(lower)

      result = case lower
               when /ies$/ then "#{word[0..-4]}y"
               when /(s|x|z|ch|sh)es$/, /oes$/ then word[0..-3]
               when /ss$/ then word
               when /s$/ then word[0..-2]
               else word
               end
      result
    end

    def self.plural(word)
      return word if word.nil? || word.empty?

      lower = word.downcase
      return word if UNCOUNTABLE.include?(lower)
      return apply_case(word, IRREGULAR_SINGULAR_TO_PLURAL[lower]) if IRREGULAR_SINGULAR_TO_PLURAL.key?(lower)

      case lower
      when /[^aeiou]y$/ then "#{word[0..-2]}ies"
      when /(s|x|z|ch|sh)$/, /[^aeiou]o$/ then "#{word}es"
      else "#{word}s"
      end
    end

    def self.uncountable?(word)
      UNCOUNTABLE.include?(word.to_s.downcase)
    end

    # --- Unit handling ---

    # Normalize a raw unit string to its canonical singular form.
    # Handles abbreviations, multi-word aliases, plurals, casing, and trailing periods.
    def self.normalize_unit(raw_unit)
      cleaned = raw_unit.strip.downcase.chomp('.')
      return UNIT_ALIASES[cleaned] if UNIT_ALIASES.key?(cleaned)
      return ABBREVIATIONS[cleaned] if ABBREVIATIONS.key?(cleaned)

      singular(cleaned)
    end

    # Display a unit with correct number agreement.
    # Abbreviated units never pluralize: "100 g", "2 tbsp".
    # Full-word units agree with count: "1 cup", "2 cups".
    def self.unit_display(unit, count)
      return unit if ABBREVIATIONS.key?(unit.downcase)

      count == 1 ? unit : plural(unit)
    end

    # --- Name display ---

    # For grocery list display: always plural for countables, unchanged for uncountables.
    # Handles qualified names like "Flour (all-purpose)" by pluralizing only the base word.
    def self.name_for_grocery(name)
      return name if uncountable_name?(name)

      base, qualifier = split_qualified(name)
      pluralized = plural(base)
      qualifier ? "#{pluralized} (#{qualifier})" : pluralized
    end

    # For quantity-dependent display: singular when count is 1, plural otherwise.
    def self.name_for_count(name, count)
      return name if uncountable_name?(name)

      count == 1 ? name : plural(name)
    end

    # --- Private helpers ---

    def self.apply_case(original, replacement)
      return replacement unless original[0] == original[0].upcase

      replacement.sub(/^./, &:upcase)
    end
    private_class_method :apply_case

    # Check uncountability, stripping qualifiers like "(all-purpose)".
    def self.uncountable_name?(name)
      base, = split_qualified(name)
      uncountable?(base)
    end
    private_class_method :uncountable_name?

    # Split "Flour (all-purpose)" into ["Flour", "all-purpose"].
    # Returns [name, nil] if no qualifier.
    def self.split_qualified(name)
      if name =~ /\A(.+?)\s*\((.+)\)\z/
        [::Regexp.last_match(1).strip, ::Regexp.last_match(2).strip]
      else
        [name, nil]
      end
    end
    private_class_method :split_qualified
  end
end
```

**Step 4: Add require to `lib/familyrecipes.rb`**

Add `require_relative 'familyrecipes/inflector'` after the `require_relative 'familyrecipes/quantity'` line (line 170), before `require_relative 'familyrecipes/ingredient'` since Ingredient will depend on it.

**Step 5: Run tests to verify they pass**

Run: `ruby -Ilib -Itest test/inflector_test.rb`
Expected: All tests pass.

Then run full suite to verify nothing is broken:
Run: `rake test`
Expected: All existing tests still pass.

**Step 6: Commit**

```bash
git add lib/familyrecipes/inflector.rb test/inflector_test.rb lib/familyrecipes.rb
git commit -m "Add centralized Inflector module with tests

Introduces FamilyRecipes::Inflector with singular/plural morphology,
uncountable word detection, unit normalization, and context-aware
display methods. This will replace the three scattered pluralization
systems (Ingredient, NutritionEntryHelpers, build_alias_map).

Closes #54, closes #55"
```

---

### Task 2: Migrate Ingredient class to use Inflector

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb`
- Modify: `test/ingredient_test.rb`

This task removes all pluralization code from Ingredient and delegates to Inflector. The Ingredient class keeps its `quantity_value` and `quantity_unit` methods but `quantity_unit` now calls `Inflector.normalize_unit` instead of using its own `UNIT_NORMALIZATIONS` hash.

**Step 1: Update `quantity_unit` to use Inflector**

In `lib/familyrecipes/ingredient.rb`, remove these constants and methods:
- `IRREGULAR_PLURALS` (line 11)
- `IRREGULAR_SINGULARS` (line 12)
- `UNIT_NORMALIZATIONS` (lines 24-52)
- `self.pluralize` (lines 65-80)
- `self.singularize` (lines 82-98)

Replace the `quantity_unit` method (lines 111-119):

```ruby
# Before:
def quantity_unit
  return nil if quantity_blank?
  raw_unit = parsed_quantity[1]
  return nil if raw_unit.nil?
  cleaned = raw_unit.strip.downcase.chomp('.')
  UNIT_NORMALIZATIONS[cleaned] || cleaned
end

# After:
def quantity_unit
  return nil if quantity_blank?
  raw_unit = parsed_quantity[1]
  return nil if raw_unit.nil?
  Inflector.normalize_unit(raw_unit)
end
```

The resulting `ingredient.rb` should only contain: `attr_reader`, `QUANTITY_FRACTIONS`, `initialize`, `normalized_name`, `quantity_value`, `quantity_unit`, and the private helpers.

**Step 2: Update tests**

In `test/ingredient_test.rb`:
- Remove all `Ingredient.pluralize` tests (lines 7-49)
- Remove all `Ingredient.singularize` tests (lines 52-74)
- Keep all `quantity_unit` tests (they should still pass since Inflector handles the same normalizations)
- Keep all `quantity_value` tests
- Keep `normalized_name` tests

**Step 3: Run tests**

Run: `rake test`
Expected: All tests pass. The Ingredient quantity_unit tests validate that Inflector.normalize_unit produces the same results as the old UNIT_NORMALIZATIONS hash.

**Step 4: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "Migrate Ingredient to use Inflector for unit normalization

Remove IRREGULAR_PLURALS, IRREGULAR_SINGULARS, UNIT_NORMALIZATIONS,
self.pluralize, and self.singularize from Ingredient. The quantity_unit
method now delegates to Inflector.normalize_unit."
```

---

### Task 3: Migrate NutritionEntryHelpers to use Inflector

**Files:**
- Modify: `lib/familyrecipes/nutrition_entry_helpers.rb`
- Modify: `test/nutrition_entry_helpers_test.rb`

**Step 1: Remove redundant code from NutritionEntryHelpers**

In `lib/familyrecipes/nutrition_entry_helpers.rb`:
- Remove `SINGULARIZE_MAP` (lines 7-15)
- Remove `self.singularize_simple` (lines 83-95)
- Update `parse_serving_size` (line 75): replace `SINGULARIZE_MAP[unit_down] || singularize_simple(unit_down)` with `Inflector.normalize_unit(unit_down)`

The `normalize_unit` method in Inflector handles the same singularization (cloves->clove, pieces->piece, etc.) that `SINGULARIZE_MAP` did. For nutrition-specific units like `cookies`, `chips`, `patties`, `sheets`, `strips`, `cubes`, `rings`, `balls`, `links`, `servings` — these are regular English plurals that `Inflector.singular` handles correctly via its regex rules (remove trailing 's' or 'ies->y'). The special case `eggs -> ~unitless` needs to be handled in the nutrition entry tool itself (it's a nutrition-specific concern, not a general pluralization rule).

Note: Check whether the `eggs -> ~unitless` mapping from `SINGULARIZE_MAP` is used during `parse_serving_size`. If a serving size says "1 egg (50g)", the `~unitless` mapping is applied. This should be moved to a nutrition-specific constant in `parse_serving_size`, or the Inflector could have a hook for it. The simplest approach: keep a small `NUTRITION_UNIT_OVERRIDES` constant in NutritionEntryHelpers just for `'eggs' => '~unitless'`.

**Step 2: Update tests**

In `test/nutrition_entry_helpers_test.rb`:
- Remove `singularize_simple` tests (lines 106-128) since that method no longer exists
- Keep all `parse_serving_size` tests — they validate end-to-end behavior
- Keep all `parse_fraction` tests

**Step 3: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add lib/familyrecipes/nutrition_entry_helpers.rb test/nutrition_entry_helpers_test.rb
git commit -m "Migrate NutritionEntryHelpers to use Inflector

Remove SINGULARIZE_MAP and singularize_simple. parse_serving_size
now uses Inflector.normalize_unit for unit singularization."
```

---

### Task 4: Migrate YAML files to singular canonical keys

**Files:**
- Modify: `resources/grocery-info.yaml`
- Modify: `resources/nutrition-data.yaml`

**Step 1: Migrate grocery-info.yaml**

Rename all countable-plural keys to singular. Leave uncountable and already-singular entries alone. Clean up aliases.

Key renames (every plural entry in the file):
- `Apples` -> `Apple`
- `Bananas` -> `Banana`
- `Red bell peppers` -> `Red bell pepper`
- `Green bell peppers` -> `Green bell pepper`
- `Berries` -> `Berry`  (note: might prefer keeping as uncountable — check usage)
- `Blueberries` -> `Blueberry`
- `Brussels sprouts` -> `Brussels sprout`
- `Carrots` -> `Carrot`
- `Cherries` -> `Cherry`
- `Clementines` -> `Clementine`
- `Cucumbers` -> `Cucumber`
- `Grapes` -> `Grape`
- `Green onions` -> `Green onion`
- `Lemons` -> `Lemon`
- `Limes` -> `Lime`
- `Mangoes` -> `Mango`
- `Onions` -> `Onion`
- `Oranges` -> `Orange`
- `Potatoes` -> `Potato`
- `Red onions` -> `Red onion`
- `Strawberries` -> `Strawberry`
- `Tomatoes (fresh)` -> `Tomato (fresh)`
- `Calabrian chilis` -> `Calabrian chili`
- `Olives` -> `Olive`
- `Hamburger buns` -> `Hamburger bun`
- `Beans (any dry)` -> `Bean (any dry)` — but reconsider: "Bean" sounds odd. Maybe keep as uncountable or use a more natural form. Check actual recipe usage.
- `Beans (any canned)`, `Black beans (canned)`, `Red beans (dry)`, `Chickpeas (canned)` -> singular forms
- `Pickled jalapeños` -> `Pickled jalapeño`
- `Lentils` -> `Lentil`
- `Tortillas (corn)` -> `Tortilla (corn)`
- `Tortillas (large flour)` -> `Tortilla (large flour)`
- `RXBARs` -> `RXBAR`
- `Eggs` -> `Egg` (with aliases: Egg yolk, Egg white — remove "Egg yolks" alias since Inflector handles it)
- `Cookies` -> `Cookie`
- `Chocolate chips` -> `Chocolate chip`
- `Hershey's Kisses` -> `Hershey's Kiss`
- `Peanut M&Ms` -> stay as-is (brand name, uncountable-ish)
- `Pretzels` -> `Pretzel`
- `Ritz crackers` -> `Ritz cracker`
- `Tortilla chips` -> `Tortilla chip`
- `Triscuits` -> `Triscuit`
- `Artichokes (jarred)` -> `Artichoke (jarred)`
- `Jarred red peppers` -> `Jarred red pepper`
- `Pickles` -> `Pickle`
- `Raisins` -> `Raisin`
- `Tomatoes (canned)` -> `Tomato (canned)`
- `Walnuts` -> `Walnut`
- `Pecans` -> `Pecan`
- `French fries` -> stay as-is (the food is called "French fries")
- `Fro-yo bars` -> `Fro-yo bar`
- `Green beans` -> `Green bean`
- `Impossible burgers` -> `Impossible burger`
- `Peas and carrots (frozen)` -> stay as-is (compound name)
- `Soft pretzels` -> `Soft pretzel`
- `Tater tots` -> stay as-is (mass noun / brand name)
- `Chik'n nuggets` -> `Chik'n nugget`
- `Frozen potatoes` -> `Frozen potato`

Alias cleanup:
- `Eggs` entry: remove `Egg` alias (Inflector handles singular). Keep `Egg yolk` and `Egg white`. Remove `Egg yolks` (Inflector handles plural of alias).
- `Chocolate` entry: remove `Dark chocolate` alias (false synonym — these are different products). Dark chocolate should be its own entry or omitted.
- Leave all other true-synonym and grocery-consolidation aliases.

**Important consideration during migration:** Run `bin/generate` after changes to verify the build validator doesn't flag new unknown ingredients. The alias map generation in `build_alias_map` will need to generate plural variants (see Task 5) for recipe ingredients written as "Carrots" to still resolve to canonical "Carrot".

**Step 2: Migrate nutrition-data.yaml**

Rename the ~6 plural keys to singular. These must match the grocery-info.yaml keys exactly:
- `Carrots` -> `Carrot`
- `Eggs` -> `Egg`
- `Lemons` -> `Lemon`
- `Limes` -> `Lime`
- `Onions` -> `Onion`
- `Red bell peppers` -> `Red bell pepper`

**Step 3: Commit**

```bash
git add resources/grocery-info.yaml resources/nutrition-data.yaml
git commit -m "Migrate YAML keys to singular canonical form

Rename countable-plural ingredient keys to Title Case singular in
both grocery-info.yaml and nutrition-data.yaml. Clean up aliases:
remove plural-form aliases (handled by Inflector), remove false
synonyms (Dark chocolate != Chocolate)."
```

---

### Task 5: Update build_alias_map to generate plural variants

**Files:**
- Modify: `lib/familyrecipes.rb` (lines 87-109)
- Modify: `test/familyrecipes_test.rb` (if alias map tests exist; check first)

**Step 1: Update `build_alias_map`**

The keys are now singular, so the alias map needs to generate **plural** variants (instead of singular) so recipe ingredients written as "Carrots" resolve to canonical "Carrot".

In `lib/familyrecipes.rb`, update `build_alias_map` (lines 87-109):

```ruby
# Before: generates singular aliases from plural canonical names
# After: generates plural aliases from singular canonical names

def self.build_alias_map(grocery_aisles)
  grocery_aisles.each_value.with_object({}) do |items, alias_map|
    items.each do |item|
      canonical = item[:name]

      # Map the canonical name (lowercase)
      alias_map[canonical.downcase] = canonical

      # Map explicit aliases
      item[:aliases].each { |al| alias_map[al.downcase] = canonical }

      # Generate plural variant of canonical name
      plural = Inflector.plural(canonical)
      alias_map[plural.downcase] = canonical unless plural == canonical

      # Generate plural variants of each alias
      item[:aliases].each do |al|
        plural = Inflector.plural(al)
        alias_map[plural.downcase] = canonical unless plural == al
      end
    end
  end
end
```

**Step 2: Run tests and the full build**

Run: `rake test`
Expected: All tests pass.

Run: `bin/generate`
Expected: No new unknown ingredient warnings. All recipes still resolve their ingredients correctly.

**Step 3: Commit**

```bash
git add lib/familyrecipes.rb
git commit -m "Update build_alias_map to generate plural variants

Now that canonical keys are singular, the alias map generates plural
forms (e.g., 'carrots' -> 'Carrot') so recipe ingredients written
in natural plural form still resolve correctly."
```

---

### Task 6: Update recipe template to emit plural unit data attributes

**Files:**
- Modify: `templates/web/recipe-template.html.erb` (line 40)
- Modify: `lib/familyrecipes/recipe.rb` (line 37-51, `to_html` method)

**Step 1: Add Inflector to recipe template locals**

In `lib/familyrecipes/recipe.rb`, add `inflector` to the `to_html` result_with_hash (around line 39):

```ruby
def to_html(erb_template_path:, nutrition: nil)
  template = File.read(erb_template_path)
  ERB.new(template, trim_mode: '-').result_with_hash(
    markdown: MARKDOWN,
    render: ->(name, locals = {}) { FamilyRecipes.render_partial(name, locals) },
    inflector: Inflector,
    title: @title,
    # ... rest unchanged
  )
end
```

**Step 2: Update recipe template**

In `templates/web/recipe-template.html.erb`, update line 40 to emit both singular and plural unit forms:

```erb
<%# Before: %>
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<% end %>>

<%# After: %>
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{inflector.plural(item.quantity_unit)}") if item.quantity_unit %><% end %>>
```

Note: For abbreviated units (g, tbsp, tsp, oz, lb), `Inflector.plural('g')` returns `'gs'` which is wrong. The template should use `Inflector.unit_display(unit, 2)` to get the correct plural form, or check if the unit is abbreviated first. Better approach: use a helper that returns the right plural form for display:

```erb
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{inflector.unit_display(item.quantity_unit, 2)}") if item.quantity_unit %><% end %>>
```

This way, `unit_display('g', 2)` returns `'g'` (abbreviated, never pluralized) and `unit_display('cup', 2)` returns `'cups'`.

**Step 3: Run build and inspect output**

Run: `bin/generate`
Expected: Recipe HTML files now contain `data-quantity-unit-plural` attributes.

Inspect a generated file to verify:
```bash
grep 'data-quantity-unit' output/web/black-bean-tacos.html
```
Expected: `data-quantity-unit="go" data-quantity-unit-plural="gos"` (or similar).

**Step 4: Commit**

```bash
git add templates/web/recipe-template.html.erb lib/familyrecipes/recipe.rb
git commit -m "Emit plural unit data attributes in recipe HTML

Add data-quantity-unit-plural attribute to ingredient list items so
JavaScript can display correct plural forms during recipe scaling."
```

---

### Task 7: Update recipe-state-manager.js to use plural units

**Files:**
- Modify: `resources/web/recipe-state-manager.js` (lines 146-160)

**Step 1: Update applyScale method**

In `resources/web/recipe-state-manager.js`, update the scaling logic (around line 153-159):

```javascript
// Before:
const unit = li.dataset.quantityUnit || '';
// ...
if (span) span.textContent = pretty + (unit ? ' ' + unit : '');

// After:
const unitSingular = li.dataset.quantityUnit || '';
const unitPlural = li.dataset.quantityUnitPlural || unitSingular;
const unit = (scaled === 1) ? unitSingular : unitPlural;
// ...
if (span) span.textContent = pretty + (unit ? ' ' + unit : '');
```

**Step 2: Test manually**

Run: `bin/generate && bin/serve` (if server not already running)
Open a recipe page (e.g., `http://rika:8888/black-bean-tacos`).
Click Scale. Scale to 1x — units should be singular ("1 cup", "1 clove"). Scale to 2x — units should be plural ("2 cups", "2 cloves"). Abbreviated units should never change ("100 g" at any scale).

**Step 3: Commit**

```bash
git add resources/web/recipe-state-manager.js
git commit -m "Fix recipe scaling to display correct plural units

Read data-quantity-unit-plural attribute and select singular vs
plural form based on scaled quantity. Fixes '4 clove' -> '4 cloves'."
```

---

### Task 8: Update groceries template and JS for plural display

**Files:**
- Modify: `templates/web/groceries-template.html.erb` (lines 92-106)
- Modify: `lib/familyrecipes/site_generator.rb` (lines 168-199, `generate_groceries_page`)
- Modify: `resources/web/groceries.js` (lines 215-270)

**Step 1: Pass Inflector display names to grocery template**

In `lib/familyrecipes/site_generator.rb`, update `generate_groceries_page` to pass display-ready ingredient names. The `grocery_info` hash (line 173-175) currently passes raw `item[:name]`. Update it to include the display name:

```ruby
grocery_info = @grocery_aisles.transform_values do |items|
  items.map do |item|
    { name: item[:name], display_name: Inflector.name_for_grocery(item[:name]) }
  end
end
```

**Step 2: Update grocery template to use display names**

In `templates/web/groceries-template.html.erb`, update line 98 and 101 to use `display_name` instead of `name` for visual display, but keep `name` (singular canonical) for data matching:

```erb
<li data-item="<%= h.call(ingredient[:name]) %>" hidden>
  <label class="check-off">
    <input type="checkbox">
    <span><%= ingredient[:display_name] %><span class="qty"></span></span>
  </label>
</li>
```

**Step 3: Update grocery JS to pluralize aggregated units**

The grocery list's `data-ingredients` JSON (from `all_ingredients_with_quantities`) includes amounts as `[value, unit]` pairs where `unit` is the singular canonical form. We need to pass plural forms too.

Option A (simpler): Include `unit_plural` in the JSON. This requires updating `all_ingredients_with_quantities` or the template's JSON serialization.

Option B (recommended): Build a small unit-plural map in the template and embed it in a data attribute or script block:

In `groceries-template.html.erb`, add a script block before groceries.js that provides unit plural forms:

```erb
<script>
  window.UNIT_PLURALS = <%= all_unit_plurals.to_json %>;
</script>
```

Where `all_unit_plurals` is computed in the site generator and passed as a template local — a hash of `{ "cup" => "cups", "clove" => "cloves", "g" => "g", ... }` covering all units that appear in recipes.

Then in `groceries.js`, update `aggregateQuantities` (line 238 and 253) to look up the plural form:

```javascript
// Helper to get the display form of a unit based on quantity
function displayUnit(unit, qty) {
  if (!unit) return '';
  if (qty === 1) return unit;
  return (window.UNIT_PLURALS && window.UNIT_PLURALS[unit]) || unit;
}
```

And use it in the display lines:

```javascript
// Line ~238: per-recipe display
var part = formatQtyNumber(val);
if (unit) part += '\u00a0' + displayUnit(unit, val);

// Line ~253: aggregated display
var str = formatQtyNumber(sums[unit]);
if (unit) str += '\u00a0' + displayUnit(unit, sums[unit]);
```

**Step 4: Compute unit plurals in site_generator**

In `lib/familyrecipes/site_generator.rb`, compute the unit plural map before rendering the groceries template. Add to `generate_groceries_page`:

```ruby
all_units = @recipes.flat_map do |recipe|
  recipe.all_ingredients_with_quantities(@alias_map, @recipe_map).flat_map do |_, amounts|
    amounts.compact.filter_map(&:unit)
  end
end.uniq

unit_plurals = all_units.to_h { |u| [u, Inflector.unit_display(u, 2)] }
```

Pass `all_unit_plurals: unit_plurals` to the template locals.

**Step 5: Test manually**

Run: `bin/generate && bin/serve`
Open `http://rika:8888/groceries/`.
Select two recipes. Check that the grocery list shows "2 cups" not "2 cup", "4 cloves" not "4 clove", and "100 g" stays "100 g".

**Step 6: Commit**

```bash
git add templates/web/groceries-template.html.erb lib/familyrecipes/site_generator.rb resources/web/groceries.js
git commit -m "Fix grocery list to display plural units and ingredient names

Grocery list now shows 'Carrots' instead of 'Carrot' for countable
items, and '4 cloves' instead of '4 clove' for aggregated quantities."
```

---

### Task 9: Update IngredientAggregator (if needed)

**Files:**
- Modify: `lib/familyrecipes/ingredient_aggregator.rb` (lines 10-28)
- Check: `test/ingredient_aggregator_test.rb`

**Step 1: Check if IngredientAggregator references old constants**

`IngredientAggregator.aggregate_amounts` (line 13) currently does:
```ruby
unit = Ingredient::UNIT_NORMALIZATIONS[unit] || unit if unit
```

Since we removed `UNIT_NORMALIZATIONS` from Ingredient in Task 2, this line will raise a `NameError`. Replace it:

```ruby
unit = Inflector.normalize_unit(unit) if unit
```

**Step 2: Run tests**

Run: `rake test`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add lib/familyrecipes/ingredient_aggregator.rb
git commit -m "Update IngredientAggregator to use Inflector for unit normalization"
```

---

### Task 10: Full integration test

**Step 1: Run the full test suite**

Run: `rake` (runs both lint and test)
Expected: All tests pass, no lint errors.

**Step 2: Run the full build**

Run: `bin/generate`
Expected: No warnings about unknown ingredients or missing nutrition data (beyond pre-existing ones). All recipe pages and the grocery page generate successfully.

**Step 3: Manual smoke test**

Start the dev server: `bin/serve` (if not already running)
Test these scenarios from the Mac at `http://rika:8888`:

1. **Recipe page scaling**: Open a recipe with units (e.g., Black Bean Tacos). Click Scale. Verify "2 gō" stays "2 gō" (or "2 go"), "2 cans" shows correctly. Scale to different factors and check singular/plural transitions.

2. **Grocery page**: Select multiple recipes. Verify:
   - Ingredient names are correct ("Carrots" not "Carrot" for countable, "Garlic" not "Garlics" for uncountable)
   - Aggregated quantities show plural units ("4 cloves", "2 cups")
   - Single quantities show singular units ("1 cup", "1 clove")
   - Abbreviated units never pluralize ("100 g", "2 tbsp")

3. **Nutrition facts**: Verify nutrition facts still render correctly on recipe pages with nutrition data.

**Step 4: Final commit (if any fixups needed)**

If manual testing reveals issues, fix them and commit.

---

### Task 11: Clean up and verify

**Step 1: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses. Fix any that appear.

**Step 2: Verify no dead code**

Search for any remaining references to the removed constants/methods:
- `Ingredient.pluralize` / `Ingredient.singularize`
- `Ingredient::UNIT_NORMALIZATIONS`
- `Ingredient::IRREGULAR_PLURALS` / `IRREGULAR_SINGULARS`
- `NutritionEntryHelpers::SINGULARIZE_MAP`
- `NutritionEntryHelpers.singularize_simple`

Run: `grep -r 'UNIT_NORMALIZATIONS\|IRREGULAR_PLURALS\|IRREGULAR_SINGULARS\|SINGULARIZE_MAP\|singularize_simple\|Ingredient\.pluralize\|Ingredient\.singularize' lib/ test/ bin/ templates/`
Expected: No matches.

**Step 3: Final commit**

```bash
git commit -m "Clean up: remove dead references to old pluralization systems"
```

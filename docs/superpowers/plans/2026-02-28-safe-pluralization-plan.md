# Safe Pluralization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the rule-based pluralization engine with a display-safe allowlist so the app never produces incorrect English ("oreganoes", "tomatoeses") while still pluralizing units and known ingredient names correctly.

**Architecture:** Two-tier Inflector: `KNOWN_PLURALS` allowlist for all user-visible output, private rule engine retained only for internal catalog matching. UNCOUNTABLE and IRREGULAR constants dropped entirely. Grocery units pluralized server-side. Recipe scaling uses pre-computed data attributes for name/unit forms. Template data attributes built via `tag.attributes` (no `.html_safe`).

**Tech Stack:** Ruby (Inflector module, ShoppingListBuilder service, NutritionCalculator, ScalableNumberPreprocessor, ERB partials, RecipesHelper), JavaScript (Stimulus recipe_state_controller), Minitest.

**Design doc:** `docs/plans/2026-02-28-safe-pluralization-design.md`

---

### Task 1: Rewrite Inflector with KNOWN_PLURALS allowlist

**Files:**
- Modify: `lib/familyrecipes/inflector.rb` (entire file rewrite)
- Modify: `test/inflector_test.rb` (entire file rewrite)

**Step 1: Write the failing tests for the new API**

Replace `test/inflector_test.rb` with tests for the new public methods. The new file should contain these test groups:

**safe_plural tests** (replaces old singular/plural/uncountable tests):

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class InflectorTest < Minitest::Test
  # --- safe_plural ---

  def test_safe_plural_known_unit
    assert_equal 'cups', FamilyRecipes::Inflector.safe_plural('cup')
  end

  def test_safe_plural_known_ingredient
    assert_equal 'eggs', FamilyRecipes::Inflector.safe_plural('egg')
  end

  def test_safe_plural_known_yield_noun
    assert_equal 'loaves', FamilyRecipes::Inflector.safe_plural('loaf')
  end

  def test_safe_plural_unknown_word_passes_through
    assert_equal 'oregano', FamilyRecipes::Inflector.safe_plural('oregano')
  end

  def test_safe_plural_preserves_capitalization
    assert_equal 'Eggs', FamilyRecipes::Inflector.safe_plural('Egg')
  end

  def test_safe_plural_already_plural_passes_through
    assert_equal 'eggs', FamilyRecipes::Inflector.safe_plural('eggs')
  end

  def test_safe_plural_abbreviated_passes_through
    assert_equal 'g', FamilyRecipes::Inflector.safe_plural('g')
  end

  def test_safe_plural_nil
    assert_nil FamilyRecipes::Inflector.safe_plural(nil)
  end

  def test_safe_plural_empty
    assert_equal '', FamilyRecipes::Inflector.safe_plural('')
  end
```

**safe_singular tests:**

```ruby
  # --- safe_singular ---

  def test_safe_singular_known_unit
    assert_equal 'cup', FamilyRecipes::Inflector.safe_singular('cups')
  end

  def test_safe_singular_known_ingredient
    assert_equal 'egg', FamilyRecipes::Inflector.safe_singular('eggs')
  end

  def test_safe_singular_known_yield_noun
    assert_equal 'loaf', FamilyRecipes::Inflector.safe_singular('loaves')
  end

  def test_safe_singular_unknown_word_passes_through
    assert_equal 'paprikas', FamilyRecipes::Inflector.safe_singular('paprikas')
  end

  def test_safe_singular_preserves_capitalization
    assert_equal 'Egg', FamilyRecipes::Inflector.safe_singular('Eggs')
  end

  def test_safe_singular_already_singular_passes_through
    assert_equal 'cup', FamilyRecipes::Inflector.safe_singular('cup')
  end

  def test_safe_singular_nil
    assert_nil FamilyRecipes::Inflector.safe_singular(nil)
  end

  def test_safe_singular_empty
    assert_equal '', FamilyRecipes::Inflector.safe_singular('')
  end
```

**display_name tests:**

```ruby
  # --- display_name ---

  def test_display_name_pluralizes_known_ingredient
    assert_equal 'Eggs', FamilyRecipes::Inflector.display_name('Egg', 2)
  end

  def test_display_name_singularizes_known_ingredient
    assert_equal 'Egg', FamilyRecipes::Inflector.display_name('Eggs', 1)
  end

  def test_display_name_unknown_ingredient_passes_through
    assert_equal 'Oregano', FamilyRecipes::Inflector.display_name('Oregano', 5)
  end

  def test_display_name_multi_word_inflects_last
    assert_equal 'Egg yolks', FamilyRecipes::Inflector.display_name('Egg yolk', 2)
  end

  def test_display_name_qualifier_preserved
    assert_equal 'Tomatoes (canned)', FamilyRecipes::Inflector.display_name('Tomato (canned)', 2)
  end

  def test_display_name_nil
    assert_nil FamilyRecipes::Inflector.display_name(nil, 2)
  end

  def test_display_name_empty
    assert_equal '', FamilyRecipes::Inflector.display_name('', 2)
  end
```

**Keep ALL existing normalize_unit tests** (lines 182-304 of the current file) — these methods use the private rule engine and their behavior must not change. Copy them verbatim.

**Keep ALL existing unit_display tests** (lines 308-346) — `unit_display` now uses `safe_plural` instead of `plural`, but the results are identical for all tested units because they're all in KNOWN_PLURALS. Copy them verbatim.

**Update 4 ingredient_variants tests** (the rest copy verbatim):

```ruby
  # These 4 change because UNCOUNTABLE and IRREGULAR are dropped:

  def test_ingredient_variants_mass_noun_returns_variant
    # Was: assert_empty (butter was uncountable)
    # Now: rules produce a variant — harmless for matching
    assert_equal ['Butters'], FamilyRecipes::Inflector.ingredient_variants('Butter')
  end

  def test_ingredient_variants_mass_noun_with_qualifier_returns_variant
    # Was: assert_empty (flour was uncountable)
    # Now: rules produce a variant — harmless for matching
    assert_equal ['Flours (all-purpose)'], FamilyRecipes::Inflector.ingredient_variants('Flour (all-purpose)')
  end

  def test_ingredient_variants_irregular_leaves_via_rules
    # Was: ['Bay leaf'] (via IRREGULAR map)
    # Now: rules produce 'leave' from 'leaves' — imperfect but harmless
    assert_equal ['Bay leave'], FamilyRecipes::Inflector.ingredient_variants('Bay leaves')
  end

  def test_ingredient_variants_irregular_leaf_via_rules
    # Was: ['Bay leaves'] (via IRREGULAR map)
    # Now: rules produce 'leafs' from 'leaf' — imperfect but harmless
    assert_equal ['Bay leafs'], FamilyRecipes::Inflector.ingredient_variants('Bay leaf')
  end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/inflector_test.rb`
Expected: FAIL — `safe_plural`, `safe_singular`, `display_name` methods don't exist yet.

**Step 3: Rewrite the Inflector**

Replace `lib/familyrecipes/inflector.rb` with the new implementation:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  module Inflector # rubocop:disable Metrics/ModuleLength
    KNOWN_PLURALS = {
      # Units
      'cup' => 'cups', 'clove' => 'cloves', 'slice' => 'slices',
      'can' => 'cans', 'bunch' => 'bunches', 'spoonful' => 'spoonfuls',
      'head' => 'heads', 'stalk' => 'stalks', 'sprig' => 'sprigs',
      'piece' => 'pieces', 'stick' => 'sticks', 'item' => 'items',
      # Yield nouns
      'cookie' => 'cookies', 'loaf' => 'loaves', 'roll' => 'rolls',
      'pizza' => 'pizzas', 'taco' => 'tacos', 'pancake' => 'pancakes',
      'bagel' => 'bagels', 'biscuit' => 'biscuits', 'gougère' => 'gougères',
      'quesadilla' => 'quesadillas', 'pizzelle' => 'pizzelle',
      'bar' => 'bars', 'sandwich' => 'sandwiches', 'sheet' => 'sheets',
      # Ingredient names
      'egg' => 'eggs', 'onion' => 'onions', 'lime' => 'limes',
      'pepper' => 'peppers', 'tomato' => 'tomatoes', 'carrot' => 'carrots',
      'walnut' => 'walnuts', 'olive' => 'olives', 'lentil' => 'lentils',
      'tortilla' => 'tortillas', 'bean' => 'beans', 'leaf' => 'leaves',
      'yolk' => 'yolks', 'berry' => 'berries', 'apple' => 'apples',
      'potato' => 'potatoes', 'lemon' => 'lemons'
    }.freeze

    KNOWN_SINGULARS = KNOWN_PLURALS.invert.freeze

    ABBREVIATIONS = {
      'g' => 'g', 'gram' => 'g', 'grams' => 'g',
      'gō' => 'gō',
      'tbsp' => 'tbsp', 'tablespoon' => 'tbsp', 'tablespoons' => 'tbsp',
      'tsp' => 'tsp', 'teaspoon' => 'tsp', 'teaspoons' => 'tsp',
      'oz' => 'oz', 'ounce' => 'oz', 'ounces' => 'oz',
      'lb' => 'lb', 'lbs' => 'lb', 'pound' => 'lb', 'pounds' => 'lb',
      'l' => 'l', 'liter' => 'l', 'liters' => 'l',
      'ml' => 'ml'
    }.freeze

    UNIT_ALIASES = {
      'small slices' => 'slice'
    }.freeze

    ABBREVIATED_FORMS = ABBREVIATIONS.values.to_set.freeze

    def self.safe_plural(word)
      return word if word.blank?
      return word if ABBREVIATED_FORMS.include?(word.downcase)

      known = KNOWN_PLURALS[word.downcase]
      return apply_case(word, known) if known

      word
    end

    def self.safe_singular(word)
      return word if word.blank?

      known = KNOWN_SINGULARS[word.downcase]
      return apply_case(word, known) if known

      word
    end

    def self.unit_display(unit, count)
      return unit if ABBREVIATED_FORMS.include?(unit)

      count == 1 ? unit : safe_plural(unit)
    end

    def self.display_name(name, count)
      return name if name.blank?

      base, qualifier = split_ingredient_name(name)
      words = base.split
      last_word = words.last
      prefix = words[0..-2].join(' ')

      adjusted = count == 1 ? safe_singular(last_word) : safe_plural(last_word)
      return name if adjusted == last_word

      rejoin_ingredient(prefix, adjusted, qualifier)
    end

    def self.ingredient_variants(name)
      return [] if name.blank?

      base, qualifier = split_ingredient_name(name)
      words = base.split
      last_word = words.last
      prefix = words[0..-2].join(' ')

      alternate = alternate_form(last_word)
      return [] unless alternate

      [rejoin_ingredient(prefix, alternate, qualifier)]
    end

    def self.normalize_unit(raw_unit)
      cleaned = raw_unit.strip.downcase.chomp('.')
      UNIT_ALIASES[cleaned] || ABBREVIATIONS[cleaned] || singular(cleaned)
    end

    def self.apply_case(original, replacement)
      original[0] == original[0].upcase ? replacement.capitalize : replacement
    end
    private_class_method :apply_case

    def self.singular(word)
      return word if word.blank?

      singularize_by_rules(word)
    end
    private_class_method :singular

    def self.plural(word)
      return word if word.blank?
      return word if ABBREVIATED_FORMS.include?(word.downcase)

      pluralize_by_rules(word)
    end
    private_class_method :plural

    def self.singularize_by_rules(word)
      case word.downcase
      when /ies$/ then "#{word[0..-4]}y"
      when /(s|x|z|ch|sh)es$/, /oes$/ then word[0..-3]
      when /(?<!s)s$/ then word[0..-2]
      else word
      end
    end
    private_class_method :singularize_by_rules

    def self.pluralize_by_rules(word)
      case word.downcase
      when /[^aeiou]y$/ then "#{word[0..-2]}ies"
      when /(s|x|z|ch|sh)$/, /[bcdfghjklmnpqrstvwxyz]o$/i then "#{word}es"
      else "#{word}s"
      end
    end
    private_class_method :pluralize_by_rules

    # Words ending in 's' are ambiguous — could already be plural
    def self.alternate_form(word)
      singular_form = singular(word)
      return singular_form if singular_form != word

      plural_form = plural(word)
      return plural_form if plural_form != word && !word.end_with?('s')

      nil
    end
    private_class_method :alternate_form

    def self.split_ingredient_name(name)
      match = name.match(/\A(.+?)\s*(\([^)]+\))\z/)
      match ? [match[1].strip, match[2]] : [name, nil]
    end
    private_class_method :split_ingredient_name

    def self.rejoin_ingredient(prefix, word, qualifier)
      parts = [prefix.presence, word].compact.join(' ')
      qualifier ? "#{parts} #{qualifier}" : parts
    end
    private_class_method :rejoin_ingredient
  end
end
```

Key changes from current file:
- Added: `KNOWN_PLURALS`, `KNOWN_SINGULARS`, `safe_plural`, `safe_singular`, `display_name`
- Removed: `UNCOUNTABLE`, `IRREGULAR_SINGULAR_TO_PLURAL`, `IRREGULAR_PLURAL_TO_SINGULAR`, `uncountable?`
- Changed: `singular`, `plural` become private (no UNCOUNTABLE/IRREGULAR checks)
- Changed: `unit_display` uses `safe_plural` instead of `plural`
- Unchanged: `ingredient_variants`, `normalize_unit`, `singularize_by_rules`, `pluralize_by_rules`, `alternate_form`, `split_ingredient_name`, `rejoin_ingredient`, `apply_case`, `ABBREVIATIONS`, `UNIT_ALIASES`, `ABBREVIATED_FORMS`

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/inflector_test.rb`
Expected: ALL PASS

**Step 5: Run full test suite**

Run: `rake test`
Expected: FAIL — `NutritionCalculator` still calls the now-private `singular`/`plural` methods. That's fixed in Task 2.

**Step 6: Commit**

```bash
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "refactor: rewrite Inflector with KNOWN_PLURALS allowlist (#113)

Display-safe safe_plural/safe_singular use allowlist only.
Drop UNCOUNTABLE (33 entries) and IRREGULAR (4 entries).
Rule engine stays private for catalog matching."
```

---

### Task 2: Update NutritionCalculator to use safe API

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:107,113`
- Test: existing nutrition calculator tests should continue to pass

**Step 1: Update the two Inflector calls**

In `lib/familyrecipes/nutrition_calculator.rb`, change line 107:

```ruby
# Before (line 107)
unit_singular = Inflector.singular(recipe.makes_unit_noun) if recipe.makes_unit_noun

# After
unit_singular = Inflector.safe_singular(recipe.makes_unit_noun) if recipe.makes_unit_noun
```

And change line 113:

```ruby
# Before (line 113)
makes_unit_plural: (Inflector.plural(unit_singular) if unit_singular),

# After
makes_unit_plural: (Inflector.safe_plural(unit_singular) if unit_singular),
```

**Step 2: Run tests**

Run: `rake test`
Expected: ALL PASS — `singular`/`plural` are no longer called publicly anywhere.

**Step 3: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb
git commit -m "refactor: NutritionCalculator uses safe_singular/safe_plural (#113)"
```

---

### Task 3: Pluralize grocery list units server-side

**Files:**
- Modify: `app/services/shopping_list_builder.rb:116-118`
- Modify: `test/services/shopping_list_builder_test.rb` (add new tests + update one assertion)

**Step 1: Write failing tests**

Add these tests to `test/services/shopping_list_builder_test.rb` (after the existing tests, before the final `end`):

```ruby
  test 'serializes plural units for quantity greater than one' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    flour_amount = flour[:amounts].find { |_v, u| u == 'cups' }
    assert flour_amount, 'Expected plural unit "cups" for quantity 3.0'
    assert_in_delta 3.0, flour_amount[0], 0.01
  end

  test 'serializes singular unit for quantity of one' do
    MarkdownImporter.import(<<~MD, kitchen: @kitchen)
      # Toast

      Category: Bread

      ## Make (toast)

      - Flour, 1 cup

      Toast.
    MD

    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'toast', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    flour = result['Baking'].find { |i| i[:name] == 'Flour' }

    flour_amount = flour[:amounts].find { |_v, u| u == 'cup' }
    assert flour_amount, 'Expected singular unit "cup" for quantity 1.0'
  end

  test 'abbreviated units stay singular regardless of quantity' do
    list = MealPlan.for_kitchen(@kitchen)
    list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

    result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
    salt = result['Spices'].find { |i| i[:name] == 'Salt' }

    salt_amount = salt[:amounts].find { |_v, u| u == 'tsp' }
    assert salt_amount, 'Abbreviated units should not pluralize'
  end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n '/serializes|abbreviated/'`
Expected: FAIL — units are currently always singular.

**Step 3: Update ShoppingListBuilder**

In `app/services/shopping_list_builder.rb`, replace lines 116-118:

```ruby
  # Before (lines 116-118)
  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value.to_f, q.unit] }
  end

  # After
  def serialize_amounts(amounts)
    amounts.compact.map { |q| [q.value.to_f, display_unit(q)] }
  end

  def display_unit(quantity)
    return quantity.unit unless quantity.unit

    FamilyRecipes::Inflector.unit_display(quantity.unit, quantity.value)
  end
```

**Step 4: Fix the existing aggregation test assertion**

The existing test `aggregates quantities from multiple recipes` (line 111) asserts `u == 'cup'`. Now that units are pluralized, the aggregated 5.0 cups will be `'cups'`. Update line 111:

```ruby
# Before (line 111)
flour_cup = flour[:amounts].find { |_v, u| u == 'cup' }

# After
flour_cup = flour[:amounts].find { |_v, u| u == 'cups' }
```

**Step 5: Run all ShoppingListBuilder tests**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: ALL PASS

**Step 6: Run full test suite**

Run: `rake test`
Expected: ALL PASS

**Step 7: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "fix: pluralize grocery list units based on quantity (#113)

ShoppingListBuilder now shows '5 cups' instead of '5 cup'.
Abbreviated units (g, tsp, tbsp) are never pluralized."
```

---

### Task 4: Add `.yield-unit` span to ScalableNumberPreprocessor

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb:44-57`
- Modify: `test/scalable_number_preprocessor_test.rb` (update 3 test assertions)

**Step 1: Update tests to expect `.yield-unit` span**

In `test/scalable_number_preprocessor_test.rb`, update 3 assertions:

Line 141 — change:
```ruby
    assert_includes result, '>12</span> pancakes'
```
To:
```ruby
    assert_includes result, '<span class="yield-unit"> pancakes</span>'
```

Line 150 — change:
```ruby
    assert_includes result, '>two</span> loaves'
```
To:
```ruby
    assert_includes result, '<span class="yield-unit"> loaves</span>'
```

Line 157 — change:
```ruby
    assert_includes result, '>1</span> loaf'
```
To:
```ruby
    assert_includes result, '<span class="yield-unit"> loaf</span>'
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb -n /yield_with_unit/`
Expected: FAIL — no `.yield-unit` span yet.

**Step 3: Update `process_yield_with_unit`**

In `lib/familyrecipes/scalable_number_preprocessor.rb`, replace lines 44-57 of `process_yield_with_unit`:

```ruby
  # Before (lines 44-57)
  def process_yield_with_unit(text, unit_singular, unit_plural)
    match = text.match(YIELD_NUMBER_PATTERN)
    return ERB::Util.html_escape(text) unless match

    value = match[1] ? WORD_VALUES[match[1].downcase] : parse_numeral(match[2])
    inner_span = build_span(value, match[1] || match[2])
    rest = ERB::Util.html_escape(text[match.end(0)..])
    escaped_singular = ERB::Util.html_escape(unit_singular)
    escaped_plural = ERB::Util.html_escape(unit_plural)
    "#{ERB::Util.html_escape(text[...match.begin(0)])}" \
      "<span class=\"yield\" data-base-value=\"#{value}\" " \
      "data-unit-singular=\"#{escaped_singular}\" data-unit-plural=\"#{escaped_plural}\">" \
      "#{inner_span}#{rest}</span>"
  end

  # After
  def process_yield_with_unit(text, unit_singular, unit_plural)
    match = text.match(YIELD_NUMBER_PATTERN)
    return ERB::Util.html_escape(text) unless match

    value = match[1] ? WORD_VALUES[match[1].downcase] : parse_numeral(match[2])
    inner_span = build_span(value, match[1] || match[2])
    rest = ERB::Util.html_escape(text[match.end(0)..])
    escaped_singular = ERB::Util.html_escape(unit_singular)
    escaped_plural = ERB::Util.html_escape(unit_plural)
    "#{ERB::Util.html_escape(text[...match.begin(0)])}" \
      "<span class=\"yield\" data-base-value=\"#{value}\" " \
      "data-unit-singular=\"#{escaped_singular}\" data-unit-plural=\"#{escaped_plural}\">" \
      "#{inner_span}<span class=\"yield-unit\">#{rest}</span></span>"
  end
```

The only change: `#{rest}</span>` becomes `<span class=\"yield-unit\">#{rest}</span></span>`. The `rest` text (e.g., " pancakes") is wrapped in a `<span class="yield-unit">` instead of being a bare text node.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: ALL PASS (including XSS escape tests — unit values are still escaped).

**Step 5: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb test/scalable_number_preprocessor_test.rb
git commit -m "refactor: wrap yield unit text in .yield-unit span (#113)

Replaces bare text node with a span for cleaner JS manipulation."
```

---

### Task 5: Update `_step.html.erb` and RecipesHelper

**Files:**
- Modify: `app/views/recipes/_step.html.erb:19-20`
- Modify: `app/helpers/recipes_helper.rb` (add helper before `private`)
- Modify: `config/html_safe_allowlist.yml` (remove line 19 entry)

**Step 1: Add `ingredient_data_attrs` helper**

In `app/helpers/recipes_helper.rb`, add before the `private` line (line 51):

```ruby
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

Note: `tag.attributes` (Rails 7.1+) returns an `ActionView::Attributes` object that auto-escapes all values and is html_safe by construction. No manual escaping needed.

**Step 2: Update `_step.html.erb`**

Replace line 19 (the long `<li>` with inline `.html_safe`):

```erb
        <%- # Before (line 19) -%>
        <li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{ERB::Util.html_escape(FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2))}").html_safe if item.quantity_unit %><% end %>>

        <%- # After (line 19) -%>
        <li <%= ingredient_data_attrs(item) %>>
```

Replace line 20 (add class to `<b>`):

```erb
        <%- # Before (line 20) -%>
          <b><%= item.name %></b><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>

        <%- # After (line 20) -%>
          <b class="ingredient-name"><%= item.name %></b><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>
```

**Step 3: Update `html_safe_allowlist.yml`**

Remove the line 19 entry (no longer has `.html_safe`):

```yaml
# Before
- "app/views/recipes/_step.html.erb:19" # quantity_unit_plural: ERB::Util.html_escape wraps value

# After: remove this line entirely
```

The line 33 entry for `processed_instructions` stays — line numbers don't shift because line 19 is a 1-for-1 replacement.

**Step 4: Run lint and tests**

Run: `rake lint:html_safe && rake test`
Expected: ALL PASS. If line numbers shifted, `rake lint:html_safe` will tell you which lines to update.

**Step 5: Commit**

```bash
git add app/views/recipes/_step.html.erb app/helpers/recipes_helper.rb config/html_safe_allowlist.yml
git commit -m "feat: ingredient name data attributes for scaling (#113)

Add ingredient_data_attrs helper using tag.attributes (no .html_safe).
Emit data-name-singular/data-name-plural for unitless known-safe words.
Add .ingredient-name class to <b> tag for JS selection."
```

---

### Task 6: Update recipe_state_controller.js — ingredient and yield scaling

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:162-175,203-232`

**Step 1: Fix ingredient scaling (lines 162-175)**

Replace the ingredient scaling block:

```javascript
    // Before (lines 162-175)
    this.element
      .querySelectorAll('li[data-quantity-value]')
      .forEach(li => {
        const orig = parseFloat(li.dataset.quantityValue)
        const unitSingular = li.dataset.quantityUnit || ''
        const unitPlural = li.dataset.quantityUnitPlural || unitSingular
        const scaled = orig * factor
        const unit = (scaled === 1) ? unitSingular : unitPlural
        const pretty = Number.isInteger(scaled)
          ? scaled
          : Math.round(scaled * 100) / 100
        const span = li.querySelector('.quantity')
        if (span) span.textContent = pretty + (unit ? ' ' + unit : '')
      })

    // After
    this.element
      .querySelectorAll('li[data-quantity-value]')
      .forEach(li => {
        const orig = parseFloat(li.dataset.quantityValue)
        const unitSingular = li.dataset.quantityUnit || ''
        const unitPlural = li.dataset.quantityUnitPlural || unitSingular
        const scaled = orig * factor
        const unit = isVulgarSingular(scaled) ? unitSingular : unitPlural
        const pretty = formatVulgar(scaled)
        const span = li.querySelector('.quantity')
        if (span) span.textContent = pretty + (unit ? ' ' + unit : '')

        const nameEl = li.querySelector('.ingredient-name')
        if (nameEl && li.dataset.nameSingular) {
          nameEl.textContent = isVulgarSingular(scaled)
            ? li.dataset.nameSingular
            : li.dataset.namePlural
        }
      })
```

Changes:
1. `(scaled === 1)` → `isVulgarSingular(scaled)` — fixes the fraction singular bug
2. Manual rounding → `formatVulgar(scaled)` — consistent vulgar fraction display
3. New: adjusts `.ingredient-name` text when `data-name-singular`/`data-name-plural` exist

**Step 2: Update yield scaling (lines 203-232)**

Replace the yield scaling block:

```javascript
    // Before (lines 203-232)
    this.element.querySelectorAll('.yield[data-base-value]').forEach(container => {
      const base = parseFloat(container.dataset.baseValue)
      const scaled = base * factor
      const singular = container.dataset.unitSingular || ''
      const plural = container.dataset.unitPlural || singular

      const scalableSpan = container.querySelector('.scalable')
      if (!scalableSpan) return

      if (factor === 1) {
        scalableSpan.textContent = scalableSpan.dataset.originalText
        scalableSpan.classList.remove('scaled')
        scalableSpan.removeAttribute('title')
        const originalUnit = isVulgarSingular(base) ? singular : plural
        const textAfterSpan = scalableSpan.nextSibling
        if (textAfterSpan && textAfterSpan.nodeType === Node.TEXT_NODE) {
          textAfterSpan.textContent = ' ' + originalUnit
        }
      } else {
        const pretty = formatVulgar(scaled)
        const unit = isVulgarSingular(scaled) ? singular : plural
        scalableSpan.textContent = pretty
        scalableSpan.classList.add('scaled')
        scalableSpan.title = 'Originally: ' + scalableSpan.dataset.originalText
        const textAfterSpan = scalableSpan.nextSibling
        if (textAfterSpan && textAfterSpan.nodeType === Node.TEXT_NODE) {
          textAfterSpan.textContent = ' ' + unit
        }
      }
    })

    // After
    this.element.querySelectorAll('.yield[data-base-value]').forEach(container => {
      const base = parseFloat(container.dataset.baseValue)
      const scaled = base * factor
      const singular = container.dataset.unitSingular || ''
      const plural = container.dataset.unitPlural || singular

      const scalableSpan = container.querySelector('.scalable')
      const unitSpan = container.querySelector('.yield-unit')
      if (!scalableSpan || !unitSpan) return

      if (factor === 1) {
        scalableSpan.textContent = scalableSpan.dataset.originalText
        scalableSpan.classList.remove('scaled')
        scalableSpan.removeAttribute('title')
        unitSpan.textContent = ' ' + (isVulgarSingular(base) ? singular : plural)
      } else {
        const pretty = formatVulgar(scaled)
        const unit = isVulgarSingular(scaled) ? singular : plural
        scalableSpan.textContent = pretty
        scalableSpan.classList.add('scaled')
        scalableSpan.title = 'Originally: ' + scalableSpan.dataset.originalText
        unitSpan.textContent = ' ' + unit
      }
    })
```

Change: `scalableSpan.nextSibling` text node manipulation → `container.querySelector('.yield-unit')` span manipulation. Simpler and more robust.

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "fix: recipe scaling uses vulgar fractions and adjusts names (#113)

- Fix singular check for fractions (isVulgarSingular not === 1)
- Use formatVulgar for consistent number display
- Adjust ingredient names for known-safe words during scaling
- Yield scaling uses .yield-unit span instead of text nodes"
```

---

### Task 7: Run full test suite, lint, and html_safe audit

**Files:** None (verification only)

**Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: No new offenses. If RuboCop complains about method length in the rewritten Inflector, add targeted `# rubocop:disable` comments (the existing `Metrics/ModuleLength` disable is already there).

**Step 2: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: PASS. If line numbers shifted in `_step.html.erb` or `recipes_helper.rb`, update `config/html_safe_allowlist.yml` accordingly.

**Step 3: Run full test suite**

Run: `rake test`
Expected: ALL PASS.

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint fixes for safe pluralization (#113)"
```

Skip this commit if there are no changes.

---

### Task 8: Manual smoke test in browser

**Files:** None (verification only)

**Step 1: Start dev server**

Run: `pkill -f puma; rm -f tmp/pids/server.pid && bin/dev`

**Step 2: Test recipe scaling**

Test these recipes:
- **Chocolate Chip Cookies** (`/recipes/chocolate-chip-cookies`): Has "Egg, 1" and "Makes: 24 cookies". Scale 2x → "Eggs, 2", "48 cookies". Scale ½x → "Egg, ½", "12 cookies". Scale 1/24 → "1 cookie" (singular).
- **Focaccia** (`/recipes/focaccia`): Has "Flour, 3 cups". Scale 2x → "6 cups". Scale ⅓x → "1 cup".
- **Black Bean Tacos** (`/recipes/black-bean-tacos`): Has "Makes: 6 tacos". Scale ⅙x → "1 taco".

**Step 3: Test grocery list**

Select Focaccia + another bread recipe on the menu page. Go to groceries. Verify:
- "Flour (5 cups)" not "Flour (5 cup)"
- "Salt (1.5 tsp)" — abbreviated unit stays singular
- Ingredient names are the catalog's canonical form

**Step 4: Test oregano/paprika edge case**

Find a recipe with oregano on the grocery list. Verify it shows "Oregano (2 tsp)" — NOT "Oreganoes" anywhere.

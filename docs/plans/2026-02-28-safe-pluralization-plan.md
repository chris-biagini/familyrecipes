# Safe Pluralization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Replace the rule-based pluralization engine with a display-safe allowlist so the app never produces incorrect English ("oreganoes", "tomatoeses") while still pluralizing units and known ingredient names correctly.

**Architecture:** Two-tier Inflector: `KNOWN_PLURALS` allowlist for all user-visible output, private rule engine retained only for internal catalog matching. Grocery units pluralized server-side. Recipe scaling uses pre-computed data attributes for name/unit forms.

**Tech Stack:** Ruby (Inflector module, ShoppingListBuilder service, ERB partials), JavaScript (Stimulus recipe_state_controller), CSS (ingredient styling), Minitest.

**Design doc:** `docs/plans/2026-02-28-safe-pluralization-design.md`

---

### Task 1: Rewrite Inflector with KNOWN_PLURALS allowlist

**Files:**
- Modify: `lib/familyrecipes/inflector.rb` (entire file rewrite)
- Test: `test/inflector_test.rb` (entire file rewrite)

**Step 1: Write the failing tests for the new API**

Replace `test/inflector_test.rb` with tests for the new public methods. Key test categories:

```ruby
# safe_plural — allowlist-only, unknown words pass through
def test_safe_plural_known_word
  assert_equal 'cups', FamilyRecipes::Inflector.safe_plural('cup')
end

def test_safe_plural_unknown_word_passes_through
  assert_equal 'oregano', FamilyRecipes::Inflector.safe_plural('oregano')
end

def test_safe_plural_preserves_capitalization
  assert_equal 'Eggs', FamilyRecipes::Inflector.safe_plural('Egg')
end

def test_safe_plural_irregular
  assert_equal 'loaves', FamilyRecipes::Inflector.safe_plural('loaf')
end

def test_safe_plural_nil
  assert_nil FamilyRecipes::Inflector.safe_plural(nil)
end

def test_safe_plural_empty
  assert_equal '', FamilyRecipes::Inflector.safe_plural('')
end

def test_safe_plural_abbreviated_passes_through
  assert_equal 'g', FamilyRecipes::Inflector.safe_plural('g')
end

# safe_singular — allowlist-only, unknown words pass through
def test_safe_singular_known_word
  assert_equal 'cup', FamilyRecipes::Inflector.safe_singular('cups')
end

def test_safe_singular_unknown_word_passes_through
  assert_equal 'paprikas', FamilyRecipes::Inflector.safe_singular('paprikas')
end

def test_safe_singular_preserves_capitalization
  assert_equal 'Egg', FamilyRecipes::Inflector.safe_singular('Eggs')
end

def test_safe_singular_nil
  assert_nil FamilyRecipes::Inflector.safe_singular(nil)
end

# display_name — inflects last word of multi-word names if known
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

# unit_display — now uses safe_plural (same behavior, safe implementation)
def test_unit_display_abbreviated_never_pluralizes
  assert_equal 'g', FamilyRecipes::Inflector.unit_display('g', 100)
end

def test_unit_display_known_unit_pluralizes
  assert_equal 'cups', FamilyRecipes::Inflector.unit_display('cup', 2)
end

def test_unit_display_known_unit_singular
  assert_equal 'cup', FamilyRecipes::Inflector.unit_display('cup', 1)
end

def test_unit_display_unknown_unit_passes_through
  assert_equal 'gō', FamilyRecipes::Inflector.unit_display('gō', 2)
end

# normalize_unit — still uses rules (matching context, not display)
# Keep existing tests for normalize_unit, they should still pass

# ingredient_variants — still uses rules (matching context, not display)
# Keep existing tests for ingredient_variants, they should still pass
```

Also keep ALL existing `normalize_unit` tests (lines 182-304 of current file) and ALL existing `ingredient_variants` tests (lines 350-397). These methods use the private rule engine and their behavior must not change.

Remove all `test_singular_*`, `test_plural_*`, and `test_uncountable_*` tests — those methods are no longer public.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/inflector_test.rb`
Expected: FAIL — `safe_plural`, `safe_singular`, `display_name` methods don't exist yet.

**Step 3: Rewrite the Inflector**

Replace `lib/familyrecipes/inflector.rb`. Key structure:

```ruby
module FamilyRecipes
  module Inflector
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
      # Ingredient names
      'egg' => 'eggs', 'onion' => 'onions', 'lime' => 'limes',
      'pepper' => 'peppers', 'tomato' => 'tomatoes', 'carrot' => 'carrots',
      'walnut' => 'walnuts', 'olive' => 'olives', 'lentil' => 'lentils',
      'tortilla' => 'tortillas', 'bean' => 'beans', 'leaf' => 'leaves',
      'yolk' => 'yolks', 'berry' => 'berries', 'apple' => 'apples',
      'potato' => 'potatoes', 'lemon' => 'lemons',
    }.freeze

    KNOWN_SINGULARS = KNOWN_PLURALS.invert.freeze

    # ABBREVIATIONS and ABBREVIATED_FORMS stay exactly as-is
    # UNIT_ALIASES stays exactly as-is

    # --- Display-safe public API ---

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
      return name if adjusted == last_word  # unknown word, pass through

      rejoin_ingredient(prefix, adjusted, qualifier)
    end

    # --- Matching-only API (rules-based, NOT for display) ---

    def self.ingredient_variants(name)
      # Same implementation as before, using private singular/plural
    end

    def self.normalize_unit(raw_unit)
      # Same implementation as before, using private singular
    end

    # --- Private rule engine (matching only) ---

    def self.singular(word) ... end      # private
    def self.plural(word) ... end        # private
    def self.singularize_by_rules ... end # private
    def self.pluralize_by_rules ... end   # private
  end
end
```

IMPORTANT: Drop `UNCOUNTABLE`, `IRREGULAR_SINGULAR_TO_PLURAL`, `IRREGULAR_PLURAL_TO_SINGULAR`. The private `singular`/`plural` methods keep their rule engine logic but NO LONGER check UNCOUNTABLE — they're only used by `ingredient_variants` where "butteres" as a lookup key is harmless (won't match anything). The `alternate_form` private method still uses the private rules.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/inflector_test.rb`
Expected: ALL PASS

**Step 5: Run full test suite**

Run: `rake test`
Expected: PASS — no other code calls `singular`/`plural` publicly except `nutrition_calculator.rb` (fixed in Task 2).

**Step 6: Commit**

```bash
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "refactor: rewrite Inflector with KNOWN_PLURALS allowlist (#113)

Display-safe safe_plural/safe_singular use allowlist only.
Rule engine stays private for catalog matching."
```

---

### Task 2: Update NutritionCalculator to use safe API

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:107-113`
- Test: existing nutrition calculator tests should continue to pass

**Step 1: Update the two Inflector calls**

In `lib/familyrecipes/nutrition_calculator.rb`, change lines 107 and 113:

```ruby
# Before
unit_singular = Inflector.singular(recipe.makes_unit_noun) if recipe.makes_unit_noun
makes_unit_plural: (Inflector.plural(unit_singular) if unit_singular),

# After
unit_singular = Inflector.safe_singular(recipe.makes_unit_noun) if recipe.makes_unit_noun
makes_unit_plural: (Inflector.safe_plural(unit_singular) if unit_singular),
```

This is a safe change because yield nouns (cookies, loaves, rolls, etc.) are all in KNOWN_PLURALS. Unknown yield nouns will pass through unchanged, which is correct behavior.

**Step 2: Run tests**

Run: `rake test`
Expected: ALL PASS

**Step 3: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb
git commit -m "refactor: NutritionCalculator uses safe_singular/safe_plural (#113)"
```

---

### Task 3: Pluralize grocery list units server-side

**Files:**
- Modify: `app/services/shopping_list_builder.rb:116-118`
- Test: `test/services/shopping_list_builder_test.rb` (add new tests)

**Step 1: Write failing tests**

Add to `test/services/shopping_list_builder_test.rb`:

```ruby
test 'serializes units with correct plurality for count' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  flour = result['Baking'].find { |i| i[:name] == 'Flour' }

  flour_amount = flour[:amounts].find { |_v, u| u&.include?('cup') }
  assert_equal 'cups', flour_amount[1], 'Expected plural unit for quantity > 1'
end

test 'serializes singular unit for quantity of 1' do
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

  flour_amount = flour[:amounts].find { |_v, u| u&.include?('cup') }
  assert_equal 'cup', flour_amount[1], 'Expected singular unit for quantity of 1'
end

test 'abbreviated units stay singular regardless of quantity' do
  list = MealPlan.for_kitchen(@kitchen)
  list.apply_action('select', type: 'recipe', slug: 'focaccia', selected: true)

  result = ShoppingListBuilder.new(kitchen: @kitchen, meal_plan: list).build
  salt = result['Spices'].find { |i| i[:name] == 'Salt' }

  salt_amount = salt[:amounts].find { |_v, u| u == 'tsp' }
  assert_equal 'tsp', salt_amount[1], 'Abbreviated units should not pluralize'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb -n /serializes|abbreviated/`
Expected: FAIL — units are currently singular regardless of count.

**Step 3: Update ShoppingListBuilder**

In `app/services/shopping_list_builder.rb`, replace lines 116-118:

```ruby
def serialize_amounts(amounts)
  amounts.compact.map { |q| [q.value.to_f, display_unit(q)] }
end

def display_unit(quantity)
  return quantity.unit unless quantity.unit

  FamilyRecipes::Inflector.unit_display(quantity.unit, quantity.value)
end
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/shopping_list_builder_test.rb`
Expected: ALL PASS

Note: The existing `aggregates quantities from multiple recipes` test asserts `flour_cup = flour[:amounts].find { |_v, u| u == 'cup' }` on line 111. This will now fail because the unit is `'cups'` (plural for 5.0). Update this assertion:

```ruby
# Line 111 — change:
flour_cup = flour[:amounts].find { |_v, u| u == 'cup' }
# To:
flour_cup = flour[:amounts].find { |_v, u| u&.start_with?('cup') }
```

Also check the `consolidates singular and plural` test assertion on line 347 — `[[4.0, nil]]` has nil units, so it's unaffected.

**Step 5: Run full test suite**

Run: `rake test`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add app/services/shopping_list_builder.rb test/services/shopping_list_builder_test.rb
git commit -m "fix: pluralize grocery list units based on quantity (#113)

ShoppingListBuilder now shows '5 cups' instead of '5 cup'."
```

---

### Task 4: Add `.yield-unit` span to ScalableNumberPreprocessor

**Files:**
- Modify: `lib/familyrecipes/scalable_number_preprocessor.rb:44-57`
- Test: `test/scalable_number_preprocessor_test.rb` (update existing tests)

**Step 1: Update failing tests**

In `test/scalable_number_preprocessor_test.rb`, update the `process_yield_with_unit` tests to expect the new `.yield-unit` span:

```ruby
def test_yield_with_unit_wraps_number_and_noun
  result = ScalableNumberPreprocessor.process_yield_with_unit('12 pancakes', 'pancake', 'pancakes')

  assert_includes result, 'class="yield"'
  assert_includes result, 'data-base-value="12.0"'
  assert_includes result, 'data-unit-singular="pancake"'
  assert_includes result, 'data-unit-plural="pancakes"'
  assert_includes result, '<span class="scalable"'
  assert_includes result, '<span class="yield-unit"> pancakes</span>'
end

def test_yield_with_unit_handles_word_numbers
  result = ScalableNumberPreprocessor.process_yield_with_unit('two loaves', 'loaf', 'loaves')

  assert_includes result, 'data-base-value="2"'
  assert_includes result, '<span class="yield-unit"> loaves</span>'
end

def test_yield_with_unit_handles_single_item
  result = ScalableNumberPreprocessor.process_yield_with_unit('1 loaf', 'loaf', 'loaves')

  assert_includes result, 'data-base-value="1.0"'
  assert_includes result, '<span class="yield-unit"> loaf</span>'
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb -n /yield_with_unit/`
Expected: FAIL — no `.yield-unit` span yet.

**Step 3: Update `process_yield_with_unit`**

In `lib/familyrecipes/scalable_number_preprocessor.rb`, change lines 44-57:

```ruby
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

The key change: `rest` (the text after the number, e.g., " pancakes") goes inside a `<span class="yield-unit">` instead of being a bare text node.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/scalable_number_preprocessor_test.rb`
Expected: ALL PASS

Also check the XSS tests still pass — the unit escaping tests on lines 169-185 should be unaffected since unit values are still escaped.

**Step 5: Commit**

```bash
git add lib/familyrecipes/scalable_number_preprocessor.rb test/scalable_number_preprocessor_test.rb
git commit -m "refactor: wrap yield unit text in .yield-unit span (#113)

Replaces bare text node with a span for cleaner JS manipulation."
```

---

### Task 5: Update `_step.html.erb` — ingredient name markup and data attributes

**Files:**
- Modify: `app/views/recipes/_step.html.erb:18-24`
- Modify: `app/helpers/recipes_helper.rb` (add helper)
- Modify: `config/html_safe_allowlist.yml` (update line numbers if shifted)

**Step 1: Add helper method for ingredient name data attributes**

In `app/helpers/recipes_helper.rb`, add before the `private` line:

```ruby
def ingredient_name_attrs(name)
  singular = FamilyRecipes::Inflector.display_name(name, 1)
  plural = FamilyRecipes::Inflector.display_name(name, 2)
  return '' if singular == plural  # unknown word, no adjustment

  %( data-name-singular="#{ERB::Util.html_escape(singular)}" data-name-plural="#{ERB::Util.html_escape(plural)}")
end
```

**Step 2: Update the ingredient `<li>` in `_step.html.erb`**

Replace the ingredient `<li>` block (lines 18-24) with:

```erb
<li<% if item.quantity_value %> data-quantity-value="<%= item.quantity_value %>" data-quantity-unit="<%= item.quantity_unit %>"<%= %( data-quantity-unit-plural="#{ERB::Util.html_escape(FamilyRecipes::Inflector.unit_display(item.quantity_unit, 2))}").html_safe if item.quantity_unit %><% end %><%= ingredient_name_attrs(item.name).html_safe %>>
  <span class="ingredient-name"><%= item.name %></span><% if item.quantity_display %>, <span class="quantity"><%= item.quantity_display %></span><% end %>
<%- if item.prep_note -%>
  <small><%= item.prep_note %></small>
<%- end -%>
</li>
```

Changes from current:
- `<b>` → `<span class="ingredient-name">`
- Added `ingredient_name_attrs` call for `data-name-singular`/`data-name-plural`

**Step 3: Update `html_safe_allowlist.yml`**

The `.html_safe` call on `ingredient_name_attrs` is a new call in `_step.html.erb`. Add it to the allowlist (adjust line number to match actual output):

```yaml
- "app/views/recipes/_step.html.erb:19" # quantity_unit_plural: ERB::Util.html_escape wraps value
- "app/views/recipes/_step.html.erb:XX" # ingredient_name_attrs: ERB::Util.html_escape wraps values
```

Note: the existing line 19 allowlist entry may shift. Run `rake lint:html_safe` to identify the exact line numbers and update accordingly.

**Step 4: Add CSS for `.ingredient-name`**

In `app/assets/stylesheets/style.css`, add near the `.ingredients li` rules (around line 548):

```css
.ingredient-name { font-weight: bold; }
```

This preserves the visual bold that `<b>` provided.

**Step 5: Run lint and tests**

Run: `rake lint:html_safe && rake test`
Expected: ALL PASS

**Step 6: Commit**

```bash
git add app/views/recipes/_step.html.erb app/helpers/recipes_helper.rb \
  config/html_safe_allowlist.yml app/assets/stylesheets/style.css
git commit -m "feat: ingredient name data attributes for scaling (#113)

Replace <b> with <span class='ingredient-name'> and emit
data-name-singular/data-name-plural for known-safe words."
```

---

### Task 6: Update recipe_state_controller.js — ingredient scaling

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:159-175` (ingredient scaling)

**Step 1: Fix fraction singular check and add name adjustment**

Replace the ingredient scaling block (lines 162-175):

```javascript
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

    const nameSpan = li.querySelector('.ingredient-name')
    if (nameSpan && li.dataset.nameSingular) {
      nameSpan.textContent = isVulgarSingular(scaled)
        ? li.dataset.nameSingular
        : li.dataset.namePlural
    }
  })
```

Key changes:
1. `scaled === 1` → `isVulgarSingular(scaled)` for unit selection (fixes fraction bug)
2. Number formatting uses `formatVulgar(scaled)` instead of raw rounding (consistent with yield lines)
3. New: adjusts `.ingredient-name` text when `data-name-singular`/`data-name-plural` are present

**Step 2: Verify manually in browser**

Start dev server: `bin/dev`

Navigate to a recipe with eggs (e.g., Chocolate Chip Cookies at `/recipes/chocolate-chip-cookies`). Click Scale, enter "2". Verify:
- "Egg, 1" becomes "Eggs, 2"
- "Flour (all-purpose), 250 g" stays unchanged (no name data attrs for "Flour")
- "1 cup" becomes "2 cups" (not "2 cup")
- Scaling to ½x shows "½ cup" (singular) not "0.5 cups"

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "fix: recipe scaling uses vulgar fractions and adjusts names (#113)

- Fix singular check for fractions (isVulgarSingular not === 1)
- Use formatVulgar for consistent number display
- Adjust ingredient names for known-safe words during scaling"
```

---

### Task 7: Update recipe_state_controller.js — yield line scaling

**Files:**
- Modify: `app/javascript/controllers/recipe_state_controller.js:203-232` (yield scaling)

**Step 1: Update yield scaling to use `.yield-unit` span**

Replace the yield scaling block (lines 203-232):

```javascript
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

Key change: `container.querySelector('.yield-unit')` replaces `scalableSpan.nextSibling` text node manipulation.

**Step 2: Verify manually in browser**

Navigate to a recipe with Makes line (e.g., Pancakes: "Makes: 12 pancakes"). Scale to 2x. Verify:
- Shows "24 pancakes"
- Scale to ½x shows "6 pancakes"
- Reset to 1x shows "12 pancakes"
- Scale to 1/12 shows "1 pancake" (singular)

**Step 3: Commit**

```bash
git add app/javascript/controllers/recipe_state_controller.js
git commit -m "refactor: yield scaling uses .yield-unit span (#113)

Replaces fragile nextSibling text node manipulation."
```

---

### Task 8: Run full test suite and lint

**Files:** None (verification only)

**Step 1: Run lint**

Run: `rake lint`
Expected: No new offenses. If RuboCop complains about method length in the rewritten Inflector, add targeted `rubocop:disable` comments.

**Step 2: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: PASS. If line numbers shifted in `_step.html.erb` or `recipes_helper.rb`, update `config/html_safe_allowlist.yml`.

**Step 3: Run full test suite**

Run: `rake test`
Expected: ALL PASS.

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint fixes for safe pluralization (#113)"
```

---

### Task 9: Manual smoke test in browser

**Files:** None (verification only)

**Step 1: Start dev server**

Run: `pkill -f puma; rm -f tmp/pids/server.pid && bin/dev`

**Step 2: Test recipe scaling**

Test these recipes:
- **Chocolate Chip Cookies** (`/recipes/chocolate-chip-cookies`): Has "Egg, 1" and "Makes: 24 cookies". Scale 2x → "Eggs, 2", "48 cookies". Scale ½x → "Egg, ½", "12 cookies". Scale 1/24 → "cookie" (singular).
- **Focaccia** (`/recipes/focaccia`): Has "Flour, 3 cups". Scale 2x → "6 cups". Scale ⅓x → "1 cup".
- **Black Bean Tacos** (`/recipes/black-bean-tacos`): Has "Makes: 6 tacos". Scale ⅙x → "1 taco".

**Step 3: Test grocery list**

Select Focaccia + another bread recipe on the menu page. Go to groceries. Verify:
- "Flour (5 cups)" not "Flour (5 cup)"
- "Salt (1.5 tsp)" — abbreviated unit stays singular
- Ingredient names are the catalog's canonical form

**Step 4: Test with oregano/paprika (the important edge case)**

Create a test recipe via the editor with "Oregano, 2 tsp". Verify grocery list shows "Oregano (2 tsp)" — NOT "Oreganoes" anywhere. The ingredient name passes through unchanged.

---

### Task 10: Final cleanup and commit summary

**Files:** Potentially `docs/plans/2026-02-28-safe-pluralization-design.md`

**Step 1: Review the diff**

Run: `git log --oneline main..HEAD` to see all commits.

**Step 2: Verify GH#113 can be closed**

Check all items from the issue are addressed:
- [x] Grocery units pluralized: "5 cups", "12 cloves"
- [x] Recipe scaling fractions: "½ cup" (singular)
- [x] No more "oreganoes" — unknown words pass through
- [x] UNCOUNTABLE set removed
- [x] HTML cleanup: `<b>` → `<span>`, `.yield-unit` span
- [x] Consistent data attribute patterns

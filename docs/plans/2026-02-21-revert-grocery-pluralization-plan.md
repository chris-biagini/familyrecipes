# Revert Grocery Pluralization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix grocery list display bugs ("Kombus", "Jasmine rices", "Salad greenses") by reverting YAML keys to natural display forms and removing auto-pluralization.

**Architecture:** Revert the singular-canonical YAML migration (commit 519d143). Both grocery-info.yaml and nutrition-data.yaml return to natural display forms as shared canonical keys. The grocery template uses YAML values directly instead of auto-pluralizing via `name_for_grocery()`. The alias_map flips to generate singular aliases from display canonicals, so recipe input like "Carrot" still matches "Carrots".

**Tech Stack:** Ruby, ERB templates, Minitest, YAML data files

---

### Task 1: Revert grocery-info.yaml to display forms

**Files:**
- Modify: `resources/grocery-info.yaml`

**Step 1: Revert the countable items**

Apply the inverse of commit 519d143's grocery-info.yaml changes. Countable items return to their natural plural/display form. Mass nouns and inherently-plural items are already in their natural form and don't change.

Key changes (not exhaustive — apply the full inverse):
```yaml
# Produce
- Apple        →  - Apples
- Banana       →  - Bananas
- Red bell pepper  →  - Red bell peppers
- Green bell pepper  →  - Green bell peppers
- Berry        →  - Berries
- Blueberry    →  - Blueberries
- Brussels sprout  →  - Brussels sprouts
- Carrot       →  - Carrots
- Cherry       →  - Cherries
- Clementine   →  - Clementines
- Cucumber     →  - Cucumbers
- Grape        →  - Grapes
- Green onion  →  - Green onions
- Lemon        →  - Lemons
- Lime         →  - Limes
- Mango        →  - Mangoes
- Onion        →  - Onions
- Orange       →  - Oranges
- Potato       →  - Potatoes
- Red onion    →  - Red onions
- Strawberry   →  - Strawberries
- Tomato (fresh)  →  - Tomatoes (fresh)

# Gourmet
- Calabrian chili  →  - Calabrian chilis
- Olive        →  - Olives

# Bread
- Hamburger bun  →  - Hamburger buns

# International
- Bean (any dry)   →  - Beans (any dry)
- Bean (any canned)  →  - Beans (any canned)
- Black bean (canned)  →  - Black beans (canned)
- Red bean (dry)  →  - Red beans (dry)
- Chickpea (canned)  →  - Chickpeas (canned)
- Lentil       →  - Lentils
- Pickled jalapeño  →  - Pickled jalapeños
- Tortilla (corn)  →  - Tortillas (corn)
- Tortilla (large flour)  →  - Tortillas (large flour)

# Health
- RXBAR        →  - RXBARs

# Refrigerated
- name: Egg    →  - name: Eggs
  aliases: [Egg yolk, Egg white]  →    aliases: [Egg, Egg yolk, Egg white]

# Snacks
- Chocolate chip  →  - Chocolate chips
- Cookie       →  - Cookies
- Hershey's Kiss  →  - Hershey's Kisses
- Pretzel      →  - Pretzels
- Ritz cracker  →  - Ritz crackers
- Tortilla chip  →  - Tortilla chips
- Triscuit     →  - Triscuits

# Pantry
- name: Artichoke (jarred)  →  - name: Artichokes (jarred)
  aliases: [Marinated artichoke]  →    aliases: [Marinated artichokes]
- name: Jarred red pepper  →  - name: Jarred red peppers
  aliases: [Roasted pepper (jarred)]  →    aliases: [Roasted peppers (jarred)]
- Pecan        →  - Pecans
- Pickle       →  - Pickles
- Raisin       →  - Raisins
- Tomato (canned)  →  - Tomatoes (canned)
- Walnut       →  - Walnuts

# Frozen
- Chik'n nugget  →  - Chik'n nuggets
- Fro-yo bar   →  - Fro-yo bars
- Frozen potato  →  - Frozen potatoes
- Green bean   →  - Green beans
- Impossible burger  →  - Impossible burgers
- Soft pretzel  →  - Soft pretzels
```

Items that stay unchanged (already in natural form):
- All mass nouns: Bread, Asparagus, Baby spinach, Basil, Broccoli, Celery, Kombu, Rice, etc.
- Already-plural items: Salad greens, Sesame seeds, French fries, Rolled oats, Tater tots, Asian snacks, Chipotles en adobo, Peas and carrots (frozen), etc.
- Brand names: Goldfish, Peanut M&Ms, Peanut butter pretzels, Frank's Red Hot, Diet Coke, etc.

**Step 2: Verify YAML parses correctly**

Run: `ruby -ryaml -e "puts YAML.load_file('resources/grocery-info.yaml').keys.join(', ')"`
Expected: All aisle names printed without error.

**Step 3: Commit**

```
git add resources/grocery-info.yaml
git commit -m "revert: grocery-info.yaml keys to natural display forms"
```

---

### Task 2: Revert nutrition-data.yaml keys to match

**Files:**
- Modify: `resources/nutrition-data.yaml`

**Step 1: Rename the 6 countable keys**

These are the only keys that changed in commit 519d143:
```yaml
Carrot:          →  Carrots:
Egg:             →  Eggs:
Lemon:           →  Lemons:
Lime:            →  Limes:
Onion:           →  Onions:
Red bell pepper: →  Red bell peppers:
```

All other keys are already in their natural form (mass nouns, etc.) and don't change.

**Step 2: Verify YAML parses correctly**

Run: `ruby -ryaml -e "puts YAML.load_file('resources/nutrition-data.yaml').keys.sort.join(', ')"`
Expected: All keys printed, including "Carrots", "Eggs", "Lemons", "Limes", "Onions", "Red bell peppers".

**Step 3: Commit**

```
git add resources/nutrition-data.yaml
git commit -m "revert: nutrition-data.yaml keys to match display canonical"
```

---

### Task 3: Flip build_alias_map to generate singular aliases

**Files:**
- Modify: `lib/familyrecipes.rb:87-105`
- Test: `test/familyrecipes_test.rb`

**Step 1: Update the test for the new alias direction**

In `test/familyrecipes_test.rb`, the `test_build_alias_map` test currently uses singular canonical ("Apple") and expects plural aliases. Reverse it:

```ruby
def test_build_alias_map
  grocery_aisles = {
    'Produce' => [
      { name: 'Apples', aliases: ['Granny Smith apples', 'Gala apples'] }
    ]
  }

  alias_map = FamilyRecipes.build_alias_map(grocery_aisles)

  # Canonical name downcased maps to canonical
  assert_equal 'Apples', alias_map['apples']

  # Direct aliases (downcased) should map to canonical
  assert_equal 'Apples', alias_map['granny smith apples']
  assert_equal 'Apples', alias_map['gala apples']

  # Singular forms (downcased) should map to canonical
  assert_equal 'Apples', alias_map['apple']
  assert_equal 'Apples', alias_map['granny smith apple']
  assert_equal 'Apples', alias_map['gala apple']
end
```

Also update `test_build_known_ingredients`:

```ruby
def test_build_known_ingredients
  grocery_aisles = {
    'Produce' => [
      { name: 'Apples', aliases: ['Gala apples'] }
    ]
  }
  alias_map = { 'gala apples' => 'Apples', 'apple' => 'Apples', 'gala apple' => 'Apples' }

  known = FamilyRecipes.build_known_ingredients(grocery_aisles, alias_map)

  assert_includes known, 'apples'
  assert_includes known, 'gala apples'
  assert_includes known, 'apple'
  assert_includes known, 'gala apple'
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rake test TEST=test/familyrecipes_test.rb`
Expected: FAIL — alias_map still generates plural aliases from singular keys.

**Step 3: Update build_alias_map**

In `lib/familyrecipes.rb`, replace the plural alias generation with singular alias generation:

```ruby
def self.build_alias_map(grocery_aisles)
  grocery_aisles.each_value.with_object({}) do |items, alias_map|
    items.each do |item|
      canonical = item[:name]

      alias_map[canonical.downcase] = canonical

      item[:aliases].each { |al| alias_map[al.downcase] = canonical }

      singular = Inflector.singular(canonical)
      alias_map[singular.downcase] = canonical unless singular.downcase == canonical.downcase

      item[:aliases].each do |al|
        singular = Inflector.singular(al)
        alias_map[singular.downcase] = canonical unless singular.downcase == al.downcase
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bundle exec rake test TEST=test/familyrecipes_test.rb`
Expected: PASS

**Step 5: Commit**

```
git add lib/familyrecipes.rb test/familyrecipes_test.rb
git commit -m "fix: build_alias_map generates singular aliases from display canonicals"
```

---

### Task 4: Remove name_for_grocery from grocery page generation

**Files:**
- Modify: `lib/familyrecipes/site_generator.rb:188-190`
- Modify: `templates/web/groceries-template.html.erb:98,101`

**Step 1: Update SiteGenerator to use YAML name directly**

In `site_generator.rb`, change `generate_groceries_page` (line 188-190):

Before:
```ruby
grocery_info = @grocery_aisles.transform_values do |items|
  items.map { |item| { name: item[:name], display_name: Inflector.name_for_grocery(item[:name]) } }
end
```

After:
```ruby
grocery_info = @grocery_aisles.transform_values do |items|
  items.map { |item| { name: item[:name] } }
end
```

**Step 2: Update groceries template to use `name` instead of `display_name`**

In `groceries-template.html.erb`, line 101:

Before:
```erb
<span><%= ingredient[:display_name] %><span class="qty"></span></span>
```

After:
```erb
<span><%= ingredient[:name] %><span class="qty"></span></span>
```

**Step 3: Run full test suite**

Run: `bundle exec rake test`
Expected: PASS (template rendering tests should still work)

**Step 4: Run build and spot-check output**

Run: `bin/generate`
Expected: No errors. Spot-check `output/web/groceries/index.html` — search for "Carrots", "Salad greens", "Kombu" and confirm no malformed plurals like "Kombus" or "Salad greenses".

**Step 5: Commit**

```
git add lib/familyrecipes/site_generator.rb templates/web/groceries-template.html.erb
git commit -m "fix: grocery display uses YAML names directly, drop name_for_grocery"
```

---

### Task 5: Remove name_for_grocery and name_for_count from Inflector

**Files:**
- Modify: `lib/familyrecipes/inflector.rb:80-114`
- Modify: `test/inflector_test.rb:348-415`

**Step 1: Remove the methods from Inflector**

Delete `name_for_grocery`, `name_for_count`, and private helpers `uncountable_name?` and `split_qualified` from `lib/familyrecipes/inflector.rb` (lines 80-114).

**Step 2: Remove the corresponding tests**

Delete the `# --- name_for_grocery ---` and `# --- name_for_count ---` test sections from `test/inflector_test.rb` (lines 348-415).

**Step 3: Verify no remaining callers**

Run: `grep -r 'name_for_grocery\|name_for_count\|split_qualified\|uncountable_name' lib/ templates/ test/`
Expected: No matches.

**Step 4: Run full test suite**

Run: `bundle exec rake test`
Expected: PASS

**Step 5: Commit**

```
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "refactor: remove name_for_grocery and name_for_count from Inflector"
```

---

### Task 6: Add "go" irregular and run full validation

**Files:**
- Modify: `lib/familyrecipes/inflector.rb` (IRREGULAR_SINGULAR_TO_PLURAL)
- Modify: `test/inflector_test.rb`

**Step 1: Write the failing test**

```ruby
def test_plural_irregular_go
  assert_equal 'go', FamilyRecipes::Inflector.plural('go')
end

def test_singular_irregular_go
  assert_equal 'go', FamilyRecipes::Inflector.singular('go')
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rake test TEST=test/inflector_test.rb TESTOPTS="--name=/irregular_go/"`
Expected: FAIL — `plural('go')` currently returns "goes".

**Step 3: Add the irregular**

Add to `IRREGULAR_SINGULAR_TO_PLURAL` in `inflector.rb`:
```ruby
IRREGULAR_SINGULAR_TO_PLURAL = {
  'cookie' => 'cookies',
  'go' => 'go',
  'leaf' => 'leaves',
  'loaf' => 'loaves',
  'taco' => 'tacos'
}.freeze
```

**Step 4: Run full validation**

Run: `bundle exec rake` (runs lint + tests)
Expected: All pass.

Run: `bin/generate`
Expected: Clean build with no warnings related to ingredient matching.

**Step 5: Commit**

```
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "fix: add go→go irregular for Japanese gō unit

Closes #62"
```

---

### Task 7: Update design docs

**Files:**
- Update: `docs/plans/2026-02-20-unified-pluralization-design.md` — add a note at the top that the singular-canonical decision was reversed in the 2026-02-21 design.

**Step 1: Add reversal note**

Add after the title:
```markdown
> **Note:** The singular-canonical YAML key decision was reversed on 2026-02-21.
> See `2026-02-21-revert-grocery-pluralization-design.md` for rationale.
> YAML keys now use natural display forms (the pre-migration convention).
```

**Step 2: Commit**

```
git add docs/plans/
git commit -m "docs: add reversal note to unified pluralization design"
```

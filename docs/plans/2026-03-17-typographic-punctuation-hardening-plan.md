# Typographic Punctuation Hardening Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden quantity parsing against em-dashes and string comparisons against smart apostrophes/quotes.

**Architecture:** Three independent changes: (1) extend dash normalization in the parser-layer `Ingredient` class, (2) add a shared `normalize_for_comparison` helper and wire it into `IngredientResolver` and `CrossReferenceUpdater`, (3) add `normalizeForSearch` to the search overlay JS.

**Tech Stack:** Ruby (Minitest), JavaScript (Stimulus)

**Spec:** `docs/plans/2026-03-17-typographic-punctuation-hardening-design.md`

---

### Task 1: Em-dash normalization in quantity parsing

**Files:**
- Modify: `lib/familyrecipes/ingredient.rb:25,31,61`
- Test: `test/ingredient_test.rb`

- [ ] **Step 1: Write failing tests for em-dash handling**

Add three tests after the existing `test_normalize_quantity_already_ascii` (line 203):

```ruby
def test_normalize_quantity_em_dash_to_hyphen
  assert_equal '2-3 cups', FamilyRecipes::Ingredient.normalize_quantity("2\u20143 cups")
end

def test_parse_range_em_dash
  assert_equal [2.0, 3.0], FamilyRecipes::Ingredient.parse_range("2\u20143")
end

def test_numeric_value_em_dash_range
  ingredient = FamilyRecipes::Ingredient.new(name: 'Eggs', quantity: "2\u20143")

  assert_equal '3', ingredient.quantity_value
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/ingredient_test.rb -n '/em_dash/'`
Expected: 3 failures — `normalize_quantity` doesn't convert em-dash, `parse_range` doesn't split on it, `numeric_value` doesn't split on it.

- [ ] **Step 3: Fix normalize_quantity**

In `lib/familyrecipes/ingredient.rb`, change line 25 from:

```ruby
result.tr("\u2013", '-')
```

to:

```ruby
result.tr("\u2013\u2014", '--')
```

- [ ] **Step 4: Fix parse_range**

In `lib/familyrecipes/ingredient.rb`, change line 31 from:

```ruby
parts = value_str.strip.split(/[-–]/, 2)
```

to:

```ruby
parts = value_str.strip.split(/[-–—]/, 2)
```

- [ ] **Step 5: Fix numeric_value**

In `lib/familyrecipes/ingredient.rb`, change both occurrences on line 61 from:

```ruby
value_str = value_str.split(/[-–]/).last.strip if value_str.match?(/[-–]/)
```

to:

```ruby
value_str = value_str.split(/[-–—]/).last.strip if value_str.match?(/[-–—]/)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `ruby -Itest test/ingredient_test.rb`
Expected: All tests pass (existing + 3 new).

- [ ] **Step 7: Run full test suite**

Run: `rake test`
Expected: All green.

- [ ] **Step 8: Commit**

```bash
git add lib/familyrecipes/ingredient.rb test/ingredient_test.rb
git commit -m "Add em-dash normalization to quantity parsing"
```

---

### Task 2: Shared `normalize_for_comparison` helper

**Files:**
- Modify: `lib/familyrecipes.rb`
- Test: `test/familyrecipes_test.rb` (or create if needed)

This task adds the shared Ruby helper used by Tasks 3 and 4. It's a simple
`.tr` call, placed on the `FamilyRecipes` module next to `slugify`.

- [ ] **Step 1: Write failing tests**

Add to the existing `test/familyrecipes_test.rb` (a `Minitest::Test` file —
already exists with `slugify` tests):

```ruby
def test_normalize_for_comparison_curly_single_quotes
  assert_equal "Grandma's Cookies", FamilyRecipes.normalize_for_comparison("Grandma\u2019s Cookies")
end

def test_normalize_for_comparison_left_single_quote
  assert_equal "'quoted'", FamilyRecipes.normalize_for_comparison("\u2018quoted\u2019")
end

def test_normalize_for_comparison_curly_double_quotes
  assert_equal '"hello"', FamilyRecipes.normalize_for_comparison("\u201Chello\u201D")
end

def test_normalize_for_comparison_mixed
  assert_equal "Baker's \"Best\" Rolls", FamilyRecipes.normalize_for_comparison("Baker\u2019s \u201CBest\u201D Rolls")
end

def test_normalize_for_comparison_no_change
  assert_equal "plain text", FamilyRecipes.normalize_for_comparison("plain text")
end

def test_normalize_for_comparison_nil
  assert_equal "", FamilyRecipes.normalize_for_comparison(nil)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/familyrecipes_test.rb -n '/normalize_for_comparison/'`
Expected: Failures — method doesn't exist yet.

- [ ] **Step 3: Implement `normalize_for_comparison`**

In `lib/familyrecipes.rb`, add after the `slugify` method (after line 31):

```ruby
def self.normalize_for_comparison(str)
  return '' if str.nil?

  str.tr("\u2018\u2019\u201C\u201D", "''\"\"")
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/familyrecipes_test.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/familyrecipes.rb test/familyrecipes_test.rb
git commit -m "Add FamilyRecipes.normalize_for_comparison for smart punctuation"
```

---

### Task 3: Harden IngredientResolver lookups

**Files:**
- Modify: `app/services/ingredient_resolver.rb:18-21,57-58,64-65,75`
- Test: `test/services/ingredient_resolver_test.rb`

The resolver builds two hashes: `@lookup` (exact match) and `@ci_lookup`
(case-insensitive fallback). Smart punctuation can cause mismatches in both.
The fix: normalize keys in `@ci_lookup` at build time, and normalize the query
in `find_entry` and `resolve_uncataloged`.

**Note on `IngredientCatalog.lookup_for`:** The spec mentions normalizing keys
there too, but it's unnecessary. The catalog builds the lookup hash keyed by
`ingredient_name` (author-controlled, typically ASCII). The resolver's
`@ci_lookup` fallback with `normalize_key` catches any mismatch. Normalizing
at the resolver level is sufficient and less invasive than modifying the
catalog's hash-building logic (which also feeds alias collision detection).

- [ ] **Step 1: Write failing tests**

Add to `test/services/ingredient_resolver_test.rb`:

```ruby
test 'resolves curly apostrophe when catalog has straight' do
  catalog = { "baker's chocolate" => FakeEntry.new(ingredient_name: "baker's chocolate") }
  resolver = IngredientResolver.new(catalog)

  assert_equal "baker's chocolate", resolver.resolve("baker\u2019s chocolate")
end

test 'resolves straight apostrophe when catalog has curly' do
  catalog = { "baker\u2019s chocolate" => FakeEntry.new(ingredient_name: "baker\u2019s chocolate") }
  resolver = IngredientResolver.new(catalog)

  assert_equal "baker\u2019s chocolate", resolver.resolve("baker's chocolate")
end

test 'cataloged? matches across apostrophe styles' do
  catalog = { "baker's chocolate" => FakeEntry.new(ingredient_name: "baker's chocolate") }
  resolver = IngredientResolver.new(catalog)

  assert resolver.cataloged?("baker\u2019s chocolate")
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/ingredient_resolver_test.rb -n '/apostrophe/'`
Expected: 3 failures — current code doesn't normalize apostrophes.

- [ ] **Step 3: Implement normalization in IngredientResolver**

In `app/services/ingredient_resolver.rb`:

Change `initialize` (lines 18-21) to normalize keys for `@ci_lookup`:

```ruby
def initialize(lookup)
  @lookup = lookup
  @ci_lookup = lookup.each_with_object({}) { |(k, v), h| h[normalize_key(k)] ||= v }
  @uncataloged = {}
end
```

Change `find_entry` (lines 57-58) to normalize the query:

```ruby
def find_entry(name)
  @lookup[name] || @ci_lookup[normalize_key(name)]
end
```

Change `resolve_uncataloged` (lines 64-65) to use normalized keys:

```ruby
def resolve_uncataloged(name)
  return name if name.blank?

  normalized = normalize_key(name)
  return @uncataloged[normalized] if @uncataloged.key?(normalized)

  existing = find_variant_match(name, normalized)
  return existing if existing

  @uncataloged[normalized] = name
end
```

Update `find_variant_match` (line 75) and `register_alias` (line 81):

```ruby
def find_variant_match(name, normalized_name = normalize_key(name))
  FamilyRecipes::Inflector.ingredient_variants(name).each do |variant|
    canonical = @uncataloged[normalize_key(variant)]
    return register_alias(normalized_name, canonical) if canonical
  end
  nil
end

def register_alias(normalized_name, canonical)
  @uncataloged[normalized_name] = canonical
  canonical
end
```

Add the private helper:

```ruby
def normalize_key(str)
  FamilyRecipes.normalize_for_comparison(str).downcase
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/ingredient_resolver_test.rb`
Expected: All tests pass (existing + 3 new).

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add app/services/ingredient_resolver.rb test/services/ingredient_resolver_test.rb
git commit -m "Harden IngredientResolver lookups against smart apostrophes"
```

---

### Task 4: Harden CrossReferenceUpdater against smart punctuation

**Files:**
- Modify: `app/services/cross_reference_updater.rb:21-23`
- Test: `test/services/cross_reference_updater_test.rb`

The generated markdown comes from `RecipeSerializer` (which reads
`CrossReference#target_title` from the DB). If the DB has a curled apostrophe
in `target_title` but `@recipe.title` has a straight one, the literal `gsub`
misses. The fix uses a regex that matches within `@[...]` syntax and compares
normalized titles, preserving all other content unchanged.

- [ ] **Step 1: Write failing tests**

Add to `test/services/cross_reference_updater_test.rb`:

```ruby
test 'rename_references matches when cross-reference has curly apostrophe' do
  dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
    # Grandma's Dough

    ## Mix

    - Flour, 3 cups

    Mix together.
  MD

  # Simulate a cross-reference stored with curly apostrophe in target_title.
  # RecipeSerializer will emit @[Grandma\u2019s Dough] in the generated
  # markdown, but @recipe.title is "Grandma's Dough" (straight).
  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
    # Sunday Pizza

    ## Make dough
    > @[Grandma's Dough], 1

    ## Assemble

    - Cheese, 8 oz

    Top it.
  MD

  xref = pizza.cross_references.first
  xref.update_column(:target_title, "Grandma\u2019s Dough")

  CrossReferenceUpdater.rename_references(old_title: "Grandma's Dough",
                                          new_title: "Nana's Dough",
                                          kitchen: @kitchen)

  pizza.reload
  assert pizza.cross_references.find_by(target_title: "Nana's Dough"),
         'cross-reference should be updated despite apostrophe mismatch'
end

test 'rename_references preserves non-cross-reference prose unchanged' do
  dough = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
    # Grandma's Dough

    ## Mix

    - Flour, 3 cups

    Mix together.
  MD

  pizza = MarkdownImporter.import(<<~MD, kitchen: @kitchen, category: @category).recipe
    # Sunday Pizza

    ## Make dough
    > @[Grandma's Dough], 1

    ## Assemble

    - Cheese, 8 oz

    Grandma\u2019s tip: stretch gently.
  MD

  xref = pizza.cross_references.first
  xref.update_column(:target_title, "Grandma\u2019s Dough")

  CrossReferenceUpdater.rename_references(old_title: "Grandma's Dough",
                                          new_title: "Nana's Dough",
                                          kitchen: @kitchen)

  pizza.reload
  step = pizza.steps.find_by(title: 'Assemble')
  assert_includes step.instructions, "\u2019",
                  'curly apostrophe in prose should be preserved'
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/services/cross_reference_updater_test.rb -n '/curly|prose/'`
Expected: First test fails (gsub misses the curled apostrophe). Second test
may pass or fail depending on whether the current code touches prose.

- [ ] **Step 3: Implement normalization in CrossReferenceUpdater**

In `app/services/cross_reference_updater.rb`, change `rename_references`
(lines 21-23) from:

```ruby
def rename_references(new_title)
  old_title = @recipe.title
  update_referencing_recipes { |source, _| source.gsub("@[#{old_title}]", "@[#{new_title}]") }
end
```

to:

```ruby
def rename_references(new_title)
  normalized_old = FamilyRecipes.normalize_for_comparison(@recipe.title)
  update_referencing_recipes do |source, _|
    source.gsub(/@\[([^\]]+)\]/) do |match|
      ref_title = Regexp.last_match(1)
      FamilyRecipes.normalize_for_comparison(ref_title) == normalized_old ? "@[#{new_title}]" : match
    end
  end
end
```

This regex matches only `@[...]` cross-reference patterns. For each match, it
normalizes the captured title and compares against the normalized old title.
Only matching references are replaced; all other content (including smart
punctuation in prose) is preserved unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/services/cross_reference_updater_test.rb`
Expected: All tests pass (existing + 1 new).

- [ ] **Step 5: Run full test suite**

Run: `rake test`
Expected: All green.

- [ ] **Step 6: Commit**

```bash
git add app/services/cross_reference_updater.rb test/services/cross_reference_updater_test.rb
git commit -m "Harden CrossReferenceUpdater against smart apostrophes"
```

---

### Task 5: Harden search overlay against smart punctuation

**Files:**
- Modify: `app/javascript/controllers/search_overlay_controller.js`

No existing JS test file for the search overlay, so this is manual
verification only.

- [ ] **Step 1: Add normalizeForSearch helper**

Add at the top of `search_overlay_controller.js`, after the import:

```javascript
function normalizeForSearch(str) {
  return (str || "")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
}
```

- [ ] **Step 2: Normalize indexed data in loadData()**

In `loadData()`, add normalized shadow fields to each recipe for matching.
Change the `loadData` method to:

```javascript
loadData() {
  const data = this.hasDataTarget
    ? JSON.parse(this.dataTarget.textContent || "{}")
    : {}
  this.recipes = (data.recipes || []).map(r => ({
    ...r,
    _title: normalizeForSearch(r.title).toLowerCase(),
    _description: normalizeForSearch(r.description).toLowerCase(),
    _ingredients: r.ingredients.map(i => normalizeForSearch(i).toLowerCase()),
    _tags: r.tags?.map(t => normalizeForSearch(t).toLowerCase()),
    _category: normalizeForSearch(r.category).toLowerCase()
  }))
  this.allTags = new Set((data.all_tags || []).map(t => normalizeForSearch(t).toLowerCase()))
  this.allCategories = new Set((data.all_categories || []).map(c => normalizeForSearch(c).toLowerCase()))
}
```

- [ ] **Step 3: Update matching methods to use normalized fields**

Change `performSearch` query normalization:

```javascript
const query = normalizeForSearch(this.inputTarget.value).toLowerCase().trim()
```

Change `checkForPillConversion`:

```javascript
const lower = normalizeForSearch(word).toLowerCase()
```

Change `textContains` to use shadow fields:

```javascript
textContains(recipe, text) {
  return recipe._title.includes(text) ||
    recipe._description.includes(text) ||
    recipe._ingredients.some(i => i.includes(text))
}
```

Change `matchTier` to use shadow fields:

```javascript
matchTier(recipe, query) {
  if (recipe._title.includes(query)) return 0
  if (recipe._description.includes(query)) return 1
  if (recipe._category.includes(query)) return 2
  if (recipe._tags?.some(t => t.includes(query))) return 3
  if (recipe._ingredients.some(i => i.includes(query))) return 4
  return 5
}
```

Change `matchesPill` to use shadow fields:

```javascript
matchesPill(recipe, pill) {
  const text = pill.text
  if (pill.type === "tag") {
    return recipe._tags?.some(t => t === text) || this.textContains(recipe, text)
  }
  if (pill.type === "category") {
    return recipe._category === text || this.textContains(recipe, text)
  }
  return false
}
```

Change `updateHint` to normalize:

```javascript
updateHint() {
  const word = normalizeForSearch(this.inputTarget.value).trim().toLowerCase()
  const matches = word && (this.allTags.has(word) || this.allCategories.has(word))
  this.inputTarget.classList.toggle("search-input--hinted", matches)
}
```

Note: `renderResults` continues to use the original `recipe.title` and
`recipe.category` for display — the shadow `_` fields are only for matching.

- [ ] **Step 4: Build JS**

Run: `npm run build`
Expected: Clean build, no errors.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/search_overlay_controller.js
git commit -m "Harden search overlay against smart apostrophes"
```

---

### Task 6: Lint and final verification

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop`
Expected: 0 offenses. Fix any that appear.

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All green.

- [ ] **Step 3: Run JS build**

Run: `npm run build`
Expected: Clean build.

- [ ] **Step 4: Final commit if any lint fixes were needed**

```bash
git add -A && git commit -m "Fix lint offenses from typographic punctuation changes"
```

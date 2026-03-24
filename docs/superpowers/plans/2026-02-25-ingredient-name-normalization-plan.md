# Ingredient Name Normalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Wire the existing `Inflector` singular/plural logic into `IngredientCatalog.lookup_for` and `BuildValidator` so variant names like "Egg"/"Eggs" resolve to the same catalog entry.

**Architecture:** Add `Inflector.ingredient_variants(name)` that returns alternate singular/plural forms of an ingredient name. Enhance `lookup_for` to populate variant keys in the returned hash. Update `BuildValidator` to check variants when validating known ingredients.

**Tech Stack:** Ruby, Rails, Minitest. No new gems, no migrations.

---

### Task 1: Add `Inflector.ingredient_variants`

**Files:**
- Modify: `lib/familyrecipes/inflector.rb:64` (after `uncountable?`)
- Test: `test/inflector_test.rb`

**Step 1: Write the failing tests**

Add to the end of `test/inflector_test.rb`, before the final `end`:

```ruby
# --- ingredient_variants ---

def test_ingredient_variants_plural_to_singular
  assert_equal ['Egg'], FamilyRecipes::Inflector.ingredient_variants('Eggs')
end

def test_ingredient_variants_singular_to_plural
  assert_equal ['Eggs'], FamilyRecipes::Inflector.ingredient_variants('Egg')
end

def test_ingredient_variants_uncountable_returns_empty
  assert_empty FamilyRecipes::Inflector.ingredient_variants('Butter')
end

def test_ingredient_variants_uncountable_with_qualifier_returns_empty
  assert_empty FamilyRecipes::Inflector.ingredient_variants('Flour (all-purpose)')
end

def test_ingredient_variants_qualified_name_inflects_base
  assert_equal ['Tomato (canned)'], FamilyRecipes::Inflector.ingredient_variants('Tomatoes (canned)')
end

def test_ingredient_variants_multi_word_inflects_last_word
  assert_equal ['Egg yolk'], FamilyRecipes::Inflector.ingredient_variants('Egg yolks')
end

def test_ingredient_variants_multi_word_singular_to_plural
  assert_equal ['Egg yolks'], FamilyRecipes::Inflector.ingredient_variants('Egg yolk')
end

def test_ingredient_variants_nil_returns_empty
  assert_empty FamilyRecipes::Inflector.ingredient_variants(nil)
end

def test_ingredient_variants_empty_returns_empty
  assert_empty FamilyRecipes::Inflector.ingredient_variants('')
end

def test_ingredient_variants_irregular_leaves
  assert_equal ['Bay leaf'], FamilyRecipes::Inflector.ingredient_variants('Bay leaves')
end

def test_ingredient_variants_irregular_singular_to_plural
  assert_equal ['Bay leaves'], FamilyRecipes::Inflector.ingredient_variants('Bay leaf')
end

def test_ingredient_variants_already_both_forms_same
  # "grass" singularizes to "grass" (ss ending) — no useful variant
  assert_empty FamilyRecipes::Inflector.ingredient_variants('grass')
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/inflector_test.rb -n /ingredient_variants/`
Expected: FAIL — `NoMethodError: undefined method 'ingredient_variants'`

**Step 3: Implement `ingredient_variants`**

Add to `lib/familyrecipes/inflector.rb` after the `uncountable?` method (line 67), before the `normalize_unit` method:

```ruby
def self.ingredient_variants(name)
  return [] if name.blank?

  base, qualifier = split_ingredient_name(name)
  last_word = base.split.last
  prefix = base.split[0..-2].join(' ')

  singular_form = singular(last_word)
  plural_form = plural(last_word)

  variants = []
  variants << rejoin_ingredient(prefix, singular_form, qualifier) if singular_form != last_word
  variants << rejoin_ingredient(prefix, plural_form, qualifier) if plural_form != last_word
  variants
end
```

And two private helpers at the bottom of the module (before the final `end`):

```ruby
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
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/inflector_test.rb -n /ingredient_variants/`
Expected: All 12 tests PASS.

**Step 5: Run full inflector test suite**

Run: `ruby -Itest test/inflector_test.rb`
Expected: All tests PASS (existing tests unaffected).

**Step 6: Lint**

Run: `bundle exec rubocop lib/familyrecipes/inflector.rb test/inflector_test.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "feat: add Inflector.ingredient_variants for singular/plural name resolution"
```

---

### Task 2: Enhance `IngredientCatalog.lookup_for` with variant keys

**Files:**
- Modify: `app/models/ingredient_catalog.rb:17-20`
- Test: `test/models/ingredient_catalog_test.rb`

**Step 1: Write the failing tests**

Add to `test/models/ingredient_catalog_test.rb` before the final `end`:

```ruby
test 'lookup_for resolves singular variant of plural catalog name' do
  IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert result.key?('Eggs'), 'exact key should exist'
  assert result.key?('Egg'), 'singular variant should resolve'
  assert_equal result['Eggs'].id, result['Egg'].id
end

test 'lookup_for resolves plural variant of singular catalog name' do
  IngredientCatalog.create!(ingredient_name: 'Carrot', basis_grams: 50, calories: 25)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert result.key?('Carrot'), 'exact key should exist'
  assert result.key?('Carrots'), 'plural variant should resolve'
  assert_equal result['Carrot'].id, result['Carrots'].id
end

test 'lookup_for does not overwrite explicit entry with variant' do
  eggs_entry = IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
  egg_entry = IngredientCatalog.create!(ingredient_name: 'Egg', basis_grams: 50, calories: 80)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert_equal eggs_entry.id, result['Eggs'].id
  assert_equal egg_entry.id, result['Egg'].id
end

test 'lookup_for skips variants for uncountable names' do
  IngredientCatalog.create!(ingredient_name: 'Butter', basis_grams: 14)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert result.key?('Butter')
  assert_equal 1, result.size
end

test 'lookup_for handles qualified names with variants' do
  IngredientCatalog.create!(ingredient_name: 'Tomatoes (canned)', basis_grams: 100)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert result.key?('Tomatoes (canned)')
  assert result.key?('Tomato (canned)')
end

test 'lookup_for kitchen override applies to variants too' do
  IngredientCatalog.create!(ingredient_name: 'Eggs', basis_grams: 50, calories: 70)
  kitchen_entry = IngredientCatalog.create!(kitchen: @kitchen, ingredient_name: 'Eggs', basis_grams: 50, calories: 80)
  result = IngredientCatalog.lookup_for(@kitchen)

  assert_equal kitchen_entry.id, result['Egg'].id
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /variant/`
Expected: FAIL — variant keys not in the hash.

**Step 3: Implement the variant-aware `lookup_for`**

Replace the `lookup_for` method in `app/models/ingredient_catalog.rb`:

```ruby
def self.lookup_for(kitchen)
  base = global.index_by(&:ingredient_name)
               .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
  add_ingredient_variants(base)
end

def self.add_ingredient_variants(lookup)
  variants = {}
  lookup.each do |_name, entry|
    FamilyRecipes::Inflector.ingredient_variants(entry.ingredient_name).each do |variant|
      variants[variant] = entry unless lookup.key?(variant)
    end
  end
  lookup.merge(variants)
end
private_class_method :add_ingredient_variants
```

**Step 4: Run the new tests**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb -n /variant/`
Expected: All 6 variant tests PASS.

**Step 5: Run full catalog test suite**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: All tests PASS (existing tests unaffected).

**Step 6: Lint**

Run: `bundle exec rubocop app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add app/models/ingredient_catalog.rb test/models/ingredient_catalog_test.rb
git commit -m "feat: IngredientCatalog.lookup_for resolves singular/plural variants"
```

---

### Task 3: Update `BuildValidator` to check variants

**Files:**
- Modify: `lib/familyrecipes/build_validator.rb:28`
- Test: `test/build_validator_test.rb`

**Step 1: Write the failing test**

Add to `test/build_validator_test.rb` before the `private` line:

```ruby
def test_validate_ingredients_matches_plural_variant
  md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Egg, 2\n\nScramble."
  recipe = make_recipe(md, id: 'test-recipe')
  IngredientCatalog.find_or_create_by!(ingredient_name: 'Eggs', kitchen_id: nil) do |p|
    p.basis_grams = 50
    p.calories = 70
  end
  validator = build_validator(recipes: [recipe])

  output = capture_io { validator.validate_ingredients }

  assert_match(/All ingredients validated/, output.first)
end

def test_validate_ingredients_matches_singular_variant
  md = "# Test Recipe\n\nCategory: Test\n\n## Step (do it)\n\n- Carrots, 3\n\nChop."
  recipe = make_recipe(md, id: 'test-recipe')
  IngredientCatalog.find_or_create_by!(ingredient_name: 'Carrot', kitchen_id: nil) do |p|
    p.basis_grams = 50
    p.calories = 25
  end
  validator = build_validator(recipes: [recipe])

  output = capture_io { validator.validate_ingredients }

  assert_match(/All ingredients validated/, output.first)
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/build_validator_test.rb -n /variant/`
Expected: FAIL — "Egg" flagged as unknown (catalog has "Eggs").

**Step 3: Implement variant-aware validation**

In `lib/familyrecipes/build_validator.rb`, replace the `validate_ingredients` method (lines 24-39):

```ruby
def validate_ingredients
  print 'Validating ingredients...'

  ingredients_to_recipes = build_ingredient_recipe_index
  known = build_known_ingredient_set

  unknown_ingredients = ingredients_to_recipes.keys.reject do |name|
    known.include?(name.downcase)
  end.to_set

  if unknown_ingredients.any?
    print_unknown_ingredients(unknown_ingredients, ingredients_to_recipes)
  else
    print "done! (All ingredients validated.)\n"
  end
end
```

Add a private method `build_known_ingredient_set` after `build_ingredient_recipe_index`:

```ruby
def build_known_ingredient_set
  names = IngredientCatalog.pluck(:ingredient_name)
  variants = names.flat_map { |name| FamilyRecipes::Inflector.ingredient_variants(name) }
  (names + variants).to_set { |n| n.downcase }
end
```

**Step 4: Run the new tests**

Run: `ruby -Itest test/build_validator_test.rb -n /variant/`
Expected: Both variant tests PASS.

**Step 5: Run full validator test suite**

Run: `ruby -Itest test/build_validator_test.rb`
Expected: All tests PASS (existing tests unaffected).

**Step 6: Lint**

Run: `bundle exec rubocop lib/familyrecipes/build_validator.rb test/build_validator_test.rb`
Expected: No offenses.

**Step 7: Commit**

```bash
git add lib/familyrecipes/build_validator.rb test/build_validator_test.rb
git commit -m "feat: BuildValidator matches singular/plural ingredient variants"
```

---

### Task 4: Full test suite + seed validation

**Files:** None (verification only)

**Step 1: Run full test suite**

Run: `rake test`
Expected: All tests PASS.

**Step 2: Run lint**

Run: `rake lint`
Expected: No offenses.

**Step 3: Run seed with validation to confirm fewer warnings**

Run: `rails db:seed`
Expected: Ingredients like "Egg", "Onion", "Carrot", "Lemon", "Lime" that previously appeared as unknown (because catalog has "Eggs", "Onions", "Carrots", "Lemons", "Limes") should no longer appear in warnings.

**Step 4: Final commit — close the issue**

```bash
git add -A
git commit -m "feat: normalize ingredient names via singular/plural lookup (closes #102)"
```

Only commit if there are changes (e.g., if lint fixed anything). If the working tree is clean after Task 3, this step is a no-op and the issue can be closed via any of the prior commits.

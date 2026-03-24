# NutritionCalculator AR Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make `NutritionCalculator` consume `IngredientCatalog` records directly instead of hand-built string-keyed hashes, eliminating the translation layer in `RecipeNutritionJob` and simplifying all callers.

**Architecture:** Mechanical refactor — swap hash access (`entry.dig('nutrients', 'basis_grams')`) for AR accessors (`entry.basis_grams`) throughout the calculator. Delete the `build_nutrition_data`/`nutrients_hash`/`density_hash` translation methods in `RecipeNutritionJob`. Update `BuildValidator` tests to pass AR records.

**Tech Stack:** Ruby, Rails (ActiveRecord), Minitest

---

### Task 1: Convert NutritionCalculator test fixtures to IngredientCatalog records

The tests currently build string-keyed hashes. Convert them to `IngredientCatalog.new(...)` (unsaved AR records). Tests will fail after this — that's the red phase.

**Files:**
- Modify: `test/nutrition_calculator_test.rb`

**Step 1: Replace the setup fixtures**

The test class stays as `Minitest::Test` (no DB needed — `IngredientCatalog.new` doesn't persist). Replace `@nutrition_data` hash:

```ruby
def setup
  @nutrition_data = {
    'Flour (all-purpose)' => IngredientCatalog.new(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30, calories: 109.2, protein: 3.099, fat: 0.294,
      saturated_fat: 0.05, carbs: 22.893, fiber: 0.81, sodium: 0.6,
      density_grams: 125, density_volume: 1, density_unit: 'cup'
    ),
    'Eggs' => IngredientCatalog.new(
      ingredient_name: 'Eggs',
      basis_grams: 50, calories: 71.5, protein: 6.28, fat: 4.755,
      saturated_fat: 1.6, carbs: 0.36, fiber: 0, sodium: 71,
      portions: { '~unitless' => 50 }
    ),
    'Butter' => IngredientCatalog.new(
      ingredient_name: 'Butter',
      basis_grams: 14, calories: 100.38, protein: 0.119, fat: 11.3554,
      saturated_fat: 7.17, carbs: 0.0084, fiber: 0, sodium: 90.02,
      density_grams: 227, density_volume: 1, density_unit: 'cup',
      portions: { 'stick' => 113.0 }
    ),
    'Olive oil' => IngredientCatalog.new(
      ingredient_name: 'Olive oil',
      basis_grams: 14, calories: 123.76, protein: 0, fat: 14,
      saturated_fat: 1.9, carbs: 0, fiber: 0, sodium: 0.28,
      density_grams: 14, density_volume: 1, density_unit: 'tbsp'
    ),
    'Sugar (white)' => IngredientCatalog.new(
      ingredient_name: 'Sugar (white)',
      basis_grams: 4, calories: 15.48, protein: 0, fat: 0,
      saturated_fat: 0, carbs: 4, fiber: 0, sodium: 0.04,
      density_grams: 200, density_volume: 1, density_unit: 'cup'
    )
  }

  @omit_set = Set.new(['water', 'ice', 'poolish', 'sourdough starter'])
  @calculator = FamilyRecipes::NutritionCalculator.new(@nutrition_data, omit_set: @omit_set)
  @recipe_map = {}
end
```

**Step 2: Update inline test fixtures**

Several tests create local `nutrition_data` hashes. Convert each:

`test_new_nutrients_calculated` (line 656):
```ruby
nutrition_data = {
  'Butter' => IngredientCatalog.new(
    ingredient_name: 'Butter',
    basis_grams: 14, calories: 100, fat: 11, saturated_fat: 7, trans_fat: 0.5,
    cholesterol: 30, sodium: 90, carbs: 0, fiber: 0,
    total_sugars: 0, added_sugars: 0, protein: 0.1,
    portions: { 'stick' => 113 }
  )
}
```

`test_missing_new_nutrient_keys_default_to_zero` (line 690):
```ruby
nutrition_data = {
  'Flour (all-purpose)' => IngredientCatalog.new(
    ingredient_name: 'Flour (all-purpose)',
    basis_grams: 30, calories: 109.2, protein: 3.0, fat: 0.3,
    saturated_fat: 0.05, carbs: 22.9, fiber: 0.8, sodium: 0.6,
    density_grams: 125, density_volume: 1, density_unit: 'cup'
  )
}
```

`test_silently_skips_entries_without_nutrients` (line 728):
```ruby
data = { 'Celery' => IngredientCatalog.new(ingredient_name: 'Celery', aisle: 'Produce') }
```

`test_malformed_entry_missing_basis_grams` (line 735):
```ruby
nutrition_data = {
  'Good' => IngredientCatalog.new(ingredient_name: 'Good', basis_grams: 30, calories: 100),
  'Bad' => IngredientCatalog.new(ingredient_name: 'Bad', calories: 100)
}
```

`test_malformed_entry_invalid_nutrients` (line 751) — this tested `'nutrients' => 'not a hash'` which can't happen with AR. Replace with a nil basis_grams test:
```ruby
def test_entry_without_basis_grams_filtered
  nutrition_data = {
    'NoBasis' => IngredientCatalog.new(ingredient_name: 'NoBasis', calories: 100)
  }
  calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
  refute calculator.nutrition_data.key?('NoBasis')
end
```

`test_zero_basis_grams_skipped` (line 763):
```ruby
nutrition_data = {
  'ZeroGrams' => IngredientCatalog.new(ingredient_name: 'ZeroGrams', basis_grams: 0, calories: 100)
}
```

**Step 3: Run tests to confirm they fail**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: Failures — the calculator still expects string-keyed hashes.

---

### Task 2: Rewrite NutritionCalculator to consume IngredientCatalog records

Change all hash access to AR accessor calls. The calculator now expects `{ name => IngredientCatalog }` instead of `{ name => string_hash }`.

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb`

**Step 1: Rewrite the constructor filter**

Old (lines 43-51):
```ruby
@nutrition_data = nutrition_data.select do |_name, entry|
  next false unless entry['nutrients'].is_a?(Hash)
  basis_grams = entry.dig('nutrients', 'basis_grams')
  next false unless basis_grams.is_a?(Numeric) && basis_grams.positive?
  true
end.to_h
```

New:
```ruby
@nutrition_data = nutrition_data.select do |_name, entry|
  entry.basis_grams.present? && entry.basis_grams.positive?
end.to_h
```

**Step 2: Rewrite `nutrient_per_gram`**

Old (lines 135-140):
```ruby
def nutrient_per_gram(entry, nutrient)
  basis_grams = entry.dig('nutrients', 'basis_grams')
  return 0 if basis_grams.nil? || basis_grams <= 0
  (entry.dig('nutrients', nutrient.to_s) || 0) / basis_grams.to_f
end
```

New:
```ruby
def nutrient_per_gram(entry, nutrient)
  (entry.public_send(nutrient) || 0) / entry.basis_grams.to_f
end
```

The constructor already guarantees `basis_grams` is present and positive, so the guard is unnecessary.

**Step 3: Rewrite `to_grams`**

Old (lines 142-171) accesses `entry['portions']` and calls `derive_density(entry)`.

New — replace `entry['portions'] || {}` with `entry.portions || {}`. The rest of the portion/weight logic is unchanged:
```ruby
def to_grams(value, unit, entry)
  portions = entry.portions || {}
  # ... (steps 1-3 unchanged — they use local `portions` variable)
  # Step 4: replace derive_density(entry)
  ml_factor = VOLUME_TO_ML[unit_down]
  if ml_factor
    density = derive_density(entry)
    return value * ml_factor * density if density
  end
  nil
end
```

**Step 4: Rewrite `derive_density`**

Old (lines 173-185):
```ruby
def derive_density(entry)
  density = entry['density']
  return nil unless density
  return nil unless density['volume'] && density['unit']
  ml_factor = VOLUME_TO_ML[density['unit'].to_s.downcase]
  return nil unless ml_factor
  volume_ml = density['volume'] * ml_factor
  return nil if volume_ml <= 0
  density['grams'] / volume_ml
end
```

New:
```ruby
def derive_density(entry)
  return nil unless entry.density_grams && entry.density_volume && entry.density_unit

  ml_factor = VOLUME_TO_ML[entry.density_unit.downcase]
  return nil unless ml_factor

  volume_ml = entry.density_volume * ml_factor
  return nil if volume_ml <= 0

  entry.density_grams / volume_ml
end
```

**Step 5: Update the header comment**

Replace the first line of the class comment — remove "from ingredient-catalog YAML data" and note it consumes `IngredientCatalog` records:
```ruby
# Computes FDA-label nutrition facts for a recipe from IngredientCatalog
# entries. Resolves ingredient quantities to grams via a priority chain: ...
```

**Step 6: Run calculator tests**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: All tests pass.

**Step 7: Remove stale rubocop disables if method sizes shrink**

Check if `to_grams` and the constructor are now short enough to drop the `rubocop:disable` comments.

**Step 8: Run full test suite + lint**

Run: `rake`
Expected: NutritionCalculator tests pass. `RecipeNutritionJob` tests and `BuildValidator` tests will fail (they still build hashes). That's expected — we fix them in subsequent tasks.

**Step 9: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "refactor: NutritionCalculator consumes IngredientCatalog records directly"
```

---

### Task 3: Simplify RecipeNutritionJob

Delete the translation layer. Pass `resolver.lookup` straight to the calculator.

**Files:**
- Modify: `app/jobs/recipe_nutrition_job.rb`
- Test: `test/jobs/recipe_nutrition_job_test.rb` (should pass without changes)

**Step 1: Delete translation methods and simplify `perform`**

Remove `build_nutrition_data`, `nutrients_hash`, `density_hash`. The `perform` method becomes:

```ruby
def perform(recipe, resolver: nil)
  loaded = eager_load_recipe(recipe)
  resolver ||= IngredientCatalog.resolver_for(loaded.kitchen)
  return if resolver.lookup.empty?

  calculator = FamilyRecipes::NutritionCalculator.new(resolver.lookup, omit_set: resolver.omit_set)
  result = calculator.calculate(loaded, {})

  recipe.update_column(:nutrition_data, serialize_result(result)) # rubocop:disable Rails/SkipsModelValidations
end
```

**Step 2: Update the header comment**

Remove "Bridges the AR world (IngredientCatalog entries) to the domain NutritionCalculator by building a lookup hash in the format the calculator expects." — the bridge is gone. New comment:
```ruby
# Recalculates a recipe's nutrition_data JSON from its ingredients and the
# IngredientCatalog. Passes the resolver's catalog lookup directly to
# NutritionCalculator — no format translation needed. Runs synchronously
# via perform_now at import time. Accepts an optional resolver: to avoid
# redundant catalog queries when called in a batch.
#
# - IngredientCatalog: overlay model for ingredient metadata
# - IngredientResolver: variant-aware name resolution
# - FamilyRecipes::NutritionCalculator: FDA-label computation
```

**Step 3: Run job tests**

Run: `ruby -Itest test/jobs/recipe_nutrition_job_test.rb`
Expected: All pass — the job's tests exercise the full pipeline through AR records, so they should work without changes.

**Step 4: Commit**

```bash
git add app/jobs/recipe_nutrition_job.rb
git commit -m "refactor: delete translation layer in RecipeNutritionJob"
```

---

### Task 4: Update BuildValidator and its tests

The `BuildValidator` receives a `NutritionCalculator` and calls `.nutrition_data` (the filtered lookup) and `.resolvable?`. After the refactor, the calculator expects AR records. The validator code itself needs no changes — only its tests do, because they construct the calculator from string hashes.

**Files:**
- Modify: `test/build_validator_test.rb`
- Verify: `lib/familyrecipes/build_validator.rb` (no code changes expected)

**Step 1: Update `test_validate_nutrition_warns_on_missing_data`**

Old (line 106-107):
```ruby
nutrition_data = {}
calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
```

No change needed — empty hash works with both old and new interface.

**Step 2: Update `test_validate_nutrition_passes_when_complete`**

Old (lines 119-125):
```ruby
nutrition_data = {
  'Flour' => {
    'nutrients' => { 'basis_grams' => 30.0, 'calories' => 110.0 },
    'density' => { 'grams' => 30.0, 'volume' => 0.25, 'unit' => 'cup' }
  }
}
calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data)
```

New:
```ruby
catalog_lookup = {
  'Flour' => IngredientCatalog.new(
    ingredient_name: 'Flour', basis_grams: 30.0, calories: 110.0,
    density_grams: 30.0, density_volume: 0.25, density_unit: 'cup'
  )
}
calculator = FamilyRecipes::NutritionCalculator.new(catalog_lookup)
```

**Step 3: Run validator tests**

Run: `ruby -Itest test/build_validator_test.rb`
Expected: All pass.

**Step 4: Run full suite + lint**

Run: `rake`
Expected: All green — 0 failures, 0 RuboCop offenses.

**Step 5: Commit**

```bash
git add test/build_validator_test.rb
git commit -m "refactor: update BuildValidator tests for AR-based NutritionCalculator"
```

---

### Task 5: Final verification and cleanup

**Files:**
- Verify: all changed files
- Update: `CLAUDE.md` if any conventions changed (unlikely)

**Step 1: Run full suite one more time**

Run: `rake`
Expected: All tests pass, 0 RuboCop offenses.

**Step 2: Verify no stale references to the old hash format**

Search for `entry.dig('nutrients'` or `entry['nutrients']` or `entry['density']` or `entry['portions']` in `lib/familyrecipes/nutrition_calculator.rb` — should find none.

Search for `build_nutrition_data` or `nutrients_hash` or `density_hash` in `app/jobs/recipe_nutrition_job.rb` — should find none.

**Step 3: Check that NutritionTui::Data references are only in `lib/nutrition_tui/`**

The TUI will break, but that's scoped to its own directory. Verify no Rails code depends on `NutritionTui::Data`.

**Step 4: Squash or leave commits as-is per user preference**

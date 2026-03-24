# Nutrition Constants Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate nutrient metadata duplication across 5 files and unify volume unit lists, adding fl oz/pt/qt/gal support.

**Architecture:** Create `NutrientDef` in `NutritionConstraints` as single source of truth for nutrient metadata; all consumers derive their constants. Expand `NutritionCalculator::VOLUME_TO_ML` as single source of truth for volume conversions; delete redundant unit lists from TUI and UsdaClient.

**Tech Stack:** Ruby, Rails 8, Minitest

**Design doc:** `docs/plans/2026-03-04-nutrition-constants-consolidation-design.md`

---

### Task 0: Add NutrientDef to NutritionConstraints

**Files:**
- Modify: `lib/familyrecipes/nutrition_constraints.rb:12-14`
- Test: `test/nutrition_constraints_test.rb`

**Step 1: Write the failing tests**

Add to `test/nutrition_constraints_test.rb`:

```ruby
# --- NutrientDef ---

test 'NUTRIENT_DEFS has eleven entries' do
  assert_equal 11, NC::NUTRIENT_DEFS.size
end

test 'NUTRIENT_KEYS matches NUTRIENT_DEFS order' do
  expected = NC::NUTRIENT_DEFS.map(&:key)

  assert_equal expected, NC::NUTRIENT_KEYS
end

test 'NutrientDef exposes key, label, unit, indent' do
  first = NC::NUTRIENT_DEFS.first

  assert_equal :calories, first.key
  assert_equal 'Calories', first.label
  assert_equal '', first.unit
  assert_equal 0, first.indent
end

test 'NUTRIENT_KEYS starts with calories and ends with protein' do
  assert_equal :calories, NC::NUTRIENT_KEYS.first
  assert_equal :protein, NC::NUTRIENT_KEYS.last
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_constraints_test.rb`
Expected: FAIL — `NutrientDef` not defined

**Step 3: Implement NutrientDef and NUTRIENT_DEFS**

In `lib/familyrecipes/nutrition_constraints.rb`, add inside the module before `NUTRIENT_MAX`:

```ruby
NutrientDef = Data.define(:key, :label, :unit, :indent)

NUTRIENT_DEFS = [
  NutrientDef.new(key: :calories,      label: 'Calories',      unit: '',   indent: 0),
  NutrientDef.new(key: :fat,           label: 'Total Fat',      unit: 'g',  indent: 0),
  NutrientDef.new(key: :saturated_fat, label: 'Saturated Fat',  unit: 'g',  indent: 1),
  NutrientDef.new(key: :trans_fat,     label: 'Trans Fat',      unit: 'g',  indent: 1),
  NutrientDef.new(key: :cholesterol,   label: 'Cholesterol',    unit: 'mg', indent: 0),
  NutrientDef.new(key: :sodium,        label: 'Sodium',         unit: 'mg', indent: 0),
  NutrientDef.new(key: :carbs,         label: 'Total Carbs',    unit: 'g',  indent: 0),
  NutrientDef.new(key: :fiber,         label: 'Fiber',          unit: 'g',  indent: 1),
  NutrientDef.new(key: :total_sugars,  label: 'Total Sugars',   unit: 'g',  indent: 1),
  NutrientDef.new(key: :added_sugars,  label: 'Added Sugars',   unit: 'g',  indent: 2),
  NutrientDef.new(key: :protein,       label: 'Protein',        unit: 'g',  indent: 0)
].freeze

NUTRIENT_KEYS = NUTRIENT_DEFS.map(&:key).freeze
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/nutrition_constraints_test.rb`
Expected: PASS — all 4 new tests pass

**Step 5: Commit**

```bash
git add lib/familyrecipes/nutrition_constraints.rb test/nutrition_constraints_test.rb
git commit -m "feat: add NutrientDef source of truth to NutritionConstraints"
```

---

### Task 1: Derive NutritionCalculator::NUTRIENTS from NutrientDef

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:11-12`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Replace the hardcoded NUTRIENTS constant**

In `lib/familyrecipes/nutrition_calculator.rb`, replace:

```ruby
NUTRIENTS = %i[calories fat saturated_fat trans_fat cholesterol sodium
               carbs fiber total_sugars added_sugars protein].freeze
```

with:

```ruby
NUTRIENTS = NutritionConstraints::NUTRIENT_KEYS
```

**Step 2: Run tests to verify nothing broke**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: PASS — all existing tests pass unchanged. The constant value is identical.

**Step 3: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb
git commit -m "refactor: derive NutritionCalculator::NUTRIENTS from NutritionConstraints"
```

---

### Task 2: Derive IngredientCatalog nutrient constants from NutrientDef

**Files:**
- Modify: `app/models/ingredient_catalog.rb:18-33`
- Test: `test/models/ingredient_catalog_test.rb`

**Step 1: Replace NUTRIENT_COLUMNS and NUTRIENT_DISPLAY**

In `app/models/ingredient_catalog.rb`, replace:

```ruby
NUTRIENT_COLUMNS = %i[calories fat saturated_fat trans_fat cholesterol
                      sodium carbs fiber total_sugars added_sugars protein].freeze

NUTRIENT_DISPLAY = [
  ['Calories',         :calories,      ''],
  ['Total Fat',        :fat,           'g'],
  ['  Saturated Fat',  :saturated_fat, 'g'],
  ['  Trans Fat',      :trans_fat,     'g'],
  ['Cholesterol',      :cholesterol,   'mg'],
  ['Sodium',           :sodium,        'mg'],
  ['Total Carbs',      :carbs,         'g'],
  ['  Dietary Fiber',  :fiber,         'g'],
  ['  Total Sugars',   :total_sugars,  'g'],
  ['    Added Sugars', :added_sugars,  'g'],
  ['Protein',          :protein,       'g']
].freeze
```

with:

```ruby
NUTRIENT_COLUMNS = FamilyRecipes::NutritionConstraints::NUTRIENT_KEYS

NUTRIENT_DISPLAY = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map { |d|
  label = d.indent.positive? ? "#{'  ' * d.indent}#{d.label}" : d.label
  [label, d.key, d.unit]
}.freeze
```

Note: the old `NUTRIENT_DISPLAY` used `'Dietary Fiber'` for the fiber label; `NUTRIENT_DEFS` uses `'Fiber'`. Check the view template to confirm which label renders — if the view uses `NUTRIENT_DISPLAY`, the label will change from `'  Dietary Fiber'` to `'  Fiber'`. This is acceptable (shorter, matches FDA label). If there's a test asserting the exact string `'Dietary Fiber'`, update it.

**Step 2: Run tests to verify**

Run: `ruby -Itest test/models/ingredient_catalog_test.rb`
Expected: PASS — validators and scopes don't depend on label text.

Also run the full suite to catch any view tests:

Run: `rake test`
Expected: PASS

**Step 3: Commit**

```bash
git add app/models/ingredient_catalog.rb
git commit -m "refactor: derive IngredientCatalog nutrient constants from NutritionConstraints"
```

---

### Task 3: Derive RecipesHelper::NUTRITION_ROWS from NutrientDef

**Files:**
- Modify: `app/helpers/recipes_helper.rb:9-21`

**Step 1: Replace the hardcoded NUTRITION_ROWS constant**

In `app/helpers/recipes_helper.rb`, replace:

```ruby
NUTRITION_ROWS = [
  ['Calories', 'calories', '', 0],
  ['Total Fat', 'fat', 'g', 0],
  ['Sat. Fat', 'saturated_fat', 'g', 1],
  ['Trans Fat', 'trans_fat', 'g', 1],
  ['Cholesterol', 'cholesterol', 'mg', 0],
  ['Sodium', 'sodium', 'mg', 0],
  ['Total Carbs', 'carbs', 'g', 0],
  ['Fiber', 'fiber', 'g', 1],
  ['Total Sugars', 'total_sugars', 'g', 1],
  ['Added Sugars', 'added_sugars', 'g', 2],
  ['Protein', 'protein', 'g', 0]
].freeze
```

with:

```ruby
NUTRITION_ROWS = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map { |d|
  [d.label, d.key.to_s, d.unit, d.indent]
}.freeze
```

Note: the old constant used `'Sat. Fat'` as the label for saturated fat; the new version uses `'Saturated Fat'` from `NUTRIENT_DEFS`. Check the nutrition table view template (`app/views/recipes/_nutrition_table.html.erb`) to see if the label renders directly or is truncated by CSS. Update the template if needed.

**Step 2: Run tests**

Run: `rake test`
Expected: PASS — the nutrition table is rendered in integration tests but label text is unlikely to be asserted. If a test fails on the label change, update the assertion.

**Step 3: Commit**

```bash
git add app/helpers/recipes_helper.rb
git commit -m "refactor: derive RecipesHelper::NUTRITION_ROWS from NutritionConstraints"
```

---

### Task 4: Derive NutritionTui::Data::NUTRIENTS from NutrientDef

**Files:**
- Modify: `lib/nutrition_tui/data.rb:23-35`
- Test: `test/nutrition_tui/data_test.rb:270-272`

**Step 1: Replace the hardcoded NUTRIENTS constant**

In `lib/nutrition_tui/data.rb`, replace:

```ruby
NUTRIENTS = [
  { key: 'calories', label: 'Calories', unit: '', indent: 0 },
  { key: 'fat', label: 'Total fat', unit: 'g', indent: 0 },
  { key: 'saturated_fat', label: 'Saturated fat', unit: 'g', indent: 1 },
  { key: 'trans_fat', label: 'Trans fat', unit: 'g', indent: 1 },
  { key: 'cholesterol', label: 'Cholesterol', unit: 'mg', indent: 0 },
  { key: 'sodium', label: 'Sodium', unit: 'mg', indent: 0 },
  { key: 'carbs', label: 'Total carbs', unit: 'g', indent: 0 },
  { key: 'fiber', label: 'Fiber', unit: 'g', indent: 1 },
  { key: 'total_sugars', label: 'Total sugars', unit: 'g', indent: 1 },
  { key: 'added_sugars', label: 'Added sugars', unit: 'g', indent: 2 },
  { key: 'protein', label: 'Protein', unit: 'g', indent: 0 }
].freeze
```

with:

```ruby
NUTRIENTS = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map { |d|
  { key: d.key.to_s, label: d.label, unit: d.unit, indent: d.indent }
}.freeze
```

Note: the old constant used lowercase labels (`'Total fat'`, `'Saturated fat'`, `'Total carbs'`, `'Total sugars'`, `'Added sugars'`). The new version uses title-case from `NUTRIENT_DEFS` (`'Total Fat'`, etc.). The TUI renders these in `format_nutrient_line` (ingredient.rb:490-493) — title-case is fine for a TUI label.

**Step 2: Run tests**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: PASS — `test_nutrients_has_eleven_entries` still passes (count unchanged).

**Step 3: Commit**

```bash
git add lib/nutrition_tui/data.rb
git commit -m "refactor: derive NutritionTui::Data::NUTRIENTS from NutritionConstraints"
```

---

### Task 5: Add fl oz and volume unit aliases to Inflector

**Files:**
- Modify: `lib/familyrecipes/inflector.rb:34-46`
- Test: `test/inflector_test.rb`

**Step 1: Write the failing tests**

Add to `test/inflector_test.rb` after the existing `normalize_unit` tests:

```ruby
def test_normalize_unit_fl_oz_passthrough
  assert_equal 'fl oz', FamilyRecipes::Inflector.normalize_unit('fl oz')
end

def test_normalize_unit_fluid_ounce_to_fl_oz
  assert_equal 'fl oz', FamilyRecipes::Inflector.normalize_unit('fluid ounce')
end

def test_normalize_unit_fluid_ounces_to_fl_oz
  assert_equal 'fl oz', FamilyRecipes::Inflector.normalize_unit('fluid ounces')
end

def test_normalize_unit_pint_to_pt
  assert_equal 'pt', FamilyRecipes::Inflector.normalize_unit('pint')
end

def test_normalize_unit_pints_already_covered
  assert_equal 'pt', FamilyRecipes::Inflector.normalize_unit('pints')
end

def test_normalize_unit_quart_to_qt
  assert_equal 'qt', FamilyRecipes::Inflector.normalize_unit('quart')
end

def test_normalize_unit_gallon_to_gal
  assert_equal 'gal', FamilyRecipes::Inflector.normalize_unit('gallon')
end

def test_normalize_unit_gallons_to_gal
  assert_equal 'gal', FamilyRecipes::Inflector.normalize_unit('gallons')
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/inflector_test.rb -n /fl_oz|fluid|pint_to|quart_to|gallon_to|gallons_to/`
Expected: FAIL — `fl oz` returns `'fl oz'` by accident (already in lowered form, not in ABBREVIATIONS, `singular` passes through). `fluid ounce` and `fluid ounces` will fail. `pint` already works via `KNOWN_SINGULARS` → `pint`. `quart`/`gallon` already work similarly. Let's see which actually fail — run and check.

Actually, `pint`/`quart`/`gallon` normalize via `singular()` fallback which strips the 's' and matches the KNOWN_PLURALS entry. They may already return `'pint'`/`'quart'`/`'gallon'` rather than `'pt'`/`'qt'`/`'gal'`. The tests assert abbreviated forms, so these will fail.

**Step 3: Add abbreviation entries to Inflector**

In `lib/familyrecipes/inflector.rb`, add to `ABBREVIATIONS` hash (after the `'ml' => 'ml'` line):

```ruby
'fl oz' => 'fl oz', 'fluid ounce' => 'fl oz', 'fluid ounces' => 'fl oz',
```

The `pt`/`qt`/`gal` entries already exist in ABBREVIATIONS (lines 43-45), so `pint` → `pt`, `quart` → `qt`, `gallon` → `gal` already work. Verify by running the tests.

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/inflector_test.rb`
Expected: PASS — all new tests pass

**Step 5: Commit**

```bash
git add lib/familyrecipes/inflector.rb test/inflector_test.rb
git commit -m "feat: add fl oz abbreviation to Inflector"
```

---

### Task 6: Expand VOLUME_TO_ML with fl oz, pt, qt, gal

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:18-20`
- Test: `test/nutrition_calculator_test.rb`

**Step 1: Write the failing test**

Add to `test/nutrition_calculator_test.rb`:

```ruby
# --- Volume conversions for new units ---

def test_fl_oz_volume_conversion
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test

    ## Mix (combine)

    - Olive oil, 2 fl oz

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # 2 fl oz = 2 * 29.5735ml; density: 14g / 14.787ml = 0.9468 g/ml
  # grams = 2 * 29.5735 * (14.0 / 14.787) = 55.97g
  # cal = (123.76 / 14) * 55.97 = 494.7
  expected_grams = 2 * 29.5735 * (14.0 / 14.787)
  expected_cal = (123.76 / 14.0) * expected_grams

  assert_in_delta expected_cal, result.totals[:calories], 2
  assert_empty result.partial_ingredients
end

def test_pint_volume_conversion
  recipe = make_recipe(<<~MD)
    # Test

    Category: Test

    ## Mix (combine)

    - Olive oil, 1 pt

    Mix.
  MD

  result = @calculator.calculate(recipe, @recipe_map)

  # 1 pt = 473.176ml; density = 14g / 14.787ml
  expected_grams = 473.176 * (14.0 / 14.787)
  expected_cal = (123.76 / 14.0) * expected_grams

  assert_in_delta expected_cal, result.totals[:calories], 2
  assert_empty result.partial_ingredients
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/nutrition_calculator_test.rb -n /fl_oz_volume|pint_volume/`
Expected: FAIL — `fl oz` and `pt` not in VOLUME_TO_ML, reported as partial ingredients

**Step 3: Expand VOLUME_TO_ML**

In `lib/familyrecipes/nutrition_calculator.rb`, replace:

```ruby
VOLUME_TO_ML = {
  'cup' => 236.588, 'tbsp' => 14.787, 'tsp' => 4.929, 'ml' => 1, 'l' => 1000
}.freeze
```

with:

```ruby
VOLUME_TO_ML = {
  'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
  'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
  'gal' => 3785.41, 'ml' => 1, 'l' => 1000
}.freeze
```

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/nutrition_calculator_test.rb`
Expected: PASS — all existing + new tests pass

**Step 5: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb
git commit -m "feat: add fl oz, pt, qt, gal to NutritionCalculator::VOLUME_TO_ML"
```

---

### Task 7: Derive TUI volume/weight constants from calculator

**Files:**
- Modify: `lib/nutrition_tui/data.rb:37-39, 143-148`
- Test: `test/nutrition_tui/data_test.rb`

**Step 1: Replace VOLUME_UNITS and WEIGHT_UNITS, refactor modifier checks**

In `lib/nutrition_tui/data.rb`, delete the hardcoded constants:

```ruby
VOLUME_UNITS = ['cup', 'cups', 'tbsp', 'tsp', 'tablespoon', 'tablespoons',
                'teaspoon', 'teaspoons', 'fl oz'].freeze
WEIGHT_UNITS = %w[oz ounce ounces lb lbs pound pounds kg g gram grams].freeze
```

Replace `volume_modifier?` (line 143-145) with a version that derives recognized prefixes from the Inflector + NutritionCalculator:

```ruby
def volume_modifier?(modifier)
  volume_prefixes.any? { |u| modifier.to_s.downcase.start_with?(u) }
end

def weight_modifier?(modifier)
  weight_prefixes.any? { |u| modifier.to_s.downcase.start_with?(u) }
end
```

Add private helpers to build the prefix sets lazily:

```ruby
def volume_prefixes
  @volume_prefixes ||= build_unit_prefixes(FamilyRecipes::NutritionCalculator::VOLUME_TO_ML)
end

def weight_prefixes
  @weight_prefixes ||= build_unit_prefixes(FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS)
end

def build_unit_prefixes(canonical_map)
  prefixes = canonical_map.keys.to_set
  FamilyRecipes::Inflector::ABBREVIATIONS.each do |long_form, short_form|
    prefixes << long_form if canonical_map.key?(short_form)
  end
  prefixes.freeze
end
```

Add these to `private_class_method` at the bottom.

**Important:** The `volume_modifier?` method is `module_function` — instance variables won't work. Use `||=` with a module-level variable or just compute inline. Since `module_function` makes methods both module-level and instance methods, and this is called infrequently (only during USDA classification), computing inline is fine:

```ruby
def volume_modifier?(modifier)
  build_unit_prefixes(FamilyRecipes::NutritionCalculator::VOLUME_TO_ML)
    .any? { |u| modifier.to_s.downcase.start_with?(u) }
end

def weight_modifier?(modifier)
  build_unit_prefixes(FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS)
    .any? { |u| modifier.to_s.downcase.start_with?(u) }
end

def build_unit_prefixes(canonical_map)
  prefixes = canonical_map.keys.to_set
  FamilyRecipes::Inflector::ABBREVIATIONS.each do |long_form, short_form|
    prefixes << long_form if canonical_map.key?(short_form)
  end
  prefixes
end
```

**Step 2: Run tests to verify**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: PASS — all existing `volume_modifier?`, `weight_modifier?`, and `classify_usda_modifiers` tests pass. The prefix sets now include all the old entries and more.

Check that `test_volume_modifier_fl_oz` (line 134-136) still passes — `fl oz` is now in `VOLUME_TO_ML` keys directly.

Check that `test_weight_modifier_oz` (line 144-146) still passes — `oz` is in `WEIGHT_CONVERSIONS` keys.

Check that `test_weight_modifier_pound` (line 148-150) still passes — `pound` maps to `lb` via Inflector::ABBREVIATIONS, `lb` is in WEIGHT_CONVERSIONS.

**Step 3: Commit**

```bash
git add lib/nutrition_tui/data.rb
git commit -m "refactor: derive TUI volume/weight unit lists from NutritionCalculator"
```

---

### Task 8: Simplify UsdaClient.volume_unit?

**Files:**
- Modify: `lib/familyrecipes/usda_client.rb:32, 172-174`
- Test: `test/nutrition_tui/data_test.rb` (USDA tests are in the TUI data test)

**Step 1: Delete VOLUME_UNITS and refactor volume_unit?**

In `lib/familyrecipes/usda_client.rb`, delete:

```ruby
VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons].freeze
```

Replace `volume_unit?` (line 172-174):

```ruby
def volume_unit?(modifier)
  VOLUME_UNITS.include?(modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip)
end
```

with:

```ruby
def volume_unit?(modifier)
  clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
  normalized = FamilyRecipes::Inflector.normalize_unit(clean)
  FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.key?(normalized)
end
```

**Step 2: Run tests**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: PASS — USDA modifier classification tests still pass. `volume_unit?('cup')` → normalize to `'cup'` → in VOLUME_TO_ML. `volume_unit?('tablespoon')` → normalize to `'tbsp'` → in VOLUME_TO_ML.

Also check that the `fl oz` USDA modifier is now correctly classified:

Run: `ruby -Itest test/nutrition_tui/data_test.rb -n test_volume_modifier_fl_oz`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/familyrecipes/usda_client.rb
git commit -m "refactor: derive UsdaClient volume_unit? from Inflector + VOLUME_TO_ML"
```

---

### Task 9: Update editor form dropdown to derive from VOLUME_TO_ML

**Files:**
- Modify: `app/views/ingredients/_editor_form.html.erb:50`

**Step 1: Replace hardcoded volume unit list**

In `app/views/ingredients/_editor_form.html.erb`, replace:

```erb
<% %w[cup tbsp tsp ml l].each do |u| %>
```

with:

```erb
<% FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.each_key do |u| %>
```

This will now include all 9 volume units (tsp, tbsp, fl oz, cup, pt, qt, gal, ml, l) in the dropdown.

**Step 2: Verify visually (optional) or run integration tests**

Run: `rake test`
Expected: PASS

The dropdown will be longer but all units are valid density units.

**Step 3: Commit**

```bash
git add app/views/ingredients/_editor_form.html.erb
git commit -m "refactor: derive editor density dropdown from VOLUME_TO_ML"
```

---

### Task 10: Add documentation comments for omit-set duplication

**Files:**
- Modify: `lib/nutrition_tui/data.rb:229`
- Modify: `app/jobs/recipe_nutrition_job.rb:38`

**Step 1: Add comment to TUI Data.build_omit_set**

In `lib/nutrition_tui/data.rb`, add a comment above `build_omit_set`:

```ruby
# Mirrors RecipeNutritionJob#extract_omit_set — same business rule, different
# input types (YAML hash vs AR objects). Update both if the omit rule changes.
def build_omit_set(catalog)
```

**Step 2: Add comment to RecipeNutritionJob#extract_omit_set**

In `app/jobs/recipe_nutrition_job.rb`, add a comment above `extract_omit_set`:

```ruby
# Mirrors NutritionTui::Data.build_omit_set — same business rule, different
# input types (AR objects vs YAML hash). Update both if the omit rule changes.
def extract_omit_set(catalog)
```

**Step 3: Commit**

```bash
git add lib/nutrition_tui/data.rb app/jobs/recipe_nutrition_job.rb
git commit -m "docs: cross-reference omit-set implementations"
```

---

### Task 11: Full test suite + lint

**Step 1: Run the full test suite**

Run: `rake test`
Expected: PASS — all tests green

**Step 2: Run linter**

Run: `bundle exec rubocop`
Expected: 0 offenses (or only pre-existing ones)

**Step 3: Run html_safe audit**

Run: `rake lint:html_safe`
Expected: PASS — line numbers may have shifted in edited files; update `config/html_safe_allowlist.yml` if needed

**Step 4: Final commit if any allowlist updates**

```bash
git add config/html_safe_allowlist.yml
git commit -m "chore: update html_safe allowlist for shifted line numbers"
```

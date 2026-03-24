# UnitResolver Extraction Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract unit conversion tables and resolution logic from `NutritionCalculator` into a standalone `UnitResolver` class, eliminating duplicated logic in `IngredientRowBuilder` and fixing a semantic dependency in `UsdaPortionClassifier`.

**Architecture:** Pure structural extraction — the resolution chain is moved verbatim, no behavioral changes. `UnitResolver` wraps one `IngredientCatalog` entry and answers unit resolution questions. Conversion tables and unit-type predicates are class-level. All existing consumers repoint to the new class.

**Tech Stack:** Ruby, Minitest, Rails (views only for constant reference)

**Spec:** `docs/plans/2026-03-15-unit-resolver-extraction-design.md`

---

## Chunk 1: Create UnitResolver with TDD

### Task 1: Create UnitResolver (tests + implementation)

**Files:**
- Create: `test/unit_resolver_test.rb`
- Create: `lib/familyrecipes/unit_resolver.rb`
- Modify: `lib/familyrecipes.rb:94-95` (add require)

Tests and implementation are committed together so every commit on main passes
the test suite. The tests are adapted from the five `resolvable?` tests
currently in `test/nutrition_calculator_test.rb`, plus new tests for `to_grams`,
`density`, nil entry, and class predicates. Uses plain `Minitest::Test` (no
Rails) — same convention as other parser-layer tests.

- [ ] **Step 1: Create test file**

```ruby
# frozen_string_literal: true

require_relative 'test_helper'

class UnitResolverTest < Minitest::Test
  def setup
    @flour = IngredientCatalog.new(
      ingredient_name: 'Flour (all-purpose)',
      basis_grams: 30, calories: 109.2, protein: 3.099, fat: 0.294,
      saturated_fat: 0.05, carbs: 22.893, fiber: 0.81, sodium: 0.6,
      density_grams: 125, density_volume: 1, density_unit: 'cup'
    )
    @eggs = IngredientCatalog.new(
      ingredient_name: 'Eggs',
      basis_grams: 50, calories: 71.5, protein: 6.28, fat: 4.755,
      portions: { '~unitless' => 50 }
    )
    @butter = IngredientCatalog.new(
      ingredient_name: 'Butter',
      basis_grams: 14, calories: 100.38, fat: 11.3554,
      density_grams: 227, density_volume: 1, density_unit: 'cup',
      portions: { 'stick' => 113.0 }
    )
    @olive_oil = IngredientCatalog.new(
      ingredient_name: 'Olive oil',
      basis_grams: 14, calories: 123.76, fat: 14,
      density_grams: 14, density_volume: 1, density_unit: 'tbsp'
    )
    @aisle_only = IngredientCatalog.new(
      ingredient_name: 'Celery', aisle: 'Produce'
    )
  end

  # --- to_grams: weight units ---

  def test_grams_passthrough
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_in_delta 500.0, resolver.to_grams(500, 'g')
  end

  def test_oz_conversion
    resolver = FamilyRecipes::UnitResolver.new(@butter)
    assert_in_delta 113.398, resolver.to_grams(4, 'oz'), 0.01
  end

  def test_lb_conversion
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_in_delta 453.592, resolver.to_grams(1, 'lb'), 0.01
  end

  def test_kg_conversion
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_in_delta 1000.0, resolver.to_grams(1, 'kg')
  end

  def test_weight_unit_case_insensitive
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_in_delta 500.0, resolver.to_grams(500, 'G')
  end

  # --- to_grams: bare count (nil unit) ---

  def test_bare_count_with_unitless_portion
    resolver = FamilyRecipes::UnitResolver.new(@eggs)
    assert_in_delta 150.0, resolver.to_grams(3, nil)
  end

  def test_bare_count_without_unitless_portion
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_nil resolver.to_grams(4, nil)
  end

  # --- to_grams: named portions ---

  def test_named_portion
    resolver = FamilyRecipes::UnitResolver.new(@butter)
    assert_in_delta 113.0, resolver.to_grams(1, 'stick')
  end

  def test_named_portion_case_insensitive
    resolver = FamilyRecipes::UnitResolver.new(@butter)
    assert_in_delta 113.0, resolver.to_grams(1, 'Stick')
  end

  # --- to_grams: volume with density ---

  def test_volume_with_density
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    # 1 cup = 236.588ml; density = 125g / 236.588ml
    expected = 236.588 * (125.0 / 236.588)
    assert_in_delta expected, resolver.to_grams(1, 'cup'), 0.1
  end

  def test_volume_tbsp_with_density
    resolver = FamilyRecipes::UnitResolver.new(@olive_oil)
    # 2 tbsp: 2 * 14.787ml * (14g / 14.787ml) = 28g
    expected = 2 * 14.787 * (14.0 / 14.787)
    assert_in_delta expected, resolver.to_grams(2, 'tbsp'), 0.1
  end

  def test_volume_without_density_returns_nil
    entry = IngredientCatalog.new(
      ingredient_name: 'NoDensity', basis_grams: 100, calories: 50
    )
    resolver = FamilyRecipes::UnitResolver.new(entry)
    assert_nil resolver.to_grams(1, 'cup')
  end

  # --- to_grams: unresolvable ---

  def test_unknown_unit_returns_nil
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert_nil resolver.to_grams(2, 'bushels')
  end

  # --- resolvable? ---

  def test_resolvable_with_weight_unit
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    assert resolver.resolvable?(1, 'g')
    assert resolver.resolvable?(1, 'cup')
  end

  def test_resolvable_bare_count_with_unitless
    resolver = FamilyRecipes::UnitResolver.new(@eggs)
    assert resolver.resolvable?(1, nil)
  end

  def test_not_resolvable_with_unknown_unit
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    refute resolver.resolvable?(1, 'bushel')
  end

  def test_resolvable_with_density
    resolver = FamilyRecipes::UnitResolver.new(@olive_oil)
    assert resolver.resolvable?(1, 'cup')
  end

  def test_bare_count_not_resolvable_without_unitless
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    refute resolver.resolvable?(1, nil)
  end

  # --- density ---

  def test_density_returns_grams_per_ml
    resolver = FamilyRecipes::UnitResolver.new(@flour)
    # 125g per cup; 1 cup = 236.588ml → 0.5283 g/ml
    assert_in_delta 125.0 / 236.588, resolver.density, 0.001
  end

  def test_density_nil_without_density_fields
    resolver = FamilyRecipes::UnitResolver.new(@eggs)
    assert_nil resolver.density
  end

  def test_density_nil_with_zero_volume
    entry = IngredientCatalog.new(
      ingredient_name: 'Bad', basis_grams: 100,
      density_grams: 100, density_volume: 0, density_unit: 'cup'
    )
    resolver = FamilyRecipes::UnitResolver.new(entry)
    assert_nil resolver.density
  end

  # --- nil entry ---

  def test_nil_entry_weight_still_resolves
    resolver = FamilyRecipes::UnitResolver.new(nil)
    assert_in_delta 500.0, resolver.to_grams(500, 'g')
  end

  def test_nil_entry_non_weight_returns_nil
    resolver = FamilyRecipes::UnitResolver.new(nil)
    assert_nil resolver.to_grams(1, 'cup')
    assert_nil resolver.to_grams(1, nil)
    assert_nil resolver.to_grams(1, 'stick')
  end

  def test_nil_entry_resolvable_only_for_weight
    resolver = FamilyRecipes::UnitResolver.new(nil)
    assert resolver.resolvable?(1, 'g')
    refute resolver.resolvable?(1, 'cup')
    refute resolver.resolvable?(1, nil)
  end

  def test_nil_entry_density_is_nil
    resolver = FamilyRecipes::UnitResolver.new(nil)
    assert_nil resolver.density
  end

  # --- class predicates ---

  def test_weight_unit_predicate
    assert FamilyRecipes::UnitResolver.weight_unit?('g')
    assert FamilyRecipes::UnitResolver.weight_unit?('OZ')
    refute FamilyRecipes::UnitResolver.weight_unit?('cup')
    refute FamilyRecipes::UnitResolver.weight_unit?(nil)
  end

  def test_volume_unit_predicate
    assert FamilyRecipes::UnitResolver.volume_unit?('cup')
    assert FamilyRecipes::UnitResolver.volume_unit?('TSP')
    assert FamilyRecipes::UnitResolver.volume_unit?('fl oz')
    refute FamilyRecipes::UnitResolver.volume_unit?('g')
    refute FamilyRecipes::UnitResolver.volume_unit?(nil)
  end
end
```

- [ ] **Step 2: Create UnitResolver class**

```ruby
# frozen_string_literal: true

module FamilyRecipes
  # Resolves ingredient quantities to grams via a priority chain: weight units →
  # named portions → density-derived volume conversions. Wraps one
  # IngredientCatalog entry; nil entries are safe (only weight units resolve).
  # Owns the canonical unit conversion tables and their Inflector-expanded
  # variants — the single source of truth for unit recognition across the app.
  #
  # Collaborators:
  # - NutritionCalculator (delegates to_grams here during nutrition aggregation)
  # - IngredientRowBuilder (calls resolvable? for coverage analysis)
  # - UsdaPortionClassifier (reads EXPANDED_*_UNITS for portion classification)
  # - NutritionConstraints (no direct dependency, but co-loaded in the pipeline)
  class UnitResolver
    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
      'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
      'gal' => 3785.41, 'ml' => 1, 'l' => 1000
    }.freeze

    DENSITY_UNITS = ['cup', 'tbsp', 'tsp', 'fl oz', 'ml', 'l'].freeze

    EXPANDED_VOLUME_UNITS = begin
      units = VOLUME_TO_ML.keys.to_set
      Inflector::ABBREVIATIONS.each { |long, short| units << long if VOLUME_TO_ML.key?(short) }
      Inflector::KNOWN_PLURALS.each { |sing, pl| units << pl if units.include?(sing) }
      units.freeze
    end

    EXPANDED_WEIGHT_UNITS = begin
      units = WEIGHT_CONVERSIONS.keys.to_set
      Inflector::ABBREVIATIONS.each { |long, short| units << long if WEIGHT_CONVERSIONS.key?(short) }
      Inflector::KNOWN_PLURALS.each { |sing, pl| units << pl if units.include?(sing) }
      units.freeze
    end

    def self.weight_unit?(unit)
      unit && WEIGHT_CONVERSIONS.key?(unit.downcase)
    end

    def self.volume_unit?(unit)
      unit && VOLUME_TO_ML.key?(unit.downcase)
    end

    def initialize(entry)
      @entry = entry
    end

    def to_grams(value, unit)
      return resolve_bare_count(value) if unit.nil?

      unit_down = unit.downcase
      resolve_weight(value, unit_down) ||
        resolve_named_portion(value, unit, unit_down) ||
        resolve_volume(value, unit_down)
    end

    def resolvable?(value, unit)
      !to_grams(value, unit).nil?
    end

    def density
      return nil unless @entry

      volume_ml = density_volume_ml
      return nil unless volume_ml&.positive?

      @entry.density_grams / volume_ml
    end

    private

    def density_volume_ml
      return nil unless @entry.density_grams && @entry.density_volume && @entry.density_unit

      ml_factor = VOLUME_TO_ML[@entry.density_unit.downcase]
      @entry.density_volume * ml_factor if ml_factor
    end

    def resolve_bare_count(value)
      return nil unless @entry

      grams_per_unit = @entry.portions&.dig('~unitless')
      grams_per_unit ? value * grams_per_unit : nil
    end

    def resolve_weight(value, unit_down)
      factor = WEIGHT_CONVERSIONS[unit_down]
      value * factor if factor
    end

    def resolve_named_portion(value, unit, unit_down)
      return nil unless @entry

      portions = @entry.portions || {}
      grams = portions[unit] || portions[unit_down] ||
              portions.find { |k, _| k.downcase == unit_down }&.last
      value * grams if grams
    end

    def resolve_volume(value, unit_down)
      return nil unless @entry

      ml_factor = VOLUME_TO_ML[unit_down]
      return nil unless ml_factor

      d = density
      value * ml_factor * d if d
    end
  end
end
```

- [ ] **Step 3: Add require to lib/familyrecipes.rb**

Insert `require_relative 'familyrecipes/unit_resolver'` between line 94 (`nutrition_constraints`) and line 95 (`nutrition_calculator`), since both `NutritionCalculator` and `UsdaPortionClassifier` will depend on `UnitResolver`.

In `lib/familyrecipes.rb`, after line 94:
```ruby
require_relative 'familyrecipes/unit_resolver'
```

- [ ] **Step 4: Run UnitResolver tests — verify they pass**

Run: `ruby -Itest test/unit_resolver_test.rb`
Expected: All tests pass (0 failures, 0 errors)

- [ ] **Step 5: Run full test suite — verify no regressions**

Run: `rake test`
Expected: All existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add lib/familyrecipes/unit_resolver.rb lib/familyrecipes.rb test/unit_resolver_test.rb
git commit -m "feat: add UnitResolver — extract unit tables and resolution chain"
```

---

## Chunk 2: Repoint All Consumers (atomic)

All consumer changes are made in a single task and committed together. This is
necessary because Task 1 added `UnitResolver` alongside the existing constants
in `NutritionCalculator`. Deleting those constants from `NutritionCalculator`
would break `IngredientRowBuilder` and `UsdaPortionClassifier` at class load
time if they haven't been repointed yet. One atomic commit avoids this.

### Task 2: Repoint all consumers to UnitResolver

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb`
- Modify: `test/nutrition_calculator_test.rb`
- Modify: `app/services/ingredient_row_builder.rb`
- Modify: `lib/familyrecipes/usda_portion_classifier.rb`
- Modify: `lib/familyrecipes/build_validator.rb:152-155`
- Modify: `app/views/ingredients/_editor_form.html.erb:95`

- [ ] **Step 1: Repoint NutritionCalculator — delete constants and resolution methods**

Remove from `nutrition_calculator.rb`:
- `WEIGHT_CONVERSIONS` hash (lines 20-22)
- `VOLUME_TO_ML` hash (lines 24-28)
- `DENSITY_UNITS` array (lines 30-32)
- `EXPANDED_VOLUME_UNITS` block (lines 36-41)
- `EXPANDED_WEIGHT_UNITS` block (lines 43-48)
- `resolvable?` method (lines 94-96)
- `to_grams` method (lines 164-193)
- `derive_density` method (lines 195-205)
- The `# rubocop:disable Metrics/ClassLength` on the class definition

In `accumulate_amounts`, replace the `to_grams` call:

Before:
```ruby
grams = to_grams(amount.value, amount.unit, entry)
```

After:
```ruby
grams = UnitResolver.new(entry).to_grams(amount.value, amount.unit)
```

- [ ] **Step 2: Remove moved tests from nutrition_calculator_test.rb**

Delete these five test methods (they now live in `unit_resolver_test.rb`):
- `test_resolvable_with_known_unit`
- `test_resolvable_bare_count_with_unitless`
- `test_not_resolvable_with_unknown_unit`
- `test_resolvable_with_density`
- `test_bare_count_not_resolvable_without_unitless`

Also delete the section comment `# --- Resolvable? API ---` and `# --- Bare count without ~unitless (#2 fix) ---` header for `test_bare_count_not_resolvable_without_unitless`.

Keep `test_bare_count_without_unitless_reported_as_partial` — that tests the calculator pipeline, not `resolvable?` directly.

- [ ] **Step 3: Repoint IngredientRowBuilder — delete reimplemented logic**

Remove from `app/services/ingredient_row_builder.rb`:
- `WEIGHT_UNITS` constant (line 17)
- `VOLUME_UNITS` constant (line 18)
- `weight_unit?` method (lines 210-212)
- `volume_unit?` method (lines 196-198)
- `portion_defined?` method (lines 200-204)
- `density_defined?` method (lines 206-208)

Replace the current `unit_resolvable?` method (lines 187-194) with:

```ruby
def unit_resolvable?(unit, entry)
  FamilyRecipes::UnitResolver.new(entry).resolvable?(1, unit)
end
```

`IngredientRowBuilder` is a top-level class (not inside `FamilyRecipes`), so the
fully qualified name is required.

Replace the current `resolution_method` (lines 214-221):

```ruby
def resolution_method(unit, resolvable, entry)
  return 'weight' if FamilyRecipes::UnitResolver.weight_unit?(unit)
  return 'no nutrition data' if entry&.basis_grams.blank?
  return unitless_method(resolvable) if unit.nil?
  return volume_method(resolvable) if FamilyRecipes::UnitResolver.volume_unit?(unit)

  resolvable ? "via #{unit}" : 'no portion'
end
```

Keep `unitless_method` and `volume_method` as-is — they're presentation helpers.

- [ ] **Step 4: Repoint UsdaPortionClassifier — three constant references**

In `lib/familyrecipes/usda_portion_classifier.rb`:

Line 37:
```ruby
# Before
return two_word if NutritionCalculator::VOLUME_TO_ML.key?(two_word)
# After
return two_word if UnitResolver::VOLUME_TO_ML.key?(two_word)
```

Line 47:
```ruby
# Before
unit_prefix_match?(modifier, NutritionCalculator::EXPANDED_VOLUME_UNITS)
# After
unit_prefix_match?(modifier, UnitResolver::EXPANDED_VOLUME_UNITS)
```

Line 51:
```ruby
# Before
unit_prefix_match?(modifier, NutritionCalculator::EXPANDED_WEIGHT_UNITS)
# After
unit_prefix_match?(modifier, UnitResolver::EXPANDED_WEIGHT_UNITS)
```

Update the header comment collaborator line from:
```ruby
# - NutritionCalculator (EXPANDED_VOLUME_UNITS, EXPANDED_WEIGHT_UNITS)
```
to:
```ruby
# - UnitResolver (EXPANDED_VOLUME_UNITS, EXPANDED_WEIGHT_UNITS, VOLUME_TO_ML)
```

- [ ] **Step 5: Repoint BuildValidator**

In `check_amounts_resolvable` (around line 155 of `lib/familyrecipes/build_validator.rb`):

```ruby
# Before
next if @nutrition_calculator.resolvable?(quantity.value, quantity.unit, entry)
# After
next if UnitResolver.new(entry).resolvable?(quantity.value, quantity.unit)
```

- [ ] **Step 6: Repoint editor form view**

In `app/views/ingredients/_editor_form.html.erb` (line 95):

```erb
<%# Before %>
<% FamilyRecipes::NutritionCalculator::DENSITY_UNITS.each do |u| %>
<%# After %>
<% FamilyRecipes::UnitResolver::DENSITY_UNITS.each do |u| %>
```

- [ ] **Step 7: Run full test suite — verify no regressions**

Run: `rake test`
Expected: All tests pass

- [ ] **Step 8: Commit all consumer changes atomically**

```bash
git add lib/familyrecipes/nutrition_calculator.rb test/nutrition_calculator_test.rb \
  app/services/ingredient_row_builder.rb lib/familyrecipes/usda_portion_classifier.rb \
  lib/familyrecipes/build_validator.rb app/views/ingredients/_editor_form.html.erb
git commit -m "refactor: repoint all consumers from NutritionCalculator to UnitResolver"
```

---

## Chunk 3: Documentation and Cleanup

### Task 3: Update NutritionCalculator header comment

**Files:**
- Modify: `lib/familyrecipes/nutrition_calculator.rb:3-16`

- [ ] **Step 1: Update the header comment**

The current header says the class "owns canonical unit conversion tables" and lists `UsdaPortionClassifier` as a collaborator that "consumes EXPANDED_*_UNITS". After extraction:

- Remove the sentence about owning unit conversion tables
- Remove `UsdaPortionClassifier` from collaborators
- Add `UnitResolver` as a collaborator (delegates unit resolution)

The updated comment should describe what the class actually does now: aggregates nutrient totals from ingredient quantities, delegates unit-to-grams resolution to `UnitResolver`, and produces a `Result` with totals, per-serving, and per-unit breakdowns.

- [ ] **Step 2: Commit**

```bash
git add lib/familyrecipes/nutrition_calculator.rb
git commit -m "docs: update NutritionCalculator header comment after UnitResolver extraction"
```

### Task 4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:254-256`

- [ ] **Step 1: Update the NutritionCalculator bullet and add UnitResolver**

Replace the current `NutritionCalculator` bullet (lines 254-256):
```markdown
- `NutritionCalculator` — consumes `IngredientCatalog` records directly. Owns
  canonical unit conversion tables (`VOLUME_TO_ML`, `WEIGHT_CONVERSIONS`) and
  Inflector-expanded variants — all unit recognition flows through these.
```

With two bullets:
```markdown
- `UnitResolver` — wraps one `IngredientCatalog` entry, resolves quantities to
  grams via weight → portion → density chain. Owns canonical unit conversion
  tables (`VOLUME_TO_ML`, `WEIGHT_CONVERSIONS`) and Inflector-expanded variants.
- `NutritionCalculator` — aggregates nutrient totals for a recipe, delegates
  unit resolution to `UnitResolver`. Produces `Result` with totals, per-serving,
  and per-unit breakdowns.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md nutrition pipeline for UnitResolver extraction"
```

### Task 5: Run lint and full test suite

- [ ] **Step 1: Run RuboCop**

Run: `bundle exec rubocop lib/familyrecipes/unit_resolver.rb lib/familyrecipes/nutrition_calculator.rb app/services/ingredient_row_builder.rb lib/familyrecipes/usda_portion_classifier.rb lib/familyrecipes/build_validator.rb`
Expected: 0 offenses

- [ ] **Step 2: Run full test suite**

Run: `rake test`
Expected: All tests pass, no regressions

- [ ] **Step 3: Run lint:html_safe**

Run: `rake lint:html_safe`
Expected: Pass (no `.html_safe`/`raw()` changes in this extraction)

- [ ] **Step 4: Fix any issues found, then commit if needed**

If RuboCop or tests surface issues, fix them and commit:
```bash
git commit -m "fix: address lint/test issues from UnitResolver extraction"
```

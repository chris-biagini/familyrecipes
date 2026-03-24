# USDA Portion Classifier Extraction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extract USDA portion classification logic from `NutritionTui::Data` into a shared domain class `FamilyRecipes::UsdaPortionClassifier`, simplify `UsdaClient` to return raw portions, and retarget all tests.

**Architecture:** New domain class in `lib/familyrecipes/` owns all classification logic. `UsdaClient` becomes a pure HTTP adapter returning flat portion arrays. TUI calls the new class directly. Web editor (future) will consume the same class.

**Tech Stack:** Ruby, Minitest, FamilyRecipes domain module

**Design doc:** `docs/plans/2026-03-11-usda-portion-classifier-design.md`

---

### Task 1: Create `UsdaPortionClassifier` with tests

**Files:**
- Create: `lib/familyrecipes/usda_portion_classifier.rb`
- Create: `test/usda_portion_classifier_test.rb`
- Modify: `lib/familyrecipes.rb` (add require)

**Step 1: Write the test file**

Create `test/usda_portion_classifier_test.rb`. These are the classification
tests currently in `test/nutrition_tui/data_test.rb`, retargeted at the new
class. Uses `Minitest::Test` (no Rails dependency). The `Result` is now a
`Data.define` object, so use dot-accessor syntax (`.density_candidates`) not
hash syntax (`[:density_candidates]`).

```ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/familyrecipes'

class UsdaPortionClassifierTest < Minitest::Test
  Classifier = FamilyRecipes::UsdaPortionClassifier

  # --- classify ---

  def test_volume_modifier_becomes_density_candidate
    result = Classifier.classify([{ modifier: 'cup', grams: 125.0, amount: 1.0 }])

    assert_equal 1, result.density_candidates.size
    assert_in_delta 125.0, result.density_candidates.first[:each]
    assert_empty result.portion_candidates
    assert_empty result.filtered
  end

  def test_volume_with_prep_becomes_density_candidate
    result = Classifier.classify([{ modifier: 'cup, chopped', grams: 130.0, amount: 1.0 }])

    assert_equal 1, result.density_candidates.size
    assert_in_delta 130.0, result.density_candidates.first[:each]
  end

  def test_count_unit_becomes_portion_candidate
    result = Classifier.classify([{ modifier: 'clove', grams: 3.0, amount: 1.0 }])

    assert_equal 1, result.portion_candidates.size
    candidate = result.portion_candidates.first

    assert_equal 'clove', candidate[:display_name]
    assert_in_delta 3.0, candidate[:each]
  end

  def test_portion_candidate_strips_parenthetical_for_display_name
    result = Classifier.classify([{ modifier: 'medium (2-1/4" dia)', grams: 150.0, amount: 1.0 }])

    assert_equal 1, result.portion_candidates.size
    assert_equal 'medium', result.portion_candidates.first[:display_name]
  end

  def test_weight_unit_filtered
    result = Classifier.classify([{ modifier: 'oz', grams: 28.35, amount: 1.0 }])

    assert_equal 1, result.filtered.size
    assert_equal 'weight unit', result.filtered.first[:reason]
    assert_empty result.density_candidates
  end

  def test_regulatory_filtered
    result = Classifier.classify([{ modifier: 'NLEA serving', grams: 30.0, amount: 1.0 }])

    assert_equal 1, result.filtered.size
    assert_equal 'regulatory', result.filtered.first[:reason]
  end

  def test_amount_normalization_computes_each
    result = Classifier.classify([{ modifier: 'oz', grams: 113.0, amount: 4.0 }])

    assert_in_delta 28.25, result.filtered.first[:each]
  end

  def test_mixed_modifiers_classified_correctly
    modifiers = [
      { modifier: 'cup', grams: 240.0, amount: 1.0 },
      { modifier: 'oz', grams: 28.35, amount: 1.0 },
      { modifier: 'NLEA serving', grams: 30.0, amount: 1.0 },
      { modifier: 'large', grams: 50.0, amount: 1.0 }
    ]
    result = Classifier.classify(modifiers)

    assert_equal 1, result.density_candidates.size
    assert_equal 1, result.portion_candidates.size
    assert_equal 2, result.filtered.size
  end

  # --- pick_best_density ---

  def test_pick_best_density_selects_largest_grams
    candidates = [
      { modifier: 'tbsp', grams: 15.0, amount: 1.0, each: 15.0 },
      { modifier: 'cup', grams: 240.0, amount: 1.0, each: 240.0 }
    ]
    best = Classifier.pick_best_density(candidates)

    assert_equal 'cup', best[:modifier]
    assert_in_delta 240.0, best[:grams]
  end

  def test_pick_best_density_returns_nil_for_empty
    assert_nil Classifier.pick_best_density([])
  end

  # --- strip_parenthetical ---

  def test_strip_parenthetical_removes_parens
    assert_equal 'medium', Classifier.strip_parenthetical('medium (2-1/4" dia)')
  end

  def test_strip_parenthetical_no_parens_unchanged
    assert_equal 'clove', Classifier.strip_parenthetical('clove')
  end

  def test_strip_parenthetical_empty_string
    assert_equal '', Classifier.strip_parenthetical('')
  end

  # --- volume_modifier? ---

  def test_volume_modifier_cup
    assert Classifier.volume_modifier?('cup')
  end

  def test_volume_modifier_tbsp
    assert Classifier.volume_modifier?('tbsp')
  end

  def test_volume_modifier_tablespoon
    assert Classifier.volume_modifier?('tablespoon')
  end

  def test_volume_modifier_tsp_packed
    assert Classifier.volume_modifier?('tsp packed')
  end

  def test_volume_modifier_fl_oz
    assert Classifier.volume_modifier?('fl oz')
  end

  def test_volume_modifier_cups_plural
    assert Classifier.volume_modifier?('cups')
  end

  def test_volume_modifier_liter_exact
    assert Classifier.volume_modifier?('l')
  end

  def test_volume_modifier_rejects_large
    refute Classifier.volume_modifier?('large')
  end

  def test_volume_modifier_fluid_ounce
    assert Classifier.volume_modifier?('fluid ounce')
  end

  def test_volume_modifier_case_insensitive
    assert Classifier.volume_modifier?('Cup')
    assert Classifier.volume_modifier?('TBSP')
  end

  def test_volume_modifier_with_parenthetical
    assert Classifier.volume_modifier?('cup(s)')
  end

  def test_volume_modifier_nil_input
    refute Classifier.volume_modifier?(nil)
  end

  def test_volume_modifier_empty_string
    refute Classifier.volume_modifier?('')
  end

  def test_volume_modifier_rejects_clove
    refute Classifier.volume_modifier?('clove')
  end

  # --- weight_modifier? ---

  def test_weight_modifier_oz
    assert Classifier.weight_modifier?('oz')
  end

  def test_weight_modifier_pound
    assert Classifier.weight_modifier?('pound')
  end

  def test_weight_modifier_kg
    assert Classifier.weight_modifier?('kg')
  end

  def test_weight_modifier_g_exact
    assert Classifier.weight_modifier?('g')
  end

  def test_weight_modifier_rejects_garlic
    refute Classifier.weight_modifier?('garlic')
  end

  def test_weight_modifier_lbs
    assert Classifier.weight_modifier?('lbs')
  end

  def test_weight_modifier_ounce_is_weight_not_volume
    assert Classifier.weight_modifier?('ounce')
    refute Classifier.volume_modifier?('ounce')
  end

  def test_weight_modifier_rejects_cup
    refute Classifier.weight_modifier?('cup')
  end

  # --- regulatory_modifier? ---

  def test_regulatory_nlea
    assert Classifier.regulatory_modifier?('NLEA serving')
  end

  def test_regulatory_serving_packet
    assert Classifier.regulatory_modifier?('serving packet')
  end

  def test_regulatory_individual_packet
    assert Classifier.regulatory_modifier?('individual packet')
  end

  def test_regulatory_rejects_cup
    refute Classifier.regulatory_modifier?('cup')
  end

  # --- normalize_volume_unit ---

  def test_normalize_cup_chopped
    assert_equal 'cup', Classifier.normalize_volume_unit('cup, chopped')
  end

  def test_normalize_tablespoon
    assert_equal 'tbsp', Classifier.normalize_volume_unit('tablespoon')
  end

  def test_normalize_tsp_packed
    assert_equal 'tsp', Classifier.normalize_volume_unit('tsp packed')
  end

  def test_normalize_cups_plural
    assert_equal 'cup', Classifier.normalize_volume_unit('cups')
  end

  def test_normalize_fl_oz
    assert_equal 'fl oz', Classifier.normalize_volume_unit('fl oz')
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/usda_portion_classifier_test.rb`
Expected: Error — `UsdaPortionClassifier` not defined

**Step 3: Write the implementation**

Create `lib/familyrecipes/usda_portion_classifier.rb`:

```ruby
# frozen_string_literal: true

module FamilyRecipes
  # Classifies raw USDA FoodData Central portion entries into three buckets:
  # density candidates (volume-based, usable for g/mL density), portion
  # candidates (discrete units like "clove" or "large"), and filtered entries
  # (weight units and regulatory labels that carry no new information).
  #
  # Collaborators:
  # - UsdaClient (produces the raw portion hashes this class consumes)
  # - NutritionCalculator (VOLUME_TO_ML, WEIGHT_CONVERSIONS for unit sets)
  # - Inflector (ABBREVIATIONS, KNOWN_PLURALS for variant expansion)
  class UsdaPortionClassifier
    Result = Data.define(:density_candidates, :portion_candidates, :filtered)

    VOLUME_PREFIXES = begin
      prefixes = NutritionCalculator::VOLUME_TO_ML.keys.to_set
      Inflector::ABBREVIATIONS.each do |long_form, short_form|
        prefixes << long_form if NutritionCalculator::VOLUME_TO_ML.key?(short_form)
      end
      Inflector::KNOWN_PLURALS.each do |singular, plural|
        prefixes << plural if prefixes.include?(singular)
      end
      prefixes.freeze
    end

    WEIGHT_PREFIXES = begin
      prefixes = NutritionCalculator::WEIGHT_CONVERSIONS.keys.to_set
      Inflector::ABBREVIATIONS.each do |long_form, short_form|
        prefixes << long_form if NutritionCalculator::WEIGHT_CONVERSIONS.key?(short_form)
      end
      Inflector::KNOWN_PLURALS.each do |singular, plural|
        prefixes << plural if prefixes.include?(singular)
      end
      prefixes.freeze
    end

    def self.classify(portions)
      buckets = portions.each_with_object(density: [], portions: [], filtered: []) do |mod, result|
        entry = mod.merge(each: per_unit_grams(mod))
        bucket, extra = modifier_bucket(mod[:modifier])
        result[bucket] << entry.merge(extra)
      end

      Result.new(
        density_candidates: buckets[:density],
        portion_candidates: buckets[:portions],
        filtered: buckets[:filtered]
      )
    end

    def self.pick_best_density(density_candidates)
      density_candidates.max_by { |c| c[:grams] }
    end

    def self.normalize_volume_unit(modifier)
      clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
      words = clean.split(/[\s,]+/)
      two_word = Inflector.normalize_unit(words.first(2).join(' '))
      return two_word if NutritionCalculator::VOLUME_TO_ML.key?(two_word)

      Inflector.normalize_unit(words.first)
    end

    def self.strip_parenthetical(modifier)
      modifier.to_s.sub(/\s*\([^)]*\)/, '').strip
    end

    def self.volume_modifier?(modifier)
      unit_prefix_match?(modifier, VOLUME_PREFIXES)
    end

    def self.weight_modifier?(modifier)
      unit_prefix_match?(modifier, WEIGHT_PREFIXES)
    end

    def self.regulatory_modifier?(modifier)
      modifier.to_s.downcase.match?(/\bnlea\b|\bserving\b|\bpacket\b/)
    end

    # Matches when modifier starts with a unit and the next char is
    # a word boundary (space, comma, paren, or end-of-string). Prevents
    # 'l' matching 'large' or 'g' matching 'garlic'.
    def self.unit_prefix_match?(modifier, prefixes)
      downcased = modifier.to_s.downcase
      prefixes.any? { |u| downcased.start_with?(u) && (downcased.size == u.size || downcased[u.size] =~ /[\s,(]/) }
    end
    private_class_method :unit_prefix_match?

    def self.per_unit_grams(mod)
      (mod[:grams] / mod[:amount].to_f).round(2)
    end
    private_class_method :per_unit_grams

    def self.modifier_bucket(modifier)
      if weight_modifier?(modifier)
        [:filtered, { reason: 'weight unit' }]
      elsif regulatory_modifier?(modifier)
        [:filtered, { reason: 'regulatory' }]
      elsif volume_modifier?(modifier)
        [:density, {}]
      else
        [:portions, { display_name: strip_parenthetical(modifier) }]
      end
    end
    private_class_method :modifier_bucket
  end
end
```

**Step 4: Register in `lib/familyrecipes.rb`**

Add after the `usda_client` require (line 93):

```ruby
require_relative 'familyrecipes/usda_portion_classifier'
```

**Step 5: Run tests to verify they pass**

Run: `ruby -Itest test/usda_portion_classifier_test.rb`
Expected: All 35 tests pass

**Step 6: Commit**

```bash
git add lib/familyrecipes/usda_portion_classifier.rb test/usda_portion_classifier_test.rb lib/familyrecipes.rb
git commit -m "feat: extract UsdaPortionClassifier from TUI into shared domain layer"
```

---

### Task 2: Simplify `UsdaClient` to return flat portions

**Files:**
- Modify: `lib/familyrecipes/usda_client.rb` (lines 150-174)
- Modify: `test/usda_client_test.rb` (lines 78-109, 161-193)

**Step 1: Update tests for flat portions**

In `test/usda_client_test.rb`, replace
`test_fetch_classifies_volume_and_non_volume_portions` with a test that expects
a flat array:

```ruby
def test_fetch_returns_flat_portions_array
  body = sample_food_detail

  with_api_response(200, body) do
    result = @client.fetch(fdc_id: 168_913)
    portions = result[:portions]

    assert_kind_of Array, portions
    assert_equal 2, portions.size
    assert_equal 'cup', portions.first[:modifier]
    assert_in_delta 125.0, portions.first[:grams]
    assert_equal 'serving', portions.last[:modifier]
  end
end
```

Replace `test_fetch_skips_portions_with_empty_modifier` assertions:

```ruby
def test_fetch_skips_portions_with_empty_modifier
  body = {
    'fdcId' => 100, 'description' => 'Test',
    'foodNutrients' => [],
    'foodPortions' => [
      { 'modifier' => '', 'gramWeight' => 50.0, 'amount' => 1.0 },
      { 'modifier' => 'cup', 'gramWeight' => 125.0, 'amount' => 1.0 }
    ]
  }

  with_api_response(200, body) do
    result = @client.fetch(fdc_id: 100)

    assert_equal 1, result[:portions].size
    assert_equal 'cup', result[:portions].first[:modifier]
  end
end
```

Delete all `volume_unit?` tests (lines 161-193) — that private method no longer
exists.

**Step 2: Run tests to verify they fail**

Run: `ruby -Itest test/usda_client_test.rb`
Expected: Failures on the two modified tests (still getting hash with
`:volume`/`:non_volume` keys)

**Step 3: Simplify `UsdaClient`**

In `lib/familyrecipes/usda_client.rb`:

Replace `classify_portions` (lines 150-158) with:

```ruby
def extract_portions(food_detail)
  (food_detail['foodPortions'] || []).filter_map { |p| build_portion_entry(p) }
end
```

In `format_fetch_response` (line 135), change `classify_portions(data)` to
`extract_portions(data)`.

Delete the `volume_unit?` private method (lines 170-174).

**Step 4: Run tests to verify they pass**

Run: `ruby -Itest test/usda_client_test.rb`
Expected: All tests pass

**Step 5: Run full test suite to check nothing else broke**

Run: `bundle exec rake test`
Expected: The TUI ingredient screen tests (if any exist) may fail — that's
expected and fixed in Task 4. The `data_test.rb` tests still pass because
`NutritionTui::Data` hasn't been modified yet.

**Step 6: Commit**

```bash
git add lib/familyrecipes/usda_client.rb test/usda_client_test.rb
git commit -m "refactor: simplify UsdaClient to return flat portions array"
```

---

### Task 3: Remove USDA classification from `NutritionTui::Data`

**Files:**
- Modify: `lib/nutrition_tui/data.rb` (delete ~60 lines)
- Modify: `test/nutrition_tui/data_test.rb` (delete ~220 lines of moved tests)

**Step 1: Delete USDA classification tests from `data_test.rb`**

Remove all tests from line 8 through line 247 (everything from
`# --- classify_usda_modifiers ---` through the last
`test_normalize_fl_oz` test). Keep the `# --- build_lookup ---` section
(line 250 onward) and everything after it.

The remaining tests should be:
- `test_build_lookup_finds_exact_name`
- `test_build_lookup_finds_case_insensitive`
- `test_build_lookup_includes_aliases`
- `test_build_lookup_skips_alias_that_is_also_a_key`
- `test_resolve_to_canonical_exact`
- `test_resolve_to_canonical_case_insensitive`
- `test_resolve_to_canonical_returns_nil_for_unknown`
- `test_format_pct_normal`
- `test_format_pct_zero_total`
- `test_format_pct_rounds`
- `test_nutrients_has_eleven_entries`
- `test_project_root_points_to_repo`

**Step 2: Run trimmed tests to verify they still pass**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: 12 tests pass

**Step 3: Delete USDA classification methods from `data.rb`**

Remove from `lib/nutrition_tui/data.rb`:

1. Constants `VOLUME_PREFIXES` (lines 29-38) and `WEIGHT_PREFIXES` (lines
   40-49)
2. Methods in the `# --- USDA modifier classification ---` section (lines
   136-181): `classify_usda_modifiers`, `pick_best_density`,
   `strip_parenthetical`, `volume_modifier?`, `weight_modifier?`,
   `unit_prefix_match?`, `regulatory_modifier?`, `normalize_volume_unit`
3. Private helpers `per_unit_grams` and `modifier_bucket` (lines 291-305)
4. Their `private_class_method` declarations — remove
   `:unit_prefix_match?`, `:per_unit_grams`, `:modifier_bucket` from the
   second `private_class_method` call (lines 313-317)
5. Remove `# rubocop:disable Metrics/ModuleLength` from line 18 and
   `# rubocop:enable Metrics/ModuleLength` from line 318

**Step 4: Run data tests again to confirm nothing broke**

Run: `ruby -Itest test/nutrition_tui/data_test.rb`
Expected: 12 tests pass

**Step 5: Commit**

```bash
git add lib/nutrition_tui/data.rb test/nutrition_tui/data_test.rb
git commit -m "refactor: remove USDA classification from NutritionTui::Data"
```

---

### Task 4: Update TUI ingredient screen to use `UsdaPortionClassifier`

**Files:**
- Modify: `lib/nutrition_tui/screens/ingredient.rb` (lines 364-375)

**Step 1: Update `classify_and_apply_density`**

Replace the current method (lines 364-369):

```ruby
def classify_and_apply_density(detail)
  all_modifiers = detail[:portions][:volume] + detail[:portions][:non_volume]
  @usda_classified = Data.classify_usda_modifiers(all_modifiers)
  best = Data.pick_best_density(@usda_classified[:density_candidates])
  apply_density(best) if best
end
```

With:

```ruby
def classify_and_apply_density(detail)
  @usda_classified = FamilyRecipes::UsdaPortionClassifier.classify(detail[:portions])
  best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(@usda_classified.density_candidates)
  apply_density(best) if best
end
```

**Step 2: Update `apply_density`**

Replace the current method (lines 371-374):

```ruby
def apply_density(best)
  unit = Data.normalize_volume_unit(best[:modifier])
  @entry['density'] = { 'grams' => best[:each].round(2), 'volume' => 1.0, 'unit' => unit }
  @auto_density_source = best[:modifier]
end
```

With:

```ruby
def apply_density(best)
  unit = FamilyRecipes::UsdaPortionClassifier.normalize_volume_unit(best[:modifier])
  @entry['density'] = { 'grams' => best[:each].round(2), 'volume' => 1.0, 'unit' => unit }
  @auto_density_source = best[:modifier]
end
```

**Step 3: Update `usda_candidate_lines` for `Data.define` accessor**

Replace the current method (lines 250-254):

```ruby
def usda_candidate_lines
  density_lines = @usda_classified[:density_candidates].map { |c| format_usda_candidate(c) }
  portion_lines = @usda_classified[:portion_candidates].map { |c| format_usda_candidate(c) }
  density_lines + portion_lines
end
```

With:

```ruby
def usda_candidate_lines
  density_lines = @usda_classified.density_candidates.map { |c| format_usda_candidate(c) }
  portion_lines = @usda_classified.portion_candidates.map { |c| format_usda_candidate(c) }
  density_lines + portion_lines
end
```

**Step 4: Run full test suite**

Run: `bundle exec rake test`
Expected: All tests pass

**Step 5: Run lint**

Run: `bundle exec rubocop`
Expected: No new offenses

**Step 6: Commit**

```bash
git add lib/nutrition_tui/screens/ingredient.rb
git commit -m "refactor: wire TUI ingredient screen to UsdaPortionClassifier"
```

---

### Task 5: Final verification and cleanup

**Step 1: Run full test suite**

Run: `bundle exec rake`
Expected: 0 RuboCop offenses, all tests pass

**Step 2: Verify the old code paths are fully removed**

Grep for any remaining references to the deleted methods:

```bash
grep -rn 'Data\.classify_usda_modifiers\|Data\.pick_best_density\|Data\.normalize_volume_unit\|Data\.volume_modifier\|Data\.weight_modifier' lib/ test/
```

Expected: No matches

**Step 3: Grep for any remaining `classify_portions` or `volume_unit?` in UsdaClient**

```bash
grep -rn 'classify_portions\|volume_unit?' lib/familyrecipes/usda_client.rb
```

Expected: No matches

**Step 4: Commit (if any cleanup needed)**

Only if prior steps revealed something to fix.

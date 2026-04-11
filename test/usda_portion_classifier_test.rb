# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support/core_ext/object/blank'
require_relative '../lib/mirepoix'

class UsdaPortionClassifierTest < Minitest::Test
  Classifier = Mirepoix::UsdaPortionClassifier

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

  def test_pick_best_density_uses_per_unit_not_total_grams
    candidates = [
      { modifier: 'cup', grams: 480.0, amount: 2.0, each: 240.0 },
      { modifier: 'cup', grams: 250.0, amount: 1.0, each: 250.0 }
    ]
    best = Classifier.pick_best_density(candidates)

    assert_in_delta 250.0, best[:each]
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

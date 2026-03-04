# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support/core_ext/object/blank'
require_relative '../../lib/nutrition_tui/data'

class NutritionTuiDataTest < Minitest::Test
  # --- classify_usda_modifiers ---

  def test_volume_modifier_becomes_density_candidate
    modifiers = [{ modifier: 'cup', grams: 125.0, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:density_candidates].size
    assert_in_delta 125.0, result[:density_candidates].first[:each]
    assert_empty result[:portion_candidates]
    assert_empty result[:filtered]
  end

  def test_volume_with_prep_becomes_density_candidate
    modifiers = [{ modifier: 'cup, chopped', grams: 130.0, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:density_candidates].size
    assert_in_delta 130.0, result[:density_candidates].first[:each]
  end

  def test_count_unit_becomes_portion_candidate
    modifiers = [{ modifier: 'clove', grams: 3.0, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:portion_candidates].size
    candidate = result[:portion_candidates].first

    assert_equal 'clove', candidate[:display_name]
    assert_in_delta 3.0, candidate[:each]
  end

  def test_portion_candidate_strips_parenthetical_for_display_name
    modifiers = [{ modifier: 'medium (2-1/4" dia)', grams: 150.0, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:portion_candidates].size
    assert_equal 'medium', result[:portion_candidates].first[:display_name]
  end

  def test_weight_unit_filtered
    modifiers = [{ modifier: 'oz', grams: 28.35, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:filtered].size
    assert_equal 'weight unit', result[:filtered].first[:reason]
    assert_empty result[:density_candidates]
  end

  def test_regulatory_filtered
    modifiers = [{ modifier: 'NLEA serving', grams: 30.0, amount: 1.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:filtered].size
    assert_equal 'regulatory', result[:filtered].first[:reason]
  end

  def test_amount_normalization_computes_each
    modifiers = [{ modifier: 'oz', grams: 113.0, amount: 4.0 }]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_in_delta 28.25, result[:filtered].first[:each]
  end

  def test_mixed_modifiers_classified_correctly
    modifiers = [
      { modifier: 'cup', grams: 240.0, amount: 1.0 },
      { modifier: 'oz', grams: 28.35, amount: 1.0 },
      { modifier: 'NLEA serving', grams: 30.0, amount: 1.0 },
      { modifier: 'large', grams: 50.0, amount: 1.0 }
    ]
    result = NutritionTui::Data.classify_usda_modifiers(modifiers)

    assert_equal 1, result[:density_candidates].size
    assert_equal 1, result[:portion_candidates].size
    assert_equal 2, result[:filtered].size
  end

  # --- pick_best_density ---

  def test_pick_best_density_selects_largest_grams
    candidates = [
      { modifier: 'tbsp', grams: 15.0, amount: 1.0, each: 15.0 },
      { modifier: 'cup', grams: 240.0, amount: 1.0, each: 240.0 }
    ]
    best = NutritionTui::Data.pick_best_density(candidates)

    assert_equal 'cup', best[:modifier]
    assert_in_delta 240.0, best[:grams]
  end

  def test_pick_best_density_returns_nil_for_empty
    assert_nil NutritionTui::Data.pick_best_density([])
  end

  # --- strip_parenthetical ---

  def test_strip_parenthetical_removes_parens
    assert_equal 'medium', NutritionTui::Data.strip_parenthetical('medium (2-1/4" dia)')
  end

  def test_strip_parenthetical_no_parens_unchanged
    assert_equal 'clove', NutritionTui::Data.strip_parenthetical('clove')
  end

  def test_strip_parenthetical_empty_string
    assert_equal '', NutritionTui::Data.strip_parenthetical('')
  end

  # --- volume_modifier? ---

  def test_volume_modifier_cup
    assert NutritionTui::Data.volume_modifier?('cup')
  end

  def test_volume_modifier_tbsp
    assert NutritionTui::Data.volume_modifier?('tbsp')
  end

  def test_volume_modifier_tablespoon
    assert NutritionTui::Data.volume_modifier?('tablespoon')
  end

  def test_volume_modifier_tsp_packed
    assert NutritionTui::Data.volume_modifier?('tsp packed')
  end

  def test_volume_modifier_fl_oz
    assert NutritionTui::Data.volume_modifier?('fl oz')
  end

  def test_volume_modifier_rejects_clove
    refute NutritionTui::Data.volume_modifier?('clove')
  end

  # --- weight_modifier? ---

  def test_weight_modifier_oz
    assert NutritionTui::Data.weight_modifier?('oz')
  end

  def test_weight_modifier_pound
    assert NutritionTui::Data.weight_modifier?('pound')
  end

  def test_weight_modifier_kg
    assert NutritionTui::Data.weight_modifier?('kg')
  end

  def test_weight_modifier_rejects_cup
    refute NutritionTui::Data.weight_modifier?('cup')
  end

  # --- regulatory_modifier? ---

  def test_regulatory_nlea
    assert NutritionTui::Data.regulatory_modifier?('NLEA serving')
  end

  def test_regulatory_serving_packet
    assert NutritionTui::Data.regulatory_modifier?('serving packet')
  end

  def test_regulatory_individual_packet
    assert NutritionTui::Data.regulatory_modifier?('individual packet')
  end

  def test_regulatory_rejects_cup
    refute NutritionTui::Data.regulatory_modifier?('cup')
  end

  # --- normalize_volume_unit ---

  def test_normalize_cup_chopped
    assert_equal 'cup', NutritionTui::Data.normalize_volume_unit('cup, chopped')
  end

  def test_normalize_tablespoon
    assert_equal 'tbsp', NutritionTui::Data.normalize_volume_unit('tablespoon')
  end

  def test_normalize_tsp_packed
    assert_equal 'tsp', NutritionTui::Data.normalize_volume_unit('tsp packed')
  end

  def test_normalize_cups_plural
    assert_equal 'cup', NutritionTui::Data.normalize_volume_unit('cups')
  end

  def test_normalize_fl_oz
    assert_equal 'fl oz', NutritionTui::Data.normalize_volume_unit('fl oz')
  end

  # --- build_lookup ---

  def test_build_lookup_finds_exact_name
    data = { 'Flour (all-purpose)' => { 'nutrients' => {} } }
    lookup = NutritionTui::Data.build_lookup(data)

    assert_equal 'Flour (all-purpose)', lookup['Flour (all-purpose)']
  end

  def test_build_lookup_finds_case_insensitive
    data = { 'Butter' => { 'nutrients' => {} } }
    lookup = NutritionTui::Data.build_lookup(data)

    assert_equal 'Butter', lookup['butter']
  end

  def test_build_lookup_includes_aliases
    data = { 'Flour (all-purpose)' => { 'aliases' => ['All-purpose flour'] } }
    lookup = NutritionTui::Data.build_lookup(data)

    assert_equal 'Flour (all-purpose)', lookup['All-purpose flour']
    assert_equal 'Flour (all-purpose)', lookup['all-purpose flour']
  end

  def test_build_lookup_skips_alias_that_is_also_a_key
    data = {
      'Butter' => { 'aliases' => ['Margarine'] },
      'Margarine' => { 'nutrients' => {} }
    }
    lookup = NutritionTui::Data.build_lookup(data)

    assert_equal 'Margarine', lookup['Margarine']
  end

  # --- resolve_to_canonical ---

  def test_resolve_to_canonical_exact
    lookup = { 'Butter' => 'Butter', 'butter' => 'Butter' }

    assert_equal 'Butter', NutritionTui::Data.resolve_to_canonical('Butter', lookup)
  end

  def test_resolve_to_canonical_case_insensitive
    lookup = { 'Butter' => 'Butter', 'butter' => 'Butter' }

    assert_equal 'Butter', NutritionTui::Data.resolve_to_canonical('butter', lookup)
  end

  def test_resolve_to_canonical_returns_nil_for_unknown
    lookup = { 'Butter' => 'Butter' }

    assert_nil NutritionTui::Data.resolve_to_canonical('Cheese', lookup)
  end

  # --- format_pct ---

  def test_format_pct_normal
    assert_equal '50%', NutritionTui::Data.format_pct(5, 10)
  end

  def test_format_pct_zero_total
    assert_equal '0%', NutritionTui::Data.format_pct(0, 0)
  end

  def test_format_pct_rounds
    assert_equal '33%', NutritionTui::Data.format_pct(1, 3)
  end

  # --- Constants ---

  def test_nutrients_has_eleven_entries
    assert_equal 11, NutritionTui::Data::NUTRIENTS.size
  end

  def test_project_root_points_to_repo
    assert File.directory?(NutritionTui::Data::PROJECT_ROOT)
    assert_path_exists File.join(NutritionTui::Data::PROJECT_ROOT, 'Gemfile')
  end
end

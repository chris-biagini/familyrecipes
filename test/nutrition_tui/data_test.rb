# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support/core_ext/object/blank'
require_relative '../../lib/nutrition_tui/data'

class NutritionTuiDataTest < Minitest::Test
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

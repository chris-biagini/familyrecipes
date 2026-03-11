# frozen_string_literal: true

require 'test_helper'

class UsdaImportServiceTest < ActiveSupport::TestCase
  setup do
    @detail = {
      fdc_id: 9003,
      description: 'Apples, raw, with skin',
      data_type: 'SR Legacy',
      nutrients: {
        'basis_grams' => 100.0, 'calories' => 52.0, 'fat' => 0.17,
        'saturated_fat' => 0.03, 'trans_fat' => 0.0, 'cholesterol' => 0.0,
        'sodium' => 1.0, 'carbs' => 13.81, 'fiber' => 2.4,
        'total_sugars' => 10.39, 'added_sugars' => 0.0, 'protein' => 0.26
      },
      portions: [
        { modifier: 'cup, quartered or chopped', grams: 125.0, amount: 1.0 },
        { modifier: 'tbsp', grams: 8.5, amount: 1.0 },
        { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 },
        { modifier: 'large (3-1/4" dia)', grams: 223.0, amount: 1.0 }
      ]
    }
  end

  test 'maps nutrients to catalog schema with basis_grams and symbol keys' do
    result = UsdaImportService.call(@detail)

    assert_in_delta(100.0, result.nutrients[:basis_grams])
    assert_in_delta 52.0, result.nutrients[:calories]
    assert_in_delta 0.17, result.nutrients[:fat]
    assert_in_delta 13.81, result.nutrients[:carbs]

    FamilyRecipes::NutritionConstraints::NUTRIENT_KEYS.each do |key|
      assert result.nutrients.key?(key), "Expected nutrient key #{key}"
    end
  end

  test 'auto-picks density from largest per-unit volume candidate' do
    result = UsdaImportService.call(@detail)

    assert_not_nil result.density
    assert_equal 'cup', result.density[:unit]
    assert_in_delta 125.0, result.density[:grams]
    assert_in_delta 1.0, result.density[:volume]
  end

  test 'returns nil density when no volume candidates exist' do
    @detail[:portions] = [
      { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 },
      { modifier: 'large (3-1/4" dia)', grams: 223.0, amount: 1.0 }
    ]

    result = UsdaImportService.call(@detail)

    assert_nil result.density
  end

  test 'builds source metadata' do
    result = UsdaImportService.call(@detail)

    assert_equal 'usda', result.source[:type]
    assert_equal 'SR Legacy', result.source[:dataset]
    assert_equal 9003, result.source[:fdc_id]
    assert_equal 'Apples, raw, with skin', result.source[:description]
  end

  test 'extracts portion candidates with display names' do
    result = UsdaImportService.call(@detail)

    names = result.portions.pluck(:name)

    assert_includes names, 'medium'
    assert_includes names, 'large'

    medium = result.portions.find { |p| p[:name] == 'medium' }

    assert_in_delta 182.0, medium[:grams]
  end

  test 'includes density candidates for informational display' do
    result = UsdaImportService.call(@detail)

    assert_not_empty result.density_candidates
    modifiers = result.density_candidates.pluck(:modifier)

    assert_includes modifiers, 'cup, quartered or chopped'
    assert_includes modifiers, 'tbsp'
  end

  test 'Result#as_json returns hash with all keys' do
    result = UsdaImportService.call(@detail)
    json = result.as_json

    assert_kind_of Hash, json
    assert_equal %i[density density_candidates nutrients portions source], json.keys.sort
    assert_in_delta 52.0, json[:nutrients][:calories]
  end

  test 'handles empty portions gracefully' do
    @detail[:portions] = []

    result = UsdaImportService.call(@detail)

    assert_nil result.density
    assert_empty result.portions
    assert_empty result.density_candidates
  end
end

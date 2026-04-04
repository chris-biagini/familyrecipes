# frozen_string_literal: true

require 'test_helper'

class IngredientsHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    setup_test_kitchen
    IngredientCatalog.where(kitchen_id: nil).delete_all
  end

  test 'format_nutrient_value omits trailing zeros' do
    assert_equal '110', format_nutrient_value(110.0)
    assert_equal '0.5', format_nutrient_value(0.5)
    assert_equal '0', format_nutrient_value(0.0)
  end

  test "formats 'via density' as 'volume conversion'" do
    assert_equal 'volume conversion', format_resolution_method('via density', nil)
  end

  test "formats 'weight' as 'standard weight'" do
    assert_equal 'standard weight', format_resolution_method('weight', nil)
  end

  test "formats 'no density' as 'no volume conversion'" do
    assert_equal 'no volume conversion', format_resolution_method('no density', nil)
  end

  test "formats 'no portion' with actionable prompt" do
    assert_equal 'no matching unit — add one below', format_resolution_method('no portion', nil)
  end

  test "formats 'no ~unitless portion' with each language" do
    result = format_resolution_method('no ~unitless portion', nil)

    assert_equal "no 'each' weight — add one below", result
  end

  test "formats 'via ~unitless' with gram weight from entry" do
    entry = Struct.new(:portions).new({ '~unitless' => 50.0 })

    assert_equal 'unit weight (50 g)', format_resolution_method('via ~unitless', entry)
  end

  test "formats 'via stick' with gram weight from entry" do
    entry = Struct.new(:portions).new({ 'stick' => 113.0 })

    assert_equal 'unit weight (113 g)', format_resolution_method('via stick', entry)
  end

  test "formats 'via clove' without entry gracefully" do
    assert_equal 'unit weight', format_resolution_method('via clove', nil)
  end

  test "passes through 'no nutrition data' unchanged" do
    assert_equal 'no nutrition data', format_resolution_method('no nutrition data', nil)
  end

  test "format_unit_name returns 'each' for nil" do
    assert_equal 'each', format_unit_name(nil)
  end

  test 'format_unit_name passes through named units' do
    assert_equal 'cup', format_unit_name('cup')
  end
end

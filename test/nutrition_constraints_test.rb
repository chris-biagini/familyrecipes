# frozen_string_literal: true

require 'test_helper'

class NutritionConstraintsTest < ActiveSupport::TestCase
  NC = FamilyRecipes::NutritionConstraints

  # --- valid_basis_grams? ---

  test 'valid_basis_grams? accepts positive number' do
    valid, = NC.valid_basis_grams?(30)

    assert valid
  end

  test 'valid_basis_grams? rejects zero' do
    valid, msg = NC.valid_basis_grams?(0)

    assert_not valid
    assert_includes msg, 'greater than 0'
  end

  test 'valid_basis_grams? rejects negative' do
    valid, = NC.valid_basis_grams?(-5)

    assert_not valid
  end

  test 'valid_basis_grams? rejects nil' do
    valid, = NC.valid_basis_grams?(nil)

    assert_not valid
  end

  test 'valid_basis_grams? rejects non-numeric' do
    valid, = NC.valid_basis_grams?('abc')

    assert_not valid
  end

  # --- valid_nutrient? ---

  test 'valid_nutrient? accepts zero' do
    valid, = NC.valid_nutrient?('calories', 0)

    assert valid
  end

  test 'valid_nutrient? accepts value at default cap' do
    valid, = NC.valid_nutrient?('calories', 10_000)

    assert valid
  end

  test 'valid_nutrient? rejects value over default cap' do
    valid, msg = NC.valid_nutrient?('calories', 10_001)

    assert_not valid
    assert_includes msg, '10000'
  end

  test 'valid_nutrient? rejects negative' do
    valid, = NC.valid_nutrient?('fat', -1)

    assert_not valid
  end

  test 'valid_nutrient? allows sodium up to 50000' do
    valid, = NC.valid_nutrient?('sodium', 38_758)

    assert valid
  end

  test 'valid_nutrient? rejects sodium over 50000' do
    valid, msg = NC.valid_nutrient?('sodium', 50_001)

    assert_not valid
    assert_includes msg, '50000'
  end

  test 'valid_nutrient? rejects non-numeric' do
    valid, = NC.valid_nutrient?('calories', 'abc')

    assert_not valid
  end

  # --- density_complete? ---

  test 'density_complete? accepts all three fields' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0, 'unit' => 'cup' })

    assert valid
  end

  test 'density_complete? accepts empty hash' do
    valid, = NC.density_complete?({})

    assert valid
  end

  test 'density_complete? accepts nil' do
    valid, = NC.density_complete?(nil)

    assert valid
  end

  test 'density_complete? rejects missing unit' do
    valid, msg = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0 })

    assert_not valid
    assert_includes msg, 'unit'
  end

  test 'density_complete? rejects missing grams' do
    valid, msg = NC.density_complete?({ 'volume' => 1.0, 'unit' => 'cup' })

    assert_not valid
    assert_includes msg, 'grams'
  end

  test 'density_complete? rejects missing volume' do
    valid, msg = NC.density_complete?({ 'grams' => 120, 'unit' => 'cup' })

    assert_not valid
    assert_includes msg, 'volume'
  end

  test 'density_complete? rejects non-positive grams' do
    valid, = NC.density_complete?({ 'grams' => 0, 'volume' => 1.0, 'unit' => 'cup' })

    assert_not valid
  end

  test 'density_complete? rejects non-positive volume' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => -1, 'unit' => 'cup' })

    assert_not valid
  end

  test 'density_complete? rejects blank unit' do
    valid, = NC.density_complete?({ 'grams' => 120, 'volume' => 1.0, 'unit' => '' })

    assert_not valid
  end

  # --- valid_portion_value? ---

  test 'valid_portion_value? accepts positive number' do
    valid, = NC.valid_portion_value?(113)

    assert valid
  end

  test 'valid_portion_value? rejects zero' do
    valid, msg = NC.valid_portion_value?(0)

    assert_not valid
    assert_includes msg, 'greater than 0'
  end

  test 'valid_portion_value? rejects negative' do
    valid, = NC.valid_portion_value?(-10)

    assert_not valid
  end

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

  # --- valid_aisle? ---

  test 'valid_aisle? accepts string within limit' do
    valid, = NC.valid_aisle?('Produce')

    assert valid
  end

  test 'valid_aisle? accepts string at max length' do
    valid, = NC.valid_aisle?('a' * 50)

    assert valid
  end

  test 'valid_aisle? rejects string over max length' do
    valid, msg = NC.valid_aisle?('a' * 51)

    assert_not valid
    assert_includes msg, '50'
  end
end

# frozen_string_literal: true

require_relative '../test_helper'

class NutritionLabelParserTest < ActiveSupport::TestCase
  # Lightweight stand-in for IngredientCatalog — duck-typed attribute reader
  # avoids acts_as_tenant requirement in unit tests
  FakeEntry = Data.define(
    :ingredient_name, :basis_grams,
    :calories, :fat, :saturated_fat, :trans_fat,
    :cholesterol, :sodium, :carbs, :fiber,
    :total_sugars, :added_sugars, :protein,
    :density_grams, :density_volume, :density_unit,
    :portions
  )

  test 'parses complete label with density' do
    result = parse_complete_label

    assert_predicate result, :success?
    assert_empty result.errors
    assert_correct_nutrients(result.nutrients)
    assert_equal({ grams: 30.0, volume: 0.25, unit: 'cup' }, result.density)
  end

  test 'parses label with gram-only serving size' do
    text = <<~LABEL
      Serving size: 28g

      Calories    140
      Total Fat   7g
      Protein     5g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 28.0, result.nutrients[:basis_grams]
    assert_in_delta 140.0, result.nutrients[:calories]
    assert_in_delta 7.0, result.nutrients[:fat]
    assert_in_delta 5.0, result.nutrients[:protein]
    assert_nil result.density
  end

  test 'parses label with portions section' do
    text = <<~LABEL
      Serving size: 30g

      Calories    110

      Portions:
        stick: 113g
        slice: 21g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal({ 'stick' => 113.0, 'slice' => 21.0 }, result.portions)
  end

  test 'parses ~unitless portion' do
    text = <<~LABEL
      Serving size: 50g

      Calories    70

      Portions:
        ~unitless: 50g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal({ '~unitless' => 50.0 }, result.portions)
  end

  test 'missing nutrient lines default to zero' do
    text = <<~LABEL
      Serving size: 30g

      Calories    100
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 100.0, result.nutrients[:calories]
    assert_all_zero(result.nutrients, :fat, :saturated_fat, :trans_fat,
                    :cholesterol, :sodium, :carbs, :fiber, :total_sugars,
                    :added_sugars, :protein)
  end

  test 'fails when serving size is missing' do
    text = <<~LABEL
      Calories    100
      Total Fat   5g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_not_predicate result, :success?
    assert(result.errors.any? { |e| e.include?('Serving size') })
  end

  test 'fails when serving size has no gram weight' do
    text = <<~LABEL
      Serving size: 1/4 cup

      Calories    100
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_not_predicate result, :success?
    assert(result.errors.any? { |e| e.include?('gram weight') })
  end

  test 'handles unit suffixes case-insensitively' do
    text = <<~LABEL
      Serving size: 30g

      calories          100
      TOTAL FAT         5G
      saturated fat     2g
      TRANS FAT         0G
      cholesterol       10MG
      sodium            100MG
      total carbs       12G
      dietary fiber     1G
      total sugars      3G
      added sugars      1G
      protein           4G
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 100.0, result.nutrients[:calories]
    assert_in_delta 5.0, result.nutrients[:fat]
    assert_in_delta 2.0, result.nutrients[:saturated_fat]
    assert_in_delta 10.0, result.nutrients[:cholesterol]
    assert_in_delta 100.0, result.nutrients[:sodium]
    assert_in_delta 12.0, result.nutrients[:carbs]
    assert_in_delta 1.0, result.nutrients[:fiber]
    assert_in_delta 3.0, result.nutrients[:total_sugars]
    assert_in_delta 1.0, result.nutrients[:added_sugars]
    assert_in_delta 4.0, result.nutrients[:protein]
  end

  test 'ignores unknown lines gracefully' do
    text = <<~LABEL
      Serving size: 30g

      Calories      100
      Vitamin D     2mcg
      Iron          1mg
      Some nonsense here
      Protein       3g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 100.0, result.nutrients[:calories]
    assert_in_delta 3.0, result.nutrients[:protein]
  end

  test 'handles blank nutrient values as zero' do
    text = <<~LABEL
      Serving size: 30g

      Calories
      Total Fat
      Protein
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 0.0, result.nutrients[:calories]
    assert_in_delta 0.0, result.nutrients[:fat]
    assert_in_delta 0.0, result.nutrients[:protein]
  end

  test 'parses auto-portion from discrete serving size' do
    text = <<~LABEL
      Serving size: 1 slice (21g)

      Calories    60
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 21.0, result.nutrients[:basis_grams]
    assert_equal({ 'slice' => 21.0 }, result.portions)
    assert_nil result.density
  end

  test 'portions g suffix is optional' do
    text = <<~LABEL
      Serving size: 30g

      Calories    100

      Portions:
        stick: 113
        slice: 21g
    LABEL

    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_equal({ 'stick' => 113.0, 'slice' => 21.0 }, result.portions)
  end

  test 'formats entry with density as label text' do
    entry = build_entry(
      basis_grams: 30.0, calories: 110.0, fat: 0.5, saturated_fat: 0.0,
      trans_fat: 0.0, cholesterol: 0.0, sodium: 5.0, carbs: 23.0,
      fiber: 1.0, total_sugars: 0.0, added_sugars: 0.0, protein: 3.0,
      density_grams: 30.0, density_volume: 0.25, density_unit: 'cup'
    )

    text = NutritionLabelParser.format(entry)

    assert_includes text, 'Serving size: 0.25 cup (30g)'
    assert_includes text, 'Calories'
    assert_includes text, '110'
    assert_includes text, 'Total Fat'
    assert_includes text, '0.5g'
    assert_includes text, 'Protein'
    assert_includes text, '3g'
  end

  test 'formats entry without density' do
    entry = build_entry(basis_grams: 28.0, calories: 140.0, fat: 7.0, protein: 5.0)

    text = NutritionLabelParser.format(entry)

    assert_includes text, 'Serving size: 28g'
    assert_includes text, 'Calories'
    assert_includes text, '140'
  end

  test 'formats entry with mismatched density as gram-only serving' do
    entry = build_entry(
      basis_grams: 100.0, calories: 884.0, fat: 100.0,
      density_grams: 216.0, density_volume: 1.0, density_unit: 'cup'
    )

    text = NutritionLabelParser.format(entry)

    assert_includes text, 'Serving size: 100g'
    assert_not_includes text, 'cup'
  end

  test 'formats entry with portions' do
    entry = build_entry(
      basis_grams: 30.0, calories: 110.0,
      portions: { 'stick' => 113.0, '~unitless' => 50.0 }
    )

    text = NutritionLabelParser.format(entry)

    assert_includes text, 'Portions:'
    assert_includes text, 'stick: 113g'
    assert_includes text, '~unitless: 50g'
  end

  test 'round-trips through parse and format' do
    entry = build_entry(
      basis_grams: 30.0, calories: 110.0, fat: 0.5, saturated_fat: 0.0,
      trans_fat: 0.0, cholesterol: 0.0, sodium: 5.0, carbs: 23.0,
      fiber: 1.0, total_sugars: 0.0, added_sugars: 0.0, protein: 3.0,
      density_grams: 30.0, density_volume: 0.25, density_unit: 'cup',
      portions: { 'stick' => 113.0 }
    )

    text = NutritionLabelParser.format(entry)
    result = NutritionLabelParser.parse(text)

    assert_predicate result, :success?
    assert_in_delta 30.0, result.nutrients[:basis_grams]
    assert_in_delta 110.0, result.nutrients[:calories]
    assert_in_delta 0.5, result.nutrients[:fat]
    assert_in_delta 23.0, result.nutrients[:carbs]
    assert_in_delta 3.0, result.nutrients[:protein]
    assert_equal({ grams: 30.0, volume: 0.25, unit: 'cup' }, result.density)
    assert_equal({ 'stick' => 113.0 }, result.portions)
  end

  test 'blank_skeleton produces expected template' do
    skeleton = NutritionLabelParser.blank_skeleton

    expected_lines = [
      'Serving size:', 'Calories', 'Total Fat', '  Saturated Fat',
      '  Trans Fat', 'Cholesterol', 'Sodium', 'Total Carbs',
      '  Dietary Fiber', '  Total Sugars', '    Added Sugars', 'Protein'
    ]

    expected_lines.each { |line| assert_includes skeleton, line }
    assert_not_includes skeleton, 'Portions'
  end

  private

  def build_entry(**attrs)
    defaults = {
      ingredient_name: 'Test Ingredient', basis_grams: 30.0,
      calories: 0.0, fat: 0.0, saturated_fat: 0.0, trans_fat: 0.0,
      cholesterol: 0.0, sodium: 0.0, carbs: 0.0, fiber: 0.0,
      total_sugars: 0.0, added_sugars: 0.0, protein: 0.0,
      density_grams: nil, density_volume: nil, density_unit: nil,
      portions: {}
    }
    FakeEntry.new(**defaults, **attrs)
  end

  def parse_complete_label
    text = <<~LABEL
      Serving size: 1/4 cup (30g)

      Calories          110
      Total Fat         0.5g
        Saturated Fat   0g
        Trans Fat       0g
      Cholesterol       0mg
      Sodium            5mg
      Total Carbs       23g
        Dietary Fiber   1g
        Total Sugars    0g
          Added Sugars  0g
      Protein           3g
    LABEL

    NutritionLabelParser.parse(text)
  end

  def assert_correct_nutrients(nutrients)
    assert_in_delta 30.0, nutrients[:basis_grams]
    assert_in_delta 110.0, nutrients[:calories]
    assert_in_delta 0.5, nutrients[:fat]
    assert_in_delta 0.0, nutrients[:saturated_fat]
    assert_in_delta 0.0, nutrients[:trans_fat]
    assert_in_delta 0.0, nutrients[:cholesterol]
    assert_in_delta 5.0, nutrients[:sodium]
    assert_in_delta 23.0, nutrients[:carbs]
    assert_in_delta 1.0, nutrients[:fiber]
    assert_in_delta 0.0, nutrients[:total_sugars]
    assert_in_delta 0.0, nutrients[:added_sugars]
    assert_in_delta 3.0, nutrients[:protein]
  end

  def assert_all_zero(nutrients, *keys)
    keys.each { |key| assert_in_delta 0.0, nutrients[key], 0.001, "expected #{key} to be 0" }
  end
end

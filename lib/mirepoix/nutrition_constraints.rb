# frozen_string_literal: true

module Mirepoix
  # Canonical nutrient definitions and shared validation for ingredient catalog
  # data. NUTRIENT_DEFS is the single source of truth for which nutrients exist,
  # their display labels, units, and indent levels — all downstream constants
  # derive from it. Predicate methods return [valid, error_message] tuples.
  #
  # Collaborators:
  # - IngredientCatalog (NUTRIENT_COLUMNS, NUTRIENT_DISPLAY, validation)
  # - NutritionCalculator (NUTRIENTS key list)
  # - RecipesHelper (NUTRITION_ROWS for label rendering)
  module NutritionConstraints
    NutrientDef = Data.define(:key, :label, :unit, :indent, :daily_value)

    NUTRIENT_DEFS = [
      NutrientDef.new(key: :calories,      label: 'Calories',      unit: '',   indent: 0, daily_value: nil),
      NutrientDef.new(key: :fat,           label: 'Total Fat',     unit: 'g',  indent: 0, daily_value: 78),
      NutrientDef.new(key: :saturated_fat, label: 'Saturated Fat', unit: 'g',  indent: 1, daily_value: 20),
      NutrientDef.new(key: :trans_fat,     label: 'Trans Fat',     unit: 'g',  indent: 1, daily_value: nil),
      NutrientDef.new(key: :cholesterol,   label: 'Cholesterol',   unit: 'mg', indent: 0, daily_value: 300),
      NutrientDef.new(key: :sodium,        label: 'Sodium',        unit: 'mg', indent: 0, daily_value: 2300),
      NutrientDef.new(key: :carbs,         label: 'Total Carbs',   unit: 'g',  indent: 0, daily_value: 275),
      NutrientDef.new(key: :fiber,         label: 'Fiber',         unit: 'g',  indent: 1, daily_value: 28),
      NutrientDef.new(key: :total_sugars,  label: 'Total Sugars',  unit: 'g',  indent: 1, daily_value: nil),
      NutrientDef.new(key: :added_sugars,  label: 'Added Sugars',  unit: 'g',  indent: 2, daily_value: 50),
      NutrientDef.new(key: :protein,       label: 'Protein',       unit: 'g',  indent: 0, daily_value: 50)
    ].freeze

    DAILY_VALUES = NUTRIENT_DEFS
                   .select(&:daily_value)
                   .to_h { |d| [d.key, d.daily_value] }
                   .freeze

    NUTRIENT_KEYS = NUTRIENT_DEFS.map(&:key).freeze

    NUTRIENT_MAX = Hash.new(10_000).merge('sodium' => 50_000).freeze
    AISLE_MAX_LENGTH = 50

    module_function

    def valid_nutrient?(key, value)
      return [false, "#{key} must be a number"] unless value.is_a?(Numeric)

      max = NUTRIENT_MAX[key.to_s]
      return [false, "#{key} must be between 0 and #{max}"] unless value.between?(0, max)

      [true, nil]
    end

    def valid_portion_value?(value)
      return [false, 'Portion value must be greater than 0'] unless value.is_a?(Numeric) && value.positive?

      [true, nil]
    end
  end
end

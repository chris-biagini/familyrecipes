# frozen_string_literal: true

# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

module FamilyRecipes
  class Ingredient
    attr_reader :name, :quantity, :prep_note

    # Fraction-to-decimal conversions for quantity parsing
    QUANTITY_FRACTIONS = {
      '1/2' => '0.5',
      '1/4' => '0.25',
      '1/3' => '0.333',
      '2/3' => '0.667',
      '3/4' => '0.75'
    }.freeze

    # Converts a raw numeric string (e.g., "1/2", "2-3", "250") to its
    # resolved value. Handles fractions via QUANTITY_FRACTIONS and ranges
    # by taking the high end. Used by both the parser and AR model.
    def self.numeric_value(raw)
      return nil if raw.nil? || raw.strip.empty?

      value_str = raw.strip
      value_str = value_str.split(/[-–]/).last.strip if value_str.match?(/[-–]/)

      QUANTITY_FRACTIONS[value_str] || value_str
    end

    # name is required, quantity and prep_note are optional
    def initialize(name:, quantity: nil, prep_note: nil)
      @name = name
      @quantity = quantity
      @prep_note = prep_note
    end

    def normalized_name = @name

    def quantity_value
      return nil if quantity_blank?

      self.class.numeric_value(parsed_quantity[0])
    end

    def quantity_unit
      return nil if quantity_blank?

      raw_unit = parsed_quantity[1]
      return nil if raw_unit.nil?

      FamilyRecipes::Inflector.normalize_unit(raw_unit)
    end

    private

    def quantity_blank?
      @quantity.nil? || @quantity.strip.empty?
    end

    def parsed_quantity
      @parsed_quantity ||= @quantity.strip.split(' ', 2)
    end
  end
end

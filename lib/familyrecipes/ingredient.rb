# frozen_string_literal: true

module FamilyRecipes
  # Parsed ingredient from a recipe step's bullet list (e.g., "Flour, 2 cups:
  # sifted"). Carries name, optional quantity string, and optional prep note.
  # IngredientAggregator and NutritionCalculator consume the parsed quantity_value
  # and quantity_unit for math; Inflector normalizes unit strings.
  class Ingredient
    attr_reader :name, :quantity, :prep_note

    # Resolves fractions and ranges (takes high end) to a numeric string.
    def self.numeric_value(raw)
      return nil if raw.nil? || raw.strip.empty?

      value_str = raw.strip
      value_str = value_str.split(/[-–]/).last.strip if value_str.match?(/[-–]/)

      if value_str.match?(%r{/}o) || value_str.match?(NumericParsing::VULGAR_PATTERN)
        return NumericParsing.parse_fraction(value_str).to_s
      end

      return nil unless Float(value_str, exception: false)

      value_str
    end

    # Splits a raw quantity string into [value, unit], merging mixed numbers
    # like "2 1/2 cups" into ["2 1/2", "cups"]. Returns [nil, nil] for blank.
    def self.split_quantity(raw)
      return [nil, nil] if raw.nil? || raw.strip.empty?

      parts = raw.strip.split(' ', 3)
      return [raw.strip, nil] unless numeric_token?(parts[0])

      if parts.size >= 2 && fraction_token?(parts[1])
        ["#{parts[0]} #{parts[1]}", parts[2]]
      else
        value, unit = raw.strip.split(' ', 2)
        [value, unit]
      end
    end

    def self.fraction_token?(token)
      token.match?(%r{\A\d+/\d+\z}) || token.match?(NumericParsing::VULGAR_PATTERN)
    end

    def self.numeric_token?(token)
      token.match?(/\A\d/) || token.match?(NumericParsing::VULGAR_PATTERN)
    end
    private_class_method :fraction_token?, :numeric_token?

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
      @parsed_quantity ||= self.class.split_quantity(@quantity)
    end
  end
end

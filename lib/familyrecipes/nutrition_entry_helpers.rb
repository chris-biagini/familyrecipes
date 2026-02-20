# frozen_string_literal: true

module FamilyRecipes
  module NutritionEntryHelpers
    KNOWN_VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons ml l liter liters].freeze

    NUTRITION_UNIT_OVERRIDES = { 'eggs' => '~unitless' }.freeze

    def self.parse_fraction(str)
      str = str.to_s.strip
      if str.include?('/')
        num, den = str.split('/')
        return nil if den.nil? || den.to_f.zero?

        num.to_f / den.to_i
      else
        Float(str, exception: false)
      end
    end

    def self.parse_serving_size(input)
      # Extract gram weight: "30g", "(30g)", "(3.3g)", "30 grams", "30 gram"
      grams_match = input.match(/(\d+(?:\.\d+)?)\s*(?:grams?|g)\b/)
      return nil unless grams_match

      grams = grams_match[1].to_f
      return nil if grams <= 0

      result = { grams: grams }

      # Get the descriptor: everything before the gram portion (parenthetical or slash-separated)
      descriptor = input.sub(%r{[/(]?\s*\d+(?:\.\d+)?\s*(?:grams?|g)\b[)\s]*}, '').strip

      # Strip "about" prefix
      descriptor = descriptor.sub(/\A(?:about|approximately|approx\.?)\s+/i, '').strip

      return result if descriptor.empty?

      # Parse descriptor for amount + unit
      match = descriptor.match(%r{\A(\d+(?:[/.]\d+)?)\s+(.+)\z})
      return result unless match

      amount = parse_fraction(match[1])
      return result unless amount&.positive?

      raw_unit = match[2].strip

      # Strip size modifiers: "3.5 inch piece" -> "piece"
      raw_unit = raw_unit.sub(/\d+\.?\d*\s*(?:inch|in|cm|mm)\s+/i, '').strip

      unit_down = raw_unit.downcase.chomp('.')

      # Classify: volume unit or discrete portion?
      if KNOWN_VOLUME_UNITS.include?(unit_down)
        # Normalize to canonical volume unit
        canonical = case unit_down
                    when 'cups' then 'cup'
                    when 'tablespoon', 'tablespoons' then 'tbsp'
                    when 'teaspoon', 'teaspoons' then 'tsp'
                    when 'liter', 'liters' then 'l'
                    else unit_down
                    end
        result[:volume_amount] = amount
        result[:volume_unit] = canonical
      else
        # Discrete unit -> create auto-portion
        singular = NUTRITION_UNIT_OVERRIDES[unit_down] || Inflector.normalize_unit(unit_down)
        grams_per_one = (grams / amount).round(2)
        result[:auto_portion] = { unit: singular, grams: grams_per_one }
      end

      result
    end

    def self.volume_to_ml(unit)
      NutritionCalculator::VOLUME_TO_ML[unit] || 1
    end
  end
end

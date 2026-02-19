module FamilyRecipes
  module NutritionEntryHelpers
    KNOWN_VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons ml l liter liters].freeze

    SINGULARIZE_MAP = {
      "crackers" => "cracker", "slices" => "slice", "pieces" => "piece",
      "cloves" => "clove", "stalks" => "stalk", "sticks" => "stick",
      "items" => "item", "eggs" => "~unitless", "tortillas" => "tortilla",
      "cookies" => "cookie", "chips" => "chip", "sheets" => "sheet",
      "strips" => "strip", "cubes" => "cube", "rings" => "ring",
      "patties" => "patty", "balls" => "ball", "links" => "link",
      "servings" => "serving"
    }.freeze

    def self.parse_fraction(str)
      str = str.to_s.strip
      if str.include?('/')
        num, den = str.split('/')
        return nil if den.nil? || den.to_f == 0
        num.to_f / den.to_f
      else
        Float(str) rescue nil
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
      descriptor = input.sub(/[\/(]?\s*\d+(?:\.\d+)?\s*(?:grams?|g)\b[)\s]*/, '').strip

      # Strip "about" prefix
      descriptor = descriptor.sub(/\A(?:about|approximately|approx\.?)\s+/i, '').strip

      return result if descriptor.empty?

      # Parse descriptor for amount + unit
      match = descriptor.match(/\A(\d+(?:[\/\.]\d+)?)\s+(.+)\z/)
      return result unless match

      amount = parse_fraction(match[1])
      return result unless amount && amount > 0

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
        singular = SINGULARIZE_MAP[unit_down] || singularize_simple(unit_down)
        grams_per_one = (grams / amount).round(2)
        result[:auto_portion] = { unit: singular, grams: grams_per_one }
      end

      result
    end

    def self.singularize_simple(word)
      return word if word.length < 3
      if word.end_with?('ies')
        word[0..-4] + 'y'
      elsif word.end_with?('ses', 'xes', 'zes', 'ches', 'shes')
        word[0..-3]
      elsif word.end_with?('s') && !word.end_with?('ss')
        word[0..-2]
      else
        word
      end
    end

    def self.volume_to_ml(unit)
      { 'cup' => 236.588, 'tbsp' => 14.787, 'tsp' => 4.929, 'ml' => 1, 'l' => 1000 }[unit] || 1
    end
  end
end

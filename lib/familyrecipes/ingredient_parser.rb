# frozen_string_literal: true

module IngredientParser
  CROSS_REF_PATTERN = %r{\A@\[(.+?)\](?:\.\s*)?(?:,\s*(\d+(?:/\d+)?(?:\.\d+)?))?\s*(?::\s*(.+))?\z}

  # Catches the old quantity-first syntax ("2 @[Pizza Dough]") to give a helpful error
  OLD_CROSS_REF_PATTERN = %r{\A\d+(?:/\d+)?(?:\.\d+)?x?\s*@\[}

  def self.parse(text)
    if text.match?(OLD_CROSS_REF_PATTERN)
      raise "Invalid cross-reference syntax: \"#{text}\". " \
            'Use @[Recipe Title], quantity (quantity after reference), not quantity before.'
    end

    if (match = text.match(CROSS_REF_PATTERN))
      title, multiplier_str, prep_note = match.captures
      multiplier = parse_multiplier(multiplier_str)
      return {
        cross_reference: true,
        target_title: title,
        multiplier: multiplier,
        prep_note: prep_note
      }
    end

    parts = text.split(':', 2)
    left_side = parts[0]
    prep_note = parts[1]&.strip
    prep_note = nil if prep_note&.empty?

    left_parts = left_side.split(',', 2)
    name = left_parts[0].strip
    quantity = left_parts[1]&.strip
    quantity = nil if quantity&.empty?

    {
      name: name,
      quantity: quantity,
      prep_note: prep_note
    }
  end

  def self.parse_multiplier(str)
    FamilyRecipes::NumericParsing.parse_fraction(str) || 1.0
  end

  private_class_method :parse_multiplier
end

# frozen_string_literal: true

# Parses a single ingredient bullet line into a structured hash with :name,
# :quantity, and :prep_note keys. Called by RecipeBuilder for each :ingredient
# token. Cross-references use CrossReferenceParser instead.
module IngredientParser
  def self.parse(text)
    raise "Cross-references now use >>> syntax. Write: >>> #{text}" if text.start_with?('@[')

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
end

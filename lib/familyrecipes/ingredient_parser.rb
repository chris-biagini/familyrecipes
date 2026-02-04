# IngredientParser module
#
# Parses ingredient line text into structured data.
# Handles the format: "Name, Quantity: Prep note"

module IngredientParser
  # Parse an ingredient line into a hash of attributes
  # Input: "Walnuts, 75 g: Roughly chop."
  # Output: { name: "Walnuts", quantity: "75 g", prep_note: "Roughly chop." }
  def self.parse(text)
    # Split on colon to separate name/quantity from prep note
    parts = text.split(':', 2)
    left_side = parts[0]
    prep_note = parts[1]&.strip
    prep_note = nil if prep_note&.empty?

    # Split left side on comma to separate name from quantity
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

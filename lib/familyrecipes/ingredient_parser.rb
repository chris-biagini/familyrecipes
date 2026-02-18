# IngredientParser module
#
# Parses ingredient line text into structured data.
# Handles the format: "Name, Quantity: Prep note"
# Also detects cross-references: "@[Recipe Title]" with optional multiplier

module IngredientParser
  # Pattern for cross-reference: optional multiplier, then @[Title], optional prep note
  # Multiplier can be: integer (2), decimal (0.5), fraction (1/2), with optional trailing x
  CROSS_REF_PATTERN = /\A(?:(\d+(?:\/\d+)?(?:\.\d+)?)x?\s+)?@\[(.+?)\](?:\.\s*)?(?::\s*(.+))?\z/

  # Parse an ingredient line into a hash of attributes
  # Input: "Walnuts, 75 g: Roughly chop."
  # Output: { name: "Walnuts", quantity: "75 g", prep_note: "Roughly chop." }
  #
  # For cross-references:
  # Input: "2 @[Pizza Dough]: Let rest."
  # Output: { cross_reference: true, target_title: "Pizza Dough", multiplier: 2.0, prep_note: "Let rest." }
  def self.parse(text)
    if (match = text.match(CROSS_REF_PATTERN))
      multiplier_str, title, prep_note = match.captures
      multiplier = parse_multiplier(multiplier_str)
      return {
        cross_reference: true,
        target_title: title,
        multiplier: multiplier,
        prep_note: prep_note
      }
    end

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

  def self.parse_multiplier(str)
    return 1.0 if str.nil?

    if str.include?('/')
      num, den = str.split('/')
      num.to_f / den.to_f
    else
      str.to_f
    end
  end

  private_class_method :parse_multiplier
end

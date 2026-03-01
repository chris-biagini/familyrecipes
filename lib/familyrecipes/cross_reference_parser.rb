# frozen_string_literal: true

# Parses "@[Recipe Title], multiplier: prep note" cross-reference syntax into a
# structured hash. Extracted from IngredientParser to isolate cross-reference
# concerns for the inline-rendering pipeline. Used by RecipeBuilder when
# processing :cross_reference_block tokens.
module CrossReferenceParser
  PATTERN = %r{\A@\[(.+?)\](?:\.\s*)?(?:,\s*(\d+(?:/\d+)?(?:\.\d+)?))?\s*(?::\s*(.+))?\z}
  OLD_SYNTAX = %r{\A\d+(?:/\d+)?(?:\.\d+)?x?\s*@\[}

  def self.parse(text)
    reject_old_syntax!(text)

    match = text.match(PATTERN)
    raise "Invalid cross-reference syntax: \"#{text}\". Expected @[Recipe Title]" unless match

    title, multiplier_str, prep_note = match.captures
    {
      target_title: title,
      multiplier: parse_multiplier(multiplier_str),
      prep_note: prep_note
    }
  end

  def self.reject_old_syntax!(text)
    return unless text.match?(OLD_SYNTAX)

    raise "Invalid cross-reference syntax: \"#{text}\". " \
          'Use @[Recipe Title], quantity (quantity after reference), not quantity before.'
  end

  def self.parse_multiplier(str)
    FamilyRecipes::NumericParsing.parse_fraction(str) || 1.0
  end

  private_class_method :reject_old_syntax!, :parse_multiplier
end

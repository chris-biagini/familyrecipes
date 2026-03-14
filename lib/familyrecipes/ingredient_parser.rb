# frozen_string_literal: true

# Parses a single ingredient bullet line into a structured hash with :name,
# :quantity, and :prep_note keys. Called by RecipeBuilder for each :ingredient
# token. Cross-references use CrossReferenceParser instead.
#
# Collaborators:
# - RecipeBuilder: calls parse for each :ingredient token during assembly
# - CrossReferenceParser: handles the complementary > @[Title] syntax
module IngredientParser
  def self.parse(text)
    reject_cross_reference_syntax!(text)

    parts = text.split(':', 2)
    left_side = parts[0]
    prep_note = parts[1]&.strip.presence

    left_parts = left_side.split(',', 2)
    name = left_parts[0].strip
    quantity = left_parts[1]&.strip.presence

    { name:, quantity:, prep_note: }
  end

  def self.reject_cross_reference_syntax!(text)
    return unless text.start_with?('@[')

    raise FamilyRecipes::ParseError,
          "Cross-references now use > @[...] syntax. Write: > #{text}"
  end

  private_class_method :reject_cross_reference_syntax!
end

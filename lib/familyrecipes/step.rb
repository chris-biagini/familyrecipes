# Step class
#
# Handles parsing and providing information about top-level Steps in a Recipe

class Step
  attr_reader :tldr, :ingredients, :cross_references, :instructions, :ingredient_list_items

  def initialize(tldr:, ingredient_list_items: [], instructions:)
    raise ArgumentError, "Step must have a tldr." if tldr.nil? || tldr.strip.empty?

    raise ArgumentError, "Step must have either ingredients or instructions." if ingredient_list_items.empty? && (instructions.nil? || instructions.strip.empty?)

    @tldr = tldr
    @ingredient_list_items = ingredient_list_items
    @ingredients = ingredient_list_items.grep(Ingredient)
    @cross_references = ingredient_list_items.grep(CrossReference)
    @instructions = instructions
  end
end

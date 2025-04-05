# Step class
#
# Handles parsing and providing information about top-level Steps in a Recipe

class Step
  attr_accessor :tldr, :ingredients, :instructions

  def initialize(tldr:, ingredients: [], instructions:)
    if tldr.nil? || tldr.strip.empty?
      raise ArgumentError, "Step must have a tldr."
    end
    
    if ingredients.empty? && (instructions.nil? || instructions.strip.empty?)
      raise ArgumentError, "Step must have either ingredients or instructions."
    end

    @tldr = tldr
    @ingredients = ingredients
    @instructions = instructions
  end
end

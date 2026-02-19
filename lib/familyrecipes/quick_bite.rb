class QuickBite
  attr_reader :text_source, :category, :title, :id, :ingredients

  def initialize(text_source:, category:)
    @text_source = text_source
    @category = category

    title, rest = text_source.split(":", 2).map(&:strip)
    rest ||= ""
    
    @title = title
    @id = FamilyRecipes.slugify(title)
    
    # If no colon, the title itself is the ingredient (simple items like "Ice cream")
    # If colon present, parse the comma-separated list after it
    ingredients_source = rest.empty? ? title : rest

    @ingredients = ingredients_source
      .split(',')
      .map(&:strip)
      .reject(&:empty?)
  end

  def all_ingredient_names
    @ingredients.uniq
  end

  def ingredients_with_quantities
    all_ingredient_names.map { |name| [name, [nil]] }
  end
end
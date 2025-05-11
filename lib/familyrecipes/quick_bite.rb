class QuickBite
  attr_reader :text_source, :category, :title, :id, :ingredients 

  def initialize(text_source:, category:)
    @text_source = text_source
    @category = category

    if text_source.include?(":")
      title, rest = text_source.split(":", 2).map(&:strip)
    else
      title = text_source.strip
      rest = ""
    end
    
    @title = title
    @id = title.unicode_normalize(:nfkd).downcase.gsub(/\s+/, '-').gsub(/[^a-z0-9\-]/, '') # same as Recipes in generate.rb
    
    # Start with full line for ingredients if no colon, otherwise the right part
    ingredients_source = rest.empty? ? title : rest
    
    # Split ingredients by delimiters: on, with, and, commas, etc.
    @ingredients = ingredients_source
      .split(/\bon\b|\bwith\b|\band\b|,/i)
      .map(&:strip)
      .reject(&:empty?)
  end

  def all_ingredient_names
    @ingredients.uniq
  end
end
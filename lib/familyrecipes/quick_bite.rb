# frozen_string_literal: true

module FamilyRecipes
  # A "grocery bundle" — a simple name + ingredient list that isn't a full recipe.
  # Parsed from the Quick Bites Markdown format ("- Name: Ing1, Ing2"). Lives on
  # the menu page, not the homepage. Responds to the same #ingredients_with_quantities
  # duck type as Recipe so ShoppingListBuilder can treat both uniformly.
  class QuickBite
    attr_reader :text_source, :category, :title, :id, :ingredients

    def initialize(text_source:, category:)
      @text_source = text_source
      @category = category

      title, rest = text_source.split(':', 2).map(&:strip)
      rest ||= ''

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
end

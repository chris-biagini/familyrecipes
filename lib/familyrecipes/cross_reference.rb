# frozen_string_literal: true

# CrossReference class
#
# Represents a reference from one recipe to another (e.g., "- @[Pizza Dough]").
# Behaves alongside Ingredient in step ingredient lists but renders as a link.

class CrossReference
  attr_reader :target_title, :target_slug, :multiplier, :prep_note

  def initialize(target_title:, multiplier: 1.0, prep_note: nil)
    @target_title = target_title
    @target_slug = FamilyRecipes.slugify(target_title)
    @multiplier = multiplier
    @prep_note = prep_note
  end

  # Return the scaled ingredients from the target recipe.
  # recipe_map: slug -> Recipe
  # alias_map: alias -> canonical name
  def expanded_ingredients(recipe_map, alias_map = {})
    recipe = recipe_map[@target_slug]
    return [] unless recipe

    recipe.own_ingredients_with_quantities(alias_map).map do |name, amounts|
      scaled = amounts.map do |amount|
        next nil if amount.nil?

        value, unit = amount
        [value * @multiplier, unit]
      end
      [name, scaled]
    end
  end
end

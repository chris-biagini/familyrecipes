# frozen_string_literal: true

module FamilyRecipes
  class CrossReference
    attr_reader :target_title, :target_slug, :multiplier, :prep_note

    def initialize(target_title:, multiplier: 1.0, prep_note: nil)
      @target_title = target_title
      @target_slug = FamilyRecipes.slugify(target_title)
      @multiplier = multiplier
      @prep_note = prep_note
    end

    def expanded_ingredients(recipe_map)
      recipe = recipe_map[@target_slug]
      return [] unless recipe

      recipe.own_ingredients_with_quantities.map do |name, amounts|
        scaled = amounts.map do |amount|
          next nil if amount.nil?

          Quantity[amount.value * @multiplier, amount.unit]
        end
        [name, scaled]
      end
    end
  end
end

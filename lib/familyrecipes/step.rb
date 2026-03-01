# frozen_string_literal: true

module FamilyRecipes
  # One step within a parsed recipe. Holds a tldr (summary heading), a mixed list
  # of Ingredient and CrossReference items, and prose instructions. Steps are
  # constructed by Recipe during parsing and consumed by MarkdownImporter.
  # A step must have either ingredients or instructions (or both); tldr is nil
  # for implicit steps (recipes without ## headers).
  class Step
    attr_reader :tldr, :ingredients, :cross_references, :instructions, :ingredient_list_items

    def initialize(tldr:, instructions:, ingredient_list_items: [])
      raise ArgumentError, 'Step must have a tldr.' if !tldr.nil? && tldr.strip.empty?

      if ingredient_list_items.empty? && (instructions.nil? || instructions.strip.empty?)
        raise ArgumentError,
              'Step must have either ingredients or instructions.'
      end

      @tldr = tldr
      @ingredient_list_items = ingredient_list_items
      @ingredients = ingredient_list_items.grep(Ingredient)
      @cross_references = ingredient_list_items.grep(CrossReference)
      @instructions = instructions
    end
  end
end

# frozen_string_literal: true

module FamilyRecipes
  # One step within a parsed recipe. Holds a tldr (summary heading), a mixed list
  # of Ingredient and CrossReference items, and prose instructions. Steps are
  # constructed by Recipe during parsing and consumed by MarkdownImporter.
  # A step must have ingredients, instructions, or a cross_reference; tldr is nil
  # for implicit steps (recipes without ## headers).
  class Step
    attr_reader :tldr, :ingredients, :cross_references, :instructions, :ingredient_list_items, :cross_reference

    def initialize(tldr:, instructions:, ingredient_list_items: [], cross_reference: nil)
      raise ArgumentError, 'Step must have a tldr.' if !tldr.nil? && tldr.strip.empty?

      validate_has_content(ingredient_list_items, instructions, cross_reference)

      @tldr = tldr
      @ingredient_list_items = ingredient_list_items
      @ingredients = ingredient_list_items.grep(Ingredient)
      @cross_references = build_cross_references(ingredient_list_items, cross_reference)
      @cross_reference = cross_reference
      @instructions = instructions
    end

    private

    def validate_has_content(items, instructions, xref)
      return if items.any? || xref
      return unless instructions.nil? || instructions.strip.empty?

      raise ArgumentError, 'Step must have either ingredients, instructions, or a cross-reference.'
    end

    # Step-level cross_reference (from >>>) merges with any inline cross-references
    # from ingredient_list_items for a unified collection.
    def build_cross_references(items, xref)
      refs = items.grep(CrossReference)
      xref ? refs + [xref] : refs
    end
  end
end

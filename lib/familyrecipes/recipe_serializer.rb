# frozen_string_literal: true

module FamilyRecipes
  # Pure-function serializer that converts a RecipeBuilder IR hash back into
  # canonical Markdown. The inverse of the parser pipeline (LineClassifier ->
  # RecipeBuilder). Single source of truth for the recipe markdown format when
  # generating text from structured data.
  #
  # Collaborators:
  # - RecipeBuilder: produces the IR hash this module consumes
  # - MarkdownImporter: may use serialized output for structured imports
  # - RecipesController: populates plaintext textarea during mode switching
  module RecipeSerializer
    FRONT_MATTER_KEYS = %i[makes serves category tags].freeze

    module_function

    def serialize(recipe)
      lines = ["# #{recipe[:title]}"]
      append_description(lines, recipe[:description])
      append_front_matter(lines, recipe[:front_matter])
      recipe[:steps].each { |step| append_step(lines, step) }
      append_footer(lines, recipe[:footer])
      "#{lines.join("\n").rstrip}\n"
    end

    def append_description(lines, description)
      return if description.nil? || description.strip.empty?

      lines << '' << description
    end

    def append_front_matter(lines, front_matter)
      return if front_matter.nil? || front_matter.empty? # rubocop:disable Rails/Blank

      rendered = FRONT_MATTER_KEYS.filter_map { |key| format_front_matter_field(key, front_matter[key]) }
      return if rendered.empty?

      lines << ''
      lines.concat(rendered)
    end

    def format_front_matter_field(key, value)
      return nil if value.nil?
      return nil if value.respond_to?(:empty?) && value.empty?

      formatted_value = key == :tags ? value.join(', ') : value
      "#{key.to_s.capitalize}: #{formatted_value}"
    end

    def append_step(lines, step)
      lines << ''
      lines << "## #{step[:tldr]}" if step[:tldr]

      if step[:cross_reference]
        append_cross_reference(lines, step[:cross_reference])
      else
        append_ingredients(lines, step[:ingredients])
        append_instructions(lines, step[:instructions])
      end
    end

    def append_cross_reference(lines, xref)
      lines << '' << format_cross_reference(xref)
    end

    def format_cross_reference(xref)
      parts = "> @[#{xref[:target_title]}]"
      parts += ", #{format_multiplier(xref[:multiplier])}" unless default_multiplier?(xref[:multiplier])
      parts += ": #{xref[:prep_note]}" if xref[:prep_note] && !xref[:prep_note].strip.empty?
      parts
    end

    def default_multiplier?(multiplier)
      multiplier.nil? || (multiplier - 1.0).abs < 0.0001
    end

    def format_multiplier(value)
      value == value.to_i ? value.to_i.to_s : value.to_s
    end

    def append_ingredients(lines, ingredients)
      return if ingredients.nil? || ingredients.empty? # rubocop:disable Rails/Blank

      lines << ''
      lines.concat(ingredients.map { |ing| format_ingredient(ing) })
    end

    def format_ingredient(ing)
      result = "- #{ing[:name]}"
      result += ", #{ing[:quantity]}" if ing[:quantity] && !ing[:quantity].strip.empty?
      result += ": #{ing[:prep_note]}" if ing[:prep_note] && !ing[:prep_note].strip.empty?
      result
    end

    def append_instructions(lines, instructions)
      return if instructions.nil? || instructions.strip.empty?

      lines << '' << instructions
    end

    def append_footer(lines, footer)
      return if footer.nil? || footer.strip.empty?

      lines << '' << '---' << '' << footer
    end

    private_class_method :append_description, :append_front_matter, :format_front_matter_field,
                         :append_step, :append_cross_reference, :format_cross_reference,
                         :default_multiplier?, :format_multiplier, :append_ingredients,
                         :format_ingredient, :append_instructions, :append_footer
  end
end

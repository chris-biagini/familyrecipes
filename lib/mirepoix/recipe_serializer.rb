# frozen_string_literal: true

module Mirepoix
  # Pure-function serializer that converts a RecipeBuilder IR hash back into
  # canonical Markdown. The inverse of the parser pipeline (LineClassifier ->
  # RecipeBuilder). Single source of truth for the recipe markdown format when
  # generating text from structured data.
  #
  # Two entry points: `serialize` takes a plain hash (the RecipeBuilder IR),
  # while `from_record` bridges ActiveRecord Recipe objects to the same IR
  # format. The content endpoint uses both: from_record -> serialize to produce
  # enriched markdown with front matter that may not exist in the stored source.
  #
  # Collaborators:
  # - RecipeBuilder: produces the IR hash this module consumes
  # - MarkdownImporter: may use serialized output for structured imports
  # - RecipesController: populates plaintext textarea during mode switching
  module RecipeSerializer # rubocop:disable Metrics/ModuleLength
    FRONT_MATTER_KEYS = %i[makes serves category tags].freeze

    module_function

    def from_record(recipe)
      {
        title: recipe.title,
        description: recipe.description,
        front_matter: build_front_matter(recipe),
        steps: recipe.steps.map { |step| build_step_ir(step) },
        footer: recipe.footer
      }
    end

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
      multiplier.nil? || (multiplier.to_f - 1.0).abs < 0.0001
    end

    def format_multiplier(value)
      float_val = value.to_f
      float_val == float_val.to_i ? float_val.to_i.to_s : float_val.to_s
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

    def build_front_matter(recipe)
      fm = {}
      makes = [format_decimal(recipe.makes_quantity), recipe.makes_unit_noun].compact.join(' ')
      fm[:makes] = makes unless makes.empty?
      fm[:serves] = recipe.serves.to_s if recipe.serves
      fm[:category] = recipe.category.name if recipe.category
      tags = recipe.tags.map(&:name)
      fm[:tags] = tags if tags.any?
      fm
    end

    # Strip trailing ".0" from decimals so "2.0" renders as "2"
    def format_decimal(value)
      return unless value

      value == value.to_i ? value.to_i.to_s : value.to_s
    end

    def build_step_ir(step)
      return build_cross_reference_step(step) if step.cross_references.any?

      { tldr: step.title,
        ingredients: step.ingredients.map { |ing| build_ingredient_ir(ing) },
        instructions: step.instructions, cross_reference: nil }
    end

    def build_cross_reference_step(step)
      xref = step.cross_references.first
      { tldr: step.title, ingredients: [], instructions: nil,
        cross_reference: { target_title: xref.target_title,
                           multiplier: xref.multiplier, prep_note: xref.prep_note } }
    end

    def build_ingredient_ir(ing)
      { name: ing.name, quantity: serialize_ingredient_quantity(ing), prep_note: ing.prep_note }
    end

    def serialize_ingredient_quantity(ing)
      return [ing.quantity, ing.unit].compact.join(' ').presence unless ing.quantity_low

      parts = format_numeric_quantity(ing.quantity_low, ing.quantity_high)
      [parts, ing.unit].compact.join(' ')
    end

    def format_numeric_quantity(low, high)
      low_str = VulgarFractions.to_fraction_string(low.to_f)
      return low_str unless high

      "#{low_str}-#{VulgarFractions.to_fraction_string(high.to_f)}"
    end

    private_class_method :append_description, :append_front_matter, :format_front_matter_field,
                         :append_step, :append_cross_reference, :format_cross_reference,
                         :default_multiplier?, :format_multiplier, :append_ingredients,
                         :format_ingredient, :append_instructions, :append_footer,
                         :build_front_matter, :build_step_ir, :build_cross_reference_step,
                         :build_ingredient_ir, :serialize_ingredient_quantity,
                         :format_numeric_quantity, :format_decimal
  end
end

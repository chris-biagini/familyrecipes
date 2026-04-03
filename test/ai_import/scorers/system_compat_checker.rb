# frozen_string_literal: true

# Layer 1 gate check: system compatibility. Verifies the AI-generated recipe
# can survive a round-trip through the parser pipeline and that numeric
# quantities scale without errors.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline
# - FamilyRecipes::Ingredient — quantity splitting
# - FamilyRecipes::NumericParsing — fraction parsing
# - Scorers::ParseChecker — companion gate check (structural validity)
module Scorers
  class SystemCompatChecker
    Result = Data.define(:pass, :details)

    def self.check(output_text)
      errors = []

      begin
        tokens = LineClassifier.classify(output_text)
        parsed = RecipeBuilder.new(tokens).build
      rescue FamilyRecipes::ParseError => e
        return Result.new(pass: false, details: { errors: ["Parse error: #{e.message}"] })
      end

      errors.concat(check_round_trip(parsed))
      errors.concat(check_scaling(parsed))

      Result.new(pass: errors.empty?, details: { errors: errors })
    end

    def self.check_round_trip(parsed)
      reconstructed = reconstruct_markdown(parsed)

      begin
        tokens2 = LineClassifier.classify(reconstructed)
        parsed2 = RecipeBuilder.new(tokens2).build
      rescue FamilyRecipes::ParseError => e
        return ["Round-trip re-parse failed: #{e.message}"]
      end

      errors = []
      errors << "Round-trip title mismatch" if parsed[:title] != parsed2[:title]

      orig_count = ingredient_count(parsed)
      rt_count = ingredient_count(parsed2)
      errors << "Round-trip ingredient count: #{orig_count} vs #{rt_count}" if orig_count != rt_count

      orig_steps = parsed[:steps].size
      rt_steps = parsed2[:steps].size
      errors << "Round-trip step count: #{orig_steps} vs #{rt_steps}" if orig_steps != rt_steps

      errors
    end

    def self.check_scaling(parsed)
      parsed[:steps].flat_map { |step|
        (step[:ingredients] || []).filter_map { |ing| scaling_error(ing) }
      }
    end

    def self.scaling_error(ingredient)
      return nil unless ingredient[:quantity]

      qty_str, _unit = FamilyRecipes::Ingredient.split_quantity(ingredient[:quantity])
      return nil unless qty_str

      value = FamilyRecipes::NumericParsing.parse_fraction(qty_str)
      return nil unless value

      scaled = value * 2
      return "Scaling failed for #{ingredient[:name]} (#{ingredient[:quantity]})" if scaled.nan? || scaled.infinite?

      nil
    rescue ArgumentError
      nil
    end

    def self.ingredient_count(parsed)
      parsed[:steps].sum { |s| (s[:ingredients] || []).size }
    end

    def self.reconstruct_markdown(parsed)
      lines = ["# #{parsed[:title]}"]
      append_description(lines, parsed[:description])
      append_front_matter(lines, parsed[:front_matter])
      parsed[:steps].each { |step| append_step(lines, step) }
      append_footer(lines, parsed[:footer])
      lines.join("\n") + "\n"
    end

    def self.append_description(lines, desc)
      return unless desc && !desc.strip.empty?

      lines << '' << desc.strip
    end

    def self.append_front_matter(lines, fm)
      return unless fm&.any? { |_k, v| v && (v.respond_to?(:empty?) ? !v.empty? : true) }

      lines << ''
      lines << "Makes: #{fm[:makes]}" if fm[:makes]
      lines << "Serves: #{fm[:serves]}" if fm[:serves]
      lines << "Category: #{fm[:category]}" if fm[:category]
      lines << "Tags: #{fm[:tags].join(', ')}" if fm[:tags]&.size&.positive?
    end

    def self.append_step(lines, step)
      lines << ''
      lines << "## #{step[:tldr]}" if step[:tldr]
      (step[:ingredients] || []).each { |ing| lines << ingredient_line(ing) }
      return unless step[:instructions] && !step[:instructions].strip.empty?

      lines << '' << step[:instructions].strip
    end

    def self.ingredient_line(ing)
      line = "- #{ing[:name]}"
      line += ", #{ing[:quantity]}" if ing[:quantity]
      line += ": #{ing[:prep_note]}" if ing[:prep_note]
      line
    end

    def self.append_footer(lines, footer)
      return unless footer && !footer.strip.empty?

      lines << '' << '---' << '' << footer.strip
    end

    private_class_method :check_round_trip, :check_scaling, :scaling_error,
                         :ingredient_count, :reconstruct_markdown,
                         :append_description, :append_front_matter,
                         :append_step, :ingredient_line, :append_footer
  end
end

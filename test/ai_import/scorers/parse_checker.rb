# frozen_string_literal: true

# Layer 1 scorer: feeds Haiku output through LineClassifier → RecipeBuilder
# and checks for basic structural validity. Returns pass/fail plus details.
#
# Usage:
#   result = Scorers::ParseChecker.check(output_text, expected_ingredient_count: 6)
#   result.pass        # => true/false
#   result.details     # => { title: "...", steps: 3, ingredients: 6, errors: [] }
module Scorers
  class ParseChecker
    Result = Data.define(:pass, :details)

    def self.check(output_text, expected_ingredient_count:)
      errors = []

      begin
        tokens = LineClassifier.classify(output_text)
        parsed = RecipeBuilder.new(tokens).build
      rescue FamilyRecipes::ParseError => e
        return Result.new(pass: false, details: {
          title: nil, steps: 0, ingredients: 0,
          errors: ["Parse error: #{e.message}"]
        })
      end

      title = parsed[:title]
      errors << 'Missing title' if title.nil? || title.strip.empty?

      steps = parsed[:steps] || []
      ingredient_count = steps.sum { |s| (s[:ingredients] || []).size }

      # Allow 50% tolerance — ingredient counts vary depending on how compound
      # lines are decomposed and whether optional/garnish items are listed as
      # ingredients or noted in the footer
      min_count = (expected_ingredient_count * 0.5).ceil
      if ingredient_count < min_count
        errors << "Only #{ingredient_count} ingredients (expected >= #{min_count}, gold standard has #{expected_ingredient_count})"
      end

      Result.new(
        pass: errors.empty?,
        details: {
          title: title,
          steps: steps.size,
          ingredients: ingredient_count,
          errors: errors
        }
      )
    end
  end
end

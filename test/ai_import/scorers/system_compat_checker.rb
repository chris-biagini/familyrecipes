# frozen_string_literal: true

# Layer 1 gate check: system compatibility. Verifies the AI-generated recipe
# can survive a round-trip through the parser pipeline and that numeric
# quantities scale without errors.
#
# Collaborators:
# - LineClassifier, RecipeBuilder — parse pipeline
# - FamilyRecipes::RecipeSerializer — canonical serializer for round-trip
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
      rescue FamilyRecipes::ParseError => error
        return Result.new(pass: false, details: { errors: ["Parse error: #{error.message}"] })
      end

      errors.concat(check_round_trip(parsed))
      errors.concat(check_scaling(parsed))

      Result.new(pass: errors.empty?, details: { errors: errors })
    end

    def self.check_round_trip(parsed)
      reconstructed = FamilyRecipes::RecipeSerializer.serialize(parsed)

      begin
        tokens2 = LineClassifier.classify(reconstructed)
        parsed2 = RecipeBuilder.new(tokens2).build
      rescue FamilyRecipes::ParseError => error
        return ["Round-trip re-parse failed: #{error.message}"]
      end

      errors = []
      errors << 'Round-trip title mismatch' if parsed[:title] != parsed2[:title]

      orig_count = ingredient_count(parsed)
      rt_count = ingredient_count(parsed2)
      errors << "Round-trip ingredient count: #{orig_count} vs #{rt_count}" if orig_count != rt_count

      if parsed[:steps].size != parsed2[:steps].size
        errors << "Round-trip step count: #{parsed[:steps].size} vs #{parsed2[:steps].size}"
      end

      errors
    end

    def self.check_scaling(parsed)
      parsed[:steps].flat_map do |step|
        (step[:ingredients] || []).filter_map { |ing| scaling_error(ing) }
      end
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

    private_class_method :check_round_trip, :check_scaling, :scaling_error,
                         :ingredient_count
  end
end

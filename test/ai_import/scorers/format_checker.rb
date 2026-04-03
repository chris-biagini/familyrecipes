# frozen_string_literal: true

# Layer 2 scorer: algorithmic checks for formatting rule compliance.
# Each check is pass/fail. Returns percentage of checks passed plus
# per-check details.
#
# Usage:
#   result = Scorers::FormatChecker.check(output_text, valid_categories: [...])
#   result.score        # => 0.89 (89% of checks passed)
#   result.checks       # => [{ name: "ascii_fractions", pass: true }, ...]
module Scorers
  class FormatChecker
    VULGAR_FRACTIONS = /[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]/
    EN_DASH = /–/
    CODE_FENCE = /^```/
    DETRITUS_PATTERNS = [
      /\bPrint\b/i, /\bPin It\b/i, /\bJump to Recipe\b/i,
      /\bDid you make this\b/i, /★|☆/, /\b\d+\s*reviews?\b/i,
      /\bSubscribe\b/i, /\bNewsletter\b/i, /\bTag me\b/i,
      /\bInstagram\b/i, /\bFollow\b/i, /\b\d+x\s*\d+x\b/,
      /Calories:\s*\d+/i, /\bNutrition\s*(Facts|Info)/i,
      /\bWatch the Video\b/i
    ].freeze

    Result = Data.define(:score, :checks)

    # RecipeBuilder#build returns:
    #   { title:, description:, front_matter: { category:, serves:, ... }, steps:, footer: }
    # Steps: { tldr: "Step name.", ingredients: [...], instructions: "..." }
    # Ingredients: { name:, quantity:, prep_note: }
    def self.check(output_text, valid_categories:)
      tokens = LineClassifier.classify(output_text)
      parsed = safe_parse(tokens)
      return Result.new(score: 0.0, checks: [{ name: 'parse', pass: false }]) unless parsed

      checks = []

      checks << ascii_fractions(output_text)
      checks << prep_notes_formatted(parsed)
      checks << valid_front_matter(parsed, valid_categories)
      checks << no_detritus(output_text, parsed)
      checks << single_divider(tokens)
      checks << step_headers_format(parsed)
      checks << no_code_fences(output_text)
      checks << ingredient_names_concise(parsed)
      checks << no_en_dashes(output_text)

      passed = checks.count { |c| c[:pass] }
      Result.new(score: passed.to_f / checks.size, checks: checks)
    end

    def self.ascii_fractions(text)
      { name: 'ascii_fractions', pass: !text.match?(VULGAR_FRACTIONS) }
    end

    def self.prep_notes_formatted(parsed)
      preps = parsed[:steps].flat_map { |s| s[:ingredients] }
                            .filter_map { |i| i[:prep_note] }
      bad = preps.reject { |p| p.match?(/\A[A-Z]/) && p.end_with?('.') }
      { name: 'prep_notes_formatted', pass: bad.empty?, failures: bad }
    end

    def self.valid_front_matter(parsed, valid_categories)
      fm = parsed[:front_matter] || {}
      cat = fm[:category]
      serves = fm[:serves]
      errors = []
      errors << "Unknown category: #{cat}" if cat && valid_categories.exclude?(cat)
      errors << "Serves is not a number: #{serves}" if serves && !serves.to_s.match?(/\A\d+\z/)
      { name: 'valid_front_matter', pass: errors.empty?, failures: errors }
    end

    def self.no_detritus(text, parsed)
      parsed[:footer] || ''
      non_footer = text.sub(/^---\s*\n.*\z/m, '')
      hits = DETRITUS_PATTERNS.grep(non_footer)
      { name: 'no_detritus', pass: hits.empty?, failures: hits.map(&:source) }
    end

    def self.single_divider(tokens)
      count = tokens.count { |t| t.type == :divider }
      { name: 'single_divider', pass: count <= 1 }
    end

    def self.step_headers_format(parsed)
      headers = parsed[:steps].filter_map { |s| s[:tldr] }
      bad = headers.reject { |h| h.match?(/\A[A-Z]/) && h.strip.end_with?('.') }
      { name: 'step_headers_format', pass: bad.empty?, failures: bad }
    end

    def self.no_code_fences(text)
      { name: 'no_code_fences', pass: !text.match?(CODE_FENCE) }
    end

    def self.ingredient_names_concise(parsed)
      names = parsed[:steps].flat_map { |s| s[:ingredients] }.pluck(:name)
      long = names.select { |n| n && n.size > 40 }
      { name: 'ingredient_names_concise', pass: long.empty?, failures: long }
    end

    def self.no_en_dashes(text)
      { name: 'no_en_dashes', pass: !text.match?(EN_DASH) }
    end

    def self.safe_parse(tokens)
      RecipeBuilder.new(tokens).build
    rescue FamilyRecipes::ParseError
      nil
    end

    private_class_method :safe_parse, :ascii_fractions, :prep_notes_formatted,
                         :valid_front_matter, :no_detritus, :single_divider,
                         :step_headers_format, :no_code_fences,
                         :ingredient_names_concise, :no_en_dashes
  end
end

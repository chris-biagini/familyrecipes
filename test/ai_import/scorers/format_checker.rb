# frozen_string_literal: true

# Layer 2 scorer: algorithmic checks for formatting rule compliance.
# Each check is pass/fail. Returns percentage of checks passed plus
# per-check details.
#
# Usage:
#   result = Scorers::FormatChecker.check(output_text, valid_categories: [...], input_text: "...")
#   result.score        # => 0.89 (89% of checks passed)
#   result.checks       # => [{ name: "ascii_fractions", pass: true }, ...]
module Scorers
  class FormatChecker
    VULGAR_FRACTIONS = /[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]/
    EN_DASH = /–/
    CODE_FENCE = /^```/
    DETRITUS_PATTERNS = [
      /\bPin It\b/i, /\bJump to Recipe\b/i,
      /\bDid you make this\b/i, /★|☆/, /\b\d+\s*reviews?\b/i,
      /\bSubscribe\b/i, /\bNewsletter\b/i, /\bTag me\b/i,
      /\bInstagram\b/i, /\bFollow\b/i, /\b\d+x\s*\d+x\b/,
      /Calories:\s*\d+/i, /\bNutrition\s*(Facts|Info)/i,
      /\bWatch the Video\b/i
    ].freeze

    INFORMAL_QUANTITY_PATTERNS = [
      /\bgenerous\b/i, /\bhandful\b/i, /\ba\s+big\s+pinch\b/i,
      /\bor\s+so\b/i, /\bgive\s+or\s+take\b/i, /\bheaping\b/i,
      /\bscant\b/i, /\bsplash\b/i, /\bdrizzle\b/i, /\bglug\b/i
    ].freeze

    COMMENT_BLEED_PATTERNS = [
      /\b\w+\s+says:/i, /\bReply\b/, /\bI made this\b/i,
      /\bloved it\b/i, /\b\d+\s*comments?\b/i, /\bLeave a comment\b/i
    ].freeze

    Result = Data.define(:score, :checks)

    def self.check(output_text, valid_categories:, valid_tags: nil, input_text: nil, metadata: nil)
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
      checks << no_comment_bleed(output_text, parsed)
      checks << informal_quantities_preserved(input_text, output_text) if input_text
      checks << step_splitting_appropriate(parsed, metadata) if metadata
      checks << tags_from_valid_list(parsed, valid_tags) if valid_tags

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
      makes = fm[:makes]
      errors = []
      errors << "Unknown category: #{cat}" if cat && !valid_categories.include?(cat) # rubocop:disable Rails/NegateInclude -- no Rails
      errors << "Serves is not a number: #{serves}" if serves && !serves.to_s.match?(/\A\d+\z/)
      errors << "Makes does not start with a number: #{makes}" if makes && !makes.to_s.match?(/\A\d/)
      { name: 'valid_front_matter', pass: errors.empty?, failures: errors }
    end

    def self.no_detritus(text, parsed)
      parsed[:footer] || ''
      non_footer = text.sub(/^---\s*\n.*\z/m, '')
      hits = DETRITUS_PATTERNS.select { |p| non_footer.match?(p) } # rubocop:disable Style/SelectByRegexp -- reversed: array of regexps tested against string
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
      names = parsed[:steps].flat_map { |s| s[:ingredients] }.map { |i| i[:name] } # rubocop:disable Rails/Pluck -- no Rails
      long = names.select { |n| n && n.size > 40 }
      { name: 'ingredient_names_concise', pass: long.empty?, failures: long }
    end

    def self.no_en_dashes(text)
      { name: 'no_en_dashes', pass: !text.match?(EN_DASH) }
    end

    def self.tags_from_valid_list(parsed, valid_tags)
      fm = parsed[:front_matter] || {}
      tags = fm[:tags]
      return { name: 'tags_from_valid_list', pass: true } if tags.nil? || tags.empty? # rubocop:disable Rails/Blank -- no Rails

      invalid = tags.reject { |t| valid_tags.include?(t) }
      { name: 'tags_from_valid_list', pass: invalid.empty?, failures: invalid }
    end

    def self.no_comment_bleed(text, _parsed)
      non_footer = text.sub(/^---\s*\n.*\z/m, '')
      hits = COMMENT_BLEED_PATTERNS.select { |p| non_footer.match?(p) } # rubocop:disable Style/SelectByRegexp
      { name: 'no_comment_bleed', pass: hits.empty?, failures: hits.map(&:source) }
    end

    def self.informal_quantities_preserved(input_text, output_text)
      input_informals = INFORMAL_QUANTITY_PATTERNS.select { |p| input_text.match?(p) } # rubocop:disable Style/SelectByRegexp
      return { name: 'informal_quantities_preserved', pass: true } if input_informals.empty?

      missing = input_informals.reject { |p| output_text.match?(p) } # rubocop:disable Style/SelectByRegexp
      { name: 'informal_quantities_preserved', pass: missing.empty?, failures: missing.map(&:source) }
    end

    def self.step_splitting_appropriate(parsed, metadata)
      expected = metadata['expected_steps']
      return { name: 'step_splitting_appropriate', pass: true } unless expected
      return { name: 'step_splitting_appropriate', pass: true } if expected == 'ambiguous'

      steps = parsed[:steps] || []
      has_headers = steps.any? { |s| s[:tldr] }

      case expected
      when 'implicit'
        pass = steps.size == 1 && !has_headers
        { name: 'step_splitting_appropriate', pass: pass,
          failures: pass ? nil : ["Expected implicit (1 step, no headers) but got #{steps.size} steps"] }
      when 'explicit'
        pass = steps.size >= 2 && steps.all? { |s| s[:tldr] }
        { name: 'step_splitting_appropriate', pass: pass,
          failures: if pass
                      nil
                    else
                      ['Expected explicit (2+ named steps) but got ' \
                       "#{steps.size} steps, headers=#{has_headers}"]
                    end }
      else
        { name: 'step_splitting_appropriate', pass: true }
      end
    end

    def self.safe_parse(tokens)
      RecipeBuilder.new(tokens).build
    rescue FamilyRecipes::ParseError
      nil
    end

    private_class_method :safe_parse, :ascii_fractions, :prep_notes_formatted,
                         :valid_front_matter, :no_detritus, :single_divider,
                         :step_headers_format, :no_code_fences,
                         :ingredient_names_concise, :no_en_dashes,
                         :tags_from_valid_list, :no_comment_bleed,
                         :informal_quantities_preserved,
                         :step_splitting_appropriate
  end
end

# frozen_string_literal: true

module Mirepoix
  # Safe numeric string parser that handles integers, decimals, and fractions
  # (e.g., "3/4"). Used throughout the parser pipeline wherever user-authored
  # quantity strings need to become floats — IngredientParser and
  # ScalableNumberPreprocessor.
  module NumericParsing
    VULGAR_GLYPHS = {
      '½' => 1 / 2r, '⅓' => 1 / 3r, '⅔' => 2 / 3r,
      '¼' => 1 / 4r, '¾' => 3 / 4r,
      '⅛' => 1 / 8r, '⅜' => 3 / 8r, '⅝' => 5 / 8r, '⅞' => 7 / 8r
    }.freeze

    VULGAR_PATTERN = /[#{VULGAR_GLYPHS.keys.join}]/
    MIXED_VULGAR_PATTERN = /\A\s*(\d*)\s*(#{VULGAR_PATTERN})\s*\z/

    module_function

    def parse_fraction(str)
      return nil if str.nil?

      str = str.to_s.strip
      raise ArgumentError, "invalid numeric string: #{str.inspect}" if str.empty?

      parse_vulgar(str) || parse_ascii_fraction(str)
    end

    MIXED_ASCII_PATTERN = %r{\A(\d+)\s+(\d+/\d+)\z}

    def parse_ascii_fraction(str)
      mixed = str.match(MIXED_ASCII_PATTERN)
      return mixed[1].to_f + parse_fraction_parts(mixed[2]) if mixed
      return parse_fraction_parts(str) if str.include?('/')

      result = Float(str, exception: false)
      raise ArgumentError, "invalid numeric string: #{str.inspect}" unless result

      result
    end

    def parse_vulgar(str)
      return nil unless str.match?(VULGAR_PATTERN)

      prefix, glyph = extract_vulgar_parts(str)
      validate_vulgar_prefix!(prefix, str)
      prefix + VULGAR_GLYPHS[glyph].to_f
    end

    def extract_vulgar_parts(str)
      match = str.match(MIXED_VULGAR_PATTERN)
      raise ArgumentError, "invalid numeric string: #{str.inspect}" unless match

      [match[1].empty? ? 0 : match[1].to_f, match[2]]
    end

    def validate_vulgar_prefix!(prefix, str)
      return if prefix.is_a?(Numeric)

      raise ArgumentError, "invalid numeric string: #{str.inspect}"
    end

    def parse_fraction_parts(str)
      num_str, den_str = str.split('/', 2)
      num = Float(num_str, exception: false)
      den = Float(den_str, exception: false)

      raise ArgumentError, "invalid numeric string: #{str.inspect}" unless num && den
      raise ArgumentError, "division by zero: #{str.inspect}" if den.zero?

      num / den
    end

    private_class_method :parse_vulgar, :extract_vulgar_parts, :validate_vulgar_prefix!,
                         :parse_ascii_fraction, :parse_fraction_parts
  end
end

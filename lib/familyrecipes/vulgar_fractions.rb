# frozen_string_literal: true

module FamilyRecipes
  module VulgarFractions
    GLYPHS = {
      1 / 2r => "\u00BD",
      1 / 3r => "\u2153",
      2 / 3r => "\u2154",
      1 / 4r => "\u00BC",
      3 / 4r => "\u00BE",
      1 / 8r => "\u215B",
      3 / 8r => "\u215C",
      5 / 8r => "\u215D",
      7 / 8r => "\u215E"
    }.freeze

    TOLERANCE = 0.001

    module_function

    def format(value)
      return value.to_i.to_s if integer?(value)

      integer_part = value.to_i
      glyph = find_glyph(fractional_part(value))

      return format_with_glyph(integer_part, glyph) if glyph

      format_decimal(value)
    end

    def singular_noun?(value)
      return true if (value - 1.0).abs < TOLERANCE

      value < 1.0 && value.positive? && !find_glyph(value).nil?
    end

    def find_glyph(fractional_value)
      _rational, glyph = GLYPHS.find { |rational, _| (fractional_value - rational.to_f).abs < TOLERANCE }
      glyph
    end

    def integer?(value)
      fractional_part(value).abs < TOLERANCE
    end

    def fractional_part(value)
      value - value.to_i
    end

    def format_with_glyph(integer_part, glyph)
      integer_part.zero? ? glyph : "#{integer_part}#{glyph}"
    end

    def format_decimal(value)
      rounded = (value * 100).round / 100.0
      rounded.to_s.sub(/\.?0+\z/, '')
    end

    private_class_method :find_glyph, :integer?, :fractional_part, :format_with_glyph, :format_decimal
  end
end

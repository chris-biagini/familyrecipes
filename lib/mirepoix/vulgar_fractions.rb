# frozen_string_literal: true

module Mirepoix
  # Formats decimal quantities as Unicode vulgar fraction glyphs (e.g., 0.5 → "½",
  # 1.25 → "1¼") or ASCII fraction strings (0.5 → "1/2", 1.25 → "1 1/4").
  # Unit-aware: metric units (g, kg, ml, l) bypass glyph conversion and keep plain
  # decimal form. `format` produces Unicode glyphs for display; `to_fraction_string`
  # produces ASCII for plaintext serialization (RecipeSerializer). Also provides
  # singular_noun? for deciding singular vs. plural unit display.
  #
  # - RecipesHelper (display formatting)
  # - RecipeSerializer (ASCII fraction output)
  # - recipe_state_controller.js (client-side scaling via JS mirror)
  module VulgarFractions
    GLYPHS = {
      1 / 2r => "\u00BD",
      1 / 3r => "\u2153",
      2 / 3r => "\u2154",
      1 / 4r => "\u00BC",
      3 / 4r => "\u00BE",
      1 / 5r => "\u2155",
      2 / 5r => "\u2156",
      3 / 5r => "\u2157",
      4 / 5r => "\u2158",
      1 / 6r => "\u2159",
      5 / 6r => "\u215A",
      1 / 8r => "\u215B",
      3 / 8r => "\u215C",
      5 / 8r => "\u215D",
      7 / 8r => "\u215E"
    }.freeze

    FRACTION_STRINGS = {
      1 / 2r => '1/2',
      1 / 3r => '1/3',
      2 / 3r => '2/3',
      1 / 4r => '1/4',
      3 / 4r => '3/4',
      1 / 5r => '1/5',
      2 / 5r => '2/5',
      3 / 5r => '3/5',
      4 / 5r => '4/5',
      1 / 6r => '1/6',
      5 / 6r => '5/6',
      1 / 8r => '1/8',
      3 / 8r => '3/8',
      5 / 8r => '5/8',
      7 / 8r => '7/8'
    }.freeze

    TOLERANCE = 0.001
    METRIC_UNITS = %w[g kg ml l].to_set.freeze

    module_function

    def format(value, unit: nil)
      return format_decimal(value) if metric_unit?(unit)
      return value.to_i.to_s if integer?(value)

      integer_part = value.to_i
      glyph = find_glyph(fractional_part(value))

      return format_with_glyph(integer_part, glyph) if glyph

      format_decimal(value)
    end

    def to_fraction_string(value)
      return value.to_i.to_s if integer?(value)

      integer_part = value.to_i
      fraction = find_fraction_string(fractional_part(value))

      fraction ? format_ascii_fraction(integer_part, fraction) : format_decimal(value)
    end

    def singular_noun?(value)
      return true if (value - 1.0).abs < TOLERANCE

      value < 1.0 && value.positive? && !find_glyph(value).nil?
    end

    def find_glyph(fractional_value)
      GLYPHS.find { |rational, _| (fractional_value - rational.to_f).abs < TOLERANCE }&.last
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

    def find_fraction_string(fractional_value)
      FRACTION_STRINGS.find { |rational, _| (fractional_value - rational.to_f).abs < TOLERANCE }&.last
    end

    def format_ascii_fraction(integer_part, fraction)
      integer_part.zero? ? fraction : "#{integer_part} #{fraction}"
    end

    def metric_unit?(unit)
      METRIC_UNITS.include?(unit&.downcase)
    end

    private_class_method :find_glyph, :integer?, :fractional_part, :format_with_glyph, :format_decimal, :metric_unit?,
                         :find_fraction_string, :format_ascii_fraction
  end
end

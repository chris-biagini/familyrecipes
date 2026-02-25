# frozen_string_literal: true

module FamilyRecipes
  module NumericParsing
    module_function

    def parse_fraction(str)
      return nil if str.nil?

      str = str.to_s.strip
      raise ArgumentError, "invalid numeric string: #{str.inspect}" if str.empty?

      if str.include?('/')
        parse_fraction_parts(str)
      else
        result = Float(str, exception: false)
        raise ArgumentError, "invalid numeric string: #{str.inspect}" unless result

        result
      end
    end

    def parse_fraction_parts(str)
      num_str, den_str = str.split('/', 2)
      num = Float(num_str, exception: false)
      den = Float(den_str, exception: false)

      raise ArgumentError, "invalid numeric string: #{str.inspect}" unless num && den
      raise ArgumentError, "division by zero: #{str.inspect}" if den.zero?

      num / den
    end

    private_class_method :parse_fraction_parts
  end
end

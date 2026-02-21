# frozen_string_literal: true

# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

class Ingredient
  attr_reader :name, :quantity, :prep_note

  # Fraction-to-decimal conversions for quantity parsing
  QUANTITY_FRACTIONS = {
    '1/2' => '0.5',
    '1/4' => '0.25',
    '1/3' => '0.333',
    '2/3' => '0.667',
    '3/4' => '0.75'
  }.freeze

  # name is required, quantity and prep_note are optional
  def initialize(name:, quantity: nil, prep_note: nil)
    @name = name
    @quantity = quantity
    @prep_note = prep_note
  end

  def normalized_name(alias_map = {})
    alias_map[@name.downcase] || @name
  end

  def quantity_value
    return nil if quantity_blank?

    value_str = parsed_quantity[0]

    # If the value is a range (e.g., "2-5" or "2–5"), take the high end.
    value_str = value_str.split(/[-–]/).last.strip if value_str =~ /[-–]/

    QUANTITY_FRACTIONS[value_str] || value_str
  end

  def quantity_unit
    return nil if quantity_blank?

    raw_unit = parsed_quantity[1]
    return nil if raw_unit.nil?

    FamilyRecipes::Inflector.normalize_unit(raw_unit)
  end

  # Raw unit after light cleanup, preserving original characters (e.g., macrons).
  # Used for display in data attributes; quantity_unit is for nutrition lookup.
  def quantity_unit_display
    return nil if quantity_blank?

    raw_unit = parsed_quantity[1]
    return nil if raw_unit.nil?

    raw_unit.strip.downcase.chomp('.')
  end

  private

  def quantity_blank?
    @quantity.nil? || @quantity.strip.empty?
  end

  def parsed_quantity
    @parsed_quantity ||= @quantity.strip.split(' ', 2)
  end
end

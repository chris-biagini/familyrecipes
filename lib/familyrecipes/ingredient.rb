# frozen_string_literal: true

# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

class Ingredient
  attr_reader :name, :quantity, :prep_note

  # Irregular plural/singular mappings not handled by standard rules
  IRREGULAR_PLURALS = { 'leaf' => 'leaves' }.freeze
  IRREGULAR_SINGULARS = { 'leaves' => 'leaf' }.freeze

  # Fraction-to-decimal conversions for quantity parsing
  QUANTITY_FRACTIONS = {
    '1/2' => '0.5',
    '1/4' => '0.25',
    '1/3' => '0.333',
    '2/3' => '0.667',
    '3/4' => '0.75'
  }.freeze

  # Unit normalizations (applied after downcasing and period-stripping)
  UNIT_NORMALIZATIONS = {
    # Volume
    'tablespoon' => 'tbsp', 'tablespoons' => 'tbsp',
    'teaspoon' => 'tsp', 'teaspoons' => 'tsp',
    'cups' => 'cup',
    'liter' => 'l', 'liters' => 'l',

    # Weight
    'gram' => 'g', 'grams' => 'g',
    'ounce' => 'oz', 'ounces' => 'oz',
    'lbs' => 'lb', 'pound' => 'lb', 'pounds' => 'lb',

    # Discrete (plural → singular)
    'cloves' => 'clove',
    'slices' => 'slice',
    'pieces' => 'piece',
    'stalks' => 'stalk',
    'bunches' => 'bunch',
    'cans' => 'can',
    'sticks' => 'stick',
    'items' => 'item',
    'tortillas' => 'tortilla',

    # Multi-word
    'small slices' => 'slice',

    # Special
    'gō' => 'go'
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

  def self.pluralize(word)
    return [word] if word.nil? || word.empty?

    lower = word.downcase
    if IRREGULAR_PLURALS.key?(lower)
      return [IRREGULAR_PLURALS[lower].sub(/^./) do |m|
        word[0] == word[0].upcase ? m.upcase : m
      end]
    end

    case lower
    when /[^aeiou]y$/      then ["#{word[0..-2]}ies"]
    when /(s|x|z|ch|sh)$/, /[^aeiou]o$/ then ["#{word}es"]
    else ["#{word}s"]
    end
  end

  def self.singularize(word)
    return [word] if word.nil? || word.empty?

    lower = word.downcase
    if IRREGULAR_SINGULARS.key?(lower)
      return [IRREGULAR_SINGULARS[lower].sub(/^./) do |m|
        word[0] == word[0].upcase ? m.upcase : m
      end]
    end

    case lower
    when /ies$/ then ["#{word[0..-4]}y"]
    when /(s|x|z|ch|sh)es$/, /oes$/ then [word[0..-3]]
    when /s$/                then [word[0..-2]]
    else [word]
    end
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

    cleaned = raw_unit.strip.downcase.chomp('.')
    UNIT_NORMALIZATIONS[cleaned] || cleaned
  end

  private

  def quantity_blank?
    @quantity.nil? || @quantity.strip.empty?
  end

  def parsed_quantity
    @parsed_quantity ||= @quantity.strip.split(' ', 2)
  end
end

# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

class Ingredient
  attr_reader :name, :quantity, :prep_note

  # Irregular plural/singular mappings not handled by standard rules
  IRREGULAR_PLURALS = { "leaf" => "leaves" }.freeze
  IRREGULAR_SINGULARS = { "leaves" => "leaf" }.freeze

  # Fraction-to-decimal conversions for quantity parsing
  QUANTITY_FRACTIONS = {
    "1/2" => "0.5",
    "1/4" => "0.25",
    "1/3" => "0.333",
    "2/3" => "0.667",
    "3/4" => "0.75"
  }.freeze

  # Unit normalizations
  UNIT_NORMALIZATIONS = {
    "clove" => "cloves",
    "ounce" => "oz",
    "ounces" => "oz"
  }.freeze

  # name is required, quantity and prep_note are optional
  def initialize(name:, quantity: nil, prep_note: nil)
    @name = name
    @quantity = quantity
    @prep_note = prep_note
  end

  def normalized_name(alias_map = {})
    alias_map.key?(@name) ? alias_map[@name] : @name
  end

  # Generate plural forms of a word for automatic matching
  def self.pluralize(word)
    return [word] if word.nil? || word.empty?

    lower = word.downcase

    # Check irregulars first
    if IRREGULAR_PLURALS.key?(lower)
      return [IRREGULAR_PLURALS[lower].sub(/^./) { |m| word[0] == word[0].upcase ? m.upcase : m }]
    end

    # Words ending in consonant + y -> ies
    if lower =~ /[^aeiou]y$/
      return [word[0..-2] + "ies"]
    end

    # Words ending in s, x, z, ch, sh -> es
    if lower =~ /(s|x|z|ch|sh)$/
      return [word + "es"]
    end

    # Words ending in o (after consonant) -> es
    if lower =~ /[^aeiou]o$/
      return [word + "es"]
    end

    # Default: add s
    [word + "s"]
  end

  # Generate singular forms from a plural word
  def self.singularize(word)
    return [word] if word.nil? || word.empty?

    lower = word.downcase

    if IRREGULAR_SINGULARS.key?(lower)
      return [IRREGULAR_SINGULARS[lower].sub(/^./) { |m| word[0] == word[0].upcase ? m.upcase : m }]
    end

    # Words ending in ies -> y
    if lower =~ /ies$/
      return [word[0..-4] + "y"]
    end

    # Words ending in es (after s, x, z, ch, sh) -> remove es
    if lower =~ /(s|x|z|ch|sh)es$/
      return [word[0..-3]]
    end

    # Words ending in oes -> o
    if lower =~ /oes$/
      return [word[0..-3]]
    end

    # Words ending in s -> remove s
    if lower =~ /s$/
      return [word[0..-2]]
    end

    [word]
  end
  
  def quantity_value
    return nil if @quantity.nil? || @quantity.strip.empty?

    parts = @quantity.strip.split(' ', 2)
    value_str = parts[0]

    # If the value is a range (e.g., "2-5" or "2–5"), take the high end.
    if value_str =~ /[-–]/
      range_parts = value_str.split(/[-–]/).map(&:strip)
      value_str = range_parts.last
    end

    QUANTITY_FRACTIONS[value_str] || value_str
  end

  def quantity_unit
    return nil if @quantity.nil? || @quantity.strip.empty?

    parts = @quantity.strip.split(' ', 2)
    UNIT_NORMALIZATIONS[parts[1]] || parts[1]
  end
end

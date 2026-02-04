# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

class Ingredient
  attr_accessor :name, :quantity, :prep_note

  # Class-level alias map, set during build
  @@alias_map = {}

  def self.alias_map=(map)
    @@alias_map = map
  end

  def self.alias_map
    @@alias_map
  end

  # name is required, quantity and prep_note are optional
  def initialize(name:, quantity: nil, prep_note: nil)
    @name = name
    @quantity = quantity
    @prep_note = prep_note
  end

  def normalized_name
    # First check the alias map (includes explicit aliases and auto-plurals)
    return @@alias_map[@name] if @@alias_map.key?(@name)

    # Otherwise return the original name
    @name
  end

  # Generate plural forms of a word for automatic matching
  def self.pluralize(word)
    return [word] if word.nil? || word.empty?

    # Irregular plurals (only ones not handled by rules below)
    irregulars = {
      "leaf" => "leaves"
    }

    lower = word.downcase

    # Check irregulars first
    if irregulars.key?(lower)
      return [irregulars[lower].sub(/^./) { |m| word[0] == word[0].upcase ? m.upcase : m }]
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

    # Irregular plurals (reverse, only ones not handled by rules below)
    irregulars = {
      "leaves" => "leaf"
    }

    if irregulars.key?(lower)
      return [irregulars[lower].sub(/^./) { |m| word[0] == word[0].upcase ? m.upcase : m }]
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

    quantity_synonyms = {
      "1/2" => "0.5",
      "1/4" => "0.25"
    }
      
    parts = @quantity.strip.split(' ', 2)  # Split on the first space
    value_str = parts[0]
    
    # If the value is a range (e.g., "2-5" or "2–5"), take the high end.
    if value_str =~ /[-–]/
      range_parts = value_str.split(/[-–]/).map(&:strip)
      value_str = range_parts.last
    end
    
    quantity_synonyms[value_str] || value_str
  end
  
  def quantity_unit
    return nil if @quantity.nil? || @quantity.strip.empty?
    
    unit_synonyms = {
      "clove" => "cloves"
    }
      
    parts = @quantity.strip.split(' ', 2)
    unit_synonyms[parts[1]] || parts[1]
  end
end

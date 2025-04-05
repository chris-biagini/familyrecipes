# Ingredient Class
#
# Handles parsing and providing information about individual ingredient lines in a Step

class Ingredient
  attr_accessor :name, :quantity, :prep_note

  # name is required, quantity and prep_note are optional
  def initialize(name:, quantity: nil, prep_note: nil)
    @name = name
    @quantity = quantity
    @prep_note = prep_note
  end
  
  def normalized_name
    ingredient_synonyms = {
      "Egg" => "Eggs",
      "Egg yolks" => "Eggs",
      "Egg yolk" => "Eggs",
      "Onion" => "Onions",
      "Carrot" => "Carrots"
    }
    
    # Return mapped name if it exists; otherwise, keep original
    ingredient_synonyms[@name] || @name
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

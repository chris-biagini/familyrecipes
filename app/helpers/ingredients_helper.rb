# frozen_string_literal: true

# View helpers for the ingredients management page. Formats aisle labels,
# nutrient values, resolution method labels, and unit names for ingredient
# editing and display.
#
# Collaborators: ApplicationHelper (format_numeric), IngredientCatalog (portions hash)
module IngredientsHelper
  def display_aisle(aisle)
    aisle || "\u2014"
  end

  def format_nutrient_value(value)
    return '0' unless value

    format_numeric(value)
  end

  def format_resolution_method(method, entry)
    case method
    when 'via density'          then 'volume conversion'
    when 'weight'               then 'standard weight'
    when 'no density'           then 'no volume conversion'
    when 'no portion'           then 'no matching unit — add one below'
    when 'no ~unitless portion' then "no 'each' weight — add one below"
    when /\Avia (.+)\z/
      name = Regexp.last_match(1)
      grams = entry&.portions&.dig(name)
      grams ? "unit weight (#{format_nutrient_value(grams)} g)" : 'unit weight'
    else
      method
    end
  end

  def format_unit_name(unit)
    unit || 'each'
  end
end

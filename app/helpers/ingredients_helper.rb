# frozen_string_literal: true

# View helpers for the ingredients management page. Formats aisle labels and
# nutrient values from IngredientCatalog entries for table rendering.
module IngredientsHelper
  def display_aisle(aisle)
    aisle || "\u2014"
  end

  def format_nutrient_value(value)
    return '0' unless value

    format_numeric(value)
  end
end

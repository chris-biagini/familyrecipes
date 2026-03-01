# frozen_string_literal: true

# A single ingredient line within a Step (e.g., "Flour, 2 cups: sifted").
# Stores name, quantity, unit, and prep_note as separate columns. Delegates
# numeric parsing to the domain FamilyRecipes::Ingredient class and unit
# normalization to Inflector. Shares the Ingredient name with the domain class
# but lives in a different namespace (AR vs FamilyRecipes::).
class Ingredient < ApplicationRecord
  belongs_to :step, inverse_of: :ingredients

  validates :name, presence: true
  validates :position, presence: true

  def quantity_display
    [quantity, unit].compact.join(' ').presence
  end

  def quantity_value
    return unless quantity

    FamilyRecipes::Ingredient.numeric_value(quantity)
  end

  def quantity_unit
    return unless unit

    FamilyRecipes::Inflector.normalize_unit(unit)
  end
end

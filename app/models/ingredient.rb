# frozen_string_literal: true

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

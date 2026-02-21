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

    FamilyRecipes::Ingredient.new(name: name, quantity: quantity_display).quantity_value
  end

  def quantity_unit
    return unless unit

    FamilyRecipes::Inflector.normalize_unit(unit)
  end
end

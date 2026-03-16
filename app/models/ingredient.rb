# frozen_string_literal: true

# A single ingredient line within a Step (e.g., "Flour, 2 cups: sifted").
# Stores name, quantity, unit, and prep_note as separate columns. Numeric
# quantities are stored as decimals in quantity_low/quantity_high (ranges use
# both; single values use quantity_low only). The raw quantity string is kept
# for non-numeric values ("a pinch"). Delegates unit normalization to Inflector
# and display formatting to VulgarFractions.
#
# - Step (parent via belongs_to)
# - FamilyRecipes::VulgarFractions (display formatting)
# - FamilyRecipes::Inflector (unit normalization and pluralization)
class Ingredient < ApplicationRecord
  belongs_to :step, inverse_of: :ingredients

  validates :name, presence: true
  validates :position, presence: true

  def quantity_display
    return [quantity, unit].compact.join(' ').presence unless quantity_low

    [formatted_quantity, pluralized_unit].compact.join(' ')
  end

  def quantity_value
    value = quantity_high || quantity_low
    return unless value

    format_decimal(value)
  end

  def quantity_unit
    return unless unit

    FamilyRecipes::Inflector.normalize_unit(unit)
  end

  def range?
    quantity_high.present?
  end

  private

  def formatted_quantity
    return format_value(quantity_low) unless range?

    "#{format_value(quantity_low)}\u2013#{format_value(quantity_high)}"
  end

  def format_value(val)
    FamilyRecipes::VulgarFractions.format(val.to_f, unit: quantity_unit)
  end

  def format_decimal(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end

  def pluralized_unit
    return unless unit

    count = (quantity_high || quantity_low).to_f
    singular = FamilyRecipes::VulgarFractions.singular_noun?(count)
    singular ? unit : FamilyRecipes::Inflector.unit_display(unit, count)
  end
end

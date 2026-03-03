# frozen_string_literal: true

# Formatting helpers for the groceries page. Mirrors the JS formatAmounts
# function in grocery_ui_controller so server-rendered shopping list
# HTML matches what JS rebuilds on state updates.
#
# Collaborators:
# - grocery_ui_controller.js — JS counterpart that formats on client rebuild
# - ShoppingListBuilder — produces the amount arrays this helper formats
module GroceriesHelper
  def format_amounts(amounts)
    return '' if amounts.blank?

    parts = amounts.map { |value, unit| format_amount_part(value, unit) }
    "(#{parts.join(' + ')})"
  end

  private

  def format_amount_part(value, unit)
    formatted = format_number(value)
    unit ? "#{formatted}\u00a0#{unit}" : formatted
  end

  def format_number(value)
    num = value.is_a?(String) ? Float(value) : value
    num.round(2).to_s.delete_suffix('.0')
  end
end

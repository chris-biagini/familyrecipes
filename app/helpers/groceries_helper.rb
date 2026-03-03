# frozen_string_literal: true

# Formatting helpers for the groceries page. Server-renders shopping list
# amounts and item counts for Turbo Stream morphs.
#
# Collaborators:
# - _shopping_list.html.erb — partial that calls these helpers
# - ShoppingListBuilder — produces the amount arrays this helper formats
module GroceriesHelper
  def format_amounts(amounts)
    return '' if amounts.blank?

    parts = amounts.map { |value, unit| format_amount_part(value, unit) }
    "(#{parts.join(' + ')})"
  end

  def aisle_count_tag(items, checked_off)
    remaining = items.count { |i| checked_off.exclude?(i[:name]) }

    if remaining.zero? && items.any?
      tag.span("\u2713", class: 'aisle-count aisle-done')
    else
      tag.span("(#{remaining})", class: 'aisle-count')
    end
  end

  def shopping_list_count_text(shopping_list, checked_off)
    total = shopping_list.each_value.sum(&:size)
    return '' if total.zero?

    checked = shopping_list.each_value.sum { |items| items.count { |i| checked_off.include?(i[:name]) } }
    remaining = total - checked

    return "\u2713 All done!" if remaining.zero?

    checked.positive? ? "#{remaining} of #{total} items needed" : "#{total} #{'item'.pluralize(total)}"
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

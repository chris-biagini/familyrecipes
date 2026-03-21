# frozen_string_literal: true

# Formatting helpers for the groceries page. Server-renders shopping list
# amounts and item counts for Turbo Stream morphs.
#
# Collaborators:
# - _shopping_list.html.erb — partial that calls these helpers
# - ShoppingListBuilder — produces the amount arrays this helper formats
module GroceriesHelper
  def format_amounts(amounts, uncounted: 0)
    return uncounted_only_text(uncounted) if amounts.blank?

    parts = amounts.map { |value, unit| format_amount_part(value, unit) }
    inner = parts.join(' + ')
    inner += " +#{format_uncounted(uncounted)}" if uncounted.positive?
    "(#{inner})"
  end

  def shopping_list_count_text(shopping_list, on_hand_names)
    total = shopping_list.each_value.sum(&:size)
    return '' if total.zero?

    remaining = total - shopping_list.each_value.sum { |items| items.count { |i| on_hand_names.include?(i[:name]) } }

    return "\u2713 All done!" if remaining.zero?

    "#{remaining} #{'item'.pluralize(remaining)} to buy"
  end

  def parse_custom_item(text)
    prefix, separator, hint = text.rpartition('@')
    return [text.strip, nil] if separator.empty?

    stripped_hint = hint.strip
    return [prefix.strip, nil] if stripped_hint.empty?

    [prefix.strip, stripped_hint]
  end

  private

  def uncounted_only_text(count)
    return '' if count <= 1

    "(#{count}\u00a0uses)"
  end

  def format_uncounted(count)
    "#{count}\u00a0more"
  end

  def format_amount_part(value, unit)
    formatted = format_number(value)
    unit ? "#{formatted}\u00a0#{unit}" : formatted
  end

  def format_number(value)
    value.to_f.round(2).to_s.delete_suffix('.0')
  end
end

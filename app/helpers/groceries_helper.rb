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

  def item_zone(name:, on_hand_names:, on_hand_data:, custom_items:)
    return :on_hand if on_hand_names.include?(name)

    entry = on_hand_data.find { |k, _| k.casecmp?(name) }&.last
    return :to_buy if entry&.key?('depleted_at')
    return :to_buy if custom_items.any? { |c| c.casecmp?(name) }

    :inventory_check
  end

  def shopping_list_count_text(shopping_list, on_hand_names, on_hand_data: {}, custom_items: [])
    total = shopping_list.each_value.sum(&:size)
    return '' if total.zero?

    remaining = shopping_list.each_value.sum do |items|
      items.count { |i| item_zone(name: i[:name], on_hand_names:, on_hand_data:, custom_items:) == :to_buy }
    end

    return "\u2713 All done!" if remaining.zero?

    "#{remaining} #{'item'.pluralize(remaining)} to buy"
  end

  def restock_tooltip(item_name, on_hand_data, on_hand_names, now: Date.current)
    entry = on_hand_data.find { |k, _| k.casecmp?(item_name) }&.last
    return nil unless entry
    return nil if entry['interval'].nil?

    if on_hand_names.include?(item_name)
      days_left = ((Date.parse(entry['confirmed_at']) + entry['interval'].to_f.round.days) - now).to_i
      "Estimated restock in ~#{[days_left, 0].max} days"
    elsif entry['interval'] > MealPlan::STARTING_INTERVAL ||
          (entry['ease'] && entry['ease'] != MealPlan::STARTING_EASE)
      "Restocks every ~#{entry['interval'].to_f.round} days"
    end
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

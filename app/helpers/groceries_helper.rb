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
    inner += " + #{format_uncounted(uncounted)}" if uncounted.positive?
    "(#{inner})"
  end

  def item_zone(name:, on_hand_names:, on_hand_data:, custom_names:)
    return :on_hand if on_hand_names.include?(name)

    entry = on_hand_data[name.downcase]
    return :to_buy if entry&.depleted_at.present?
    return :to_buy if custom_names.include?(name.downcase)

    :inventory_check
  end

  def shopping_list_count_text(shopping_list, on_hand_names, on_hand_data: {}, custom_names: Set.new)
    total = shopping_list.each_value.sum(&:size)
    return '' if total.zero?

    remaining = shopping_list.each_value.sum do |items|
      items.count { |i| item_zone(name: i[:name], on_hand_names:, on_hand_data:, custom_names:) == :to_buy }
    end

    return "\u2713 All done!" if remaining.zero?

    "#{remaining} #{'item'.pluralize(remaining)} to buy"
  end

  def restock_tooltip(item_name, on_hand_data, on_hand_names, now: Date.current)
    entry = on_hand_data[item_name.downcase]
    return nil unless entry
    return nil if entry.interval.nil?

    effective = entry.interval * OnHandEntry::SAFETY_MARGIN

    if on_hand_names.include?(item_name)
      days_left = ((entry.confirmed_at + effective.round.days) - now).to_i
      "Estimated restock in ~#{[days_left, 0].max} days"
    elsif entry.interval > OnHandEntry::STARTING_INTERVAL ||
          (entry.ease && entry.ease != OnHandEntry::STARTING_EASE)
      "Restocks every ~#{effective.round} days"
    end
  end

  def on_hand_sort_key(name, on_hand_data, now: Date.current)
    return [0, name] if confirmed_today?(name, on_hand_data)

    entry = on_hand_data[name.downcase]
    days_left = days_until_restock(entry, now)
    [1, -days_left, name]
  end

  def confirmed_today?(name, on_hand_data)
    entry = on_hand_data[name.downcase]
    return false unless entry

    confirmed = entry.confirmed_at
    return false if confirmed.nil? || confirmed == Date.parse(OnHandEntry::ORPHAN_SENTINEL)

    confirmed == Date.current
  end

  def on_hand_freshness_class(entry, now: Date.current)
    return 'on-hand-fresh' if entry.interval.nil?

    effective = (entry.interval * OnHandEntry::SAFETY_MARGIN).to_i
    return 'on-hand-aging' if effective <= 0

    days_elapsed = (now - entry.confirmed_at).to_i
    progress = days_elapsed.to_f / effective

    return 'on-hand-aging' unless progress < 0.66
    return 'on-hand-mid' unless progress < 0.33

    'on-hand-fresh'
  end

  private

  def days_until_restock(entry, now)
    return Float::INFINITY unless entry&.interval

    effective = (entry.interval * OnHandEntry::SAFETY_MARGIN).to_i
    (entry.confirmed_at + effective.days - now).to_i
  end

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

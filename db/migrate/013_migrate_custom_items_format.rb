# frozen_string_literal: true

# Converts custom_items from a flat string array to a structured hash.
# Old format: ["birthday candles@Party Supplies", "paper towels"]
# New format: { "birthday candles" => { "aisle" => "Party Supplies", "last_used_at" => "...", "on_hand_at" => nil },
#               "paper towels" => { "aisle" => "Miscellaneous", "last_used_at" => "...", "on_hand_at" => nil } }
class MigrateCustomItemsFormat < ActiveRecord::Migration[8.0]
  def up
    MealPlanStub.find_each do |plan|
      custom = plan.state['custom_items']
      next unless custom.is_a?(Array)

      now = Date.current.iso8601
      plan.state['custom_items'] = custom.each_with_object({}) do |raw, hash|
        name, aisle = parse_custom_item(raw)
        hash[name] = { 'aisle' => aisle || 'Miscellaneous', 'last_used_at' => now, 'on_hand_at' => nil }
      end
      plan.save!(validate: false)
    end
  end

  def down
    MealPlanStub.find_each do |plan|
      custom = plan.state['custom_items']
      next unless custom.is_a?(Hash)

      plan.state['custom_items'] = custom.map do |name, entry|
        aisle = entry['aisle']
        aisle && aisle != 'Miscellaneous' ? "#{name}@#{aisle}" : name
      end
      plan.save!(validate: false)
    end
  end

  private

  def parse_custom_item(text)
    prefix, separator, hint = text.rpartition('@')
    return [text.strip, nil] if separator.empty?

    stripped_hint = hint.strip
    return [prefix.strip, nil] if stripped_hint.empty?

    [prefix.strip, stripped_hint]
  end

  class MealPlanStub < ActiveRecord::Base
    self.table_name = 'meal_plans'
  end
end

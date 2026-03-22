# Converts checked_off arrays (legacy format) to on_hand hashes.
# Recipe ingredients get interval 7 (cold start — re-verified next week).
# Custom items (detected by membership in custom_items) get interval nil (never expires).
class ConvertCheckedOffToOnHand < ActiveRecord::Migration[8.0]
  def up
    today = Date.current.iso8601

    execute("SELECT id, state FROM meal_plans").each do |row|
      state = JSON.parse(row['state'] || '{}')
      next unless state.key?('checked_off')

      checked_off = state.delete('checked_off')
      custom_items = state.fetch('custom_items', [])
      on_hand = state.fetch('on_hand', {})

      Array(checked_off).each do |item|
        custom = custom_items.any? { |c| c.downcase == item.downcase }
        on_hand[item] = { 'confirmed_at' => today, 'interval' => custom ? nil : 7, 'ease' => custom ? nil : 2.0 }
      end

      state['on_hand'] = on_hand
      execute(
        "UPDATE meal_plans SET state = #{connection.quote(JSON.generate(state))} WHERE id = #{row['id']}"
      )
    end
  end

  def down
    execute("SELECT id, state FROM meal_plans").each do |row|
      state = JSON.parse(row['state'] || '{}')
      next unless state.key?('on_hand')

      on_hand = state.delete('on_hand')
      state['checked_off'] = on_hand.keys

      execute(
        "UPDATE meal_plans SET state = #{connection.quote(JSON.generate(state))} WHERE id = #{row['id']}"
      )
    end
  end
end

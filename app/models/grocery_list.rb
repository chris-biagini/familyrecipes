# frozen_string_literal: true

class GroceryList < ApplicationRecord
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_KEYS = %w[selected_recipes selected_quick_bites custom_items checked_off].freeze

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  end

  def apply_action(action_type, **params)
    ensure_state_keys

    case action_type
    when 'select' then apply_select(**params)
    when 'check' then apply_check(**params)
    when 'custom_items' then apply_custom_items(**params)
    end
  end

  def clear!
    self.state = {}
    increment(:version)
    save!
  end

  private

  def ensure_state_keys
    STATE_KEYS.each { |key| state[key] ||= [] }
  end

  def apply_select(type:, slug:, selected:, **)
    key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
    toggle_array(key, slug, truthy?(selected))
  end

  def apply_check(item:, checked:, **)
    toggle_array('checked_off', item, truthy?(checked))
  end

  def apply_custom_items(item:, action:, **)
    toggle_array('custom_items', item, action == 'add')
  end

  def toggle_array(key, value, add)
    list = state[key]
    already_present = list.include?(value)

    if add && !already_present
      list << value
      bump_and_save!
    elsif !add && already_present
      list.delete(value)
      bump_and_save!
    end
  end

  def bump_and_save!
    increment(:version)
    save!
  end

  # Controller params arrive as strings; handle both "true"/true
  def truthy?(value)
    [true, 'true'].include?(value)
  end
end

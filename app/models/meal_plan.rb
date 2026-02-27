# frozen_string_literal: true

class MealPlan < ApplicationRecord
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_KEYS = %w[selected_recipes selected_quick_bites custom_items checked_off].freeze
  MAX_RETRY_ATTEMPTS = 3
  MAX_CUSTOM_ITEM_LENGTH = 100

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
    save!
  end

  def clear_selections!
    ensure_state_keys
    state['selected_recipes'] = []
    state['selected_quick_bites'] = []
    save!
  end

  def with_optimistic_retry(max_attempts: MAX_RETRY_ATTEMPTS)
    attempts = 0

    begin
      attempts += 1
      yield
    rescue ActiveRecord::StaleObjectError
      raise if attempts >= max_attempts

      reload
      retry
    end
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
      save!
    elsif !add && already_present
      list.delete(value)
      save!
    end
  end

  # Controller params arrive as strings; handle both "true"/true
  def truthy?(value)
    [true, 'true'].include?(value)
  end
end

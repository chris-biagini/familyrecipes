# frozen_string_literal: true

# Singleton-per-kitchen record that stores shared meal planning state as a JSON
# blob: selected recipes, selected quick bites, custom grocery items, and
# checked-off items. Both the menu and groceries pages read and write this
# model. Cross-device sync is handled by Kitchen#broadcast_update.
class MealPlan < ApplicationRecord
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_KEYS = %w[selected_recipes selected_quick_bites custom_items checked_off].freeze
  CASE_INSENSITIVE_KEYS = %w[custom_items checked_off].freeze
  MAX_RETRY_ATTEMPTS = 3
  MAX_CUSTOM_ITEM_LENGTH = 100

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(kitchen: kitchen)
  end

  # Controller params arrive as strings; handle both "true"/true
  def self.truthy?(value)
    [true, 'true'].include?(value)
  end

  def checked_off_set
    state.fetch('checked_off', []).to_set
  end

  def custom_items_list
    state.fetch('custom_items', [])
  end

  def selected_recipes_set
    state.fetch('selected_recipes', []).to_set
  end

  def selected_quick_bites_set
    state.fetch('selected_quick_bites', []).to_set
  end

  def apply_action(action_type, **params)
    ensure_state_keys

    case action_type
    when 'select' then apply_select(**params)
    when 'check' then apply_check(**params)
    when 'custom_items' then apply_custom_items(**params)
    else raise ArgumentError, "unknown action: #{action_type}"
    end
  end

  def clear!
    self.state = {}
    save!
  end

  def select_all!(recipe_slugs, quick_bite_slugs)
    ensure_state_keys
    state['selected_recipes'] = recipe_slugs
    state['selected_quick_bites'] = quick_bite_slugs
    save!
  end

  def clear_selections!
    ensure_state_keys
    state['selected_recipes'] = []
    state['selected_quick_bites'] = []
    state['checked_off'] = []
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

  def reconcile!
    ensure_state_keys
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: self).visible_names
    prune_checked_off(visible_names: visible)
    prune_stale_selections
  end

  private

  def prune_checked_off(visible_names:)
    ensure_state_keys
    custom = state['custom_items']
    before_size = state['checked_off'].size
    state['checked_off'].select! { |item| visible_names.include?(item) || custom.any? { |c| c.casecmp?(item) } }
    save! if state['checked_off'].size < before_size
  end

  def prune_stale_selections
    ensure_state_keys
    valid_slugs = kitchen.recipes.pluck(:slug).to_set
    valid_qb_ids = kitchen.parsed_quick_bites.to_set(&:id)

    recipes_before = state['selected_recipes'].size
    qb_before = state['selected_quick_bites'].size

    state['selected_recipes'].select! { |s| valid_slugs.include?(s) }
    state['selected_quick_bites'].select! { |s| valid_qb_ids.include?(s) }

    save! if state['selected_recipes'].size < recipes_before ||
             state['selected_quick_bites'].size < qb_before
  end

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
    adding = action == 'add'
    toggle_array('custom_items', item, adding, save: adding)
    return if adding

    prune_checked_off_for(item)
    save!
  end

  def prune_checked_off_for(item)
    state['checked_off']&.reject! { |v| v.casecmp?(item) }
  end

  def toggle_array(key, value, add, save: true)
    list = state[key]
    already_present = list_include?(key, list, value)

    if add && !already_present
      list << value
      save! if save
    elsif !add && already_present
      list_remove(key, list, value)
      save! if save
    end
  end

  def list_include?(key, list, value)
    CASE_INSENSITIVE_KEYS.include?(key) ? list.any? { |v| v.casecmp?(value) } : list.include?(value)
  end

  def list_remove(key, list, value)
    CASE_INSENSITIVE_KEYS.include?(key) ? list.reject! { |v| v.casecmp?(value) } : list.delete(value)
  end

  def truthy?(value)
    self.class.truthy?(value)
  end
end

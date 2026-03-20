# frozen_string_literal: true

# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, checked-off items. Both menu and
# groceries pages read/write this model.
#
# - .reconcile_kitchen!(kitchen) — computes visible ingredient names (via
#   ShoppingListBuilder) and prunes stale checked-off/selection state.
#   Called by Kitchen.run_finalization; not called directly by services.
# - #reconcile!(visible_names:) — inner pruning for callers already holding
#   the plan inside a retry block.
class MealPlan < ApplicationRecord
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_KEYS = %w[selected_recipes selected_quick_bites custom_items checked_off].freeze
  CASE_INSENSITIVE_KEYS = %w[custom_items checked_off].freeze
  MAX_RETRY_ATTEMPTS = 3
  MAX_CUSTOM_ITEM_LENGTH = 100
  COOK_HISTORY_WINDOW = 90

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(kitchen: kitchen)
  end

  def self.reconcile_kitchen!(kitchen)
    plan = for_kitchen(kitchen)
    plan.with_optimistic_retry do
      visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
      plan.reconcile!(visible_names: visible)
    end
  end

  def checked_off
    state.fetch('checked_off', [])
  end

  def custom_items
    state.fetch('custom_items', [])
  end

  def selected_recipes
    state.fetch('selected_recipes', [])
  end

  def selected_quick_bites
    state.fetch('selected_quick_bites', [])
  end

  def cook_history
    state.fetch('cook_history', [])
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

  def reconcile!(visible_names:)
    ensure_state_keys
    changed = prune_checked_off(visible_names:)
    changed |= prune_stale_selections
    save! if changed
  end

  private

  def prune_checked_off(visible_names:) # rubocop:disable Naming/PredicateMethod
    custom = state['custom_items']
    before_size = state['checked_off'].size
    state['checked_off'].select! { |item| visible_names.include?(item) || custom.any? { |c| c.casecmp?(item) } }
    state['checked_off'].size < before_size
  end

  def prune_stale_selections # rubocop:disable Metrics/AbcSize, Naming/PredicateMethod
    valid_slugs = kitchen.recipes.pluck(:slug).to_set
    valid_qb_ids = kitchen.parsed_quick_bites.to_set(&:id)

    recipes_before = state['selected_recipes'].size
    qb_before = state['selected_quick_bites'].size

    state['selected_recipes'].select! { |s| valid_slugs.include?(s) }
    state['selected_quick_bites'].select! { |s| valid_qb_ids.include?(s) }

    state['selected_recipes'].size < recipes_before ||
      state['selected_quick_bites'].size < qb_before
  end

  def ensure_state_keys
    STATE_KEYS.each { |key| state[key] ||= [] }
  end

  def apply_select(type:, slug:, selected:, **)
    key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
    record_cook_event(slug) if !selected && type == 'recipe' && state[key]&.include?(slug)
    toggle_array(key, slug, selected)
  end

  def apply_check(item:, checked:, **)
    toggle_array('checked_off', item, checked)
  end

  def apply_custom_items(item:, action:, **)
    toggle_array('custom_items', item, action == 'add')
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

  def record_cook_event(slug)
    history = state['cook_history'] ||= []
    history << { 'slug' => slug, 'at' => Time.current.iso8601 }
    cutoff = COOK_HISTORY_WINDOW.days.ago
    history.reject! { |e| Time.zone.parse(e['at']) < cutoff }
  end
end

# frozen_string_literal: true

# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, checked-off items. Both menu and
# groceries pages read/write this model.
#
# - .reconcile_kitchen!(kitchen) — computes visible ingredient names (via
#   ShoppingListBuilder) and prunes stale on_hand/selection state.
#   Called by Kitchen.run_finalization; not called directly by services.
# - #reconcile!(visible_names:, now:) — inner pruning for callers already
#   holding the plan inside a retry block.
class MealPlan < ApplicationRecord # rubocop:disable Metrics/ClassLength
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  STATE_DEFAULTS = {
    'selected_recipes' => [],
    'selected_quick_bites' => [],
    'custom_items' => [],
    'on_hand' => {}
  }.freeze
  CASE_INSENSITIVE_KEYS = %w[custom_items].freeze
  MAX_RETRY_ATTEMPTS = 3
  MAX_CUSTOM_ITEM_LENGTH = 100
  COOK_HISTORY_WINDOW = 90
  STARTING_INTERVAL = 7
  MAX_INTERVAL = 56

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(kitchen: kitchen)
  end

  def self.reconcile_kitchen!(kitchen, now: Date.current)
    plan = for_kitchen(kitchen)
    plan.with_optimistic_retry do
      resolver = IngredientCatalog.resolver_for(kitchen)
      visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan, resolver:).visible_names
      plan.reconcile!(visible_names: visible, resolver:, now:)
    end
  end

  def on_hand
    state.fetch('on_hand', {})
  end

  def effective_on_hand(now: Date.current)
    on_hand.select { |_, entry| entry_on_hand?(entry, now) }
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

  def reconcile!(visible_names:, resolver: nil, now: Date.current)
    ensure_state_keys
    changed = prune_on_hand(visible_names:, resolver:, now:)
    changed |= prune_stale_selections
    save! if changed
  end

  private

  def entry_on_hand?(entry, now)
    return true if entry['interval'].nil?

    Date.parse(entry['confirmed_at']) + entry['interval'].days >= now
  end

  def add_to_on_hand(item, custom:, now:)
    hash = state['on_hand']
    existing = hash[item]

    return if existing && existing['confirmed_at'] == now.iso8601

    hash[item] = if existing
                   { 'confirmed_at' => now.iso8601, 'interval' => next_interval(existing, custom) }
                 else
                   { 'confirmed_at' => now.iso8601, 'interval' => custom ? nil : STARTING_INTERVAL }
                 end
    save!
  end

  def remove_from_on_hand(item)
    return unless state['on_hand'].delete(item)

    save!
  end

  def next_interval(existing, custom)
    return nil if custom

    [existing['interval'].to_i * 2, MAX_INTERVAL].min
  end

  def prune_on_hand(visible_names:, now:, resolver: nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    hash = state['on_hand']
    custom = state['custom_items']

    # Pass 4 (runs first): re-canonicalize keys before orphan check
    recanon_changed = resolver ? recanon_on_hand_keys(hash, resolver) : false

    before_size = hash.size

    # Pass 1: prune orphans
    hash.select! { |key, _| visible_names.include?(key) || custom.any? { |c| c.casecmp?(key) } }

    # Pass 2: prune expired
    hash.reject! { |_, entry| entry['interval'] && Date.parse(entry['confirmed_at']) + entry['interval'].days < now }

    # Pass 3: fix orphaned null intervals
    null_fixed = false
    hash.each do |key, entry|
      next unless entry['interval'].nil?
      next if custom.any? { |c| c.casecmp?(key) }

      entry['interval'] = STARTING_INTERVAL
      null_fixed = true
    end

    hash.size != before_size || null_fixed || recanon_changed
  end

  def recanon_on_hand_keys(hash, resolver) # rubocop:disable Naming/PredicateMethod
    renames = hash.each_key.with_object({}) do |key, acc|
      canonical = resolver.resolve(key)
      acc[key] = canonical if canonical != key
    end
    return false if renames.empty?

    renames.each { |old, new_key| merge_on_hand_entry(hash, old, new_key) }
    true
  end

  def merge_on_hand_entry(hash, old_key, new_key)
    old_entry = hash.delete(old_key)
    existing = hash[new_key]
    keep_old = !existing || old_entry['interval'].to_i > existing['interval'].to_i
    hash[new_key] = keep_old ? old_entry : existing
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
    STATE_DEFAULTS.each { |key, default| state[key] ||= default.dup }
  end

  def apply_select(type:, slug:, selected:, **)
    key = type == 'recipe' ? 'selected_recipes' : 'selected_quick_bites'
    record_cook_event(slug) if !selected && type == 'recipe' && state[key]&.include?(slug)
    toggle_array(key, slug, selected)
  end

  def apply_check(item:, checked:, custom: false, now: Date.current, **)
    if checked
      add_to_on_hand(item, custom:, now:)
    else
      remove_from_on_hand(item)
    end
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

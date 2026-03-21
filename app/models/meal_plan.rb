# frozen_string_literal: true

# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, on-hand ingredient tracking with
# exponential backoff intervals. Both menu and groceries pages read/write
# this model.
#
# - .reconcile_kitchen!(kitchen) — computes visible ingredient names (via
#   ShoppingListBuilder) and runs four cleanup passes on on_hand state:
#   re-canonicalize keys, expire orphans, fix orphaned null intervals,
#   purge stale orphans. Called by Kitchen.run_finalization; not called
#   directly by services.
# - #effective_on_hand(now:) — single source of truth for on-hand status:
#   returns only non-expired entries. All display/availability code calls this.
# - #reconcile!(visible_names:, resolver:, now:) — inner pruning for callers
#   already holding the plan inside a retry block.
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
  MAX_INTERVAL = 180
  ORPHAN_RETENTION = 180
  ORPHAN_SENTINEL = '1970-01-01'

  # SM-2-inspired adaptive ease factor — per-item growth multiplier
  STARTING_EASE = 2.0
  MIN_EASE = 1.1
  MAX_EASE = 2.5
  EASE_BONUS = 0.1
  EASE_PENALTY = 0.3

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
    stored_key = find_on_hand_key(item)
    existing = stored_key ? hash[stored_key] : nil

    return recheck_depleted(hash, item, stored_key, now) if existing&.key?('depleted_at')

    return if existing && existing['confirmed_at'] == now.iso8601

    hash.delete(stored_key) if stored_key && stored_key != item
    hash[item] = build_on_hand_entry(existing, custom:, now:)
    save!
  end

  def build_on_hand_entry(existing, custom:, now:)
    if existing
      new_interval, new_ease = next_interval_and_ease(existing, custom)
      { 'confirmed_at' => now.iso8601, 'interval' => new_interval, 'ease' => new_ease }
    else
      { 'confirmed_at' => now.iso8601,
        'interval' => custom ? nil : STARTING_INTERVAL,
        'ease' => custom ? nil : STARTING_EASE }
    end
  end

  def next_interval_and_ease(existing, custom)
    return [nil, nil] if custom

    base_interval = existing['interval'] || STARTING_INTERVAL
    ease = existing['ease'] || STARTING_EASE
    new_interval = [base_interval * ease, MAX_INTERVAL].min
    new_ease = [ease + EASE_BONUS, MAX_EASE].min
    [new_interval, new_ease]
  end

  def remove_from_on_hand(item, custom: false, now: Date.current)
    key = find_on_hand_key(item) || item
    entry = state['on_hand'][key]
    return unless entry

    if custom || entry['interval'].nil?
      state['on_hand'].delete(key)
    else
      mark_depleted(entry, now)
    end
    save!
  end

  def mark_depleted(entry, now)
    observed = (now - Date.parse(entry['confirmed_at'])).to_i
    entry['interval'] = [observed, STARTING_INTERVAL].max
    entry['ease'] = [(entry['ease'] || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    entry['confirmed_at'] = ORPHAN_SENTINEL
    entry['depleted_at'] = now.iso8601
    entry.delete('orphaned_at')
  end

  def recheck_depleted(hash, item, stored_key, now)
    entry = hash.delete(stored_key)
    entry['confirmed_at'] = now.iso8601
    entry.delete('depleted_at')
    hash[item] = entry
    save!
  end

  def prune_on_hand(visible_names:, now:, resolver: nil)
    hash = state['on_hand']
    custom = state['custom_items']
    changed = resolver ? recanon_on_hand_keys(hash, resolver) : false

    changed |= expire_orphaned_on_hand(hash, visible_names, custom, now)
    changed |= fix_orphaned_null_intervals(hash, custom)
    changed |= purge_stale_orphans(hash, now)
    changed
  end

  def expire_orphaned_on_hand(hash, visible_names, custom, now)
    changed = false
    hash.each do |key, entry|
      next if visible_names.include?(key) || custom.any? { |c| c.casecmp?(key) }
      next if entry['confirmed_at'] == ORPHAN_SENTINEL

      entry['confirmed_at'] = ORPHAN_SENTINEL
      entry['orphaned_at'] = now.iso8601
      changed = true
    end
    changed
  end

  def fix_orphaned_null_intervals(hash, custom)
    changed = false
    hash.each do |key, entry|
      next unless entry['interval'].nil?
      next if custom.any? { |c| c.casecmp?(key) }

      entry['interval'] = STARTING_INTERVAL
      changed = true
    end
    changed
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
    hash[new_key] = pick_merge_winner(old_entry, existing)
  end

  def pick_merge_winner(old_entry, existing)
    return old_entry unless existing
    return existing if old_entry['confirmed_at'] == ORPHAN_SENTINEL
    return old_entry if existing['confirmed_at'] == ORPHAN_SENTINEL

    old_entry['interval'].to_i >= existing['interval'].to_i ? old_entry : existing
  end

  def find_on_hand_key(item)
    state['on_hand'].each_key.find { |k| k.casecmp?(item) }
  end

  def purge_stale_orphans(hash, now)
    changed = false
    hash.each_value do |entry|
      next unless entry['confirmed_at'] == ORPHAN_SENTINEL && !entry.key?('orphaned_at')

      entry['orphaned_at'] = now.iso8601
      changed = true
    end
    cutoff = now - ORPHAN_RETENTION
    before = hash.size
    hash.reject! { |_, e| e['confirmed_at'] == ORPHAN_SENTINEL && Date.parse(e['orphaned_at']) < cutoff }
    changed || hash.size < before
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
      remove_from_on_hand(item, custom:, now:)
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

# frozen_string_literal: true

# Singleton-per-kitchen JSON state record for shared meal planning: selected
# recipes/quick bites, custom grocery items, on-hand ingredient tracking with
# SM-2-inspired adaptive ease (per-item growth rates converge on each
# ingredient's natural restock cycle; depleted state preserves learned
# intervals when users run out). Both menu and groceries pages read/write
# this model.
#
# Action types: select, check, custom_items, have_it, need_it.
# - have_it: user confirms they still have an ingredient. Grows interval via
#   anchored growth (preserves confirmed_at at purchase date) or standard
#   growth (resets confirmed_at for sentinel/orphaned entries).
# - need_it: user says they need to buy an ingredient (Task 2).
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

  # SM-2-inspired adaptive ease factor — per-item growth multiplier.
  # Tuned for resilience: slower growth and gentler penalties make the
  # system robust to messy real-world signals (irregular shopping, delayed
  # updates, accidental taps). See grocery-interval-resilience-design.md.
  STARTING_EASE = 1.5
  MIN_EASE = 1.1
  MAX_EASE = 2.5
  EASE_BONUS = 0.05
  EASE_PENALTY = 0.15

  # Items surface in Inventory Check 10% before the predicted depletion
  # date. Better to ask and not need it than to miss a depleted staple.
  SAFETY_MARGIN = 0.9

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
    when 'have_it' then apply_have_it(**params)
    when 'need_it' then apply_need_it(**params)
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
    return false if entry.key?('depleted_at')
    return true if entry['interval'].nil?

    effective = entry['interval'] * SAFETY_MARGIN
    Date.parse(entry['confirmed_at']) + effective.to_i.days >= now
  end

  def add_to_on_hand(item, custom:, now:)
    hash = state['on_hand']
    stored_key = find_on_hand_key(item)
    existing = stored_key ? hash[stored_key] : nil

    return recheck_depleted(hash, item, stored_key, now) if existing&.key?('depleted_at')

    return if existing && existing['confirmed_at'] == now.iso8601
    return if existing && entry_on_hand?(existing, now)

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
    elsif entry['confirmed_at'] == now.iso8601
      # Same-day uncheck grace: treat as an undo, not a depletion signal.
      # Cracked eggs, wrong brand, accidental tap — don't nuke learned state.
      undo_same_day_check(entry, now)
    else
      deplete_existing(entry, now)
    end
    save!
  end

  def mark_depleted(entry, now)
    observed = (now - Date.parse(entry['confirmed_at'])).to_i
    old_interval = entry['interval']
    # Blend observed period with current estimate. Dampens oscillation when
    # observations are quantized to the shopping interval (e.g. weekly
    # shopping → eggs alternate 7d and 14d, blending converges to ~10.5d).
    # Also halves the impact of delay-inflated observations.
    blended = (observed + old_interval) / 2.0
    entry['interval'] = [blended, STARTING_INTERVAL].max
    entry['ease'] = [(entry['ease'] || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    entry['confirmed_at'] = ORPHAN_SENTINEL
    entry['depleted_at'] = now.iso8601
    entry.delete('orphaned_at')
  end

  # Same-day undo: if the entry still has default values (brand-new),
  # delete it entirely. Otherwise restore to depleted state without
  # penalizing — the learned interval and ease survive the oops.
  def undo_same_day_check(entry, now)
    if entry['interval'] == STARTING_INTERVAL && entry['ease'] == STARTING_EASE
      key = state['on_hand'].key(entry)
      state['on_hand'].delete(key)
    else
      entry['confirmed_at'] = ORPHAN_SENTINEL
      entry['depleted_at'] = now.iso8601
    end
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
      next if entry.key?('depleted_at')

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
      entry['ease'] = STARTING_EASE
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
      next if entry.key?('depleted_at')
      next unless entry['confirmed_at'] == ORPHAN_SENTINEL && !entry.key?('orphaned_at')

      entry['orphaned_at'] = now.iso8601
      changed = true
    end
    cutoff = now - ORPHAN_RETENTION
    before = hash.size
    hash.reject! do |_, e|
      e['confirmed_at'] == ORPHAN_SENTINEL &&
        !e.key?('depleted_at') &&
        e.key?('orphaned_at') && Date.parse(e['orphaned_at']) < cutoff
    end
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

  def apply_have_it(item:, now: Date.current, **)
    hash = state['on_hand']
    stored_key = find_on_hand_key(item)
    existing = stored_key ? hash[stored_key] : nil

    return create_on_hand_entry(hash, item, now) unless existing
    return if entry_on_hand?(existing, now)

    hash.delete(stored_key) if stored_key != item
    grow_on_hand(existing, now)
    hash[item] = existing
    save!
  end

  def apply_need_it(item:, now: Date.current, **)
    hash = state['on_hand']
    stored_key = find_on_hand_key(item)
    existing = stored_key ? hash[stored_key] : nil

    return create_depleted_entry(hash, item, now) unless existing

    hash.delete(stored_key) if stored_key != item
    deplete_existing(existing, now)
    hash[item] = existing
    save!
  end

  def create_depleted_entry(hash, item, now)
    hash[item] = { 'confirmed_at' => ORPHAN_SENTINEL,
                   'interval' => STARTING_INTERVAL,
                   'ease' => STARTING_EASE,
                   'depleted_at' => now.iso8601 }
    save!
  end

  def deplete_existing(entry, now)
    if entry['confirmed_at'] == ORPHAN_SENTINEL
      mark_depleted_sentinel(entry, now)
    else
      mark_depleted(entry, now)
    end
  end

  # Penalizes ease and marks depleted without touching interval — the
  # sentinel confirmed_at means we have no real observed period to record.
  def mark_depleted_sentinel(entry, now)
    entry['ease'] = [(entry['ease'] || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    entry['depleted_at'] = now.iso8601
    entry.delete('orphaned_at')
  end

  def create_on_hand_entry(hash, item, now)
    hash[item] = { 'confirmed_at' => now.iso8601,
                   'interval' => STARTING_INTERVAL,
                   'ease' => STARTING_EASE }
    save!
  end

  def grow_on_hand(entry, now)
    if entry['confirmed_at'] == ORPHAN_SENTINEL
      grow_standard(entry, now)
    else
      grow_anchored(entry, now)
    end
  end

  # Grows interval by ease, resets confirmed_at to now. Used for sentinel
  # (orphaned) entries where the original purchase date is meaningless.
  def grow_standard(entry, now)
    entry['ease'] = [entry['ease'] + EASE_BONUS, MAX_EASE].min
    entry['interval'] = [entry['interval'] * entry['ease'], MAX_INTERVAL].min
    entry['confirmed_at'] = now.iso8601
    entry.delete('orphaned_at')
  end

  # One-step anchored growth: grows interval once and checks if the anchor
  # still covers today. Capped to a single multiplication to prevent IC
  # delay from inflating intervals — a 3-week absence shouldn't turn a
  # 7-day item into a 65-day item. If one step can't bridge the gap, the
  # user was absent (not consuming), so we reset confirmed_at honestly.
  # Ease is only rewarded when anchored growth succeeds.
  def grow_anchored(entry, now)
    new_ease = [entry['ease'] + EASE_BONUS, MAX_EASE].min
    entry['interval'] = [entry['interval'] * new_ease, MAX_INTERVAL].min
    confirmed = Date.parse(entry['confirmed_at'])

    if confirmed + entry['interval'].to_i >= now
      entry['ease'] = new_ease
    else
      entry['confirmed_at'] = now.iso8601
    end
  end
end

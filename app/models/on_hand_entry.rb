# frozen_string_literal: true

# Tracks per-ingredient on-hand state with SM-2-inspired adaptive intervals.
# Each entry learns how long an ingredient lasts between purchases: the interval
# grows on confirmation ("Have It"), shrinks on depletion ("Need It"), and the
# ease factor converges on the ingredient's natural restock cycle. Replaces the
# on_hand JSON hash formerly embedded in MealPlan.
#
# Collaborators:
# - Kitchen (tenant owner, has_many)
# - CustomGroceryItem (cross-table on_hand_at sync via check!/uncheck!)
# - MealPlanWriteService (drives user actions: check, uncheck, have_it, need_it)
# - IngredientResolver (re-canonicalizes names during reconciliation)
# - ShoppingListBuilder (reads active/depleted state for grocery display)
class OnHandEntry < ApplicationRecord # rubocop:disable Metrics/ClassLength
  acts_as_tenant :kitchen

  STARTING_INTERVAL = 7
  MAX_INTERVAL = 180
  ORPHAN_RETENTION = 180
  ORPHAN_SENTINEL = '1970-01-01'

  STARTING_EASE = 1.5
  MIN_EASE = 1.05
  MAX_EASE = 2.5
  EASE_BONUS = 0.03
  EASE_PENALTY = 0.20
  BLEND_WEIGHT = 0.65
  MAX_GROWTH_FACTOR = 1.3

  # Items surface in Inventory Check before predicted depletion.
  # SAFETY_MARGIN gives proportional buffer; MIN_BUFFER ensures short-cycle
  # items (eggs, milk) get at least 2 days of warning.
  SAFETY_MARGIN = 0.78
  MIN_BUFFER = 2

  validates :ingredient_name, presence: true,
                              uniqueness: { scope: :kitchen_id, case_sensitive: false }

  scope :active, lambda { |now: Date.current|
    where(depleted_at: nil).where(
      'interval IS NULL OR date(confirmed_at, ' \
      "'+' || MIN(CAST(interval * #{SAFETY_MARGIN} AS INTEGER), " \
      "CAST(interval AS INTEGER) - #{MIN_BUFFER}) || ' days') >= date(?)",
      now.iso8601
    )
  }
  scope :depleted, -> { where.not(depleted_at: nil) }
  scope :orphaned, -> { where.not(orphaned_at: nil) }

  def have_it!(now: Date.current) # rubocop:disable Naming/PredicatePrefix
    return if on_hand?(now)

    sentinel? ? grow_standard(now) : grow_anchored(now)
    save!
  end

  def need_it!(now: Date.current)
    sentinel? ? deplete_sentinel(now) : deplete_observed(now)
    save!
  end

  def check!(now: Date.current, custom_item: nil)
    if depleted_at.present?
      recheck(now)
    elsif !new_record? && already_active?(now)
      return
    else
      assign_starting_values(now, custom: custom_item.present?)
    end

    sync_custom(custom_item, on_hand: true, now:)
    save!
  end

  def uncheck!(now: Date.current, custom_item: nil)
    if custom_item || interval.nil?
      sync_custom(custom_item, on_hand: false, now:)
      destroy!
      return
    end

    confirmed_at == now ? undo_same_day(now) : deplete_observed(now)
    save! unless destroyed?
  end

  def self.reconcile!(kitchen:, visible_names:, resolver:, now: Date.current)
    entries = ActsAsTenant.with_tenant(kitchen) { all.to_a }
    recanon_keys(entries, resolver)
    expire_orphans(entries, visible_names, kitchen, now)
    fix_null_intervals(entries, kitchen)
    purge_stale_orphans(kitchen, now)
  end

  private

  def sentinel?
    confirmed_at == Date.parse(ORPHAN_SENTINEL)
  end

  def on_hand?(now)
    return false if depleted_at.present?
    return true if interval.nil?

    confirmed_at + [interval * SAFETY_MARGIN, interval - MIN_BUFFER].min.to_i.days >= now
  end

  def already_active?(now)
    confirmed_at == now || on_hand?(now)
  end

  # Resets confirmed_at to now, grows interval by ease. Used for sentinel
  # entries where the original purchase date is meaningless.
  def grow_standard(now)
    self.ease = [ease + EASE_BONUS, MAX_EASE].min
    self.interval = [interval * [ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min
    self.confirmed_at = now
    self.orphaned_at = nil
  end

  # One-step anchored growth: grows interval once, preserves confirmed_at if
  # the anchor still covers today. Capped to a single multiplication to prevent
  # Inventory Check delay from inflating intervals. Ease is only rewarded when
  # anchored growth succeeds.
  def grow_anchored(now)
    new_ease = [ease + EASE_BONUS, MAX_EASE].min
    self.interval = [interval * [new_ease, MAX_GROWTH_FACTOR].min, MAX_INTERVAL].min

    if confirmed_at + interval.to_i >= now
      self.ease = new_ease
    else
      self.confirmed_at = now
    end
  end

  # Blends observed period with current interval to dampen oscillation from
  # quantized shopping cycles (e.g. weekly trips -> eggs alternate 7d/14d,
  # blending converges to ~10.5d). Also halves delay-inflated observations.
  def deplete_observed(now)
    observed = (now - confirmed_at).to_i
    blended = (observed * BLEND_WEIGHT) + (interval * (1 - BLEND_WEIGHT))
    self.interval = [blended, STARTING_INTERVAL].max
    self.ease = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    self.confirmed_at = Date.parse(ORPHAN_SENTINEL)
    self.depleted_at = now
    self.orphaned_at = nil
  end

  # Sentinel confirmed_at means no real observed period — penalize ease only.
  def deplete_sentinel(now)
    self.ease = [(ease || STARTING_EASE) * (1 - EASE_PENALTY), MIN_EASE].max
    self.depleted_at = now
    self.orphaned_at = nil
  end

  def recheck(now)
    self.confirmed_at = now
    self.depleted_at = nil
  end

  def assign_starting_values(now, custom:)
    self.confirmed_at = now
    self.interval = custom ? nil : STARTING_INTERVAL
    self.ease = custom ? nil : STARTING_EASE
    self.depleted_at = nil
    self.orphaned_at = nil
  end

  # Same-day undo: mark depleted without penalizing — the learned
  # interval and ease survive the accidental tap. Always depletes
  # (never destroys) so the item lands in To Buy, not Inventory Check.
  def undo_same_day(now)
    self.confirmed_at = Date.parse(ORPHAN_SENTINEL)
    self.depleted_at = now
  end

  def sync_custom(custom_item, on_hand:, now:)
    return unless custom_item

    custom_item.update!(on_hand_at: on_hand ? now : nil)
  end

  # --- Reconciliation class methods ---

  def self.recanon_keys(entries, resolver)
    renames = entries.filter_map do |entry|
      canonical = resolver.resolve(entry.ingredient_name)
      [entry, canonical] if canonical != entry.ingredient_name
    end

    renames.each { |entry, canonical| merge_or_rename(entry, canonical) }
  end
  private_class_method :recanon_keys

  def self.merge_or_rename(entry, canonical)
    existing = entry.class.find_by(kitchen_id: entry.kitchen_id, ingredient_name: canonical)

    if existing
      resolve_merge_conflict(entry, existing)
    else
      entry.update!(ingredient_name: canonical)
    end
  end
  private_class_method :merge_or_rename

  def self.resolve_merge_conflict(old_entry, existing)
    sentinel = Date.parse(ORPHAN_SENTINEL)
    winner, loser = pick_merge_winner(old_entry, existing, sentinel)
    loser.destroy!
    winner.update!(ingredient_name: existing.ingredient_name) if winner == old_entry
  end
  private_class_method :resolve_merge_conflict

  def self.pick_merge_winner(old_entry, existing, sentinel)
    return [existing, old_entry] if old_entry.confirmed_at == sentinel
    return [old_entry, existing] if existing.confirmed_at == sentinel
    return [old_entry, existing] if old_entry.interval.to_i >= existing.interval.to_i

    [existing, old_entry]
  end
  private_class_method :pick_merge_winner

  def self.expire_orphans(entries, visible_names, kitchen, now)
    custom_names = custom_name_set(kitchen)

    entries.each do |entry|
      next if visible_names.include?(entry.ingredient_name)
      next if custom_names.include?(entry.ingredient_name.downcase)
      next if entry.confirmed_at == Date.parse(ORPHAN_SENTINEL)
      next if entry.depleted_at.present?

      entry.update!(confirmed_at: Date.parse(ORPHAN_SENTINEL), orphaned_at: now)
    end
  end
  private_class_method :expire_orphans

  def self.fix_null_intervals(entries, kitchen)
    custom_names = custom_name_set(kitchen)

    entries.select { |e| e.interval.nil? }.each do |entry|
      next if custom_names.include?(entry.ingredient_name.downcase)

      entry.update!(interval: STARTING_INTERVAL, ease: STARTING_EASE)
    end
  end
  private_class_method :fix_null_intervals

  def self.custom_name_set(kitchen)
    ActsAsTenant.with_tenant(kitchen) do
      CustomGroceryItem.pluck(:name).map(&:downcase)
    end.to_set
  end
  private_class_method :custom_name_set

  def self.purge_stale_orphans(kitchen, now)
    cutoff = now - ORPHAN_RETENTION
    ActsAsTenant.with_tenant(kitchen) do
      orphaned.where(depleted_at: nil)
              .where(orphaned_at: ...cutoff)
              .delete_all
    end
  end
  private_class_method :purge_stale_orphans
end

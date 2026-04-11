# frozen_string_literal: true

# Multi-tenant container — the top-level scope for all user-facing data. Every
# query on tenant-scoped models must go through current_kitchen; unscoped finders
# like Recipe.find_by would cross kitchen boundaries. Owns recipes, categories,
# quick bites, ingredient catalog entries, a single MealPlan, and its member
# Users via Memberships. Also holds aisle_order (user-customized grocery aisle
# sequence), site branding (site_title, homepage_heading, homepage_subtitle),
# display preferences (show_nutrition), encrypted API keys (usda_api_key,
# anthropic_api_key), and an encrypted join_code for membership invitations.
# join_code uses deterministic encryption so it can be queried via find_by.
#
# Kitchen.finalize_writes(kitchen) is the single post-write entry point for
# all write services: orphan cleanup, meal plan reconciliation, broadcast.
# Kitchen.batch_writes defers finalization to block exit via the same pipeline.
class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :quick_bites, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :ingredient_catalog, dependent: :destroy, class_name: 'IngredientCatalog'
  has_many :meal_plan_selections, dependent: :destroy
  has_one :meal_plan, dependent: :destroy
  has_many :cook_history_entries, dependent: :destroy
  has_many :custom_grocery_items, dependent: :destroy
  has_many :on_hand_entries, dependent: :destroy

  encrypts :usda_api_key
  encrypts :anthropic_api_key
  encrypts :join_code, deterministic: true

  MAX_AISLES = 50
  AI_MODEL = 'claude-sonnet-4-6'

  def self.accepting_signups?
    return false if ENV['DISABLE_SIGNUPS'] == 'true'
    return true if Rails.env.development?

    ActsAsTenant.without_tenant do
      return true if Kitchen.none?
    end

    ENV['ALLOW_SIGNUPS'] == 'true'
  end

  def self.finalize_writes(kitchen)
    return if batching?

    run_finalization(kitchen)
    flush_pending_broadcast
  end

  def self.batch_writes(kitchen)
    Current.batching_kitchen = kitchen
    yield
  ensure
    Current.batching_kitchen = nil
    run_finalization(kitchen)
    flush_pending_broadcast
  end

  def self.batching?
    Current.batching_kitchen.present?
  end

  def self.run_finalization(kitchen)
    Category.cleanup_orphans(kitchen)
    Tag.cleanup_orphans(kitchen)
    reconcile_meal_plan_tables(kitchen)
    kitchen.update_column(:updated_at, Time.current) # rubocop:disable Rails/SkipsModelValidations -- intentional: invalidates search data cache without triggering callbacks
    Current.broadcast_pending = kitchen
  end
  private_class_method :run_finalization

  def self.flush_pending_broadcast
    kitchen = Current.broadcast_pending
    return unless kitchen

    Current.broadcast_pending = nil
    kitchen.broadcast_update
  end
  private_class_method :flush_pending_broadcast

  def self.reconcile_meal_plan_tables(kitchen)
    resolver = IngredientCatalog.resolver_for(kitchen)
    visible = ShoppingListBuilder.visible_names_for(kitchen:, resolver:)
    OnHandEntry.reconcile!(kitchen:, visible_names: visible, resolver:)
    CustomGroceryItem.where(kitchen_id: kitchen.id).stale(cutoff: Date.current - CustomGroceryItem::RETENTION).delete_all
    CookHistoryEntry.prune!(kitchen:)
    valid_slugs = kitchen.recipes.pluck(:slug)
    valid_qb_ids = kitchen.quick_bites.pluck(:id).map(&:to_s)
    MealPlanSelection.prune_stale!(kitchen:, valid_recipe_slugs: valid_slugs, valid_qb_ids:)
  end
  private_class_method :reconcile_meal_plan_tables

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_create :set_join_code

  def self.find_by_join_code(code)
    normalized = code.to_s.strip.downcase.squish
    find_by(join_code: normalized)
  end

  def broadcast_update
    Turbo::StreamsChannel.broadcast_refresh_to(self, :updates)
  end

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
  end

  def parsed_aisle_order
    return [] unless aisle_order

    @parsed_aisle_order ||= aisle_order.lines.map(&:strip).reject(&:empty?)
  end

  def normalize_aisle_order!
    lines = parsed_aisle_order.uniq(&:downcase)
    self.aisle_order = lines.empty? ? nil : lines.join("\n")
  end

  def all_aisles
    saved = parsed_aisle_order
    overridden = IngredientCatalog.where(kitchen_id: id).select(:ingredient_name)
    catalog_aisles = IngredientCatalog
                     .where(kitchen_id: id)
                     .or(IngredientCatalog.where(kitchen_id: nil).where.not(ingredient_name: overridden))
                     .where.not(aisle: [nil, ''])
                     .distinct.pluck(:aisle).sort

    saved_downcased = saved.to_set(&:downcase)
    saved + catalog_aisles.reject { |a| saved_downcased.include?(a.downcase) }
  end

  def regenerate_join_code!
    loop do
      self.join_code = JoinCodeGenerator.generate
      break unless Kitchen.where.not(id: id).exists?(join_code: join_code)
    end
    save!
  end

  private

  def set_join_code
    return if join_code.present?

    loop do
      self.join_code = JoinCodeGenerator.generate
      break unless Kitchen.exists?(join_code: join_code)
    end
  end
end

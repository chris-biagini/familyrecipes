# frozen_string_literal: true

# Multi-tenant container — the top-level scope for all user-facing data. Every
# query on tenant-scoped models must go through current_kitchen; unscoped finders
# like Recipe.find_by would cross kitchen boundaries. Owns recipes, categories,
# ingredient catalog entries, a single MealPlan, and its member Users via
# Memberships. Also holds quick_bites_content (web-editable), aisle_order
# (user-customized grocery aisle sequence), site branding (site_title,
# homepage_heading, homepage_subtitle), and encrypted API keys (usda_api_key).
#
# Kitchen.batch_writes wraps a block so that reconciliation and broadcast happen
# exactly once at the end, regardless of how many write services run inside.
# Write services check Kitchen.batching? to skip their own finalization.
class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :ingredient_catalog, dependent: :destroy, class_name: 'IngredientCatalog'
  has_one :meal_plan, dependent: :destroy

  encrypts :usda_api_key

  MAX_AISLE_NAME_LENGTH = FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH
  MAX_AISLES = 50

  def self.batch_writes(kitchen)
    Current.batching_kitchen = kitchen
    yield
  ensure
    Current.batching_kitchen = nil
    finalize_batch(kitchen)
  end

  def self.batching?
    Current.batching_kitchen.present?
  end

  def self.finalize_batch(kitchen)
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { plan.reconcile! }
    kitchen.broadcast_update
  end
  private_class_method :finalize_batch

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validate :enforce_single_kitchen_mode, on: :create

  def broadcast_update
    Turbo::StreamsChannel.broadcast_refresh_to(self, :updates)
  end

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
  end

  def parsed_quick_bites
    return [] unless quick_bites_content

    FamilyRecipes.parse_quick_bites_content(quick_bites_content).quick_bites
  end

  def quick_bites_by_subsection
    parsed_quick_bites.group_by { |qb| qb.category.delete_prefix('Quick Bites: ') }
  end

  def parsed_aisle_order
    return [] unless aisle_order

    aisle_order.lines.map(&:strip).reject(&:empty?)
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

  private

  def enforce_single_kitchen_mode
    return if ENV['MULTI_KITCHEN'] == 'true'

    # Intentionally unscoped — checking global kitchen count, not tenant-scoped data
    errors.add(:base, 'Only one kitchen is allowed in single-kitchen mode') if Kitchen.exists?
  end
end

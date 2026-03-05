# frozen_string_literal: true

# Multi-tenant container — the top-level scope for all user-facing data. Every
# query on tenant-scoped models must go through current_kitchen; unscoped finders
# like Recipe.find_by would cross kitchen boundaries. Owns recipes, categories,
# ingredient catalog entries, a single MealPlan, and its member Users via
# Memberships. Also holds quick_bites_content (web-editable) and aisle_order
# (user-customized grocery aisle sequence).
class Kitchen < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  has_many :categories, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :ingredient_catalog, dependent: :destroy, class_name: 'IngredientCatalog'
  has_one :meal_plan, dependent: :destroy

  MAX_AISLE_NAME_LENGTH = FamilyRecipes::NutritionConstraints::AISLE_MAX_LENGTH
  MAX_AISLES = 50

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

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
    lines = parsed_aisle_order.uniq
    self.aisle_order = lines.empty? ? nil : lines.join("\n")
  end

  def all_aisles
    saved = parsed_aisle_order
    overridden = IngredientCatalog.where(kitchen_id: id).select(:ingredient_name)
    catalog_aisles = IngredientCatalog
                     .where(kitchen_id: id)
                     .or(IngredientCatalog.where(kitchen_id: nil).where.not(ingredient_name: overridden))
                     .where.not(aisle: [nil, '', 'omit'])
                     .distinct.pluck(:aisle).sort

    saved + (catalog_aisles - saved)
  end
end

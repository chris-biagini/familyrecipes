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

  MAX_AISLE_NAME_LENGTH = 50
  MAX_AISLES = 50

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def member?(user)
    return false unless user

    memberships.exists?(user: user)
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
    catalog_aisles = IngredientCatalog.lookup_for(self)
                                      .values
                                      .filter_map(&:aisle)
                                      .uniq
                                      .reject { |a| a == 'omit' }
                                      .sort

    saved + (catalog_aisles - saved)
  end
end

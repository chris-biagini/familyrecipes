# frozen_string_literal: true

# Recipe and QuickBite grouping derived from directory names under
# db/seeds/recipes/ (e.g., "Bread", "Mains"). Ordered by position for homepage
# display. Orphaned categories (with no recipes or quick bites) are cleaned up
# via .cleanup_orphans.
#
# - Recipe (child recipes)
# - QuickBite (child grocery bundles)
# - .find_or_create_for(kitchen, name) — canonical factory; handles slug
#   generation and position assignment. Used by write services and importer.
# - .miscellaneous(kitchen) — default fallback category for uncategorized recipes.
class Category < ApplicationRecord
  acts_as_tenant :kitchen

  has_many :recipes, dependent: :destroy
  has_many :quick_bites, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :kitchen_id, case_sensitive: false }
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }

  scope :ordered, -> { order(:position, :name) }
  scope :with_recipes, -> { where.associated(:recipes).distinct }
  scope :with_content, lambda {
    left_joins(:recipes, :quick_bites)
      .where('recipes.id IS NOT NULL OR quick_bites.id IS NOT NULL')
      .distinct
  }

  def self.find_or_create_for(kitchen, name)
    slug = Mirepoix.slugify(name)
    kitchen.categories.find_or_create_by!(slug:) do |cat|
      cat.name = name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def self.miscellaneous(kitchen)
    find_or_create_for(kitchen, 'Miscellaneous')
  end

  def self.cleanup_orphans(kitchen)
    kitchen.categories.where.missing(:recipes).where.missing(:quick_bites).destroy_all
  end

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = Mirepoix.slugify(name)
end

# frozen_string_literal: true

# Recipe grouping derived from directory names under db/seeds/recipes/ (e.g.,
# "Bread", "Mains"). Ordered by position for homepage display. Orphaned
# categories (with no recipes) are cleaned up via .cleanup_orphans.
#
# - .find_or_create_for(kitchen, name) — canonical factory; handles slug
#   generation and position assignment. Used by write services and importer.
# - .miscellaneous(kitchen) — default fallback category for uncategorized recipes.
class Category < ApplicationRecord
  acts_as_tenant :kitchen

  has_many :recipes, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :kitchen_id, case_sensitive: false }
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }

  scope :ordered, -> { order(:position, :name) }
  scope :with_recipes, -> { where.associated(:recipes).distinct }

  def self.find_or_create_for(kitchen, name)
    slug = FamilyRecipes.slugify(name)
    kitchen.categories.find_or_create_by!(slug:) do |cat|
      cat.name = name
      cat.position = kitchen.categories.maximum(:position).to_i + 1
    end
  end

  def self.miscellaneous(kitchen)
    find_or_create_for(kitchen, 'Miscellaneous')
  end

  def self.cleanup_orphans(kitchen)
    kitchen.categories.where.missing(:recipes).destroy_all
  end

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(name)
end

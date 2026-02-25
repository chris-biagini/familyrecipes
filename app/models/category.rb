# frozen_string_literal: true

class Category < ApplicationRecord
  acts_as_tenant :kitchen

  has_many :recipes, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }

  scope :ordered, -> { order(:position, :name) }

  def self.cleanup_orphans(kitchen)
    kitchen.categories.left_joins(:recipes).where(recipes: { id: nil }).destroy_all
  end

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(name)
end

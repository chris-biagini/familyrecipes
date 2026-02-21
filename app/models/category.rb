# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :recipes, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  scope :ordered, -> { order(:position, :name) }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(name)
end

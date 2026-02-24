# frozen_string_literal: true

class Recipe < ApplicationRecord
  acts_as_tenant :kitchen
  belongs_to :category

  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps
  has_many :cross_references, through: :steps
  has_many :inbound_cross_references, class_name: 'CrossReference', foreign_key: :target_recipe_id

  def referencing_recipes
    Recipe.where(id: inbound_cross_references.joins(:step).select('steps.recipe_id')).distinct
  end

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :kitchen_id }
  validates :markdown_source, presence: true

  scope :alphabetical, -> { order(:title) }

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  def makes
    return unless makes_quantity

    unit = makes_unit_noun
    "#{makes_quantity.to_i == makes_quantity ? makes_quantity.to_i : makes_quantity} #{unit}"
  end

  private

  def generate_slug = self.slug = FamilyRecipes.slugify(title)
end

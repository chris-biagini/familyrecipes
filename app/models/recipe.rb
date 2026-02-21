# frozen_string_literal: true

class Recipe < ApplicationRecord
  belongs_to :category

  has_many :steps, -> { order(:position) }, dependent: :destroy, inverse_of: :recipe
  has_many :ingredients, through: :steps

  has_many :outbound_dependencies, class_name: 'RecipeDependency',
                                   foreign_key: :source_recipe_id,
                                   dependent: :destroy,
                                   inverse_of: :source_recipe
  has_many :inbound_dependencies, class_name: 'RecipeDependency',
                                  foreign_key: :target_recipe_id,
                                  dependent: :restrict_with_error,
                                  inverse_of: :target_recipe
  has_many :referenced_recipes, through: :outbound_dependencies, source: :target_recipe
  has_many :referencing_recipes, through: :inbound_dependencies, source: :source_recipe

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
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

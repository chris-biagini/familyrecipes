# frozen_string_literal: true

# One step within a recipe. Holds a title (nil for implicit steps), position,
# raw and processed instructions (with scalable number HTML), and ordered
# collections of Ingredients and CrossReferences. The mixed ingredient list
# is reconstructed via #ingredient_list_items for rendering.
class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps

  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step
  has_many :cross_references, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  validates :title, length: { minimum: 1 }, allow_nil: true
  validates :position, presence: true

  def cross_reference_step?
    cross_references.any?
  end

  def cross_reference_block
    cross_references.first
  end

  def ingredient_list_items
    (ingredients + cross_references).sort_by(&:position)
  end
end

# frozen_string_literal: true

class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps

  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step
  has_many :cross_references, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  validates :title, length: { minimum: 1 }, allow_nil: true
  validates :position, presence: true

  def ingredient_list_items
    (ingredients + cross_references).sort_by(&:position)
  end
end

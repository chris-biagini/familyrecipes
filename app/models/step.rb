# frozen_string_literal: true

class Step < ApplicationRecord
  belongs_to :recipe, inverse_of: :steps

  has_many :ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :step

  validates :title, presence: true
  validates :position, presence: true
end

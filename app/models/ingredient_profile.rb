# frozen_string_literal: true

class IngredientProfile < ApplicationRecord
  belongs_to :kitchen, optional: true

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, numericality: { greater_than: 0 }, allow_nil: true

  scope :global, -> { where(kitchen_id: nil) }
  scope :for_kitchen, ->(kitchen) { where(kitchen_id: kitchen.id) }

  def global? = kitchen_id.nil?
  def custom? = kitchen_id.present?

  def self.lookup_for(kitchen)
    global.index_by(&:ingredient_name)
          .merge(for_kitchen(kitchen).index_by(&:ingredient_name))
  end
end

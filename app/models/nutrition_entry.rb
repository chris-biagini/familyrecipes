# frozen_string_literal: true

class NutritionEntry < ApplicationRecord
  acts_as_tenant :kitchen

  validates :ingredient_name, presence: true, uniqueness: { scope: :kitchen_id }
  validates :basis_grams, presence: true, numericality: { greater_than: 0 }
end

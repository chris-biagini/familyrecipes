# frozen_string_literal: true

class IngredientRecord < ApplicationRecord
  self.table_name = 'ingredients'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :ingredient_records
  belongs_to :step_record, foreign_key: :step_id, optional: true, inverse_of: :ingredient_records

  validates :name, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end

# frozen_string_literal: true

class StepRecord < ApplicationRecord
  self.table_name = 'steps'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :step_records

  has_many :ingredient_records, foreign_key: :step_id, dependent: :destroy, inverse_of: :step_record
  has_many :cross_reference_records, foreign_key: :step_id, dependent: :destroy, inverse_of: :step_record

  validates :tldr, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end

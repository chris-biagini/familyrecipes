# frozen_string_literal: true

class CrossReferenceRecord < ApplicationRecord
  self.table_name = 'cross_references'

  belongs_to :recipe_record, foreign_key: :recipe_id, inverse_of: :cross_reference_records
  belongs_to :step_record, foreign_key: :step_id, inverse_of: :cross_reference_records
  belongs_to :target_recipe, class_name: 'RecipeRecord', foreign_key: :target_recipe_id,
                             inverse_of: :inbound_cross_references

  validates :position, presence: true
  validates :multiplier, presence: true

  default_scope { order(:position) }
end

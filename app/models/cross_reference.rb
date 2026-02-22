# frozen_string_literal: true

class CrossReference < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :step, inverse_of: :cross_references
  belongs_to :target_recipe, class_name: 'Recipe'

  validates :position, presence: true
  validates :position, uniqueness: { scope: :step_id }

  delegate :slug, to: :target_recipe, prefix: :target
  delegate :title, to: :target_recipe, prefix: :target
end

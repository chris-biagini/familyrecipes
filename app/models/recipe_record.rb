# frozen_string_literal: true

class RecipeRecord < ApplicationRecord
  self.table_name = 'recipes'

  has_many :step_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :ingredient_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :cross_reference_records, foreign_key: :recipe_id, dependent: :destroy, inverse_of: :recipe_record
  has_many :inbound_cross_references, class_name: 'CrossReferenceRecord',
                                      foreign_key: :target_recipe_id,
                                      dependent: :nullify,
                                      inverse_of: :target_recipe

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :category, presence: true
  validates :source_markdown, presence: true
  validates :version_hash, presence: true

  scope :full_recipes, -> { where(quick_bite: false) }
  scope :quick_bites, -> { where(quick_bite: true) }
  scope :in_category, ->(cat) { where(category: cat) }
end

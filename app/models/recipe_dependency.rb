# frozen_string_literal: true

class RecipeDependency < ApplicationRecord
  belongs_to :source_recipe, class_name: 'Recipe', inverse_of: :outbound_dependencies
  belongs_to :target_recipe, class_name: 'Recipe', inverse_of: :inbound_dependencies

  validates :target_recipe_id, uniqueness: { scope: :source_recipe_id }
end

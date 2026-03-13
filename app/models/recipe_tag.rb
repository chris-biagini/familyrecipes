# frozen_string_literal: true

# Join model linking recipes to tags. No business logic — just
# enforces the unique constraint preventing duplicate assignments.
#
# Collaborators:
# - Recipe: parent recipe
# - Tag: parent tag
class RecipeTag < ApplicationRecord
  belongs_to :recipe
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :recipe_id }
end

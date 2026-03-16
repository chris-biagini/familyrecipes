# frozen_string_literal: true

# Kitchen-scoped label for cross-cutting recipe classification.
# Tags are single-word (letters and hyphens only), stored lowercase.
# Managed via TagWriteService for bulk operations; created inline
# by RecipeWriteService during recipe saves.
#
# Collaborators:
# - RecipeTag: join model linking tags to recipes
# - RecipeWriteService: creates tags on recipe save
# - Kitchen.run_finalization: cleans up orphans after writes
# - TagWriteService: bulk rename/delete from management dialog
# - SearchDataHelper: includes tags in search JSON for pill recognition
class Tag < ApplicationRecord
  acts_as_tenant :kitchen

  has_many :recipe_tags, dependent: :destroy
  has_many :recipes, through: :recipe_tags

  validates :name, presence: true,
                   uniqueness: { scope: :kitchen_id, case_sensitive: false },
                   format: { with: /\A[a-zA-Z-]+\z/,
                             message: 'only allows letters and hyphens' }

  before_validation :downcase_name

  def self.cleanup_orphans(kitchen)
    kitchen.tags.where.missing(:recipe_tags).destroy_all
  end

  private

  def downcase_name
    self.name = name.downcase if name.present?
  end
end

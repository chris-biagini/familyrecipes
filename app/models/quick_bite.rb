# frozen_string_literal: true

# A lightweight grocery bundle — a title plus a flat ingredient list, without
# the step/instruction structure of a full Recipe. Lives within a Category
# alongside recipes on the menu page. Responds to the same duck-type interface
# as Recipe (#ingredients_with_quantities, #all_ingredient_names) so
# ShoppingListBuilder and RecipeAvailabilityCalculator can treat both uniformly.
#
# - Category (parent grouping, shared with Recipe)
# - QuickBiteIngredient (child ingredient names, ordered by position)
# - Kitchen (tenant owner)
# - MealPlanSelection (references by stringified integer PK)
class QuickBite < ApplicationRecord
  acts_as_tenant :kitchen

  belongs_to :category
  has_many :quick_bite_ingredients, -> { order(:position) }, dependent: :destroy, inverse_of: :quick_bite

  validates :title, presence: true, uniqueness: { scope: :kitchen_id }
  validates :position, presence: true

  scope :ordered, -> { order(:position) }

  def all_ingredient_names
    quick_bite_ingredients.map(&:name).uniq
  end

  def ingredients_with_quantities
    all_ingredient_names.map { |name| [name, [nil]] }
  end
end

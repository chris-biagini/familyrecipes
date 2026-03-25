# frozen_string_literal: true

# A single ingredient name within a QuickBite. Stores only a name and position
# — no quantities, units, or catalog FK. Names resolve through
# IngredientResolver at query time, same as recipe ingredients.
#
# - QuickBite (parent)
class QuickBiteIngredient < ApplicationRecord
  belongs_to :quick_bite, inverse_of: :quick_bite_ingredients

  validates :name, presence: true
  validates :position, presence: true
end

# frozen_string_literal: true

# Tracks which recipes and quick bites are currently selected on the menu page.
# Replaces the old MealPlan JSON arrays (selected_recipes, selected_quick_bites)
# with normalized rows. selectable_id stores a recipe slug for Recipe type or a
# quick bite ID for QuickBite type — not AR polymorphic references.
#
# Collaborators:
# - Kitchen (tenant owner, has_many)
# - MealPlanWriteService (toggle selections via controller actions)
# - ShoppingListBuilder (reads selected items to compute grocery list)
class MealPlanSelection < ApplicationRecord
  acts_as_tenant :kitchen

  validates :selectable_type, inclusion: { in: %w[Recipe QuickBite] }
  validates :selectable_id, uniqueness: { scope: %i[kitchen_id selectable_type] }

  scope :recipes, -> { where(selectable_type: 'Recipe') }
  scope :quick_bites, -> { where(selectable_type: 'QuickBite') }

  def self.recipe_slugs_for(kitchen)
    ActsAsTenant.with_tenant(kitchen) { recipes.pluck(:selectable_id) }
  end

  def self.quick_bite_ids_for(kitchen)
    ActsAsTenant.with_tenant(kitchen) { quick_bites.pluck(:selectable_id) }
  end

  def self.toggle(kitchen:, type:, id:, selected:)
    scope = ActsAsTenant.with_tenant(kitchen) { where(selectable_type: type, selectable_id: id) }

    if selected
      scope.first_or_create!
    else
      scope.delete_all
    end
  end

  def self.prune_stale!(kitchen:, valid_recipe_slugs:, valid_qb_ids:)
    ActsAsTenant.with_tenant(kitchen) do
      recipes.where.not(selectable_id: valid_recipe_slugs).delete_all
      quick_bites.where.not(selectable_id: valid_qb_ids).delete_all
    end
  end
end

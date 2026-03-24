# frozen_string_literal: true

# Singleton-per-kitchen record that anchors meal planning. Formerly a monolith
# holding all grocery/menu state in a JSON blob; now a thin coordinator that
# delegates to four normalized AR models: MealPlanSelection, OnHandEntry,
# CustomGroceryItem, and CookHistoryEntry.
#
# Collaborators:
# - Kitchen (tenant owner, belongs_to)
# - MealPlanSelection (selected recipes and quick bites)
# - OnHandEntry (per-ingredient SM-2 adaptive tracking)
# - CustomGroceryItem (user-added non-recipe grocery items)
# - CookHistoryEntry (append-only cook event log)
class MealPlan < ApplicationRecord
  acts_as_tenant :kitchen

  validates :kitchen_id, uniqueness: true

  def self.for_kitchen(kitchen)
    find_or_create_by!(kitchen: kitchen)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(kitchen: kitchen)
  end

  def selected_recipes
    MealPlanSelection.where(kitchen_id: kitchen_id).recipes.pluck(:selectable_id)
  end

  def selected_quick_bites
    MealPlanSelection.where(kitchen_id: kitchen_id).quick_bites.pluck(:selectable_id)
  end
end

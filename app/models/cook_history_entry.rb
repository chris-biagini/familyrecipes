# frozen_string_literal: true

# Append-only log of when recipes were cooked. Each entry records a single cook
# event (recipe_slug + cooked_at). Used by CookHistoryWeighter to deprioritize
# recently cooked recipes in the dinner picker via quadratic recency decay.
# Entries older than WINDOW days are irrelevant and prunable.
#
# Collaborators:
# - Kitchen (tenant owner, has_many)
# - CookHistoryWeighter (reads recent entries for decay scoring)
# - MealPlanWriteService (records cook events on menu interactions)
class CookHistoryEntry < ApplicationRecord
  WINDOW = 90

  acts_as_tenant :kitchen

  scope :recent, ->(now: Time.current) { where('cooked_at > ?', now - WINDOW.days) }

  def self.record(kitchen:, recipe_slug:)
    create!(kitchen: kitchen, recipe_slug: recipe_slug, cooked_at: Time.current)
  end

  def self.prune!(kitchen:)
    ActsAsTenant.with_tenant(kitchen) { where('cooked_at <= ?', Time.current - WINDOW.days).delete_all }
  end
end

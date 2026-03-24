# frozen_string_literal: true

# User-added grocery items that don't come from recipes (e.g. paper towels,
# cleaning supplies). Scoped per-kitchen via acts_as_tenant. Names use NOCASE
# collation for case-insensitive uniqueness at the DB level.
#
# - Kitchen: tenant owner (has_many :custom_grocery_items)
# - ShoppingListBuilder: includes visible custom items in grocery output
# - MealPlanWriteService: manages lifecycle (add, mark on-hand, prune stale)
#
# on_hand_at tracks when the item was marked as "on hand" — nil means needed.
# Stale items (unused for RETENTION days) are candidates for cleanup.
class CustomGroceryItem < ApplicationRecord
  MAX_NAME_LENGTH = 100
  RETENTION = 45

  acts_as_tenant :kitchen

  validates :name, presence: true,
                   length: { maximum: MAX_NAME_LENGTH },
                   uniqueness: { scope: :kitchen_id, case_sensitive: false }

  scope :visible, ->(now: Date.current) { where('on_hand_at IS NULL OR on_hand_at >= ?', now) }
  scope :stale, ->(cutoff:) { where('last_used_at < ?', cutoff) }
end

# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items), select-all, and clear. Owns optimistic-locking retry
# for MealPlan state changes. Post-write finalization (reconciliation,
# broadcast) is handled by Kitchen.finalize_writes.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - Kitchen.finalize_writes: centralized post-write finalization
class MealPlanWriteService
  def self.apply_action(kitchen:, action_type:, **params)
    new(kitchen:).apply_action(action_type:, **params)
  end

  def self.select_all(kitchen:, recipe_slugs:, quick_bite_slugs:)
    new(kitchen:).select_all(recipe_slugs:, quick_bite_slugs:)
  end

  def self.clear(kitchen:)
    new(kitchen:).clear
  end

  def initialize(kitchen:)
    @kitchen = kitchen
  end

  def apply_action(action_type:, **params)
    mutate_plan { |plan| plan.apply_action(action_type, **params) }
    Kitchen.finalize_writes(kitchen)
  end

  def select_all(recipe_slugs:, quick_bite_slugs:)
    mutate_plan { |plan| plan.select_all!(recipe_slugs, quick_bite_slugs) }
    Kitchen.finalize_writes(kitchen)
  end

  def clear
    mutate_plan(&:clear_selections!)
    Kitchen.finalize_writes(kitchen)
  end

  private

  attr_reader :kitchen

  def mutate_plan
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end
end

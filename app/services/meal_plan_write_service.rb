# frozen_string_literal: true

# Orchestrates all direct MealPlan mutations: action application (select,
# check, custom items), select-all, clear, and standalone reconciliation.
# Owns optimistic-locking retry, reconciliation of stale state, and
# Kitchen#broadcast_update — controllers never call these directly.
#
# - MealPlan: singleton-per-kitchen JSON state record
# - MealPlan#reconcile!: prunes stale selections and checked-off items
# - Kitchen#broadcast_update: page-refresh morph for all connected clients
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
    mutate_plan do |plan|
      plan.apply_action(action_type, **params)
      reconcile_plan(plan) unless Kitchen.batching?
    end
    finalize
  end

  def select_all(recipe_slugs:, quick_bite_slugs:)
    mutate_plan do |plan|
      plan.select_all!(recipe_slugs, quick_bite_slugs)
      reconcile_plan(plan) unless Kitchen.batching?
    end
    finalize
  end

  def clear
    mutate_plan do |plan|
      plan.clear_selections!
      reconcile_plan(plan) unless Kitchen.batching?
    end
    finalize
  end

  def reconcile
    return if Kitchen.batching?

    MealPlan.reconcile_kitchen!(kitchen)
    kitchen.broadcast_update
  end

  private

  attr_reader :kitchen

  def finalize
    return if Kitchen.batching?

    kitchen.broadcast_update
  end

  def reconcile_plan(plan)
    visible = ShoppingListBuilder.new(kitchen:, meal_plan: plan).visible_names
    plan.reconcile!(visible_names: visible)
  end

  def mutate_plan
    plan = MealPlan.for_kitchen(kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end
end

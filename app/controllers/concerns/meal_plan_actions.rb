# frozen_string_literal: true

# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry with a common StaleObjectError handler.
# Every mutation is followed by MealPlan#reconcile! to prune stale state.
# Used by MenuController and GroceriesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def mutate_plan
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry { yield plan }
    plan
  end

  def apply_plan(action_type, **action_params)
    mutate_plan do |plan|
      plan.apply_action(action_type, **action_params)
      plan.reconcile!
    end
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end

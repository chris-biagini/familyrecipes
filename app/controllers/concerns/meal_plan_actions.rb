# frozen_string_literal: true

# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry, a common StaleObjectError handler, and a
# page-refresh broadcast for cross-device sync via Turbo.
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
      prune_if_deselect(action_type, action_params)
    end
  end

  def prune_if_deselect(action_type, action_params)
    return unless action_type == 'select'
    return if MealPlan.truthy?(action_params[:selected])

    MealPlan.prune_stale_items(kitchen: current_kitchen)
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end

  def broadcast_meal_plan_refresh
    MealPlan.broadcast_refresh(current_kitchen)
  end
end

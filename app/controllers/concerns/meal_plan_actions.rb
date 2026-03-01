# frozen_string_literal: true

# Shared meal-plan mutation helpers for controllers that modify MealPlan state.
# Provides optimistic-locking retry with version broadcasting and a common
# StaleObjectError handler. Used by MenuController, GroceriesController, and
# RecipesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def apply_and_respond(action_type, **action_params)
    plan = MealPlan.for_kitchen(current_kitchen)
    plan.with_optimistic_retry do
      plan.apply_action(action_type, **action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end

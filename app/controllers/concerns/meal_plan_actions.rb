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
      prune_if_deselect(plan, action_type, action_params)
    end
    MealPlanChannel.broadcast_version(current_kitchen, plan.lock_version)
    render json: { version: plan.lock_version }
  end

  def build_visible_names(meal_plan)
    shopping_list = ShoppingListBuilder.new(kitchen: current_kitchen, meal_plan: meal_plan).build
    names = shopping_list.each_value.flat_map { |items| items.map { |i| i[:name] } }
    Set.new(names)
  end

  def prune_if_deselect(plan, action_type, action_params)
    return unless action_type == 'select'
    return if [true, 'true'].include?(action_params[:selected])

    plan.prune_checked_off(visible_names: build_visible_names(plan))
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end

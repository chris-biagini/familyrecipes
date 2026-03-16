# frozen_string_literal: true

# Shared helpers for controllers whose write paths pass through
# MealPlanWriteService: param coercion (truthy_param?) and
# StaleObjectError rescue when optimistic-locking retries are exhausted.
# Used by MenuController and GroceriesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def truthy_param?(value)
    [true, 'true'].include?(value)
  end

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end

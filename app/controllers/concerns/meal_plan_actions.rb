# frozen_string_literal: true

# Provides StaleObjectError handling for controllers whose write paths pass
# through MealPlanWriteService. The service uses optimistic-locking retry
# internally, but if retries are exhausted the exception bubbles up here.
# Used by MenuController and GroceriesController.
module MealPlanActions
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::StaleObjectError, with: :handle_stale_record
  end

  private

  def handle_stale_record
    render json: { error: 'Meal plan was modified by another request. Please refresh.' },
           status: :conflict
  end
end

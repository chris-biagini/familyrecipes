# frozen_string_literal: true

# Abstract base for async jobs. RecipeNutritionJob and CascadeNutritionJob
# inherit from this to recalculate nutrition data after imports and edits.
class ApplicationJob < ActiveJob::Base
end

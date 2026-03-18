# frozen_string_literal: true

# Pure-function service that converts cook history events into per-recipe
# recency weights for the dinner picker. Uses a quadratic decay curve over
# the MealPlan cook history window so recently/frequently cooked recipes
# are less likely to be suggested.
#
# Formula: weight = 1 / (1 + Σ ((window - days_ago) / window)²)
#
# - MealPlan: provides cook_history array and COOK_HISTORY_WINDOW constant
# - dinner_picker_controller.js: consumes the weights as a JSON data attribute
class CookHistoryWeighter
  def self.call(cook_history)
    new(cook_history).call
  end

  def initialize(cook_history)
    @cook_history = cook_history
  end

  def call
    penalty_sums = compute_penalty_sums
    penalty_sums.transform_values { |sum| 1.0 / (1.0 + sum) }
  end

  private

  attr_reader :cook_history

  def compute_penalty_sums
    window = MealPlan::COOK_HISTORY_WINDOW.to_f

    cook_history.each_with_object(Hash.new(0.0)) do |entry, sums|
      days_ago = (Time.current.to_date - Date.parse(entry['at'])).to_f
      next if days_ago >= window

      contribution = ((window - days_ago) / window)**2
      sums[entry['slug']] += contribution
    end
  end
end

# frozen_string_literal: true

# Numeric display helper used by recipe and nutrition views. Strips trailing
# ".0" from whole-number floats so quantities display as clean integers.
# Consumed by RecipesHelper, IngredientsHelper, and recipe partials.
module ApplicationHelper
  def format_numeric(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end

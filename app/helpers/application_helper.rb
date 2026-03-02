# frozen_string_literal: true

# Shared view helpers available across all controllers and views.
module ApplicationHelper
  def format_numeric(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end

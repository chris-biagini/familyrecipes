# frozen_string_literal: true

# Top-level module for the nutrition catalog TUI — a standalone terminal
# application for managing ingredient-catalog.yaml. Provides data I/O,
# USDA modifier classification, and (eventually) Ratatui-based screens.
# Not loaded by Rails; used exclusively by bin/nutrition.
module NutritionTui
end

require_relative 'nutrition_tui/data'

# frozen_string_literal: true

# Top-level module for the nutrition catalog TUI -- a standalone terminal
# application for managing ingredient-catalog.yaml. Provides data I/O,
# USDA modifier classification, and Ratatui-based screens for browsing,
# editing, and USDA search. Not loaded by Rails; used exclusively by bin/nutrition.
module NutritionTui
end

require_relative 'nutrition_tui/data'
require_relative 'nutrition_tui/editors/text_input'
require_relative 'nutrition_tui/editors/nutrients_editor'
require_relative 'nutrition_tui/editors/density_editor'
require_relative 'nutrition_tui/editors/portions_editor'
require_relative 'nutrition_tui/editors/aisle_editor'
require_relative 'nutrition_tui/editors/aliases_editor'
require_relative 'nutrition_tui/editors/sources_editor'
require_relative 'nutrition_tui/screens/dashboard'
require_relative 'nutrition_tui/screens/ingredient'
require_relative 'nutrition_tui/screens/usda_search'
require_relative 'nutrition_tui/app'

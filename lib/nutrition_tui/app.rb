# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  # Manages the ratatui terminal lifecycle for the nutrition catalog TUI.
  # Owns the event loop: init terminal, draw the current screen, poll for
  # input, delegate to the active screen, and restore terminal on exit.
  # Screen objects implement render(frame) and handle_event(event); this class
  # dispatches returned action hashes to navigate between screens.
  #
  # Collaborators:
  # - RatatuiRuby (terminal init/restore, draw, poll_event)
  # - NutritionTui::Data (nutrition catalog and recipe context loading)
  # - NutritionTui::Screens::Dashboard (main screen)
  class App
    def initialize
      @running = true
      @nutrition_data = Data.load_nutrition_data
      @ctx = Data.load_context
      @current_screen = Screens::Dashboard.new(nutrition_data: @nutrition_data, ctx: @ctx)
    end

    def run
      RatatuiRuby.run do |tui|
        while @running
          tui.draw { |frame| @current_screen.render(frame) }
          dispatch(tui.poll_event(timeout: 0.05))
        end
      end
    end

    private

    def dispatch(event)
      result = @current_screen.handle_event(event)
      return unless result

      handle_action(result)
    end

    def handle_action(result)
      case result
      in { action: :quit }
        @running = false
      else
        nil
      end
    end
  end
end

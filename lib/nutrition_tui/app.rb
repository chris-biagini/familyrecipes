# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  # Manages the ratatui terminal lifecycle for the nutrition catalog TUI.
  # Owns the event loop: init terminal, draw the current screen, poll for
  # input, delegate to the active screen, and restore terminal on exit.
  # All screen objects will receive the TUI facade and app state; this class
  # just orchestrates the loop.
  #
  # Collaborators:
  # - RatatuiRuby (terminal init/restore, draw, poll_event)
  # - NutritionTui::Data (nutrition catalog and recipe context loading)
  # - Screen classes (future — render + handle_event per screen)
  class App
    Widgets = RatatuiRuby::Widgets

    def initialize
      @running = true
      @nutrition_data = Data.load_nutrition_data
      @ctx = Data.load_context
    end

    def run
      RatatuiRuby.run do |tui|
        while @running
          tui.draw { |frame| render(frame) }
          handle_event(tui.poll_event(timeout: 0.05))
        end
      end
    end

    private

    def render(frame)
      paragraph = Widgets::Paragraph.new(
        text: 'Nutrition TUI — press q to quit',
        block: Widgets::Block.new(title: 'Nutrition Catalog', borders: [:all]),
        alignment: :center
      )
      frame.render_widget(paragraph, frame.area)
    end

    def handle_event(event)
      case event
      in { type: :key, code: 'q' }
        @running = false
      else
        # no-op
      end
    end
  end
end

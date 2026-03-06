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
  # - NutritionTui::Screens::Ingredient (ingredient detail screen)
  # - NutritionTui::Screens::UsdaSearch (USDA FoodData Central search)
  class App
    def initialize(jump_to: nil)
      @running = true
      @nutrition_data = Data.load_nutrition_data
      @ctx = Data.load_context
      @api_key = FamilyRecipes::UsdaClient.load_api_key(project_root: NutritionTui::Data::PROJECT_ROOT)
      @screen_stack = []
      @current_screen = initial_screen(jump_to)
    end

    def run
      RatatuiRuby.run do |tui|
        disable_mouse_reporting
        while @running
          tui.draw { |frame| @current_screen.render(frame) }
          dispatch(tui.poll_event(timeout: 0.05))
        end
      end
    end

    private

    # X10 (1000), button-event (1002), any-event (1003), SGR extended (1006)
    def disable_mouse_reporting
      $stdout.write("\e[?1000l\e[?1002l\e[?1003l\e[?1006l") # rubocop:disable Rails/Output
      $stdout.flush
    end

    def dispatch(event)
      result = @current_screen.handle_event(event)
      return unless result

      handle_action(result)
    end

    def handle_action(result) # rubocop:disable Metrics/MethodLength
      case result
      in { action: :quit }
        @running = false
      in { action: :open_ingredient, name: }
        open_ingredient(name)
      in { action: :usda_search }
        open_usda_search
      in { action: :usda_import, name: }
        open_usda_search(default_query: name)
      in { action: :import_complete, detail: }
        apply_import(detail)
      in { action: :back }
        switch_to_dashboard
      else
        nil
      end
    end

    def initial_screen(jump_to)
      return Screens::Dashboard.new(nutrition_data: @nutrition_data, ctx: @ctx) unless jump_to

      Screens::Ingredient.new(
        name: jump_to, entry: @nutrition_data[jump_to],
        nutrition_data: @nutrition_data, ctx: @ctx
      )
    end

    def open_ingredient(name)
      entry = @nutrition_data[name]
      @screen_stack.push(@current_screen)
      @current_screen = Screens::Ingredient.new(
        name: name, entry: entry,
        nutrition_data: @nutrition_data, ctx: @ctx
      )
    end

    def open_usda_search(default_query: '')
      return unless @api_key

      @screen_stack.push(@current_screen)
      @current_screen = Screens::UsdaSearch.new(api_key: @api_key, default_query: default_query)
    end

    def apply_import(detail)
      previous = @screen_stack.last
      if previous.is_a?(Screens::Ingredient)
        @current_screen = @screen_stack.pop
        @current_screen.apply_usda_import(detail)
      else
        switch_to_dashboard
      end
    end

    def switch_to_dashboard
      dashboard = @screen_stack.reverse.find { |s| s.is_a?(Screens::Dashboard) }
      @screen_stack.clear
      if dashboard
        @current_screen = dashboard
        @current_screen.refresh_data
      else
        @current_screen = Screens::Dashboard.new(nutrition_data: @nutrition_data, ctx: @ctx)
      end
    end
  end
end

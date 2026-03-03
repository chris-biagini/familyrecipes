# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Screens
    # USDA FoodData Central search screen -- lets the user type a query,
    # browse paginated results with nutrient previews, and select an item
    # for detail fetch. Returns an :import_complete action with the full
    # nutrient/portion data, or :back to cancel.
    #
    # Collaborators:
    # - FamilyRecipes::UsdaClient (HTTP search + detail fetch)
    # - NutritionTui::Editors::TextInput (query entry)
    # - NutritionTui::App (delegates render + handle_event here)
    class UsdaSearch # rubocop:disable Metrics/ClassLength
      Layout = RatatuiRuby::Layout
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(api_key:, default_query: '')
        @client = FamilyRecipes::UsdaClient.new(api_key: api_key)
        @text_input = Editors::TextInput.new(label: 'Search USDA', default: default_query)
        @state = :input
        @results = nil
        @selected = 0
        @page = 0
        @error = nil
      end

      def render(frame)
        chunks = split_layout(frame.area)
        render_search_bar(frame, chunks[0])
        render_body(frame, chunks[1])
        render_keybind_bar(frame, chunks[2])
      end

      def handle_event(event)
        return unless event

        case @state
        when :input then handle_input(event)
        when :results then handle_results(event)
        end
      end

      private

      def split_layout(area)
        Layout::Layout.split(
          area,
          direction: :vertical,
          constraints: [
            Layout::Constraint.length(3),
            Layout::Constraint.min(5),
            Layout::Constraint.length(1)
          ]
        )
      end

      # --- Search bar ---

      def render_search_bar(frame, area)
        @text_input.render(frame, area)
      end

      # --- Body ---

      def render_body(frame, area)
        text = body_text
        paragraph = Widgets::Paragraph.new(
          text: text,
          block: Widgets::Block.new(title: body_title, borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def body_title
        return 'USDA Search' unless @results

        "Page #{@results[:current_page] + 1} of #{@results[:total_pages]} " \
          "(#{@results[:total_hits]} results)"
      end

      def body_text
        case @state
        when :input    then input_body_text
        when :loading  then 'Searching...'
        when :fetching then 'Fetching detail...'
        when :results  then results_body_text
        end
      end

      def input_body_text
        @error ? "Error: #{@error}\n\nType a query and press Enter." : 'Type a query and press Enter to search.'
      end

      def results_body_text
        return 'No results found.' if @results[:foods].empty?

        @results[:foods].each_with_index.map { |food, i| format_food_item(food, i) }.join("\n")
      end

      def format_food_item(food, index)
        pointer = index == @selected ? '> ' : '  '
        summary = food[:nutrient_summary]
        "#{pointer}#{food[:description]}\n    #{summary}"
      end

      # --- Keybind bar ---

      def render_keybind_bar(frame, area)
        text = keybind_text
        paragraph = Widgets::Paragraph.new(
          text: " #{text}",
          style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
        )
        frame.render_widget(paragraph, area)
      end

      def keybind_text
        case @state
        when :input
          'Enter search  Esc cancel'
        when :results
          'Up/Down navigate  [ prev  ] next  Enter select  Esc back'
        else
          ''
        end
      end

      # --- Input event handling ---

      def handle_input(event)
        result = @text_input.handle_event(event)
        return unless result&.dig(:done)

        result[:cancelled] ? { action: :back } : execute_search
      end

      # --- Results event handling ---

      def handle_results(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'Escape' }
          return_to_input
        in { type: :key, code: 'Down' | 'j' }
          move_selection(1)
        in { type: :key, code: 'Up' | 'k' }
          move_selection(-1)
        in { type: :key, code: '[' }
          previous_page
        in { type: :key, code: ']' }
          next_page
        in { type: :key, code: 'Enter' }
          fetch_selected
        else
          nil
        end
      end

      # --- Navigation ---

      def move_selection(delta)
        return if @results[:foods].empty?

        @selected = (@selected + delta).clamp(0, @results[:foods].size - 1)
        nil
      end

      def return_to_input
        @state = :input
        @error = nil
        nil
      end

      def previous_page
        return nil if @page.zero?

        @page -= 1
        execute_search
      end

      def next_page
        return nil if @page + 1 >= @results[:total_pages]

        @page += 1
        execute_search
      end

      # --- API calls ---

      def execute_search
        @state = :loading
        @results = @client.search(@text_input.value, page: @page)
        @selected = 0
        @state = :results
        nil
      rescue FamilyRecipes::UsdaClient::Error => error
        @error = error.message
        @state = :input
        nil
      end

      def fetch_selected
        return nil if @results[:foods].empty?

        food = @results[:foods][@selected]
        @state = :fetching
        detail = @client.fetch(fdc_id: food[:fdc_id])
        { action: :import_complete, detail: detail }
      rescue FamilyRecipes::UsdaClient::Error => error
        @error = error.message
        @state = :input
        nil
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

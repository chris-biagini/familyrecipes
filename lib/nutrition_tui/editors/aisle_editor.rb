# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for an ingredient's grocery aisle assignment. Collects
    # unique aisle values from the full catalog as a pick-list, plus an
    # "Other..." option that opens a TextInput for custom entry.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (custom aisle entry)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class AisleEditor
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(nutrition_data:, current_aisle: nil)
        @aisles = build_aisle_list(nutrition_data)
        @selected = @aisles.index(current_aisle) || 0
        @text_input = nil
      end

      def handle_event(event)
        @text_input ? handle_text_input(event) : handle_list(event)
      end

      def render(frame, area)
        if @text_input
          frame.render_widget(Widgets::Clear.new, area)
          @text_input.render(frame, area)
        else
          render_list(frame, area)
        end
      end

      private

      def build_aisle_list(nutrition_data)
        aisles = nutrition_data.values.filter_map { |e| e['aisle'] }.uniq.sort
        aisles << 'Other...'
        aisles
      end

      def handle_list(event)
        case event
        in { type: :key, code: 'Escape' }
          { done: true, cancelled: true }
        in { type: :key, code: 'Up' | 'k' }
          @selected = (@selected - 1).clamp(0, @aisles.size - 1)
          nil
        in { type: :key, code: 'Down' | 'j' }
          @selected = (@selected + 1).clamp(0, @aisles.size - 1)
          nil
        in { type: :key, code: 'Enter' }
          select_aisle
        else
          nil
        end
      end

      def select_aisle
        choice = @aisles[@selected]
        if choice == 'Other...'
          @text_input = TextInput.new(label: 'Aisle')
          nil
        else
          { done: true, value: choice }
        end
      end

      def handle_text_input(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)

        if result[:cancelled]
          @text_input = nil
          nil
        else
          { done: true, value: result[:value].strip }
        end
      end

      def render_list(frame, area)
        list = Widgets::List.new(
          items: @aisles,
          selected_index: @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Aisle', borders: [:all])
        )
        frame.render_widget(list, area)
      end
    end
  end
end

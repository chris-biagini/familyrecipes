# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for all nutrient values on an ingredient. Shows the full
    # nutrient list with Up/Down navigation; Enter opens a TextInput to edit
    # the selected nutrient's value. Escape from selection mode returns the
    # modified entry.
    #
    # Collaborators:
    # - NutritionTui::Data (NUTRIENTS constant for labels and keys)
    # - NutritionTui::Editors::TextInput (inline value editing)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class NutrientsEditor
      Layout = RatatuiRuby::Layout
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(entry:)
        @entry = entry
        @entry['nutrients'] ||= {}
        @selected = 0
        @text_input = nil
      end

      def handle_event(event)
        @text_input ? handle_editing(event) : handle_selecting(event)
      end

      def render(frame, area)
        items = nutrient_display_lines
        list = Widgets::List.new(
          items: items,
          selected_index: @text_input ? nil : @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Edit Nutrients', borders: [:all])
        )
        frame.render_widget(list, area)
        render_text_input(frame, area) if @text_input
      end

      private

      def handle_selecting(event)
        case event
        in { type: :key, code: 'Escape' }
          { done: true, entry: @entry }
        in { type: :key, code: 'Up' | 'k' }
          @selected = (@selected - 1).clamp(0, Data::NUTRIENTS.size - 1)
          nil
        in { type: :key, code: 'Down' | 'j' }
          @selected = (@selected + 1).clamp(0, Data::NUTRIENTS.size - 1)
          nil
        in { type: :key, code: 'Enter' }
          open_text_input
        else
          nil
        end
      end

      def handle_editing(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)

        apply_edit(result) unless result[:cancelled]
        @text_input = nil
        nil
      end

      def open_text_input
        nutrient = Data::NUTRIENTS[@selected]
        current = @entry['nutrients'][nutrient[:key]]
        @text_input = TextInput.new(label: nutrient[:label], default: current || '')
        nil
      end

      def apply_edit(result)
        nutrient = Data::NUTRIENTS[@selected]
        parsed = Float(result[:value], exception: false)
        if parsed
          @entry['nutrients'][nutrient[:key]] = parsed
        elsif result[:value].strip.empty?
          @entry['nutrients'].delete(nutrient[:key])
        end
      end

      def nutrient_display_lines
        Data::NUTRIENTS.map do |n|
          indent = '  ' * n[:indent]
          value = @entry['nutrients'][n[:key]]
          formatted = value ? format_number(value) : "\u2014"
          suffix = n[:unit].empty? ? '' : " #{n[:unit]}"
          "#{indent}#{n[:label].ljust(20 - (n[:indent] * 2))}#{formatted}#{suffix}"
        end
      end

      def render_text_input(frame, area)
        input_area = Layout::Rect.new(
          x: area.x + 2,
          y: area.bottom - 3,
          width: [area.width - 4, 30].max,
          height: 3
        )
        frame.render_widget(Widgets::Clear.new, input_area)
        @text_input.render(frame, input_area)
      end

      def format_number(value)
        return "\u2014" unless value.is_a?(Numeric)
        return value.to_i.to_s if value == value.to_i

        value.round(1).to_s
      end
    end
  end
end

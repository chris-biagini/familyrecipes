# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for all nutrient values on an ingredient. Shows basis_grams
    # as the first field, then the 11 nutrient fields with Up/Down navigation.
    # Enter opens a TextInput to edit the selected value. Escape returns the
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

      BASIS_FIELD = { key: 'basis_grams', label: 'Per (grams)', unit: '', indent: 0 }.freeze

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
        list = Widgets::List.new(
          items: display_lines,
          selected_index: @text_input ? nil : @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Edit Nutrients', borders: [:all], border_type: :rounded)
        )
        frame.render_widget(list, area)
        render_text_input(frame, area) if @text_input
      end

      private

      def item_count
        Data::NUTRIENTS.size + 1
      end

      def selected_field
        @selected.zero? ? BASIS_FIELD : Data::NUTRIENTS[@selected - 1]
      end

      def handle_selecting(event)
        case event
        in { type: :key, code: 'esc' }
          { done: true, entry: @entry }
        in { type: :key, code: 'up' | 'k' }
          @selected = (@selected - 1).clamp(0, item_count - 1)
          nil
        in { type: :key, code: 'down' | 'j' }
          @selected = (@selected + 1).clamp(0, item_count - 1)
          nil
        in { type: :key, code: 'enter' }
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
        field = selected_field
        current = @entry['nutrients'][field[:key]]
        @text_input = TextInput.new(label: field[:label], default: current || '')
        nil
      end

      def apply_edit(result)
        field = selected_field
        parsed = Float(result[:value], exception: false)
        if parsed
          @entry['nutrients'][field[:key]] = parsed
        elsif result[:value].strip.empty?
          @entry['nutrients'].delete(field[:key])
        end
      end

      def display_lines
        [format_basis_line, ''] + Data::NUTRIENTS.map { |n| format_nutrient_line(n) }
      end

      def format_basis_line
        value = @entry['nutrients']['basis_grams'] || 100
        "#{BASIS_FIELD[:label].ljust(20)}#{format_number(value)}g"
      end

      def format_nutrient_line(nutrient)
        indent = '  ' * nutrient[:indent]
        value = @entry['nutrients'][nutrient[:key]]
        formatted = value ? format_number(value) : "\u2014"
        suffix = nutrient[:unit].empty? ? '' : " #{nutrient[:unit]}"
        "#{indent}#{nutrient[:label].ljust(20 - (nutrient[:indent] * 2))}#{formatted}#{suffix}"
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

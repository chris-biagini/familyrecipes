# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for ingredient density (grams-per-volume conversion).
    # Shows all three density fields (grams, volume, unit) plus a "Remove
    # density" action as a navigable list. Enter opens an inline TextInput
    # for the selected field. Escape returns the modified entry.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (inline value editing)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class DensityEditor
      Layout = RatatuiRuby::Layout
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      FIELDS = [
        { key: 'grams', label: 'Grams' },
        { key: 'volume', label: 'Volume' },
        { key: 'unit', label: 'Unit' }
      ].freeze

      REMOVE_INDEX = FIELDS.size
      ITEM_COUNT = FIELDS.size + 1

      def initialize(entry:)
        @entry = entry
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
          block: Widgets::Block.new(title: 'Edit Density', borders: [:all])
        )
        frame.render_widget(list, area)
        render_text_input(frame, area) if @text_input
      end

      private

      def handle_selecting(event)
        case event
        in { type: :key, code: 'esc' }
          { done: true, entry: @entry }
        in { type: :key, code: 'up' | 'k' }
          @selected = (@selected - 1).clamp(0, ITEM_COUNT - 1)
          nil
        in { type: :key, code: 'down' | 'j' }
          @selected = (@selected + 1).clamp(0, ITEM_COUNT - 1)
          nil
        in { type: :key, code: 'enter' }
          activate_selected
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

      def activate_selected
        return remove_density if @selected == REMOVE_INDEX

        open_text_input
      end

      def open_text_input
        field = FIELDS[@selected]
        current = @entry.dig('density', field[:key])
        @text_input = TextInput.new(label: field[:label], default: current || '')
        nil
      end

      def remove_density
        @entry.delete('density')
        { done: true, entry: @entry }
      end

      def apply_edit(result)
        field = FIELDS[@selected]
        @entry['density'] ||= {}

        if field[:key] == 'unit'
          apply_unit_edit(result[:value])
        else
          apply_numeric_edit(field[:key], result[:value])
        end
      end

      def apply_unit_edit(value)
        stripped = value.strip
        return if stripped.empty?

        @entry['density']['unit'] = stripped
      end

      def apply_numeric_edit(key, value)
        parsed = Float(value, exception: false)
        return unless parsed

        @entry['density'][key] = parsed
      end

      def display_lines
        field_lines = FIELDS.map do |f|
          value = @entry.dig('density', f[:key])
          formatted = value ? format_value(value) : "\u2014"
          "#{f[:label].ljust(20)}#{formatted}"
        end
        field_lines + ['Remove density']
      end

      def format_value(value)
        return value.to_s unless value.is_a?(Numeric)
        return value.to_i.to_s if value == value.to_i

        value.round(2).to_s
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
    end
  end
end

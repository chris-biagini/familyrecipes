# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Reusable single-line text input with cursor, used by all editors that
    # need free-text entry (nutrient values, portion names, aisle names, etc.).
    # Returns `{ done: true, value: }` on Enter, `{ done: true, cancelled: true }`
    # on Escape, or nil for internal keystrokes.
    #
    # Collaborators:
    # - NutritionTui::Editors::NutrientsEditor (inline value editing)
    # - NutritionTui::Editors::DensityEditor (grams/volume/unit entry)
    # - NutritionTui::Editors::PortionsEditor (name/grams entry)
    # - NutritionTui::Editors::AisleEditor (custom aisle entry)
    # - NutritionTui::Editors::AliasesEditor (alias name entry)
    # - NutritionTui::Editors::SourcesEditor (source field entry)
    class TextInput
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      attr_reader :value, :label

      def initialize(label:, default: '')
        @label = label
        @value = default.to_s
        @cursor = @value.size
      end

      def handle_event(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'enter' }
          { done: true, value: @value }
        in { type: :key, code: 'esc' }
          { done: true, cancelled: true }
        in { type: :key, code: 'backspace' }
          delete_char
        in { type: :key, code: 'left' }
          move_cursor(-1)
        in { type: :key, code: 'right' }
          move_cursor(1)
        in { type: :key, code: /\A.\z/ => char }
          insert_char(char)
        else
          nil
        end
      end

      def render(frame, area)
        display = "#{@label}: #{display_value}"
        paragraph = Widgets::Paragraph.new(
          text: display,
          block: Widgets::Block.new(borders: [:all], border_type: :rounded),
          style: Style::Style.new(fg: :white)
        )
        frame.render_widget(paragraph, area)
      end

      private

      def display_value
        before = @value[0...@cursor]
        cursor_char = @value[@cursor] || ' '
        after = @value[(@cursor + 1)..] || ''
        "#{before}\u2588#{cursor_char}#{after}"
      end

      def delete_char
        return nil if @cursor.zero?

        @value = @value[0...(@cursor - 1)] + @value[@cursor..]
        @cursor -= 1
        nil
      end

      def insert_char(char)
        @value = @value[0...@cursor] + char + @value[@cursor..]
        @cursor += 1
        nil
      end

      def move_cursor(delta)
        @cursor = (@cursor + delta).clamp(0, @value.size)
        nil
      end
    end
  end
end

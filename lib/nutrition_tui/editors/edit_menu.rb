# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Sub-menu overlay for choosing which aspect of an ingredient to edit
    # (nutrients, density, or portions). Triggered by pressing 'e' on the
    # ingredient detail screen, returns `{ done: true, choice: :symbol }`.
    #
    # Collaborators:
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class EditMenu
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      OPTIONS = %w[Nutrients Density Portions].freeze

      def initialize
        @selected = 0
      end

      def handle_event(event)
        case event
        in { type: :key, code: 'up' | 'k' }
          @selected = (@selected - 1).clamp(0, OPTIONS.size - 1)
          nil
        in { type: :key, code: 'down' | 'j' }
          @selected = (@selected + 1).clamp(0, OPTIONS.size - 1)
          nil
        in { type: :key, code: 'enter' }
          { done: true, choice: OPTIONS[@selected].downcase.to_sym }
        in { type: :key, code: 'esc' }
          { done: true, cancelled: true }
        else
          nil
        end
      end

      def render(frame, area)
        list = Widgets::List.new(
          items: OPTIONS,
          selected_index: @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Edit', borders: [:all])
        )
        frame.render_widget(list, area)
      end
    end
  end
end

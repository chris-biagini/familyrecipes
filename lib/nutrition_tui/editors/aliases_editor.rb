# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for an ingredient's alias list (alternate names that
    # resolve to this canonical entry during lookup). Shows current aliases
    # with Add/Remove navigation; Escape returns the modified entry.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (new alias entry)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class AliasesEditor
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(entry:)
        @entry = entry
        @entry['aliases'] ||= []
        @selected = 0
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

      def handle_list(event)
        case event
        in { type: :key, code: 'esc' }
          { done: true, entry: @entry }
        in { type: :key, code: 'up' | 'k' }
          move_selection(-1)
        in { type: :key, code: 'down' | 'j' }
          move_selection(1)
        in { type: :key, code: 'a' }
          start_add
        in { type: :key, code: 'd' }
          remove_selected
        else
          nil
        end
      end

      def move_selection(delta)
        return nil if aliases.empty?

        @selected = (@selected + delta).clamp(0, aliases.size - 1)
        nil
      end

      def start_add
        @text_input = TextInput.new(label: 'New alias')
        nil
      end

      def remove_selected
        return nil if aliases.empty?

        aliases.delete_at(@selected)
        @selected = @selected.clamp(0, [0, aliases.size - 1].max)
        nil
      end

      def handle_text_input(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)

        add_alias(result[:value]) unless result[:cancelled]
        @text_input = nil
        nil
      end

      def add_alias(value)
        name = value.strip
        aliases << name unless name.empty? || aliases.include?(name)
      end

      def aliases
        @entry['aliases']
      end

      def render_list(frame, area)
        items = aliases.empty? ? ['(no aliases)'] : aliases.dup
        title_suffix = aliases.empty? ? '  a add' : '  a add  d delete'
        list = Widgets::List.new(
          items: items,
          selected_index: aliases.empty? ? nil : @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: "Aliases#{title_suffix}", borders: [:all], border_type: :rounded)
        )
        frame.render_widget(list, area)
      end
    end
  end
end

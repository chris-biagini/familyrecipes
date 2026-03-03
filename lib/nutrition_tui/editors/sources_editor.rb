# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for an ingredient's source records (provenance tracking
    # for where nutrition data came from: USDA, food labels, etc.). Shows
    # current sources with Add/Remove navigation; adding walks through
    # TextInputs for type, name, and note.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (type/name/note entry)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class SourcesEditor
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(entry:)
        @entry = entry
        @entry['sources'] ||= []
        @selected = 0
        @state = :list
        @text_input = nil
        @pending_source = {}
      end

      def handle_event(event)
        case @state
        when :list then handle_list(event)
        when :entering_type, :entering_name, :entering_note
          handle_text_input(event)
        end
      end

      def render(frame, area)
        case @state
        when :list then render_list(frame, area)
        else
          frame.render_widget(Widgets::Clear.new, area)
          @text_input.render(frame, area)
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
        return nil if sources.empty?

        @selected = (@selected + delta).clamp(0, sources.size - 1)
        nil
      end

      def start_add
        @pending_source = {}
        @text_input = TextInput.new(label: 'Type (usda/label/other)', default: 'other')
        @state = :entering_type
        nil
      end

      def remove_selected
        return nil if sources.empty?

        sources.delete_at(@selected)
        @selected = @selected.clamp(0, [0, sources.size - 1].max)
        nil
      end

      def handle_text_input(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)

        if result[:cancelled]
          reset_to_list
        else
          advance_source_input(result[:value])
        end
      end

      def advance_source_input(value) # rubocop:disable Metrics/MethodLength
        case @state
        when :entering_type
          @pending_source['type'] = value.strip
          @text_input = TextInput.new(label: 'Description')
          @state = :entering_name
          nil
        when :entering_name
          @pending_source['description'] = value.strip
          @text_input = TextInput.new(label: 'Note (optional)')
          @state = :entering_note
          nil
        when :entering_note
          @pending_source['note'] = value.strip unless value.strip.empty?
          sources << @pending_source
          reset_to_list
        end
      end

      def reset_to_list
        @state = :list
        @text_input = nil
        @pending_source = {}
        nil
      end

      def sources
        @entry['sources']
      end

      def render_list(frame, area)
        items = sources.empty? ? ['(no sources)'] : source_display_lines
        title_suffix = sources.empty? ? '  a add' : '  a add  d delete'
        list = Widgets::List.new(
          items: items,
          selected_index: sources.empty? ? nil : @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: "Sources#{title_suffix}", borders: [:all])
        )
        frame.render_widget(list, area)
      end

      def source_display_lines
        sources.map { |s| "#{s['type']}: #{s['description']}#{source_note(s)}" }
      end

      def source_note(source)
        source['note'] ? " (#{source['note']})" : ''
      end
    end
  end
end

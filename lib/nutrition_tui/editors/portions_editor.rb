# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for named portions (e.g., "stick" => 113g, "~unitless" => 50g).
    # Shows current portions as a list with Add/Edit/Remove/Done actions.
    # State machine: :list (navigate), :adding_name, :adding_grams, :editing_grams,
    # :confirm_remove.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (name/grams entry)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class PortionsEditor # rubocop:disable Metrics/ClassLength
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(entry:)
        @entry = entry
        @entry['portions'] ||= {}
        @state = :list
        @selected = 0
        @text_input = nil
        @pending_name = nil
      end

      def handle_event(event)
        case @state
        when :list then handle_list(event)
        when :adding_name, :adding_grams, :editing_grams
          handle_text_input(event)
        end
      end

      def render(frame, area)
        case @state
        when :list then render_list(frame, area)
        else render_text_input(frame, area)
        end
      end

      private

      def handle_list(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'esc' }
          { done: true, entry: @entry }
        in { type: :key, code: 'up' | 'k' }
          move_selection(-1)
        in { type: :key, code: 'down' | 'j' }
          move_selection(1)
        in { type: :key, code: 'a' }
          start_add
        in { type: :key, code: 'e' | 'enter' }
          start_edit
        in { type: :key, code: 'd' }
          remove_selected
        else
          nil
        end
      end

      def move_selection(delta)
        return nil if portion_names.empty?

        @selected = (@selected + delta).clamp(0, portion_names.size - 1)
        nil
      end

      def start_add
        @text_input = TextInput.new(label: 'Portion name')
        @state = :adding_name
        nil
      end

      def start_edit
        return nil if portion_names.empty?

        name = portion_names[@selected]
        current = @entry['portions'][name]
        @pending_name = name
        @text_input = TextInput.new(label: "#{name} (grams)", default: current || '')
        @state = :editing_grams
        nil
      end

      def remove_selected
        return nil if portion_names.empty?

        name = portion_names[@selected]
        @entry['portions'].delete(name)
        @selected = @selected.clamp(0, [0, portion_names.size - 1].max)
        nil
      end

      def handle_text_input(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)

        if result[:cancelled]
          reset_to_list
        else
          advance_input(result[:value])
        end
      end

      def advance_input(value)
        case @state
        when :adding_name
          @pending_name = value.strip
          return reset_to_list if @pending_name.empty?

          current = @entry.dig('portions', @pending_name)
          @text_input = TextInput.new(label: "#{@pending_name} (grams)", default: current || '')
          @state = :adding_grams
          nil
        when :adding_grams, :editing_grams
          apply_grams(value)
        end
      end

      def apply_grams(value)
        parsed = Float(value, exception: false)
        @entry['portions'][@pending_name] = parsed if parsed
        reset_to_list
      end

      def reset_to_list
        @state = :list
        @text_input = nil
        @pending_name = nil
        nil
      end

      def portion_names
        @entry['portions'].keys
      end

      def render_list(frame, area)
        items = portion_display_lines
        items = ['(no portions)'] if items.empty?
        title_suffix = items == ['(no portions)'] ? '  a add' : '  a add  e edit  d delete'
        list = Widgets::List.new(
          items: items,
          selected_index: portion_names.empty? ? nil : @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: "Portions#{title_suffix}", borders: [:all])
        )
        frame.render_widget(list, area)
      end

      def portion_display_lines
        @entry['portions'].map { |name, grams| "#{name.ljust(16)}#{format_number(grams)}g" }
      end

      def render_text_input(frame, area)
        frame.render_widget(Widgets::Clear.new, area)
        @text_input.render(frame, area)
      end

      def format_number(value)
        return "\u2014" unless value.is_a?(Numeric)
        return value.to_i.to_s if value == value.to_i

        value.round(1).to_s
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

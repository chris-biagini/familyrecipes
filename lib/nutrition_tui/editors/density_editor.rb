# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Editors
    # Modal editor for ingredient density (grams-per-volume conversion).
    # State machine: :menu (Enter custom / Remove / Cancel), then a sequence
    # of TextInputs for grams, volume, and unit. Returns modified entry on
    # completion or cancellation.
    #
    # Collaborators:
    # - NutritionTui::Editors::TextInput (grams/volume/unit entry)
    # - NutritionTui::Screens::Ingredient (creates and processes results)
    class DensityEditor
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      MENU_OPTIONS = ['Enter custom', 'Remove density', 'Cancel'].freeze

      def initialize(entry:)
        @entry = entry
        @state = :menu
        @selected = 0
        @text_input = nil
        @grams = nil
        @volume = nil
      end

      def handle_event(event)
        case @state
        when :menu then handle_menu(event)
        when :entering_grams, :entering_volume, :entering_unit
          handle_text_input(event)
        end
      end

      def render(frame, area)
        case @state
        when :menu then render_menu(frame, area)
        else render_text_input(frame, area)
        end
      end

      private

      def handle_menu(event)
        case event
        in { type: :key, code: 'up' | 'k' }
          @selected = (@selected - 1).clamp(0, MENU_OPTIONS.size - 1)
          nil
        in { type: :key, code: 'down' | 'j' }
          @selected = (@selected + 1).clamp(0, MENU_OPTIONS.size - 1)
          nil
        in { type: :key, code: 'enter' }
          dispatch_menu_choice
        in { type: :key, code: 'esc' }
          { done: true, entry: @entry }
        else
          nil
        end
      end

      def dispatch_menu_choice
        case @selected
        when 0 then start_grams_entry
        when 1 then remove_density
        else cancel
        end
      end

      def start_grams_entry
        current = @entry.dig('density', 'grams')
        @text_input = TextInput.new(label: 'Grams', default: current || '')
        @state = :entering_grams
        nil
      end

      def remove_density
        @entry.delete('density')
        { done: true, entry: @entry }
      end

      def cancel
        { done: true, entry: @entry }
      end

      def handle_text_input(event)
        result = @text_input.handle_event(event)
        return nil unless result&.dig(:done)
        return cancel if result[:cancelled]

        advance_state(result[:value])
      end

      def advance_state(value) # rubocop:disable Metrics/MethodLength
        case @state
        when :entering_grams
          @grams = Float(value, exception: false)
          return cancel unless @grams

          current = @entry.dig('density', 'volume')
          @text_input = TextInput.new(label: 'Volume', default: current || '')
          @state = :entering_volume
          nil
        when :entering_volume
          @volume = Float(value, exception: false)
          return cancel unless @volume

          current = @entry.dig('density', 'unit')
          @text_input = TextInput.new(label: 'Unit', default: current || 'cup')
          @state = :entering_unit
          nil
        when :entering_unit
          @entry['density'] = { 'grams' => @grams, 'volume' => @volume, 'unit' => value.strip }
          { done: true, entry: @entry }
        end
      end

      def render_menu(frame, area)
        list = Widgets::List.new(
          items: MENU_OPTIONS,
          selected_index: @selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Density', borders: [:all])
        )
        frame.render_widget(list, area)
      end

      def render_text_input(frame, area)
        frame.render_widget(Widgets::Clear.new, area)
        @text_input.render(frame, area)
      end
    end
  end
end

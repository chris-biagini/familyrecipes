# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Screens
    # Main screen of the nutrition TUI — shows a coverage summary bar, a
    # scrollable/filterable ingredient table, and a keybind help bar. Users
    # navigate the list to drill into ingredient detail, launch USDA search,
    # or create new catalog entries.
    #
    # Collaborators:
    # - NutritionTui::Data (coverage analysis, variant lookup, missing detection)
    # - NutritionTui::App (delegates render + handle_event here)
    # - RatatuiRuby::Widgets (Table, Paragraph, Block for layout)
    class Dashboard # rubocop:disable Metrics/ClassLength
      Layout = RatatuiRuby::Layout
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style

      def initialize(nutrition_data:, ctx:)
        @nutrition_data = nutrition_data
        @ctx = ctx
        @ingredients = build_ingredient_list
        @selected = 0
        @filter = nil
        @filter_input = false
        @visible_ingredients = @ingredients
      end

      def render(frame)
        chunks = split_layout(frame.area)
        render_summary_bar(frame, chunks[0])
        render_ingredient_table(frame, chunks[1])
        render_keybind_bar(frame, chunks[2])
      end

      def handle_event(event)
        return unless event

        @filter_input ? handle_filter_event(event) : handle_normal_event(event)
      end

      private

      def split_layout(area)
        Layout::Layout.split(
          area,
          direction: :vertical,
          constraints: [
            Layout::Constraint.length(3),
            Layout::Constraint.min(5),
            Layout::Constraint.length(1)
          ]
        )
      end

      # --- Summary bar ---

      def render_summary_bar(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: summary_text,
          block: Widgets::Block.new(title: 'Coverage', borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def summary_text
        total = @ingredients.size
        with_nutrition = @ingredients.count { |i| i[:has_nutrients] }
        fully_resolvable = @ingredients.count { |i| i[:has_nutrients] && i[:issues].empty? }
        missing = total - with_nutrition

        "#{total} ingredients │ #{with_nutrition} with nutrition │ " \
          "#{fully_resolvable} fully resolvable │ #{missing} missing"
      end

      # --- Ingredient table ---

      def render_ingredient_table(frame, area)
        table = Widgets::Table.new(
          header: %w[Name Aisle Nutr Dens Port Issues],
          rows: table_rows,
          widths: column_widths,
          selected_row: @selected,
          row_highlight_style: Style::Style.new(modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Ingredients', borders: [:all])
        )
        frame.render_widget(table, area)
      end

      def table_rows
        @visible_ingredients.map do |ing|
          [
            ing[:name],
            ing[:aisle],
            check_or_dash(ing[:has_nutrients]),
            check_or_dash(ing[:has_density]),
            ing[:portion_count].positive? ? ing[:portion_count].to_s : "\u2014",
            ing[:issues].empty? ? "\u2014" : ing[:issues].join(', ')
          ]
        end
      end

      def column_widths
        [
          Layout::Constraint.min(20),
          Layout::Constraint.min(14),
          Layout::Constraint.length(6),
          Layout::Constraint.length(6),
          Layout::Constraint.length(6),
          Layout::Constraint.min(16)
        ]
      end

      def check_or_dash(value)
        value ? "\u2713" : "\u2014"
      end

      # --- Keybind bar ---

      def render_keybind_bar(frame, area)
        text = @filter_input ? filter_bar_text : normal_bar_text
        paragraph = Widgets::Paragraph.new(
          text: text,
          style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
        )
        frame.render_widget(paragraph, area)
      end

      def normal_bar_text
        ' / filter  Enter select  n new  s search  q quit'
      end

      def filter_bar_text
        " Filter: #{@filter || ''}  Esc clear"
      end

      # --- Event handling ---

      def handle_normal_event(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'q' }
          { action: :quit }
        in { type: :key, code: 'Down' | 'j' }
          move_selection(1)
        in { type: :key, code: 'Up' | 'k' }
          move_selection(-1)
        in { type: :key, code: 'Enter' }
          select_current
        in { type: :key, code: '/' }
          enter_filter_mode
        in { type: :key, code: 'n' }
          { action: :new_ingredient }
        in { type: :key, code: 's' }
          { action: :usda_search }
        else
          nil
        end
      end

      def handle_filter_event(event)
        case event
        in { type: :key, code: 'Escape' }
          clear_filter
        in { type: :key, code: 'Enter' }
          lock_filter
        in { type: :key, code: 'Backspace' }
          delete_filter_char
        in { type: :key, code: /\A.\z/ => char }
          append_filter_char(char)
        else
          nil
        end
      end

      # --- Navigation ---

      def move_selection(delta)
        return if @visible_ingredients.empty?

        @selected = (@selected + delta).clamp(0, @visible_ingredients.size - 1)
        nil
      end

      def select_current
        return if @visible_ingredients.empty?

        { action: :open_ingredient, name: @visible_ingredients[@selected][:name] }
      end

      # --- Filter ---

      def enter_filter_mode
        @filter_input = true
        @filter = ''
        apply_filter
        nil
      end

      def clear_filter
        @filter_input = false
        @filter = nil
        @visible_ingredients = @ingredients
        @selected = 0
        nil
      end

      def lock_filter
        @filter_input = false
        nil
      end

      def append_filter_char(char)
        @filter = (@filter || '') + char
        apply_filter
        nil
      end

      def delete_filter_char
        return if @filter.to_s.empty?

        @filter = @filter[0..-2]
        apply_filter
        nil
      end

      def apply_filter
        @visible_ingredients = if @filter.to_s.empty?
                                 @ingredients
                               else
                                 downcased = @filter.downcase
                                 @ingredients.select { |i| i[:name].downcase.include?(downcased) }
                               end
        @selected = @selected.clamp(0, [0, @visible_ingredients.size - 1].max)
      end

      # --- Data building ---

      def build_ingredient_list
        missing_result = Data.find_missing_ingredients(@nutrition_data, @ctx)
        unresolvable = missing_result[:unresolvable]
        recipes_map = missing_result[:ingredients_to_recipes]

        rows = @nutrition_data.map do |name, entry|
          build_ingredient_row(name, entry, unresolvable, recipes_map)
        end
        rows.sort_by { |i| [-i[:issues].size, -i[:recipe_count], i[:name].downcase] }
      end

      def build_ingredient_row(name, entry, unresolvable, recipes_map)
        {
          name: name,
          aisle: entry['aisle'] || '',
          has_nutrients: entry['nutrients'].is_a?(Hash),
          has_density: entry['density'].is_a?(Hash),
          portion_count: (entry['portions'] || {}).size,
          issues: compute_issues(name, entry, unresolvable),
          recipe_count: (recipes_map[name] || []).uniq.size
        }
      end

      def compute_issues(name, entry, unresolvable)
        issues = []
        issues << 'missing nutrition' unless entry['nutrients'].is_a?(Hash)
        unresolvable[name][:units].each { |unit| issues << "#{unit} unresolvable" } if unresolvable.key?(name)
        issues
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

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

      SORT_CYCLE = %i[recps_desc recps_asc alpha].freeze
      SORT_LABELS = {
        recps_desc: "recps \u2193",
        recps_asc: "recps \u2191",
        alpha: "A\u2013Z"
      }.freeze

      def initialize(nutrition_data:, ctx:)
        @nutrition_data = nutrition_data
        @ctx = ctx
        @ingredients = build_ingredient_list
        @selected = 0
        @filter = nil
        @filter_input = false
        @hide_complete = false
        @sort_mode = :recps_desc
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
        complete_count = @ingredients.count { |i| complete?(i) }
        missing = total - with_nutrition

        "#{total} ingredients │ #{with_nutrition} with nutrition │ " \
          "#{complete_count} fully resolvable │ #{missing} missing"
      end

      # --- Ingredient table ---

      def render_ingredient_table(frame, area)
        table = Widgets::Table.new(
          header: %w[Name Aisle Aliases Recps Nutr Dens Unres Prtns],
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
            ing[:aliases],
            ing[:recipe_count].positive? ? ing[:recipe_count].to_s : "\u2014",
            check_or_dash(ing[:has_nutrients]),
            check_or_dash(ing[:has_density]),
            ing[:unresolvable].empty? ? "\u2014" : ing[:unresolvable].to_a.join(', '),
            truncate_portions(ing[:portions])
          ]
        end
      end

      def column_widths
        [
          Layout::Constraint.min(24),
          Layout::Constraint.min(14),
          Layout::Constraint.min(18),
          Layout::Constraint.length(6),
          Layout::Constraint.length(6),
          Layout::Constraint.length(6),
          Layout::Constraint.min(14),
          Layout::Constraint.min(14)
        ]
      end

      def check_or_dash(value)
        value ? "\u2713" : "\u2014"
      end

      def truncate_portions(portions)
        return "\u2014" if portions.empty?

        portions.size <= 2 ? portions.join(', ') : "#{portions.first(2).join(', ')}\u2026"
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
        hide_label = @hide_complete ? 'show all' : 'hide done'
        " / filter  c #{hide_label}  t sort:#{SORT_LABELS[@sort_mode]}  Enter select  n new  s search  q quit"
      end

      def filter_bar_text
        " Filter: #{@filter || ''}  Esc clear"
      end

      # --- Event handling ---

      def handle_normal_event(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'q' }
          { action: :quit }
        in { type: :key, code: 'down' | 'j' }
          move_selection(1)
        in { type: :key, code: 'up' | 'k' }
          move_selection(-1)
        in { type: :key, code: 'enter' }
          select_current
        in { type: :key, code: '/' }
          enter_filter_mode
        in { type: :key, code: 'c' }
          toggle_hide_complete
        in { type: :key, code: 't' }
          toggle_sort
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
        in { type: :key, code: 'esc' }
          clear_filter
        in { type: :key, code: 'enter' }
          lock_filter
        in { type: :key, code: 'backspace' }
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
        recompute_visible
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

      def toggle_hide_complete
        @hide_complete = !@hide_complete
        recompute_visible
        nil
      end

      def toggle_sort
        @sort_mode = SORT_CYCLE[(SORT_CYCLE.index(@sort_mode) + 1) % SORT_CYCLE.size]
        @ingredients = sorted_ingredients
        recompute_visible
        nil
      end

      def recompute_visible
        list = @hide_complete ? @ingredients.reject { |i| complete?(i) } : @ingredients
        @visible_ingredients = if @filter.to_s.empty?
                                 list
                               else
                                 downcased = @filter.downcase
                                 list.select { |i| i[:name].downcase.include?(downcased) }
                               end
        @selected = @selected.clamp(0, [0, @visible_ingredients.size - 1].max)
      end

      def apply_filter
        recompute_visible
      end

      # --- Data building ---

      def build_ingredient_list
        missing_result = Data.find_missing_ingredients(@nutrition_data, @ctx)
        unresolvable = missing_result[:unresolvable]
        recipes_map = missing_result[:ingredients_to_recipes]

        @all_rows = @nutrition_data.map do |name, entry|
          build_ingredient_row(name, entry, unresolvable, recipes_map)
        end
        sorted_ingredients
      end

      def sorted_ingredients
        case @sort_mode
        when :recps_desc then @all_rows.sort_by { |i| [-i[:recipe_count], i[:name].downcase] }
        when :recps_asc  then @all_rows.sort_by { |i| [i[:recipe_count], i[:name].downcase] }
        when :alpha      then @all_rows.sort_by { |i| i[:name].downcase }
        end
      end

      def build_ingredient_row(name, entry, unresolvable, recipes_map)
        unres = unresolvable.key?(name) ? unresolvable[name][:units] : Set.new
        {
          name: name,
          aisle: entry['aisle'] || '',
          aliases: format_aliases(entry['aliases']),
          has_nutrients: entry['nutrients'].is_a?(Hash),
          has_density: entry['density'].is_a?(Hash),
          has_aisle: entry['aisle'].present?,
          portions: (entry['portions'] || {}).keys.reject { |k| k.start_with?('~') },
          unresolvable: unres,
          recipe_count: (recipes_map[name] || []).uniq.size
        }
      end

      def format_aliases(aliases)
        return '' unless aliases.is_a?(Array) && aliases.any?

        aliases.size <= 2 ? aliases.join(', ') : "#{aliases.first(2).join(', ')}\u2026"
      end

      def complete?(ing)
        ing[:has_aisle] && ing[:has_nutrients] && ing[:has_density]
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

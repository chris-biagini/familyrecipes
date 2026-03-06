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
      Text = RatatuiRuby::Text

      SORT_CYCLE = %i[recps_desc recps_asc alpha_asc alpha_desc].freeze
      SORT_ARROWS = { recps_desc: "\u2193", recps_asc: "\u2191", alpha_asc: "\u2191", alpha_desc: "\u2193" }.freeze
      SORT_ON_NAME = %i[alpha_asc alpha_desc].freeze

      def initialize(nutrition_data:, ctx:)
        @nutrition_data = nutrition_data
        @ctx = ctx
        @sort_mode = :recps_desc
        @hide_complete = false
        @filter = nil
        @filter_input = false
        @name_input = nil
        @selected = 0
        @ingredients = build_ingredient_list
        @visible_ingredients = @ingredients
      end

      def refresh_data
        @ingredients = build_ingredient_list
        recompute_visible
      end

      def render(frame)
        chunks = split_layout(frame.area)
        render_summary_bar(frame, chunks[0])
        render_ingredient_table(frame, chunks[1])
        render_keybind_bar(frame, chunks[2])
        render_name_input(frame) if @name_input
      end

      def handle_event(event)
        return unless event
        return handle_name_input_event(event) if @name_input

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
          text: summary_spans,
          block: Widgets::Block.new(
            title: 'Coverage', borders: [:all], border_type: :rounded,
            title_style: Style::Style.new(modifiers: [:bold])
          )
        )
        frame.render_widget(paragraph, area)
      end

      def summary_spans
        total = @ingredients.size
        with_nutrition = @ingredients.count { |i| i[:has_nutrients] }
        complete_count = @ingredients.count { |i| complete?(i) }
        missing = total - with_nutrition

        [styled_line(
          span(total, modifiers: [:bold]), dim(" ingredients \u2502 "),
          span(with_nutrition, fg: :green), dim(" with nutrition \u2502 "),
          span(complete_count, fg: :green), dim(" fully resolvable \u2502 "),
          span(missing, fg: missing.positive? ? :yellow : :green), dim(' missing')
        )]
      end

      # --- Ingredient table ---

      def render_ingredient_table(frame, area)
        table = Widgets::Table.new(
          header: sort_decorated_header,
          rows: table_rows,
          widths: column_widths,
          selected_row: @selected,
          row_highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(
            title: 'Ingredients', borders: [:all], border_type: :rounded,
            title_style: Style::Style.new(modifiers: [:bold])
          )
        )
        frame.render_widget(table, area)
      end

      def sort_decorated_header
        arrow = SORT_ARROWS[@sort_mode]
        name_hdr = SORT_ON_NAME.include?(@sort_mode) ? "Name#{arrow}" : 'Name'
        recps_hdr = SORT_ON_NAME.include?(@sort_mode) ? 'Recps' : "Recps#{arrow}"
        [name_hdr, 'Aisle', 'Aliases', recps_hdr, 'Nutr', 'Dens', 'Unres', 'Prtns']
      end

      def table_rows
        @visible_ingredients.map { |ing| build_table_row(ing) }
      end

      def build_table_row(ing)
        [
          ing[:name],
          ing[:aisle],
          cell(ing[:aliases], :dark_gray),
          ing[:recipe_count].positive? ? ing[:recipe_count].to_s : cell("\u2014", :dark_gray),
          check_or_dash(ing[:has_nutrients]),
          check_or_dash(ing[:has_density]),
          unresolvable_cell(ing[:unresolvable]),
          cell(truncate_portions(ing[:portions]), :dark_gray)
        ]
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
        value ? cell("\u2713", :green) : cell("\u2014", :dark_gray)
      end

      def unresolvable_cell(unres)
        return cell("\u2014", :dark_gray) if unres.empty?

        cell(unres.to_a.join(', '), :red)
      end

      def cell(text, color)
        Widgets::Paragraph.new(text: text.to_s, style: Style::Style.new(fg: color))
      end

      def truncate_portions(portions)
        return "\u2014" if portions.empty?

        portions.size <= 2 ? portions.join(', ') : "#{portions.first(2).join(', ')}\u2026"
      end

      # --- Keybind bar ---

      def render_keybind_bar(frame, area)
        paragraph = Widgets::Paragraph.new(text: @filter_input ? filter_bar_spans : keybind_bar_spans)
        frame.render_widget(paragraph, area)
      end

      def keybind_bar_spans
        hide_label = @hide_complete ? 'show all' : 'hide done'
        [styled_line(
          dim(' '), key('/'), dim(' filter  '),
          key('c'), dim(" #{hide_label}  "),
          key('t'), dim(' sort  '),
          key('Enter'), dim(' select  '),
          key('n'), dim(' new  '),
          key('s'), dim(' search  '),
          key('q'), dim(' quit')
        )]
      end

      def filter_bar_spans
        [styled_line(dim(' Filter: '), span(@filter || '', modifiers: [:bold]), dim('  Esc clear'))]
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
          start_name_input
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

      # --- New ingredient name input ---

      def start_name_input
        @name_input = Editors::TextInput.new(label: 'Ingredient name')
        nil
      end

      def handle_name_input_event(event)
        result = @name_input.handle_event(event)
        return nil unless result&.dig(:done)

        @name_input = nil
        return nil if result[:cancelled] || result[:value].strip.empty?

        { action: :open_ingredient, name: result[:value].strip }
      end

      def render_name_input(frame)
        area = name_input_area(frame.area)
        frame.render_widget(Widgets::Clear.new, area)
        @name_input.render(frame, area)
      end

      def name_input_area(screen)
        w = [screen.width / 2, 40].max
        Layout::Rect.new(
          x: screen.x + ((screen.width - w) / 2),
          y: screen.y + (screen.height / 2) - 1,
          width: w,
          height: 3
        )
      end

      # --- Data building ---

      def build_ingredient_list
        missing_result = Data.find_missing_ingredients(@nutrition_data, @ctx)
        unresolvable = missing_result[:unresolvable]
        recipes_map = missing_result[:ingredients_to_recipes]

        catalog_rows = @nutrition_data.map do |name, entry|
          build_ingredient_row(name, entry, unresolvable, recipes_map)
        end
        missing_rows = missing_result[:missing].map do |name|
          build_ingredient_row(name, {}, unresolvable, recipes_map)
        end
        @all_rows = catalog_rows + missing_rows
        sorted_ingredients
      end

      def sorted_ingredients
        case @sort_mode
        when :recps_desc then @all_rows.sort_by { |i| [-i[:recipe_count], i[:name].downcase] }
        when :recps_asc  then @all_rows.sort_by { |i| [i[:recipe_count], i[:name].downcase] }
        when :alpha_asc  then @all_rows.sort_by { |i| i[:name].downcase }
        when :alpha_desc then @all_rows.sort_by { |i| i[:name].downcase }.reverse
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

      # --- Styled text helpers ---

      def span(text, **)
        Text::Span.styled(text.to_s, Style::Style.new(**))
      end

      def dim(text)
        Text::Span.styled(text, Style::Style.new(fg: :dark_gray))
      end

      def key(text)
        Text::Span.styled(text, Style::Style.new(fg: :cyan))
      end

      def styled_line(*spans)
        Text::Line.new(spans: spans)
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Screens
    # Detail screen for a single ingredient — two-column layout. Left column
    # shows the full catalog entry (nutrients, density, portions, aisle,
    # aliases, sources). Right column shows computed reference data (recipe
    # unit resolution status, USDA portion candidates when available).
    # Direct one-key shortcuts (n/d/p/a/l/r/u/w) replace the old edit menu.
    # Manages an `@active_editor` overlay that captures events when present.
    #
    # Collaborators:
    # - NutritionTui::Data (NUTRIENTS constant, find_needed_units, save)
    # - NutritionTui::Editors::* (modal overlays for editing sections)
    # - FamilyRecipes::NutritionCalculator (resolvable? for unit checks)
    # - NutritionTui::App (delegates render + handle_event here)
    class Ingredient # rubocop:disable Metrics/ClassLength
      Layout = RatatuiRuby::Layout
      Widgets = RatatuiRuby::Widgets
      Style = RatatuiRuby::Style
      Text = RatatuiRuby::Text

      WEIGHT_UNITS = FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS.keys.freeze
      VOLUME_UNITS = FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.keys.freeze

      CONFIRM_OPTIONS = ['Save and go back', 'Discard and go back', 'Cancel'].freeze

      def initialize(name:, entry:, nutrition_data:, ctx:)
        @name = name
        @entry = entry&.dup || {}
        @nutrition_data = nutrition_data
        @ctx = ctx
        @dirty = false
        @needed_units = Data.find_needed_units(name, ctx)
        @active_editor = nil
        @confirm_exit = false
        @confirm_selected = 0
        @usda_classified = nil
        @auto_density_source = nil
      end

      def apply_usda_import(detail)
        import_nutrients(detail)
        import_source(detail)
        classify_and_apply_density(detail)
        @needed_units = Data.find_needed_units(@name, @ctx)
        @dirty = true
      end

      def render(frame)
        main_chunks = vertical_split(frame.area, [Layout::Constraint.min(10), Layout::Constraint.length(2)])
        render_content(frame, main_chunks[0])
        render_keybind_bar(frame, main_chunks[1])
        render_overlay(frame) if @active_editor
        render_confirm_exit(frame) if @confirm_exit
      end

      def handle_event(event)
        return unless event
        return dispatch_confirm_key(event) if @confirm_exit
        return delegate_to_editor(event) if @active_editor

        dispatch_key(event)
      end

      private

      # --- Editor overlay ---

      def delegate_to_editor(event)
        result = @active_editor.handle_event(event)
        return nil unless result&.dig(:done)

        process_editor_result(result)
      end

      def process_editor_result(result)
        if result[:entry]
          @entry = result[:entry]
          @dirty = true
          @active_editor = nil
        elsif result[:value]
          apply_value_result(result)
        else
          @active_editor = nil
        end
        nil
      end

      def apply_value_result(result)
        @entry['aisle'] = result[:value]
        @dirty = true
        @active_editor = nil
      end

      def render_overlay(frame)
        area = overlay_area(frame.area)
        frame.render_widget(Widgets::Clear.new, area)
        @active_editor.render(frame, area)
      end

      def overlay_area(screen)
        w = [screen.width * 3 / 5, 40].max
        h = [screen.height * 3 / 5, 10].max
        Layout::Rect.new(
          x: screen.x + ((screen.width - w) / 2),
          y: screen.y + ((screen.height - h) / 2),
          width: w,
          height: h
        )
      end

      # --- Two-column layout ---

      def render_content(frame, area)
        chunks = horizontal_split(area, [Layout::Constraint.percentage(60), Layout::Constraint.percentage(40)])
        render_left_column(frame, chunks[0])
        render_right_column(frame, chunks[1])
      end

      def render_left_column(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: left_column_lines,
          block: Widgets::Block.new(
            title: @name,
            borders: [:all],
            border_type: :rounded,
            title_style: Style::Style.new(modifiers: [:bold])
          )
        )
        frame.render_widget(paragraph, area)
      end

      def left_column_lines
        group1 = nutrients_section_lines
        group2 = density_section_lines + [blank_line] + portions_section_lines
        group3 = aisle_section_lines + [blank_line] + aliases_section_lines + [blank_line] + sources_section_lines
        [group1, group2, group3].flat_map { |g| g + [blank_line] }
      end

      def render_right_column(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: right_column_lines,
          block: Widgets::Block.new(
            title: 'Reference',
            borders: [:all],
            border_type: :rounded,
            title_style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
          )
        )
        frame.render_widget(paragraph, area)
      end

      def right_column_lines
        recipe_units_section_lines + [blank_line] + usda_reference_section_lines
      end

      # --- Left column sections ---

      def nutrients_section_lines
        nutrients = @entry['nutrients']
        return [nutrients_empty_line] unless nutrients.is_a?(Hash)

        header = styled_line(span('[n]', fg: :cyan), span(' Nutrients ', modifiers: [:bold]), span("(per #{basis_grams}g)", fg: :dark_gray))
        [header] + Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n) }
      end

      def nutrients_empty_line
        styled_line(span('[n]', fg: :cyan), span(' Nutrients: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def density_section_lines
        density = @entry['density']
        return [density_empty_line] unless density.is_a?(Hash)

        value = "#{format_number(density['grams'])}g per #{format_number(density['volume'])} #{density['unit']}"
        [styled_line(span('[d]', fg: :cyan), span(' Density: ', modifiers: [:bold]), plain(value))]
      end

      def density_empty_line
        styled_line(span('[d]', fg: :cyan), span(' Density: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def portions_section_lines
        portions = @entry['portions']
        return [portions_empty_line] unless portions.is_a?(Hash) && portions.any?

        header = styled_line(span('[p]', fg: :cyan), span(' Portions', modifiers: [:bold]))
        [header] + portions.map { |name, grams| Text::Line.from_string("    #{name.ljust(16)}#{format_number(grams)}g") }
      end

      def portions_empty_line
        styled_line(span('[p]', fg: :cyan), span(' Portions: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def aisle_section_lines
        aisle = @entry['aisle']
        return [aisle_empty_line] unless aisle

        [styled_line(span('[a]', fg: :cyan), span(' Aisle: ', modifiers: [:bold]), plain(aisle))]
      end

      def aisle_empty_line
        styled_line(span('[a]', fg: :cyan), span(' Aisle: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def aliases_section_lines
        aliases = @entry['aliases']
        return [aliases_empty_line] unless aliases.is_a?(Array) && aliases.any?
        return [styled_line(span('[l]', fg: :cyan), span(' Aliases: ', modifiers: [:bold]), plain(aliases.join(', ')))] if aliases.size < 4

        header = styled_line(span('[l]', fg: :cyan), span(' Aliases', modifiers: [:bold]))
        [header] + aliases.map { |a| Text::Line.from_string("    #{a}") }
      end

      def aliases_empty_line
        styled_line(span('[l]', fg: :cyan), span(' Aliases: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def sources_section_lines
        sources = @entry['sources']
        return [sources_empty_line] unless sources.is_a?(Array) && sources.any?

        header = styled_line(span('[r]', fg: :cyan), span(' Sources', modifiers: [:bold]))
        [header] + sources.flat_map { |s| format_source_lines(s) }
      end

      def sources_empty_line
        styled_line(span('[r]', fg: :cyan), span(' Sources: ', modifiers: [:bold]), span("\u2014", fg: :dark_gray))
      end

      def format_source_lines(source)
        header = Text::Line.from_string("    #{source['type']}#{source_detail(source)}")
        return [header] unless source['description']

        [header, Text::Line.from_string("      \"#{source['description']}\"")]
      end

      def source_detail(source)
        label = source_detail_label(source['dataset'], source['fdc_id'])
        label ? " \u2013 #{label}" : ''
      end

      def source_detail_label(dataset, fdc_id)
        return "#{dataset} (#{fdc_id})" if dataset && fdc_id

        dataset || fdc_id&.to_s
      end

      # --- Right column sections ---

      def recipe_units_section_lines
        return [styled_line(span('No recipe usage found', fg: :dark_gray))] if @needed_units.empty?

        calculator, calc_entry = build_calculator
        [styled_line(span('Recipe Units', modifiers: [:bold]))] +
          @needed_units.map { |unit| format_unit_line(unit, calculator, calc_entry) }
      end

      def usda_reference_section_lines
        return [styled_line(span("No USDA data \u2014 press u to search", fg: :dark_gray))] unless @usda_classified

        [styled_line(span('USDA Reference', modifiers: [:bold]))] + usda_candidate_lines
      end

      def usda_candidate_lines
        density_lines = @usda_classified[:density_candidates].map { |c| format_usda_candidate(c) }
        portion_lines = @usda_classified[:portion_candidates].map { |c| format_usda_candidate(c) }
        density_lines + portion_lines
      end

      def format_usda_candidate(candidate)
        star = candidate[:modifier] == @auto_density_source ? span("\u2605 ", fg: :yellow) : plain('  ')
        label = usda_candidate_label(candidate)
        grams = usda_candidate_grams(candidate)
        styled_line(star, plain(label.ljust(25)), plain(grams))
      end

      def usda_candidate_label(candidate)
        return "#{candidate[:modifier]} (\u00d7#{candidate[:amount].to_i})" if candidate[:amount] > 1

        candidate[:modifier]
      end

      def usda_candidate_grams(candidate)
        return "#{format_number(candidate[:each])}g each" if candidate[:amount] > 1

        "#{format_number(candidate[:grams])}g"
      end

      # --- Keybind bar ---

      def render_keybind_bar(frame, area)
        paragraph = Widgets::Paragraph.new(text: keybind_bar_lines)
        frame.render_widget(paragraph, area)
      end

      def keybind_bar_lines
        [keybind_line_1, keybind_line_2]
      end

      def keybind_line_1
        styled_line(
          plain(' '), span('n', fg: :cyan), span(' nutrients  ', fg: :dark_gray),
          span('d', fg: :cyan), span(' density  ', fg: :dark_gray),
          span('p', fg: :cyan), span(' portions  ', fg: :dark_gray),
          span('a', fg: :cyan), span(' aisle  ', fg: :dark_gray),
          span('l', fg: :cyan), span(' aliases  ', fg: :dark_gray),
          span('r', fg: :cyan), span(' sources', fg: :dark_gray)
        )
      end

      def keybind_line_2
        parts = [
          plain(' '), span('u', fg: :cyan), span(' USDA  ', fg: :dark_gray),
          span('w', fg: :cyan), span(' save  ', fg: :dark_gray),
          span('Esc', fg: :cyan), span(' back', fg: :dark_gray)
        ]
        parts << span('  [modified]', fg: :yellow) if @dirty
        Text::Line.new(spans: parts)
      end

      # --- Event handling ---

      def dispatch_key(event)
        case event
        in { type: :key, code: 'esc' }   then handle_escape
        in { type: :key, code: 'n' }     then open_nutrients_editor
        in { type: :key, code: 'd' }     then open_density_editor
        in { type: :key, code: 'p' }     then open_portions_editor
        in { type: :key, code: 'a' }     then open_aisle_editor
        in { type: :key, code: 'l' }     then open_aliases_editor
        in { type: :key, code: 'r' }     then open_sources_editor
        in { type: :key, code: 'u' }     then handle_usda_key
        in { type: :key, code: 'w' }     then save_entry
        else nil
        end
      end

      def handle_usda_key
        return nil if @usda_classified

        { action: :usda_import, name: @name }
      end

      def open_nutrients_editor
        @active_editor = Editors::NutrientsEditor.new(entry: @entry)
        nil
      end

      def open_density_editor
        @active_editor = Editors::DensityEditor.new(entry: @entry)
        nil
      end

      def open_portions_editor
        @active_editor = Editors::PortionsEditor.new(entry: @entry)
        nil
      end

      def open_aisle_editor
        @active_editor = Editors::AisleEditor.new(
          nutrition_data: @nutrition_data,
          current_aisle: @entry['aisle']
        )
        nil
      end

      def open_aliases_editor
        @active_editor = Editors::AliasesEditor.new(entry: @entry)
        nil
      end

      def open_sources_editor
        @active_editor = Editors::SourcesEditor.new(entry: @entry)
        nil
      end

      # --- USDA import ---

      def import_nutrients(detail)
        @entry['nutrients'] = detail[:nutrients]
      end

      def import_source(detail)
        @entry['sources'] ||= []
        @entry['sources'] << usda_source_hash(detail)
      end

      def usda_source_hash(detail)
        { 'type' => 'usda', 'dataset' => detail[:data_type],
          'fdc_id' => detail[:fdc_id], 'description' => detail[:description] }
      end

      def classify_and_apply_density(detail)
        all_modifiers = detail[:portions][:volume] + detail[:portions][:non_volume]
        @usda_classified = Data.classify_usda_modifiers(all_modifiers)
        best = Data.pick_best_density(@usda_classified[:density_candidates])
        apply_density(best) if best
      end

      def apply_density(best)
        unit = Data.normalize_volume_unit(best[:modifier])
        @entry['density'] = { 'grams' => best[:each].round(2), 'volume' => 1.0, 'unit' => unit }
        @auto_density_source = best[:modifier]
      end

      # --- Save ---

      def save_entry
        @nutrition_data[@name] = @entry
        Data.save_nutrition_data(@nutrition_data)
        @dirty = false
        nil
      end

      # --- Unsaved-changes confirmation ---

      def handle_escape
        return { action: :back } unless @dirty

        @confirm_exit = true
        @confirm_selected = 0
        nil
      end

      def dispatch_confirm_key(event)
        case event
        in { type: :key, code: 'esc' }
          dismiss_confirm
        in { type: :key, code: 'up' | 'k' }
          @confirm_selected = (@confirm_selected - 1) % CONFIRM_OPTIONS.size
          nil
        in { type: :key, code: 'down' | 'j' }
          @confirm_selected = (@confirm_selected + 1) % CONFIRM_OPTIONS.size
          nil
        in { type: :key, code: 'enter' }
          execute_confirm_choice
        else
          nil
        end
      end

      def dismiss_confirm
        @confirm_exit = false
        nil
      end

      def execute_confirm_choice
        @confirm_exit = false
        case @confirm_selected
        when 0 then save_and_back
        when 1 then { action: :back }
        when 2 then nil
        end
      end

      def save_and_back
        save_entry
        { action: :back }
      end

      def render_confirm_exit(frame)
        area = confirm_area(frame.area)
        frame.render_widget(Widgets::Clear.new, area)
        frame.render_widget(confirm_list_widget, area)
      end

      def confirm_list_widget
        Widgets::List.new(
          items: CONFIRM_OPTIONS,
          selected_index: @confirm_selected,
          highlight_style: Style::Style.new(fg: :cyan, modifiers: [:bold]),
          block: Widgets::Block.new(title: 'Unsaved changes', borders: [:all], border_type: :double)
        )
      end

      def confirm_area(screen)
        w = [screen.width / 3, 30].max
        h = 5
        Layout::Rect.new(
          x: screen.x + ((screen.width - w) / 2),
          y: screen.y + ((screen.height - h) / 2),
          width: w,
          height: h
        )
      end

      # --- Helpers ---

      def span(text, **opts)
        Text::Span.styled(text.to_s, Style::Style.new(**opts))
      end

      def plain(text)
        Text::Span.raw(text.to_s)
      end

      def styled_line(*spans)
        Text::Line.new(spans: spans)
      end

      def blank_line
        Text::Line.from_string('')
      end

      def format_nutrient_line(nutrients, nutrient)
        indent = '  ' * nutrient[:indent]
        value = nutrients[nutrient[:key]]
        formatted = value ? format_number(value) : "\u2014"
        suffix = nutrient[:unit].empty? ? '' : " #{nutrient[:unit]}"
        Text::Line.from_string("#{indent}#{nutrient[:label].ljust(20 - (nutrient[:indent] * 2))}#{formatted}#{suffix}")
      end

      def format_unit_line(unit, calculator, calc_entry)
        display = unit.nil? ? '(bare count)' : unit
        resolved = calc_entry && calculator.resolvable?(1, unit, calc_entry)
        status_span = resolved ? span("\u2713", fg: :green) : span("\u2717", fg: :red)
        method = resolution_method(unit, resolved)
        styled_line(plain("  #{display.to_s.ljust(16)}"), status_span, span("  #{method}", fg: :dark_gray))
      end

      def basis_grams
        @entry.dig('nutrients', 'basis_grams') || 100
      end

      def build_calculator
        calculator = FamilyRecipes::NutritionCalculator.new({ @name => @entry })
        calc_entry = calculator.nutrition_data[@name]
        [calculator, calc_entry]
      end

      def resolution_method(unit, resolved)
        return 'no nutrition data' unless @entry['nutrients'].is_a?(Hash)

        if unit.nil?
          resolved ? 'via ~unitless' : 'no ~unitless portion'
        elsif WEIGHT_UNITS.include?(unit.downcase)
          'weight'
        elsif matching_portion(unit)
          "via #{matching_portion(unit)}"
        elsif VOLUME_UNITS.include?(unit.downcase)
          resolved ? 'via density' : 'no density'
        else
          resolved ? "via #{unit}" : 'no portion'
        end
      end

      def matching_portion(unit)
        portions = @entry['portions'] || {}
        portions.keys.find { |k| k.downcase == unit.downcase }
      end

      def vertical_split(area, constraints)
        Layout::Layout.split(area, direction: :vertical, constraints: constraints)
      end

      def horizontal_split(area, constraints)
        Layout::Layout.split(area, direction: :horizontal, constraints: constraints)
      end

      def format_number(value)
        return "\u2014" unless value.is_a?(Numeric)
        return value.to_i.to_s if value == value.to_i

        value.round(1).to_s
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

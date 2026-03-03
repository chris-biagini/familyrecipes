# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Screens
    # Detail screen for a single ingredient -- three-panel layout showing
    # nutrients (left), density + portions (right top), and recipe unit
    # resolution status (right bottom). Users can trigger edits, USDA
    # import, and save modified entries back to ingredient-catalog.yaml.
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

      WEIGHT_UNITS = FamilyRecipes::NutritionCalculator::WEIGHT_CONVERSIONS.keys.freeze
      VOLUME_UNITS = FamilyRecipes::NutritionCalculator::VOLUME_TO_ML.keys.freeze

      def initialize(name:, entry:, nutrition_data:, ctx:)
        @name = name
        @entry = entry&.dup || {}
        @nutrition_data = nutrition_data
        @ctx = ctx
        @dirty = false
        @needed_units = Data.find_needed_units(name, ctx)
        @active_editor = nil
        @show_usda_reference = false
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
        main_chunks = vertical_split(frame.area, [Layout::Constraint.min(10), Layout::Constraint.length(1)])
        render_content(frame, main_chunks[0])
        render_keybind_bar(frame, main_chunks[1])
        render_overlay(frame) if @active_editor
      end

      def handle_event(event)
        return unless event
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
        if result[:choice]
          open_sub_editor(result[:choice])
        elsif result[:entry]
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

      def open_sub_editor(choice)
        @active_editor = case choice
                         when :nutrients then Editors::NutrientsEditor.new(entry: @entry)
                         when :density   then Editors::DensityEditor.new(entry: @entry)
                         when :portions  then Editors::PortionsEditor.new(entry: @entry)
                         end
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

      # --- Content panels ---

      def render_content(frame, area)
        content_chunks = horizontal_split(area, [Layout::Constraint.percentage(45), Layout::Constraint.percentage(55)])
        render_nutrients_panel(frame, content_chunks[0])
        render_right_panels(frame, content_chunks[1])
      end

      def render_right_panels(frame, area)
        if @show_usda_reference
          render_right_panels_with_usda(frame, area)
        else
          render_right_panels_default(frame, area)
        end
      end

      def render_right_panels_default(frame, area)
        chunks = vertical_split(area, [Layout::Constraint.percentage(55), Layout::Constraint.percentage(45)])
        render_density_portions_panel(frame, chunks[0])
        render_recipe_units_panel(frame, chunks[1])
      end

      def render_right_panels_with_usda(frame, area)
        constraints = [Layout::Constraint.percentage(35), Layout::Constraint.percentage(30), Layout::Constraint.percentage(35)]
        chunks = vertical_split(area, constraints)
        render_density_portions_panel(frame, chunks[0])
        render_recipe_units_panel(frame, chunks[1])
        render_usda_reference_panel(frame, chunks[2])
      end

      def render_nutrients_panel(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: nutrients_text,
          block: Widgets::Block.new(title: "Nutrients (per #{basis_grams}g)", borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def nutrients_text
        nutrients = @entry['nutrients']
        return dim_text('No nutrition data') unless nutrients.is_a?(Hash)

        Data::NUTRIENTS.map { |n| format_nutrient_line(nutrients, n) }.join("\n")
      end

      def format_nutrient_line(nutrients, nutrient)
        indent = '  ' * nutrient[:indent]
        value = nutrients[nutrient[:key]]
        formatted = value ? format_number(value) : "\u2014"
        suffix = nutrient[:unit].empty? ? '' : " #{nutrient[:unit]}"
        "#{indent}#{nutrient[:label].ljust(20 - (nutrient[:indent] * 2))}#{formatted}#{suffix}"
      end

      def basis_grams
        @entry.dig('nutrients', 'basis_grams') || 100
      end

      def render_density_portions_panel(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: density_portions_text,
          block: Widgets::Block.new(title: 'Density & Portions', borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def density_portions_text
        lines = [density_line, '']
        lines << 'Portions:'
        lines.concat(portion_lines)
        lines.join("\n")
      end

      def density_line
        density = @entry['density']
        return dim_text('Density: none') unless density.is_a?(Hash)

        "Density: #{format_number(density['grams'])}g per #{format_number(density['volume'])} #{density['unit']}"
      end

      def portion_lines
        portions = @entry['portions']
        return [dim_text('  No portions')] unless portions.is_a?(Hash) && portions.any?

        portions.map { |name, grams| "  #{name.ljust(16)}#{format_number(grams)}g" }
      end

      def render_recipe_units_panel(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: recipe_units_text,
          block: Widgets::Block.new(title: 'Recipe Units', borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def recipe_units_text
        return dim_text('No recipe usage found') if @needed_units.empty?

        calculator, calc_entry = build_calculator
        @needed_units.map { |unit| format_unit_line(unit, calculator, calc_entry) }.join("\n")
      end

      def build_calculator
        calculator = FamilyRecipes::NutritionCalculator.new({ @name => @entry })
        calc_entry = calculator.nutrition_data[@name]
        [calculator, calc_entry]
      end

      def format_unit_line(unit, calculator, calc_entry)
        display = unit.nil? ? '(bare count)' : unit
        resolved = calc_entry && calculator.resolvable?(1, unit, calc_entry)
        status = resolved ? "\u2713" : "\u2717"
        method = resolution_method(unit, resolved)
        "  #{display.to_s.ljust(16)}#{status}  #{method}"
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

      # --- USDA reference panel ---

      def render_usda_reference_panel(frame, area)
        paragraph = Widgets::Paragraph.new(
          text: usda_reference_text,
          block: Widgets::Block.new(title: 'USDA Reference', borders: [:all])
        )
        frame.render_widget(paragraph, area)
      end

      def usda_reference_text
        return dim_text('No USDA data') unless @usda_classified

        lines = usda_density_lines + usda_portion_lines
        lines.empty? ? dim_text('No portions from USDA') : lines.join("\n")
      end

      def usda_density_lines
        @usda_classified[:density_candidates].map { |c| format_usda_line(c) }
      end

      def usda_portion_lines
        @usda_classified[:portion_candidates].map { |c| format_usda_line(c) }
      end

      def format_usda_line(candidate)
        star = candidate[:modifier] == @auto_density_source ? "\u2605 " : '  '
        label = format_usda_modifier(candidate)
        grams = format_usda_grams(candidate)
        "#{star}#{label.ljust(25)}#{grams}"
      end

      def format_usda_modifier(candidate)
        return "#{candidate[:modifier]} (\u00d7#{candidate[:amount].to_i})" if candidate[:amount] > 1

        candidate[:modifier]
      end

      def format_usda_grams(candidate)
        return "#{format_number(candidate[:each])}g each" if candidate[:amount] > 1

        "#{format_number(candidate[:grams])}g"
      end

      # --- Keybind bar ---

      def render_keybind_bar(frame, area)
        prefix = @dirty ? '[modified] ' : ''
        text = "#{prefix} e edit  u USDA  a aisle  l aliases  r sources  w save  Esc back"
        paragraph = Widgets::Paragraph.new(
          text: " #{text}",
          style: Style::Style.new(fg: :dark_gray, modifiers: [:dim])
        )
        frame.render_widget(paragraph, area)
      end

      # --- Event handling ---

      def dispatch_key(event) # rubocop:disable Metrics/MethodLength
        case event
        in { type: :key, code: 'Escape' }
          { action: :back }
        in { type: :key, code: 'e' }
          open_edit_menu
        in { type: :key, code: 'u' }
          handle_usda_key
        in { type: :key, code: 'a' }
          open_aisle_editor
        in { type: :key, code: 'l' }
          open_aliases_editor
        in { type: :key, code: 'r' }
          open_sources_editor
        in { type: :key, code: 'w' }
          save_entry
        else
          nil
        end
      end

      def handle_usda_key
        if @usda_classified
          @show_usda_reference = !@show_usda_reference
          nil
        else
          { action: :usda_import, name: @name }
        end
      end

      def open_edit_menu
        @active_editor = Editors::EditMenu.new
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
        @show_usda_reference = true
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

      # --- Helpers ---

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

      def dim_text(text)
        text
      end
    end
  end # rubocop:enable Metrics/ClassLength
end

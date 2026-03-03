# frozen_string_literal: true

require 'ratatui_ruby'

module NutritionTui
  module Screens
    # Detail screen for a single ingredient — three-panel layout showing
    # nutrients (left), density + portions (right top), and recipe unit
    # resolution status (right bottom). Users can trigger edits, USDA
    # import, and save modified entries back to ingredient-catalog.yaml.
    #
    # Collaborators:
    # - NutritionTui::Data (NUTRIENTS constant, find_needed_units, save)
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
      end

      def render(frame)
        main_chunks = vertical_split(frame.area, [Layout::Constraint.min(10), Layout::Constraint.length(1)])
        render_content(frame, main_chunks[0])
        render_keybind_bar(frame, main_chunks[1])
      end

      def handle_event(event)
        return unless event

        dispatch_key(event)
      end

      private

      def render_content(frame, area)
        content_chunks = horizontal_split(area, [Layout::Constraint.percentage(45), Layout::Constraint.percentage(55)])
        render_nutrients_panel(frame, content_chunks[0])
        render_right_panels(frame, content_chunks[1])
      end

      def render_right_panels(frame, area)
        right_chunks = vertical_split(area, [Layout::Constraint.percentage(55), Layout::Constraint.percentage(45)])
        render_density_portions_panel(frame, right_chunks[0])
        render_recipe_units_panel(frame, right_chunks[1])
      end

      # --- Nutrients panel ---

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

      # --- Density & Portions panel ---

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

      # --- Recipe Units panel ---

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
          { action: :edit_menu }
        in { type: :key, code: 'u' }
          { action: :usda_import, name: @name }
        in { type: :key, code: 'a' }
          { action: :edit_aisle }
        in { type: :key, code: 'l' }
          { action: :edit_aliases }
        in { type: :key, code: 'r' }
          { action: :edit_sources }
        in { type: :key, code: 'w' }
          save_entry
        else
          nil
        end
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

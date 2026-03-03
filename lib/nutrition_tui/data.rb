# frozen_string_literal: true

require 'yaml'
require 'active_support/core_ext/enumerable'
require 'active_support/core_ext/object/blank'
require_relative '../familyrecipes'

module NutritionTui
  # Data I/O and lookup layer for the nutrition catalog TUI. Owns all
  # reading/writing of ingredient-catalog.yaml, variant-aware name resolution,
  # recipe context loading, coverage analysis, and USDA modifier classification.
  # Pure functions with no TTY dependencies — screens call in, never the reverse.
  #
  # Collaborators:
  # - FamilyRecipes (recipe parsing, inflector, NutritionCalculator)
  # - ingredient-catalog.yaml (seed data read/write)
  # - db/seeds/recipes/ (recipe source files for context)
  module Data # rubocop:disable Metrics/ModuleLength
    PROJECT_ROOT = File.expand_path('../..', __dir__)
    NUTRITION_PATH = File.join(PROJECT_ROOT, 'db/seeds/resources/ingredient-catalog.yaml')
    RECIPES_DIR = File.join(PROJECT_ROOT, 'db/seeds/recipes')

    NUTRIENTS = [
      { key: 'calories', label: 'Calories', unit: '', indent: 0 },
      { key: 'fat', label: 'Total fat', unit: 'g', indent: 0 },
      { key: 'saturated_fat', label: 'Saturated fat', unit: 'g', indent: 1 },
      { key: 'trans_fat', label: 'Trans fat', unit: 'g', indent: 1 },
      { key: 'cholesterol', label: 'Cholesterol', unit: 'mg', indent: 0 },
      { key: 'sodium', label: 'Sodium', unit: 'mg', indent: 0 },
      { key: 'carbs', label: 'Total carbs', unit: 'g', indent: 0 },
      { key: 'fiber', label: 'Fiber', unit: 'g', indent: 1 },
      { key: 'total_sugars', label: 'Total sugars', unit: 'g', indent: 1 },
      { key: 'added_sugars', label: 'Added sugars', unit: 'g', indent: 2 },
      { key: 'protein', label: 'Protein', unit: 'g', indent: 0 }
    ].freeze

    VOLUME_UNITS = ['cup', 'cups', 'tbsp', 'tsp', 'tablespoon', 'tablespoons',
                    'teaspoon', 'teaspoons', 'fl oz'].freeze
    WEIGHT_UNITS = %w[oz ounce ounces lb lbs pound pounds kg g gram grams].freeze

    module_function

    # --- Data I/O ---

    def load_nutrition_data
      return {} unless File.exist?(NUTRITION_PATH)

      YAML.safe_load_file(NUTRITION_PATH, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
    end

    def save_nutrition_data(data)
      sorted = data.sort_by { |k, _| k.downcase }.to_h
      sorted.each_value { |entry| round_entry_values(entry) }

      File.write(NUTRITION_PATH, YAML.dump(sorted))
    end

    # --- Variant-aware lookup (mirrors IngredientCatalog.lookup_for) ---

    def build_lookup(nutrition_data)
      nutrition_data.each_with_object({}) do |(name, entry), lookup|
        register_name(lookup, name, name)
        register_variants(lookup, name)
        register_aliases(lookup, name, entry, nutrition_data)
      end
    end

    def resolve_to_canonical(name, lookup)
      lookup[name] || lookup[name.downcase]
    end

    # --- Context loading ---

    def load_context
      recipes = FamilyRecipes.parse_recipes(RECIPES_DIR)
      catalog = load_nutrition_data

      {
        recipes: recipes,
        recipe_map: recipes.index_by(&:id),
        omit_set: build_omit_set(catalog)
      }
    end

    def find_needed_units(name, ctx, nutrition_data)
      lookup = build_lookup(nutrition_data)
      ctx[:recipes].flat_map do |recipe|
        recipe.all_ingredients_with_quantities(ctx[:recipe_map])
              .select { |ing_name, _| resolve_to_canonical(ing_name, lookup) == name }
              .flat_map { |_, amounts| amounts.compact.map(&:unit) }
      end.uniq
    end

    # --- Missing / coverage analysis ---

    def find_missing_ingredients(nutrition_data, ctx)
      lookup = build_lookup(nutrition_data)
      recipes_map = build_ingredients_to_recipes(ctx)

      missing = recipes_map.keys.reject { |name| resolve_to_canonical(name, lookup) }
      missing.sort_by! { |name| [-recipes_map[name].uniq.size, name] }

      {
        missing: missing,
        ingredients_to_recipes: recipes_map,
        unresolvable: find_unresolvable_units(nutrition_data, ctx, lookup)
      }
    end

    def count_resolvable(nutrition_data, ctx)
      lookup = build_lookup(nutrition_data)
      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: ctx[:omit_set])

      ctx[:recipes].each_with_object(Hash.new { |h, k| h[k] = true }) do |recipe, fully|
        check_recipe_resolvability(recipe, ctx, lookup, calculator, fully)
      end
    end

    def format_pct(count, total)
      return '0%' if total.zero?

      "#{(100.0 * count / total).round(0)}%"
    end

    # --- USDA modifier classification ---

    def classify_usda_modifiers(modifiers)
      modifiers.each_with_object(density_candidates: [], portion_candidates: [], filtered: []) do |mod, result|
        entry = mod.merge(each: per_unit_grams(mod))
        bucket, extra = modifier_bucket(mod[:modifier])
        result[bucket] << entry.merge(extra)
      end
    end

    def pick_best_density(density_candidates)
      density_candidates.max_by { |c| c[:grams] }
    end

    def strip_parenthetical(modifier)
      modifier.to_s.sub(/\s*\([^)]*\)/, '').strip
    end

    def volume_modifier?(modifier)
      VOLUME_UNITS.any? { |u| modifier.to_s.downcase.start_with?(u) }
    end

    def weight_modifier?(modifier)
      WEIGHT_UNITS.any? { |u| modifier.to_s.downcase.start_with?(u) }
    end

    def regulatory_modifier?(modifier)
      modifier.to_s.downcase.match?(/\bnlea\b|\bserving\b|\bpacket\b/)
    end

    def normalize_volume_unit(modifier)
      clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
      word = clean.split(/[\s,]+/).first
      canonicalize_volume(word)
    end

    # --- Private helpers ---

    def round_entry_values(entry)
      entry['nutrients']&.transform_values! { |v| v.is_a?(Float) ? v.round(4) : v } if entry['nutrients'].is_a?(Hash)
      entry['portions']&.transform_values! { |v| v.is_a?(Float) ? v.round(2) : v } if entry['portions'].is_a?(Hash)
      round_density(entry['density']) if entry['density'].is_a?(Hash)
    end

    def round_density(density)
      density['grams'] = density['grams'].round(2) if density['grams'].is_a?(Float)
      density['volume'] = density['volume'].round(4) if density['volume'].is_a?(Float)
    end

    def build_ingredients_to_recipes(ctx)
      ctx[:recipes].each_with_object(Hash.new { |h, k| h[k] = [] }) do |recipe, map|
        recipe.all_ingredient_names.each do |name|
          map[name] << recipe.title unless ctx[:omit_set].include?(name.downcase)
        end
      end
    end

    def find_unresolvable_units(nutrition_data, ctx, lookup)
      calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: ctx[:omit_set])

      ctx[:recipes].each_with_object(Hash.new { |h, k| h[k] = { units: Set.new, recipes: [] } }) do |recipe, result|
        check_recipe_units(recipe, ctx, lookup, calculator, result)
      end
    end

    def resolve_calc_entry(name, lookup, calculator)
      canonical = resolve_to_canonical(name, lookup)
      canonical && calculator.nutrition_data[canonical]
    end

    def collect_bad_units(amounts, calc_entry, calculator)
      amounts.filter_map do |amount|
        next if amount.nil? || amount.value.nil?
        next if calculator.resolvable?(amount.value, amount.unit, calc_entry)

        amount.unit || '(bare count)'
      end
    end

    private_class_method :round_entry_values, :round_density,
                         :build_ingredients_to_recipes, :find_unresolvable_units,
                         :resolve_calc_entry, :collect_bad_units

    # --- Extracted helpers to keep methods short ---

    def register_name(lookup, key, canonical)
      lookup[key] ||= canonical
      lookup[key.downcase] ||= canonical
    end

    def register_variants(lookup, name)
      FamilyRecipes::Inflector.ingredient_variants(name).each do |variant|
        register_name(lookup, variant, name)
      end
    end

    def register_aliases(lookup, name, entry, nutrition_data)
      (entry['aliases'] || []).each do |alias_name|
        next if nutrition_data.key?(alias_name)

        register_name(lookup, alias_name, name)
      end
    end

    def build_omit_set(catalog)
      catalog.each_with_object(Set.new) do |(name, entry), set|
        set << name.downcase if entry['aisle'] == 'omit'
      end
    end

    def check_recipe_resolvability(recipe, ctx, lookup, calculator, fully)
      recipe.all_ingredients_with_quantities(ctx[:recipe_map]).each do |name, amounts|
        next if ctx[:omit_set].include?(name.downcase)

        calc_entry = resolve_calc_entry(name, lookup, calculator)
        next unless calc_entry

        fully[name] = false if collect_bad_units(amounts, calc_entry, calculator).any?
        fully[name] = true unless fully.key?(name)
      end
    end

    def check_recipe_units(recipe, ctx, lookup, calculator, result)
      recipe.all_ingredients_with_quantities(ctx[:recipe_map]).each do |name, amounts|
        next if ctx[:omit_set].include?(name.downcase)

        canonical = resolve_to_canonical(name, lookup)
        next unless canonical

        calc_entry = calculator.nutrition_data[canonical]
        bad = calc_entry ? collect_bad_units(amounts, calc_entry, calculator) : collect_all_units(amounts)
        bad.each do |unit|
          result[canonical][:units] << unit
          result[canonical][:recipes] |= [recipe.title]
        end
      end
    end

    def collect_all_units(amounts)
      amounts.filter_map do |amount|
        next if amount.nil? || amount.value.nil?

        amount.unit || '(bare count)'
      end
    end

    def per_unit_grams(mod)
      (mod[:grams] / mod[:amount].to_f).round(2)
    end

    def modifier_bucket(modifier)
      if weight_modifier?(modifier)
        [:filtered, { reason: 'weight unit' }]
      elsif regulatory_modifier?(modifier)
        [:filtered, { reason: 'regulatory' }]
      elsif volume_modifier?(modifier)
        [:density_candidates, {}]
      else
        [:portion_candidates, { display_name: strip_parenthetical(modifier) }]
      end
    end

    def canonicalize_volume(word)
      case word
      when 'cups', 'cup' then 'cup'
      when 'tablespoon', 'tablespoons', 'tbsp' then 'tbsp'
      when 'teaspoon', 'teaspoons', 'tsp' then 'tsp'
      when 'fl' then 'fl oz'
      else word
      end
    end

    private_class_method :register_name, :register_variants, :register_aliases,
                         :build_omit_set, :check_recipe_resolvability,
                         :check_recipe_units, :collect_all_units,
                         :per_unit_grams, :modifier_bucket, :canonicalize_volume
  end # rubocop:enable Metrics/ModuleLength
end

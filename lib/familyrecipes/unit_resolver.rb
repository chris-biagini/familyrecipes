# frozen_string_literal: true

module FamilyRecipes
  # Resolves ingredient quantities to grams via a priority chain: weight units →
  # named portions → density-derived volume conversions. Wraps one
  # IngredientCatalog entry; nil entries are safe (only weight units resolve).
  # Owns the canonical unit conversion tables and their Inflector-expanded
  # variants — the single source of truth for unit recognition across the app.
  #
  # Collaborators:
  # - NutritionCalculator (delegates to_grams here during nutrition aggregation)
  # - IngredientRowBuilder (calls resolvable? for coverage analysis)
  # - UsdaPortionClassifier (reads EXPANDED_*_UNITS for portion classification)
  class UnitResolver
    WEIGHT_CONVERSIONS = {
      'g' => 1, 'oz' => 28.3495, 'lb' => 453.592, 'kg' => 1000
    }.freeze

    VOLUME_TO_ML = {
      'tsp' => 4.929, 'tbsp' => 14.787, 'fl oz' => 29.5735,
      'cup' => 236.588, 'pt' => 473.176, 'qt' => 946.353,
      'gal' => 3785.41, 'ml' => 1, 'l' => 1000
    }.freeze

    DENSITY_UNITS = ['cup', 'tbsp', 'tsp', 'fl oz', 'ml', 'l'].freeze

    EXPANDED_VOLUME_UNITS = begin
      units = VOLUME_TO_ML.keys.to_set
      Inflector::ABBREVIATIONS.each { |long, short| units << long if VOLUME_TO_ML.key?(short) }
      Inflector::KNOWN_PLURALS.each { |sing, pl| units << pl if units.include?(sing) }
      units.freeze
    end

    EXPANDED_WEIGHT_UNITS = begin
      units = WEIGHT_CONVERSIONS.keys.to_set
      Inflector::ABBREVIATIONS.each { |long, short| units << long if WEIGHT_CONVERSIONS.key?(short) }
      Inflector::KNOWN_PLURALS.each { |sing, pl| units << pl if units.include?(sing) }
      units.freeze
    end

    def self.weight_unit?(unit)
      unit && WEIGHT_CONVERSIONS.key?(unit.downcase)
    end

    def self.volume_unit?(unit)
      unit && VOLUME_TO_ML.key?(unit.downcase)
    end

    def initialize(entry)
      @entry = entry
    end

    def to_grams(value, unit)
      return resolve_bare_count(value) if unit.nil?

      unit_down = unit.downcase
      resolve_weight(value, unit_down) ||
        resolve_named_portion(value, unit, unit_down) ||
        resolve_volume(value, unit_down)
    end

    def resolvable?(value, unit)
      !to_grams(value, unit).nil?
    end

    def density
      return nil unless @entry

      volume_ml = density_volume_ml
      return nil unless volume_ml&.positive?

      @entry.density_grams / volume_ml
    end

    private

    def density_volume_ml
      return nil unless @entry.density_grams && @entry.density_volume && @entry.density_unit

      ml_factor = VOLUME_TO_ML[@entry.density_unit.downcase]
      @entry.density_volume * ml_factor if ml_factor
    end

    def resolve_bare_count(value)
      return nil unless @entry

      grams_per_unit = @entry.portions&.dig('~unitless')
      grams_per_unit ? value * grams_per_unit : nil
    end

    def resolve_weight(value, unit_down)
      factor = WEIGHT_CONVERSIONS[unit_down]
      value * factor if factor
    end

    def resolve_named_portion(value, unit, unit_down)
      return nil unless @entry

      portions = @entry.portions || {}
      grams = portions[unit] || portions[unit_down] ||
              portions.find { |k, _| k.downcase == unit_down }&.last
      value * grams if grams
    end

    def resolve_volume(value, unit_down)
      return nil unless @entry

      ml_factor = VOLUME_TO_ML[unit_down]
      return nil unless ml_factor

      d = density
      value * ml_factor * d if d
    end
  end
end

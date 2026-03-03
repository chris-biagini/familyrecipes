# frozen_string_literal: true

module FamilyRecipes
  # Shared validation constraints for ingredient catalog data. Single source of
  # truth for rules enforced by both the IngredientCatalog Rails model and the
  # bin/nutrition TUI editors. Predicate methods return [valid, error_message]
  # tuples — callers check the first element and use the second for display.
  #
  # Collaborators:
  # - IngredientCatalog (delegates custom validators here)
  # - NutritionTui::Editors::* (calls predicates on close/commit)
  module NutritionConstraints
    NUTRIENT_MAX = Hash.new(10_000).merge('sodium' => 50_000).freeze
    AISLE_MAX_LENGTH = 50

    module_function

    def valid_basis_grams?(value)
      return [false, 'Basis grams must be greater than 0'] unless value.is_a?(Numeric) && value.positive?

      [true, nil]
    end

    def valid_nutrient?(key, value)
      return [false, "#{key} must be a number"] unless value.is_a?(Numeric)

      max = NUTRIENT_MAX[key.to_s]
      return [false, "#{key} must be between 0 and #{max}"] unless value.between?(0, max)

      [true, nil]
    end

    def density_complete?(hash)
      return [true, nil] if hash.blank?

      missing = %w[grams volume unit].reject { |k| hash[k].present? }
      return [false, "Density requires #{missing.join(', ')}"] if missing.any?

      validate_density_values(hash)
    end

    def valid_portion_value?(value)
      return [false, 'Portion value must be greater than 0'] unless value.is_a?(Numeric) && value.positive?

      [true, nil]
    end

    def valid_aisle?(value)
      return [true, nil] if value.nil?
      return [false, "Aisle name must be #{AISLE_MAX_LENGTH} characters or fewer"] if value.to_s.size > AISLE_MAX_LENGTH

      [true, nil]
    end

    def validate_density_values(hash)
      grams = hash['grams']
      return [false, 'Density grams must be greater than 0'] unless grams.is_a?(Numeric) && grams.positive?

      volume = hash['volume']
      return [false, 'Density volume must be greater than 0'] unless volume.is_a?(Numeric) && volume.positive?

      return [false, 'Density unit must not be blank'] if hash['unit'].to_s.strip.empty?

      [true, nil]
    end

    private_class_method :validate_density_values
  end
end

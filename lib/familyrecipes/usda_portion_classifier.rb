# frozen_string_literal: true

module FamilyRecipes
  # Classifies raw USDA FoodData Central portion entries into three buckets:
  # density candidates (volume-based, usable for g/mL density), portion
  # candidates (discrete units like "clove" or "large"), and filtered entries
  # (weight units and regulatory labels that carry no new information).
  #
  # Collaborators:
  # - UsdaClient (produces the raw portion hashes this class consumes)
  # - NutritionCalculator (EXPANDED_VOLUME_UNITS, EXPANDED_WEIGHT_UNITS)
  class UsdaPortionClassifier
    Result = Data.define(:density_candidates, :portion_candidates, :filtered)

    def self.classify(portions)
      buckets = portions.each_with_object(density: [], portions: [], filtered: []) do |mod, result|
        entry = mod.merge(each: per_unit_grams(mod))
        bucket, extra = modifier_bucket(mod[:modifier])
        result[bucket] << entry.merge(extra)
      end

      Result.new(
        density_candidates: buckets[:density],
        portion_candidates: buckets[:portions],
        filtered: buckets[:filtered]
      )
    end

    def self.pick_best_density(density_candidates)
      density_candidates.max_by { |c| c[:each] }
    end

    def self.normalize_volume_unit(modifier)
      clean = modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip
      words = clean.split(/[\s,]+/)
      two_word = Inflector.normalize_unit(words.first(2).join(' '))
      return two_word if NutritionCalculator::VOLUME_TO_ML.key?(two_word)

      Inflector.normalize_unit(words.first)
    end

    def self.strip_parenthetical(modifier)
      modifier.to_s.sub(/\s*\([^)]*\)/, '').strip
    end

    def self.volume_modifier?(modifier)
      unit_prefix_match?(modifier, NutritionCalculator::EXPANDED_VOLUME_UNITS)
    end

    def self.weight_modifier?(modifier)
      unit_prefix_match?(modifier, NutritionCalculator::EXPANDED_WEIGHT_UNITS)
    end

    def self.regulatory_modifier?(modifier)
      modifier.to_s.downcase.match?(/\bnlea\b|\bserving\b|\bpacket\b/)
    end

    # Matches when modifier starts with a unit and the next char is
    # a word boundary (space, comma, paren, or end-of-string). Prevents
    # 'l' matching 'large' or 'g' matching 'garlic'.
    def self.unit_prefix_match?(modifier, prefixes)
      downcased = modifier.to_s.downcase
      prefixes.any? { |u| downcased.start_with?(u) && (downcased.size == u.size || downcased[u.size] =~ /[\s,(]/) }
    end
    private_class_method :unit_prefix_match?

    def self.per_unit_grams(mod)
      (mod[:grams] / mod[:amount].to_f).round(2)
    end
    private_class_method :per_unit_grams

    def self.modifier_bucket(modifier)
      if weight_modifier?(modifier)
        [:filtered, { reason: 'weight unit' }]
      elsif regulatory_modifier?(modifier)
        [:filtered, { reason: 'regulatory' }]
      elsif volume_modifier?(modifier)
        [:density, {}]
      else
        [:portions, { display_name: strip_parenthetical(modifier) }]
      end
    end
    private_class_method :modifier_bucket
  end
end

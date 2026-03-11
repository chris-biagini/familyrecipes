# frozen_string_literal: true

# Transforms raw USDA FoodData Central detail (from UsdaClient#fetch) into
# structured form values for the ingredient editor. Extracts nutrients, auto-
# picks density from the largest volume-based portion candidate, and classifies
# portions into informational categories. Pure data transformation — no
# persistence, no side effects. Result#as_json enables direct `render json:`
# in controllers.
#
# Collaborators:
# - UsdaClient (produces the detail hash this service consumes)
# - UsdaPortionClassifier (classifies portions into density/portion/filtered)
# - UsdaSearchController (renders Result directly as JSON)
class UsdaImportService
  Result = Data.define(:nutrients, :density, :source, :portions, :density_candidates) do
    def as_json(_options = nil)
      to_h
    end
  end

  def self.call(detail)
    new(detail).call
  end

  def initialize(detail)
    @detail = detail
  end

  def call
    classified = FamilyRecipes::UsdaPortionClassifier.classify(@detail[:portions])

    Result.new(
      nutrients: extract_nutrients,
      density: pick_density(classified.density_candidates),
      source: build_source,
      portions: extract_portions(classified.portion_candidates),
      density_candidates: classified.density_candidates
    )
  end

  private

  def extract_nutrients
    raw = @detail[:nutrients]
    FamilyRecipes::NutritionConstraints::NUTRIENT_KEYS.each_with_object(
      { basis_grams: raw['basis_grams'] }
    ) do |key, hash|
      hash[key] = raw[key.to_s]
    end
  end

  def pick_density(density_candidates)
    best = FamilyRecipes::UsdaPortionClassifier.pick_best_density(density_candidates)
    return unless best

    unit = FamilyRecipes::UsdaPortionClassifier.normalize_volume_unit(best[:modifier])
    { grams: best[:each].round(2), volume: 1.0, unit: unit }
  end

  def build_source
    { type: 'usda', dataset: @detail[:data_type],
      fdc_id: @detail[:fdc_id], description: @detail[:description] }
  end

  def extract_portions(portion_candidates)
    portion_candidates.map do |candidate|
      { name: candidate[:display_name], grams: candidate[:each] }
    end
  end
end

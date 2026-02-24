# frozen_string_literal: true

class RecipeNutritionJob < ApplicationJob
  NUTRIENT_COLUMNS = %w[calories fat saturated_fat trans_fat cholesterol
                        sodium carbs fiber total_sugars added_sugars protein].freeze

  def perform(recipe)
    nutrition_data = build_nutrition_lookup(recipe.kitchen)
    return if nutrition_data.empty?

    calculator = FamilyRecipes::NutritionCalculator.new(nutrition_data, omit_set: omit_set)
    result = calculator.calculate(parsed_recipe(recipe), recipe_map(recipe.kitchen))

    recipe.update_column(:nutrition_data, serialize_result(result))
  end

  private

  def build_nutrition_lookup(kitchen)
    IngredientCatalog.lookup_for(kitchen).transform_values do |entry|
      data = { 'nutrients' => nutrients_hash(entry) }
      data['density'] = density_hash(entry) if entry.density_grams && entry.density_volume && entry.density_unit
      data['portions'] = entry.portions if entry.portions.present?
      data
    end
  end

  def nutrients_hash(entry)
    NUTRIENT_COLUMNS.each_with_object({ 'basis_grams' => entry.basis_grams.to_f }) do |col, hash|
      hash[col] = entry.public_send(col)&.to_f || 0
    end
  end

  def density_hash(entry)
    {
      'grams' => entry.density_grams.to_f,
      'volume' => entry.density_volume.to_f,
      'unit' => entry.density_unit
    }
  end

  def parsed_recipe(recipe)
    FamilyRecipes::Recipe.new(
      markdown_source: recipe.markdown_source,
      id: recipe.slug,
      category: recipe.category.name
    )
  end

  def omit_set
    @omit_set ||= IngredientCatalog.where(aisle: 'omit').pluck(:ingredient_name).to_set(&:downcase)
  end

  def recipe_map(kitchen)
    @recipe_map ||= kitchen.recipes.includes(:category).to_h do |r|
      [r.slug, parsed_recipe(r)]
    end
  end

  def serialize_result(result)
    {
      'totals' => stringify_nutrient_keys(result.totals),
      'serving_count' => result.serving_count,
      'per_serving' => stringify_nutrient_keys(result.per_serving),
      'per_unit' => stringify_nutrient_keys(result.per_unit),
      'makes_quantity' => result.makes_quantity,
      'makes_unit_singular' => result.makes_unit_singular,
      'makes_unit_plural' => result.makes_unit_plural,
      'units_per_serving' => result.units_per_serving,
      'missing_ingredients' => result.missing_ingredients,
      'partial_ingredients' => result.partial_ingredients
    }
  end

  def stringify_nutrient_keys(hash)
    return unless hash

    hash.transform_keys(&:to_s).transform_values(&:to_f)
  end
end

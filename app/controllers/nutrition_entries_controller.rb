# frozen_string_literal: true

class NutritionEntriesController < ApplicationController
  before_action :require_membership

  def upsert
    result = NutritionLabelParser.parse(params[:label_text])
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.success?

    entry = IngredientProfile.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    assign_parsed_attributes(entry, result)

    if entry.save
      recalculate_affected_recipes
      render json: { status: 'ok' }
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    entry = IngredientProfile.find_by!(kitchen: current_kitchen, ingredient_name:)
    entry.destroy!
    recalculate_affected_recipes
    render json: { status: 'ok' }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def ingredient_name
    params[:ingredient_name].tr('-', ' ')
  end

  def assign_parsed_attributes(entry, result)
    entry.assign_attributes(
      basis_grams: result.nutrients[:basis_grams],
      calories: result.nutrients[:calories],
      fat: result.nutrients[:fat],
      saturated_fat: result.nutrients[:saturated_fat],
      trans_fat: result.nutrients[:trans_fat],
      cholesterol: result.nutrients[:cholesterol],
      sodium: result.nutrients[:sodium],
      carbs: result.nutrients[:carbs],
      fiber: result.nutrients[:fiber],
      total_sugars: result.nutrients[:total_sugars],
      added_sugars: result.nutrients[:added_sugars],
      protein: result.nutrients[:protein],
      density_grams: result.density&.dig(:grams),
      density_volume: result.density&.dig(:volume),
      density_unit: result.density&.dig(:unit),
      portions: result.portions,
      sources: [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }]
    )
  end

  def recalculate_affected_recipes
    canonical = ingredient_name.downcase
    current_kitchen.recipes.includes(steps: :ingredients)
                   .select { |recipe| recipe.ingredients.any? { |i| i.name.downcase == canonical } }
                   .each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end
end

# frozen_string_literal: true

class NutritionEntriesController < ApplicationController
  before_action :require_membership

  def upsert
    aisle = params[:aisle]&.strip.presence
    label_text = params[:label_text].to_s

    if blank_nutrition?(label_text)
      return render json: { errors: ['Nothing to save'] }, status: :unprocessable_content unless aisle

      save_aisle_only(aisle)
    else
      result = NutritionLabelParser.parse(label_text)
      return render json: { errors: result.errors }, status: :unprocessable_content unless result.success?

      save_full_entry(result, aisle)
    end
  end

  def destroy
    entry = IngredientCatalog.find_by!(kitchen: current_kitchen, ingredient_name:)
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

  def blank_nutrition?(text)
    stripped = normalize_whitespace(text)
    stripped.empty? || stripped == normalize_whitespace(NutritionLabelParser.blank_skeleton)
  end

  def normalize_whitespace(text)
    text.lines.map(&:strip).reject(&:empty?).join("\n")
  end

  def save_aisle_only(aisle)
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    entry.aisle = aisle

    if entry.save
      sync_aisle_to_kitchen(aisle)
      broadcast_aisle_change
      render json: { status: 'ok' }
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_content
    end
  end

  def save_full_entry(result, aisle)
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    assign_parsed_attributes(entry, result)
    entry.aisle = aisle if aisle

    if entry.save
      sync_aisle_to_kitchen(aisle) if aisle
      broadcast_aisle_change if aisle
      recalculate_affected_recipes
      render json: { status: 'ok' }
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_content
    end
  end

  def sync_aisle_to_kitchen(aisle)
    return if aisle == 'omit'
    return if current_kitchen.parsed_aisle_order.include?(aisle)

    existing = current_kitchen.aisle_order.to_s
    current_kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
  end

  def broadcast_aisle_change
    GroceryListChannel.broadcast_content_changed(current_kitchen)
  end

  def assign_parsed_attributes(entry, result) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
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
  end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def recalculate_affected_recipes
    canonical = ingredient_name.downcase
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where('LOWER(ingredients.name) = ?', canonical)
                   .distinct
                   .each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end
end

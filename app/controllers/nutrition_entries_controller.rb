# frozen_string_literal: true

class NutritionEntriesController < ApplicationController
  include IngredientRows

  before_action :require_membership

  WEB_SOURCE = [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }].freeze

  def upsert
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    entry.assign_from_params(**catalog_params, sources: WEB_SOURCE)
    return render_errors(entry) unless entry.save

    after_save(entry)
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

  def catalog_params
    { nutrients: permitted_nutrients, density: permitted_density,
      portions: permitted_portions, aisle: params[:aisle]&.strip.presence }
  end

  def permitted_nutrients
    return {} unless params[:nutrients]

    params[:nutrients].permit(:basis_grams, *IngredientCatalog::NUTRIENT_COLUMNS).to_h.symbolize_keys
  end

  def permitted_density
    return {} unless params[:density]

    params[:density].permit(:volume, :unit, :grams).to_h.symbolize_keys
  end

  def permitted_portions
    return {} unless params[:portions]

    params[:portions].permit!.to_h
  end

  def render_errors(entry)
    render json: { errors: entry.errors.full_messages }, status: :unprocessable_content
  end

  def after_save(entry)
    aisle = entry.aisle
    has_nutrition = entry.basis_grams.present?

    sync_aisle_to_kitchen(aisle) if aisle
    broadcast_aisle_change if aisle
    recalculate_affected_recipes if has_nutrition

    respond_to do |format|
      format.turbo_stream { render_turbo_stream_update }
      format.json { render_json_response }
    end
  end

  def render_json_response
    response_body = { status: 'ok' }
    response_body[:next_ingredient] = find_next_needing_attention if params[:save_and_next]
    render json: response_body
  end

  def render_turbo_stream_update
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    all_rows = build_ingredient_rows(lookup)
    @updated_row = all_rows.find { |r| r[:name].casecmp(ingredient_name).zero? }
    @summary = build_summary(all_rows)
    @next_ingredient = find_next_needing_attention if params[:save_and_next]

    render :upsert
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

  def recalculate_affected_recipes
    canonical = ingredient_name.downcase
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where('LOWER(ingredients.name) = ?', canonical)
                   .distinct
                   .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end

  def find_next_needing_attention
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    sorted = canonical_ingredient_names(lookup)
    idx = sorted.index { |name| name.casecmp(ingredient_name).zero? }
    return unless idx

    sorted[(idx + 1)..].find { |name| ingredient_incomplete?(lookup[name]) }
  end

  def canonical_ingredient_names(lookup)
    current_kitchen.recipes.includes(steps: :ingredients)
                   .flat_map(&:ingredients)
                   .map { |i| lookup[i.name]&.ingredient_name || i.name }
                   .uniq
                   .sort_by(&:downcase)
  end

  def ingredient_incomplete?(entry)
    entry&.basis_grams.blank? || entry.density_grams.blank?
  end
end

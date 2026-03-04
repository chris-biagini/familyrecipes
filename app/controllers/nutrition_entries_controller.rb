# frozen_string_literal: true

# JSON/Turbo Stream API for creating, updating, and deleting kitchen-scoped
# IngredientCatalog entries from the web nutrition editor. On save, syncs new
# aisles to the kitchen's aisle_order, broadcasts a page-refresh signal for
# cross-device sync, and recalculates nutrition for all affected recipes.
# Responds with Turbo Stream updates to refresh the ingredients table in-place.
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
    Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
    render json: { status: 'ok' }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def ingredient_name
    params[:ingredient_name]
  end

  def catalog_params
    { nutrients: permitted_nutrients, density: permitted_density,
      portions: permitted_portions, aisle: params[:aisle]&.strip.presence,
      aliases: permitted_aliases }
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

    params[:portions].permit!.to_h.select { |k, v| k.size <= 50 && v.to_s.match?(/\A[\d.]+\z/) }
  end

  def permitted_aliases
    return unless params.key?(:aliases)

    Array(params[:aliases]).map { |a| a.to_s.strip }.compact_blank.uniq.first(20)
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
    if params[:save_and_next]
      lookup = IngredientCatalog.lookup_for(current_kitchen)
      response_body[:next_ingredient] = next_needing_attention(after: ingredient_name, lookup:)
    end
    render json: response_body
  end

  def render_turbo_stream_update
    lookup = IngredientCatalog.lookup_for(current_kitchen)
    all_rows = build_ingredient_rows(lookup)
    @updated_row = all_rows.find { |r| r[:name].casecmp(ingredient_name).zero? }
    @summary = build_summary(all_rows)
    @next_ingredient = next_needing_attention(after: ingredient_name, lookup:) if params[:save_and_next]

    render :upsert
  end

  def sync_aisle_to_kitchen(aisle)
    return if aisle == 'omit'
    return if current_kitchen.parsed_aisle_order.include?(aisle)

    existing = current_kitchen.aisle_order.to_s
    current_kitchen.update!(aisle_order: [existing, aisle].reject(&:empty?).join("\n"))
  end

  def broadcast_aisle_change
    Turbo::StreamsChannel.broadcast_refresh_to(current_kitchen, :meal_plan_updates)
  end

  def recalculate_affected_recipes
    canonical = ingredient_name.downcase
    current_kitchen.recipes
                   .joins(steps: :ingredients)
                   .where('LOWER(ingredients.name) = ?', canonical)
                   .distinct
                   .find_each { |recipe| RecipeNutritionJob.perform_now(recipe) }
  end
end

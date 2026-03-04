# frozen_string_literal: true

# Thin adapter for the web nutrition editor — param parsing, delegation to
# CatalogWriteService for persistence and side effects, and response rendering
# via IngredientRowBuilder. No orchestration logic lives here.
#
# - CatalogWriteService: upsert/destroy with aisle sync, nutrition recalc, broadcasts
# - IngredientRowBuilder: computes table rows, summary, and next-needing-attention
class NutritionEntriesController < ApplicationController
  before_action :require_membership

  def upsert
    result = CatalogWriteService.upsert(kitchen: current_kitchen, ingredient_name:, params: catalog_params) # rubocop:disable Rails/SkipsModelValidations
    return render_errors(result.entry) unless result.persisted

    respond_to do |format|
      format.turbo_stream { render_turbo_stream_update }
      format.json { render_json_response }
    end
  end

  def destroy
    CatalogWriteService.destroy(kitchen: current_kitchen, ingredient_name:)
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

  def render_json_response
    response_body = { status: 'ok' }
    if params[:save_and_next]
      response_body[:next_ingredient] = row_builder.next_needing_attention(after: ingredient_name)
    end
    render json: response_body
  end

  def render_turbo_stream_update
    @updated_row = row_builder.rows.find { |r| r[:name].casecmp(ingredient_name).zero? }
    @summary = row_builder.summary
    @next_ingredient = row_builder.next_needing_attention(after: ingredient_name) if params[:save_and_next]

    render :upsert
  end

  def row_builder
    @row_builder ||= IngredientRowBuilder.new(kitchen: current_kitchen)
  end
end

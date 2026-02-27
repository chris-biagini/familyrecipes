# frozen_string_literal: true

class NutritionEntriesController < ApplicationController # rubocop:disable Metrics/ClassLength
  include IngredientRows

  before_action :require_membership

  NUTRIENT_KEYS = %i[basis_grams calories fat saturated_fat trans_fat cholesterol
                     sodium carbs fiber total_sugars added_sugars protein].freeze
  WEB_SOURCE = [{ 'type' => 'web', 'note' => 'Entered via ingredients page' }].freeze

  def upsert
    aisle = params[:aisle]&.strip.presence
    if aisle && aisle.size > Kitchen::MAX_AISLE_NAME_LENGTH
      return render json: { errors: ["Aisle name is too long (max #{Kitchen::MAX_AISLE_NAME_LENGTH} characters)"] },
                    status: :unprocessable_content
    end

    return handle_structured_json(aisle) if params[:nutrients]

    handle_label_text(aisle)
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

  # --- label text path (CLI / textarea) ---

  def handle_label_text(aisle)
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

  def blank_nutrition?(text)
    stripped = normalize_whitespace(text)
    stripped.empty? || stripped == normalize_whitespace(NutritionLabelParser.blank_skeleton)
  end

  def normalize_whitespace(text)
    text.lines.map(&:strip).reject(&:empty?).join("\n")
  end

  def save_full_entry(result, aisle)
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    assign_parsed_attributes(entry, result)
    entry.aisle = aisle if aisle
    save_entry_and_respond(entry, aisle:, has_nutrition: true)
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
      sources: WEB_SOURCE
    )
  end # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  # --- structured JSON path (ingredients page form) ---

  def handle_structured_json(aisle)
    nutrients = params[:nutrients].to_unsafe_h
    has_nutrition = nutrients[:basis_grams].present?

    return validate_and_build_structured_entry(nutrients, aisle) if has_nutrition
    return render json: { errors: ['Nothing to save'] }, status: :unprocessable_content unless aisle

    save_aisle_only(aisle)
  end

  def validate_and_build_structured_entry(nutrients, aisle)
    unless nutrients[:basis_grams].to_f.positive?
      return render json: { errors: ['basis_grams must be greater than 0'] }, status: :unprocessable_content
    end

    entry = build_structured_entry(nutrients, aisle)
    save_entry_and_respond(entry, aisle:, has_nutrition: true)
  end

  def build_structured_entry(nutrients, aisle)
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    entry.assign_attributes(nutrients.slice(*NUTRIENT_KEYS))
    assign_density(entry, params[:density])
    assign_portions(entry, params[:portions])
    entry.sources = WEB_SOURCE
    entry.aisle = aisle if aisle
    entry
  end

  def assign_density(entry, density_params)
    if density_params.blank?
      entry.assign_attributes(density_volume: nil, density_unit: nil, density_grams: nil)
    else
      density = density_params.to_unsafe_h
      entry.assign_attributes(density_volume: density[:volume], density_unit: density[:unit],
                              density_grams: density[:grams])
    end
  end

  def assign_portions(entry, portions_params)
    return entry.portions = {} if portions_params.blank?

    raw = portions_params.to_unsafe_h.stringify_keys
    unitless_value = raw.delete('each') || raw.delete('Each')
    raw['~unitless'] = unitless_value if unitless_value
    entry.portions = raw
  end

  # --- shared save + response ---

  def save_aisle_only(aisle)
    entry = IngredientCatalog.find_or_initialize_by(kitchen: current_kitchen, ingredient_name:)
    entry.aisle = aisle
    save_entry_and_respond(entry, aisle:, has_nutrition: false)
  end

  def save_entry_and_respond(entry, aisle:, has_nutrition:)
    return render json: { errors: entry.errors.full_messages }, status: :unprocessable_content unless entry.save

    finalize_save(aisle:, has_nutrition:)
  end

  def finalize_save(aisle:, has_nutrition:)
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

  # --- save & next ---

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

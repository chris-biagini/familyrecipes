# frozen_string_literal: true

module RecipesHelper
  def render_markdown(text)
    return '' if text.blank?

    FamilyRecipes::Recipe::MARKDOWN.render(text).html_safe
  end

  def scalable_instructions(text)
    return '' if text.blank?

    processed = ScalableNumberPreprocessor.process_instructions(text)
    render_markdown(processed)
  end

  def format_yield_line(text)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_line(text).html_safe
  end

  def format_yield_with_unit(text, singular, plural)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_with_unit(text, singular, plural).html_safe
  end

  # Returns array of [label, values_hash, is_scalable] tuples for the nutrition table.
  def nutrition_columns(nutrition)
    has_per_unit = nutrition['per_unit'] && nutrition['makes_quantity']&.to_f&.positive?
    has_per_serving = nutrition['per_serving'] && nutrition['serving_count']

    columns = []

    if has_per_unit
      columns << ["Per #{nutrition['makes_unit_singular']&.capitalize}", nutrition['per_unit'], false]
      columns << [per_serving_label(nutrition), nutrition['per_serving'], false] if has_per_serving && nutrition['units_per_serving']
      columns << ['Total', nutrition['totals'], true]
    elsif has_per_serving
      columns << ['Per Serving', nutrition['per_serving'], false]
      columns << ['Total', nutrition['totals'], true]
    else
      columns << ['Total', nutrition['totals'], true]
    end

    columns
  end

  def nutrition_missing_ingredients(nutrition)
    ((nutrition['missing_ingredients'] || []) + (nutrition['partial_ingredients'] || [])).uniq
  end

  private

  def per_serving_label(nutrition)
    ups = nutrition['units_per_serving']
    formatted_ups = FamilyRecipes::VulgarFractions.format(ups)
    singular = FamilyRecipes::VulgarFractions.singular_noun?(ups)
    ups_unit = singular ? nutrition['makes_unit_singular'] : nutrition['makes_unit_plural']
    "Per Serving<br>(#{ERB::Util.html_escape(formatted_ups)} #{ERB::Util.html_escape(ups_unit)})".html_safe
  end
end

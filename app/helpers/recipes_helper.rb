# frozen_string_literal: true

# View helpers for recipe pages: Markdown rendering (via Redcarpet with
# escape_html), scalable number formatting for instructions and yield lines,
# nutrition label column layout, and ingredient data attributes for the
# client-side scaling controller. All .html_safe calls are audited by
# rake lint:html_safe and allowlisted.
module RecipesHelper
  def render_markdown(text)
    return '' if text.blank?

    FamilyRecipes::Recipe::MARKDOWN.render(text).html_safe # rubocop:disable Rails/OutputSafety
  end

  def scalable_instructions(text)
    return '' if text.blank?

    html = FamilyRecipes::Recipe::MARKDOWN.render(text)
    ScalableNumberPreprocessor.process_instructions(html).html_safe # rubocop:disable Rails/OutputSafety
  end

  def format_yield_line(text)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_line(text).html_safe # rubocop:disable Rails/OutputSafety
  end

  def format_yield_with_unit(text, singular, plural)
    return '' if text.blank?

    ScalableNumberPreprocessor.process_yield_with_unit(text, singular, plural).html_safe # rubocop:disable Rails/OutputSafety
  end

  def nutrition_columns(nutrition) # rubocop:disable Metrics/PerceivedComplexity
    has_per_unit = nutrition['per_unit'] && nutrition['makes_quantity']&.to_f&.positive?
    has_per_serving = nutrition['per_serving'] && nutrition['serving_count']

    columns = []

    if has_per_unit
      columns << ["Per #{nutrition['makes_unit_singular']&.capitalize}", nutrition['per_unit'], false]
      if has_per_serving && nutrition['units_per_serving']
        columns << [per_serving_label(nutrition), nutrition['per_serving'], false]
      end
    elsif has_per_serving
      columns << ['Per Serving', nutrition['per_serving'], false]
    end

    columns << ['Total', nutrition['totals'], true]
  end # rubocop:enable Metrics/PerceivedComplexity

  def nutrition_missing_ingredients(nutrition)
    ((nutrition['missing_ingredients'] || []) + (nutrition['partial_ingredients'] || [])).uniq
  end

  def ingredient_data_attrs(item)
    attrs = {}
    return tag.attributes(attrs) unless item.quantity_value

    attrs[:'data-quantity-value'] = item.quantity_value
    attrs[:'data-quantity-unit'] = item.quantity_unit if item.quantity_unit
    add_unit_plural_attr(attrs, item.quantity_unit)
    add_name_inflection_attrs(attrs, item) unless item.quantity_unit

    tag.attributes(attrs)
  end

  private

  def add_unit_plural_attr(attrs, unit)
    return unless unit

    attrs[:'data-quantity-unit-plural'] =
      FamilyRecipes::Inflector.unit_display(unit, 2)
  end

  def add_name_inflection_attrs(attrs, item)
    singular = FamilyRecipes::Inflector.display_name(item.name, 1)
    plural = FamilyRecipes::Inflector.display_name(item.name, 2)
    return if singular == plural

    attrs[:'data-name-singular'] = singular
    attrs[:'data-name-plural'] = plural
  end

  def per_serving_label(nutrition)
    ups = nutrition['units_per_serving']
    formatted_ups = FamilyRecipes::VulgarFractions.format(ups)
    singular = FamilyRecipes::VulgarFractions.singular_noun?(ups)
    ups_unit = singular ? nutrition['makes_unit_singular'] : nutrition['makes_unit_plural']
    "Per Serving<br>(#{ERB::Util.html_escape(formatted_ups)} #{ERB::Util.html_escape(ups_unit)})".html_safe # rubocop:disable Rails/OutputSafety
  end
end

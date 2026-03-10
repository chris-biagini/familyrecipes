# frozen_string_literal: true

# View helpers for recipe pages: Markdown rendering (via Redcarpet with
# escape_html), scalable number formatting for instructions and yield lines,
# FDA nutrition label helpers (serving size, %DV), and ingredient data
# attributes for the client-side scaling controller. All .html_safe calls are
# audited by rake lint:html_safe and allowlisted.
#
# Collaborators:
# - NutritionConstraints (nutrient definitions, daily values)
# - VulgarFractions (human-readable fraction formatting)
# - ScalableNumberPreprocessor (instruction/yield scaling)
module RecipesHelper # rubocop:disable Metrics/ModuleLength
  NUTRITION_ROWS = FamilyRecipes::NutritionConstraints::NUTRIENT_DEFS.map do |d|
    [d.label, d.key.to_s, d.unit, d.indent, d.daily_value]
  end.freeze

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

  def format_makes(recipe)
    return unless recipe.makes_quantity

    "#{format_numeric(recipe.makes_quantity)} #{recipe.makes_unit_noun}"
  end

  def servings_per_recipe_text(nutrition)
    count = nutrition['serving_count'] || 1
    "#{count} #{'serving'.pluralize(count)} per recipe"
  end

  def serving_size_text(nutrition)
    weight = per_serving_weight(nutrition)
    weight_str = weight ? " (#{weight.round} g)" : ''

    "#{serving_unit_description(nutrition)}#{weight_str}".strip
  end

  def percent_daily_value(nutrient_key, amount)
    dv = FamilyRecipes::NutritionConstraints::DAILY_VALUES[nutrient_key]
    return unless dv

    (amount.to_f / dv * 100).round
  end

  def nutrition_missing_ingredients(nutrition)
    nutrition['missing_ingredients'] || []
  end

  def nutrition_partial_ingredients(nutrition)
    nutrition['partial_ingredients'] || []
  end

  def nutrition_skipped_ingredients(nutrition)
    nutrition['skipped_ingredients'] || []
  end

  def ingredient_data_attrs(item, scale_factor: 1.0)
    attrs = {}
    return tag.attributes(attrs) unless item.quantity_value

    attrs[:'data-quantity-value'] = item.quantity_value.to_f * scale_factor
    attrs[:'data-quantity-unit'] = item.quantity_unit if item.quantity_unit
    add_unit_plural_attr(attrs, item.quantity_unit)
    add_name_inflection_attrs(attrs, item) unless item.quantity_unit

    tag.attributes(attrs)
  end

  private

  def per_serving_weight(nutrition)
    total = nutrition['total_weight_grams']
    return unless total&.positive?

    count = nutrition['serving_count'] || 1
    total.to_f / count
  end

  def serving_unit_description(nutrition)
    makes_qty = nutrition['makes_quantity']
    serving_count = nutrition['serving_count']
    ups = nutrition['units_per_serving']

    if makes_qty && ups
      format_unit_serving(ups, nutrition)
    elsif makes_qty && serving_count
      format_unit_serving(makes_qty.to_f / serving_count, nutrition)
    elsif serving_count && serving_count > 1
      "#{FamilyRecipes::VulgarFractions.format(1.0 / serving_count)} recipe"
    else
      'entire recipe'
    end
  end

  def format_unit_serving(per_serving, nutrition)
    formatted = FamilyRecipes::VulgarFractions.format(per_serving)
    unit_key = FamilyRecipes::VulgarFractions.singular_noun?(per_serving) ? 'makes_unit_singular' : 'makes_unit_plural'
    "#{formatted} #{nutrition[unit_key]}"
  end

  def scaled_quantity_display(item, scale_factor)
    return format_quantity_display(item) if scale_factor == 1.0 || !item.quantity_value # rubocop:disable Lint/FloatComparison

    scaled = item.quantity_value.to_f * scale_factor
    formatted = FamilyRecipes::VulgarFractions.format(scaled, unit: item.quantity_unit)
    [formatted, item.unit].compact.join(' ')
  end

  def format_quantity_display(item)
    return unless item.quantity_value

    formatted = FamilyRecipes::VulgarFractions.format(item.quantity_value.to_f, unit: item.quantity_unit)
    [formatted, item.unit].compact.join(' ')
  end

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
end

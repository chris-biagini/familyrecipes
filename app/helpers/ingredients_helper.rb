# frozen_string_literal: true

module IngredientsHelper
  def nutrition_summary(entry)
    return unless entry&.basis_grams

    [
      "#{format_nutrient_value(entry.calories)} cal",
      "#{format_nutrient_value(entry.fat)}g fat",
      "#{format_nutrient_value(entry.carbs)}g carbs",
      "#{format_nutrient_value(entry.protein)}g protein"
    ].join(' · ')
  end

  def density_summary(entry)
    return unless entry&.density_grams && entry.density_volume

    vol = format_nutrient_value(entry.density_volume)
    grams = format_nutrient_value(entry.density_grams)
    "#{vol} #{entry.density_unit} = #{grams}g"
  end

  def portions_summary(entry)
    return if entry&.portions.blank?

    entry.portions.map do |name, grams|
      label = name == '~unitless' ? 'each' : name
      "1 #{label} = #{format_nutrient_value(grams)}g"
    end
  end

  def ingredient_status(entry)
    return :missing unless entry
    return :needs_nutrition unless entry.basis_grams
    return :needs_density unless entry.density_grams

    :complete
  end

  def display_aisle(aisle)
    return "\u2014" unless aisle

    aisle == 'omit' ? 'Omit' : aisle
  end

  def format_nutrient_value(value)
    return '0' unless value

    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end

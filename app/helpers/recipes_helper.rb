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
end

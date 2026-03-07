# frozen_string_literal: true

# Accepts uploaded files (ZIP or individual recipe files) and delegates to
# ImportService for upsert into the current kitchen. Thin adapter — all logic
# lives in ImportService.
#
# - ImportService: handles ZIP extraction, file routing, and delegation
# - Authentication concern: require_membership gates access to members only
# - Kitchen: tenant container receiving imported data
class ImportsController < ApplicationController
  before_action :require_membership

  def create
    files = Array(params[:files])

    if files.empty?
      render json: { message: 'No importable files found.' }
      return
    end

    result = ImportService.call(kitchen: current_kitchen, files:)
    render json: { message: import_summary(result) }
  end

  private

  def import_summary(result)
    parts = summary_parts(result)

    return 'No importable files found.' if parts.empty? && result.errors.empty?

    summary = parts.any? ? "Imported #{parts.join(', ')}." : ''
    error_detail = result.errors.any? ? " Failed: #{result.errors.join(', ')}." : ''
    "#{summary}#{error_detail}".strip
  end

  def summary_parts(result)
    parts = []
    parts << pluralize_count(result.recipes, 'recipe') if result.recipes.positive?
    parts << pluralize_count(result.ingredients, 'ingredient') if result.ingredients.positive?
    parts << 'Quick Bites' if result.quick_bites
    parts
  end

  def pluralize_count(count, noun)
    "#{count} #{noun}#{'s' unless count == 1}"
  end
end

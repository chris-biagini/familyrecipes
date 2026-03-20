# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle)
# and API keys (USDA, Anthropic). The settings dialog loads its form via a
# Turbo Frame (editor_frame) and saves via JSON PATCH.
#
# - Kitchen: settings live as columns on the tenant model
# - ApplicationController: provides current_kitchen and require_membership
class SettingsController < ApplicationController
  before_action :require_membership

  def show
    render json: {
      site_title: current_kitchen.site_title,
      homepage_heading: current_kitchen.homepage_heading,
      homepage_subtitle: current_kitchen.homepage_subtitle,
      usda_api_key: current_kitchen.usda_api_key,
      anthropic_api_key: current_kitchen.anthropic_api_key,
      show_nutrition: current_kitchen.show_nutrition,
      decorate_tags: current_kitchen.decorate_tags
    }
  end

  def editor_frame
    render partial: 'settings/editor_frame', locals: { kitchen: current_kitchen }, layout: false
  end

  def update
    if current_kitchen.update(settings_params)
      current_kitchen.broadcast_update
      render json: { status: 'ok' }
    else
      render json: { errors: current_kitchen.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key anthropic_api_key
                              show_nutrition decorate_tags])
  end
end

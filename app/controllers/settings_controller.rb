# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle)
# and API keys (USDA). JSON-only controller — the settings dialog fetches
# and saves via fetch requests.
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
      usda_api_key: current_kitchen.usda_api_key
    }
  end

  def update
    if current_kitchen.update(settings_params)
      render json: { status: 'ok' }
    else
      render json: { errors: current_kitchen.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key])
  end
end

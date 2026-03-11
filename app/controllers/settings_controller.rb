# frozen_string_literal: true

# Manages kitchen-scoped settings: site branding (title, heading, subtitle)
# and API keys (USDA). Thin controller — validates and saves directly to
# current_kitchen with no side effects.
#
# - Kitchen: settings live as columns on the tenant model
# - ApplicationController: provides current_kitchen and require_membership
class SettingsController < ApplicationController
  before_action :require_membership

  def show; end

  def update
    if current_kitchen.update(settings_params)
      redirect_to settings_path, notice: 'Settings saved.'
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def settings_params
    params.expect(kitchen: %i[site_title homepage_heading homepage_subtitle usda_api_key])
  end
end

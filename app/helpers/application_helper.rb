# frozen_string_literal: true

# Shared view helpers. format_numeric strips trailing ".0" from whole-number
# floats. app_version reads the REVISION file baked into Docker images at
# build time (falls back to "dev" in development).
module ApplicationHelper
  APP_VERSION = Rails.root.join('REVISION').then { |f| f.exist? ? f.read.strip : 'dev' }.freeze

  def format_numeric(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end

  def app_version
    APP_VERSION
  end
end

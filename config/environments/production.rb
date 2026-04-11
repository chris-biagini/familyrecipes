# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do # rubocop:disable Metrics/BlockLength
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Conservative default for non-fingerprinted files in public/ (error pages, icons, robots.txt).
  # Propshaft sets its own far-future headers for fingerprinted /assets/* via middleware.
  config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.hour.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == '/up' } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = '/up'

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # DNS rebinding protection — set ALLOWED_HOSTS to your domain(s).
  # Comma-separated: "recipes.example.com" or "recipes.local,192.168.1.50"
  # When unset, all hosts are allowed (backwards-compatible for simple setups).
  if ENV['ALLOWED_HOSTS'].present?
    config.hosts = ENV['ALLOWED_HOSTS'].split(',').map(&:strip)
    config.host_authorization = { exclude: ->(request) { request.path == '/up' } }
  end

  # Action Mailer — SMTP when configured, Rails logger delivery otherwise.
  # The logger fallback writes the full email to stdout so a homelab
  # operator without SMTP can retrieve the sign-in code from container logs.
  smtp_address = ENV.fetch('SMTP_ADDRESS', nil)
  base_url = ENV.fetch('BASE_URL', 'http://localhost:3030')
  config.action_mailer.delivery_method = smtp_address.present? ? :smtp : :logger
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.smtp_settings = {
    address: smtp_address,
    port: ENV.fetch('SMTP_PORT', 587).to_i,
    user_name: ENV.fetch('SMTP_USERNAME', nil),
    password: ENV.fetch('SMTP_PASSWORD', nil),
    authentication: ENV.fetch('SMTP_AUTHENTICATION', 'plain').to_sym,
    enable_starttls_auto: true
  }
  config.action_mailer.default_url_options = {
    host: URI.parse(base_url).host,
    protocol: base_url.start_with?('https') ? 'https' : 'http'
  }
end

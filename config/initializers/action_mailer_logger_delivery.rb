# frozen_string_literal: true

# Register the custom :logger Action Mailer delivery method so env files
# can select `config.action_mailer.delivery_method = :logger`. The fallback
# writes the full email to Rails.logger (stdout in production) for operators
# running the Docker image without SMTP configured — they retrieve the
# magic link code via `docker logs`. See FamilyRecipes::LoggerDelivery.
ActiveSupport.on_load(:action_mailer) do
  add_delivery_method :logger, FamilyRecipes::LoggerDelivery
end

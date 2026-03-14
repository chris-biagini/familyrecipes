# frozen_string_literal: true

# Configures Active Record Encryption keys for encrypting sensitive columns
# (e.g., usda_api_key on Kitchen). In production, all three env vars must be
# set — hardcoded dev defaults would silently encrypt with known keys.
ENCRYPTION_ENV_VARS = %w[
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
  ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
  ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
].freeze

if Rails.env.production?
  missing = ENCRYPTION_ENV_VARS.select { |var| ENV[var].blank? }
  raise "Missing encryption env vars in production: #{missing.join(', ')}" if missing.any?
end

Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', 'dev-primary-key-min-12-bytes')
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY', 'dev-deterministic-key-12b')
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', 'dev-key-derivation-salt')

# frozen_string_literal: true

# Configures Active Record Encryption keys for encrypting sensitive columns
# (e.g., API keys on Kitchen). In production, set these environment variables;
# in dev/test, deterministic defaults are used so encryption works out of the box.
Rails.application.config.active_record.encryption.primary_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY', 'dev-primary-key-min-12-bytes')
Rails.application.config.active_record.encryption.deterministic_key =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY', 'dev-deterministic-key-12b')
Rails.application.config.active_record.encryption.key_derivation_salt =
  ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT', 'dev-key-derivation-salt')

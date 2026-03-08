# frozen_string_literal: true

# Loads site-wide configuration (title, homepage copy, kitchen mode) into
# Rails.configuration.site. In Docker, reads from storage/site.yml (persisted
# in the app volume so user edits survive image updates). Falls back to the
# bundled config/site.yml for local development.
#
# Collaborators:
# - config/site.yml — default template shipped in the Docker image
# - storage/site.yml — user-customizable copy in the persistent volume
# - Kitchen — checks multi_kitchen flag to enforce single-kitchen mode
storage_config = Rails.root.join('storage/site.yml')

if storage_config.exist?
  all_config = YAML.safe_load_file(storage_config, permitted_classes: [], aliases: true)
  env_config = all_config[Rails.env] || all_config['default'] || all_config
  Rails.configuration.site = ActiveSupport::InheritableOptions.new(env_config.symbolize_keys)
else
  Rails.configuration.site = Rails.application.config_for(:site)
end

# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_record/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'action_cable/engine'
require 'rails/test_unit/railtie'

Bundler.require(*Rails.groups)

module Familyrecipes
  class Application < Rails::Application
    config.load_defaults 8.1

    # Don't autoload lib/familyrecipes or lib/nutrition_tui — they use their
    # own require systems and depend on dev-only gems (ratatui_ruby, etc.)
    config.autoload_lib(ignore: %w[assets tasks familyrecipes nutrition_tui])

    config.generators.system_tests = nil
  end
end

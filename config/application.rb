require_relative "boot"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Familyrecipes
  class Application < Rails::Application
    config.load_defaults 8.1

    # Don't autoload lib/familyrecipes — it uses its own require system
    # and the module name (FamilyRecipes) doesn't match Zeitwerk's expectation
    # (Familyrecipes) from the directory name.
    config.autoload_lib(ignore: %w[assets tasks familyrecipes])

    config.generators.system_tests = nil
  end
end

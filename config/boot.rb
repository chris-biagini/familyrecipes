ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# Bind to all interfaces so the dev server is LAN-accessible
# (matches WEBrick's default behavior in bin/serve).
ENV["BINDING"] ||= "0.0.0.0"

require "bundler/setup" # Set up gems listed in the Gemfile.

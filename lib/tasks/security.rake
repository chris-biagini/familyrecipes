# frozen_string_literal: true

# Runs Brakeman static security analysis. Medium and high confidence warnings
# fail the task (confidence_level: 1); weak warnings are reported but don't fail.
# False positives are documented in config/brakeman.ignore.
#
# Usage:
#   rake security          — run Brakeman
#   rake security:verbose  — run with full detail
desc 'Run Brakeman security scan'
task security: :environment do
  require 'brakeman'
  result = Brakeman.run(app_path: Rails.root.to_s, confidence_level: 1, quiet: true)

  if result.filtered_warnings.any?
    Brakeman.report(result, format: :text)
    abort "\nBrakeman found #{result.filtered_warnings.size} warning(s)."
  else
    puts 'Brakeman: no warnings found.'
  end
end

namespace :security do
  desc 'Run Brakeman with full detail'
  task verbose: :environment do
    require 'brakeman'
    result = Brakeman.run(app_path: Rails.root.to_s, confidence_level: 1)
    Brakeman.report(result, format: :text)
    abort "\nBrakeman found #{result.filtered_warnings.size} warning(s)." if result.filtered_warnings.any?
  end
end

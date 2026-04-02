# frozen_string_literal: true

# Reads SimpleCov's last_run.json and enforces the coverage floor from
# config/release_audit.yml. Expects tests to have already run with
# COVERAGE=1 or RELEASE_AUDIT=1 so SimpleCov has generated results.

namespace :release do
  namespace :audit do
    desc 'Check code coverage meets the release floor'
    task coverage: :environment do
      config = YAML.load_file(Rails.root.join('config/release_audit.yml'))
      floor = config.dig('coverage', 'floor') || 80

      last_run = Rails.root.join('coverage/.last_run.json')
      abort "Coverage data not found. Run tests first:\n  COVERAGE=1 rake test" unless last_run.exist?

      data = JSON.parse(last_run.read)
      line_pct = data.dig('result', 'line')&.round(1)

      abort 'Coverage data malformed — missing result.line in .last_run.json' unless line_pct

      if line_pct >= floor
        puts "Coverage: #{line_pct}% (floor: #{floor}%) ✓"
      else
        abort "Coverage: #{line_pct}% — BELOW floor of #{floor}%"
      end
    end
  end
end

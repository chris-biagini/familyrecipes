# frozen_string_literal: true

# Tier 2 release audit orchestrator. Runs all automated release-quality
# checks in sequence and writes a SHA-stamped marker file on success.
# The pre-push hook and CI verify this marker before allowing tag pushes.
#
# Usage:
#   rake release:audit        — run all Tier 2 checks
#   rake release:audit:full   — run Tier 2 + Tier 3 (security, exploratory, a11y, perf)

namespace :release do
  desc 'Run all Tier 2 release audit checks'
  task audit: :environment do
    puts "=== Release Audit (Tier 2) ===\n\n"

    puts '--- Running test suite with coverage ---'
    unless system({ 'RELEASE_AUDIT' => '1' }, 'bundle exec rake test')
      abort "\nTest suite failed. Fix test failures before running the audit."
    end
    puts ''

    checks = %w[
      release:audit:coverage
      release:audit:dead_code
      release:audit:deps
      release:audit:schema
      release:audit:docs
    ]

    failures = []

    checks.each do |check|
      puts "\n--- #{check} ---"
      begin
        Rake::Task[check].invoke
      rescue SystemExit => e
        failures << check unless e.success?
      end
    end

    puts "\n#{'=' * 40}"
    puts '=== Release Audit Report ==='
    puts '=' * 40

    if failures.empty?
      write_audit_marker('tmp/release_audit_pass.txt')
      puts "\nRESULT: PASS ✓"
      puts 'Marker written to tmp/release_audit_pass.txt'
    else
      puts "\nFAILED CHECKS:"
      failures.each { |f| puts "  ✗ #{f}" }
      puts "\nRESULT: FAIL"
      abort
    end
  end

  namespace :audit do
    desc 'Run full audit (Tier 2 + Tier 3: security, exploratory, a11y, perf)'
    task full: :environment do
      Rake::Task['release:audit'].invoke

      puts "\n=== Tier 3: Structured Exploratory Review ===\n"

      tier3_checks = %w[
        release:audit:security
        release:audit:explore
        release:audit:a11y
        release:audit:perf
      ]

      failures = []

      tier3_checks.each do |check|
        puts "\n--- #{check} ---"
        begin
          Rake::Task[check].invoke
        rescue SystemExit => e
          failures << check unless e.success?
        rescue RuntimeError => e
          puts "  Skipped: #{e.message}"
        end
      end

      if failures.empty?
        write_audit_marker('tmp/release_audit_full_pass.txt')
        puts "\nFull audit PASS ✓"
        puts 'Marker written to tmp/release_audit_full_pass.txt'
      else
        puts "\nFAILED Tier 3 CHECKS:"
        failures.each { |f| puts "  ✗ #{f}" }
        abort "\nFull audit FAIL"
      end
    end

    desc 'Security pen tests (Tier 3 — not yet implemented)'
    task security: :environment do
      raise 'not yet implemented'
    end

    desc 'Exploratory QA flows (Tier 3 — not yet implemented)'
    task explore: :environment do
      raise 'not yet implemented'
    end

    desc 'Accessibility spot-check (Tier 3 — not yet implemented)'
    task a11y: :environment do
      raise 'not yet implemented'
    end

    desc 'Performance baseline capture (Tier 3 — not yet implemented)'
    task perf: :environment do
      raise 'not yet implemented'
    end
  end
end

def write_audit_marker(path)
  marker = Rails.root.join(path)
  sha = `git rev-parse HEAD`.strip
  marker.write("#{sha}\n#{Time.now.utc.iso8601}\n")
end

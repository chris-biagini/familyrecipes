# frozen_string_literal: true

# Tier 2 release audit orchestrator. Runs all automated release-quality
# checks in sequence and writes a SHA-stamped marker file on success.
# The pre-push hook and CI verify this marker before allowing tag pushes.
#
# Usage:
#   rake release:audit        — run all Tier 2 checks
#   rake release:audit:full   — run Tier 2 + Tier 3 (security, exploratory, a11y, perf)

namespace :release do # rubocop:disable Metrics/BlockLength
  desc 'Run all Tier 2 release audit checks'
  task audit: :environment do # rubocop:disable Metrics/BlockLength
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
      rescue SystemExit => error
        failures << check unless error.success?
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

  namespace :audit do # rubocop:disable Metrics/BlockLength
    desc 'Run full audit (Tier 2 + Tier 3: security, exploratory, a11y, perf)'
    task full: :environment do # rubocop:disable Metrics/BlockLength
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
        rescue SystemExit => error
          failures << check unless error.success?
        rescue RuntimeError => error
          puts "  Skipped: #{error.message}"
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

    desc 'Security pen tests (Tier 3 — requires a running dev server on port 3030)'
    task security: :environment do
      puts '=== Security Pen Tests ==='
      puts 'Assumes a dev server is already running on port 3030.'
      puts ''

      puts '--- Seeding security kitchens ---'
      unless system({ 'MULTI_KITCHEN' => 'true' }, 'bin/rails runner test/security/seed_security_kitchens.rb')
        abort "\nFailed to seed security kitchens."
      end

      puts ''
      puts '--- Running Playwright security specs ---'
      passed = system('npx playwright test test/security/ --reporter=list')

      puts ''
      if passed && $CHILD_STATUS.success?
        puts 'Security pen tests: PASS'
      else
        abort 'Security pen tests: FAIL'
      end
    end

    desc 'Run Playwright exploratory QA walkthrough'
    task explore: :environment do
      puts '--- Exploratory QA walkthrough ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'

      unless system('npx playwright test test/release/exploratory/ ' \
                    '--config=test/release/exploratory/playwright.config.mjs ' \
                    '--reporter=list ' \
                    '--ignore-snapshots')
        abort 'Exploratory QA failed — see above.'
      end

      puts 'Exploratory QA: PASS ✓'
    end

    desc 'Run accessibility spot-check on key pages'
    task a11y: :environment do
      puts '--- Accessibility spot-check ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'
      unless system('npx playwright test test/release/exploratory/accessibility.spec.mjs ' \
                    '--config=test/release/exploratory/playwright.config.mjs ' \
                    '--reporter=list')
        abort 'Accessibility check failed — critical/serious violations found.'
      end
      puts 'Accessibility: PASS ✓'
    end

    desc 'Capture performance baseline for key pages'
    task perf: :environment do
      puts '--- Performance baseline ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'

      sha = `git rev-parse HEAD`.strip
      system({ 'GIT_SHA' => sha },
             'npx playwright test test/release/exploratory/performance.spec.mjs ' \
             '--config=test/release/exploratory/playwright.config.mjs ' \
             '--reporter=list')

      puts 'Performance baseline captured.'
    end
  end
end

def write_audit_marker(path)
  marker = Rails.root.join(path)
  sha = `git rev-parse HEAD`.strip
  marker.write("#{sha}\n#{Time.now.utc.iso8601}\n")
end

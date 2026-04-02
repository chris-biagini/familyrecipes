# frozen_string_literal: true

# Orchestrates three dependency health checks run during release audits:
#
# 1. bundler-audit — scans for known CVEs in Gemfile.lock (hard fail)
# 2. bundle outdated — reports available gem updates (informational)
# 3. license_finder — detects copyleft licenses (hard fail)
#
# Copyleft families are configured in config/release_audit.yml. Dev-only
# tools with non-permissive licenses can be allowlisted in
# config/license_allowlist.yml.

require 'csv'

namespace :release do
  namespace :audit do
    desc 'Check dependency health: vulnerabilities, freshness, licenses'
    task deps: :environment do
      results = {
        vulnerabilities: run_vulnerability_scan,
        outdated: run_outdated_report,
        licenses: run_license_audit
      }

      print_dep_summary(results)
      hard_failures = results.values_at(:vulnerabilities, :licenses).select { |v| v == :fail }
      abort "\nDependency check failed." if hard_failures.any?
    end
  end
end

def run_vulnerability_scan
  puts '--- Vulnerability scan (bundler-audit) ---'
  system('bundle exec bundle-audit check --update')
  $CHILD_STATUS.success? ? :pass : :fail
end

def run_outdated_report
  puts "\n--- Outdated dependencies ---"
  output = `bundle outdated 2>&1`

  if output.include?('Bundle up to date')
    puts '  All gems up to date.'
    { patch: 0, minor: 0, major: 0 }
  else
    counts = tally_outdated_levels(output)
    puts "  #{counts[:patch]} patch, #{counts[:minor]} minor, #{counts[:major]} major updates available"
    counts
  end
end

def tally_outdated_levels(output)
  # `bundle outdated` prints a table: "gem  current  latest  requested  groups"
  # We parse current vs latest and classify by semver bump level.
  output.lines
        .filter_map { |line| extract_version_pair(line) }
        .each_with_object({ patch: 0, minor: 0, major: 0 }) do |pair, counts|
          counts[semver_level(*pair)] += 1
        end
end

def extract_version_pair(line)
  parts = line.strip.split(/\s+/)
  return unless parts.size >= 3

  current = safe_gem_version(parts[1])
  latest = safe_gem_version(parts[2])
  return unless current && latest && latest > current

  [current, latest]
end

def safe_gem_version(string)
  Gem::Version.new(string)
rescue ArgumentError
  nil
end

def semver_level(current, latest)
  cur = current.segments
  lat = latest.segments
  return :major if lat[0] != cur[0]
  return :minor if lat[1] != cur[1]

  :patch
end

def run_license_audit
  puts "\n--- License audit (license_finder) ---"
  config = YAML.load_file(Rails.root.join('config/release_audit.yml'))
  copyleft_families = config.dig('licenses', 'copyleft') || []
  allowlist = load_license_allowlist

  output = `bundle exec license_finder --format=csv 2>/dev/null`
  violations = find_copyleft_violations(output, copyleft_families, allowlist)

  if violations.empty?
    puts "  All licenses permissive \u2713"
    :pass
  else
    report_license_violations(violations)
    :fail
  end
end

def find_copyleft_violations(csv_output, copyleft_families, allowlist)
  parse_license_csv(csv_output)
    .reject { |row| allowlist.key?(row[:gem]) }
    .select { |row| copyleft_families.any? { |family| row[:license]&.include?(family) } }
end

def parse_license_csv(output)
  output.lines.filter_map do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.exclude?(',')

    row = CSV.parse_line(stripped)
    next unless row && row.size >= 3

    { gem: row[0], version: row[1], license: row[2] }
  end
end

def report_license_violations(violations)
  puts "\n  COPYLEFT LICENSES DETECTED:\n"
  violations.each { |v| puts "    #{v[:gem]}: #{v[:license]}" }
  puts "\n  Add to config/license_allowlist.yml if this is a false positive."
end

def load_license_allowlist
  path = Rails.root.join('config/license_allowlist.yml')
  return {} unless path.exist?

  YAML.load_file(path) || {}
end

def print_dep_summary(results)
  puts "\n--- Dependency summary ---"
  vuln_msg = results[:vulnerabilities] == :pass ? "0 known CVEs \u2713" : "FOUND \u2014 see above"
  puts "  Vulnerabilities: #{vuln_msg}"

  outdated = results[:outdated]
  if outdated.is_a?(Hash)
    puts "  Outdated: #{outdated[:patch]} patch, #{outdated[:minor]} minor, #{outdated[:major]} major (info only)"
  end

  license_msg = results[:licenses] == :pass ? "all permissive \u2713" : 'COPYLEFT DETECTED'
  puts "  Licenses: #{license_msg}"
end

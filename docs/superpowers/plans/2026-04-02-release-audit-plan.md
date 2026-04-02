# Release Audit System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tiered release quality gate system — automated `rake release:audit` for every release, structured exploratory QA for major releases, enforced by pre-push hooks and CI.

**Architecture:** Rake tasks orchestrate six Tier 2 checks (coverage, dead code, deps, licenses, schema, doc contracts) and four Tier 3 checks (security pen tests, exploratory QA, performance baseline, accessibility). Config-driven thresholds in `config/release_audit.yml`. Pre-push hook enforces audit completion with SHA verification before tag pushes.

**Tech Stack:** Ruby/Rake (audit tasks), SimpleCov (coverage), debride (dead code), license_finder (license audit), Playwright + axe-core (Tier 3 browser tests), bash (pre-push hook).

**Spec:** `docs/superpowers/specs/2026-04-02-release-audit-design.md`

---

## File Structure

```
bin/
  hooks/
    pre-push                     # Canonical hook: lint + release audit enforcement
  setup                          # Modified: adds hook installation step

lib/tasks/
  release_audit.rake             # Tier 2 orchestrator + marker writer
  release_audit_coverage.rake    # SimpleCov floor enforcement
  release_audit_dead_code.rake   # Debride wrapper + allowlist
  release_audit_deps.rake        # bundler-audit + bundle outdated + license_finder
  release_audit_schema.rake      # FK, index, and orphan checks
  release_audit_docs.rake        # Doc-vs-app contract verification

config/
  release_audit.yml              # Thresholds and settings
  debride_allowlist.txt          # Dead code false positives (one method per line)
  license_allowlist.yml          # Gems with overridden license classification

test/release/
  doc_contract_check.rb          # Minitest integration tests for doc claims
  exploratory/
    playwright.config.mjs        # Playwright config for release tests
    setup.mjs                    # Server start/seed/teardown helpers
    recipe_flows.spec.mjs        # Recipe CRUD walkthrough
    menu_grocery_flows.spec.mjs  # Menu + grocery list walkthrough
    ingredients_flows.spec.mjs   # Ingredient catalog walkthrough
    settings_flows.spec.mjs      # Settings + tags + dinner picker
    multi_tenant.spec.mjs        # Two-kitchen isolation check
    import_export.spec.mjs       # ZIP backup/restore walkthrough
    navigation.spec.mjs          # Search, mobile FAB, breadcrumbs
    accessibility.spec.mjs       # axe-core spot-check on key pages
    performance.spec.mjs         # Performance baseline capture

.github/workflows/
  docker.yml                     # Modified: adds Tier 2 audit job before Docker build
```

---

## Milestone 1: Foundation (Tier 2 infrastructure)

### Task 1: Add new gems and JS dependencies

**Files:**
- Modify: `Gemfile`
- Modify: `package.json`
- Modify: `.gitignore`
- Create: `config/release_audit.yml`

- [ ] **Step 1: Add Ruby gems to Gemfile**

Add a `:development, :test` group (SimpleCov needs to run in test) and expand the existing `:development` group:

```ruby
group :development, :test do
  gem 'simplecov', require: false
end

group :development do
  # ... existing gems ...
  gem 'debride', require: false
  gem 'license_finder', require: false
end
```

Note: `simplecov` goes in `:development, :test` because it must load in the test environment. `debride` and `license_finder` are dev-only static analysis tools.

- [ ] **Step 2: Add JS dependency**

```bash
npm install --save-dev @axe-core/playwright
```

- [ ] **Step 3: Bundle install and verify**

```bash
bundle install
npm install
```

Expected: all gems and packages install without errors.

- [ ] **Step 4: Add coverage/ to .gitignore**

Append to `.gitignore`:

```
# SimpleCov coverage reports
/coverage/
```

- [ ] **Step 5: Create release_audit.yml config**

```yaml
# Release audit thresholds. Adjust as coverage improves.

coverage:
  floor: 80

marker:
  max_age_hours: 48

schema:
  fail_on_missing_fk: false
  fail_on_orphaned_records: true

licenses:
  copyleft:
    - GPL-2.0
    - GPL-3.0
    - AGPL-1.0
    - AGPL-3.0
    - SSPL-1.0
    - EUPL-1.1
    - EUPL-1.2
```

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock package.json package-lock.json .gitignore config/release_audit.yml
git commit -m "Add release audit dependencies and config

SimpleCov (coverage), debride (dead code), license_finder (license
audit), @axe-core/playwright (accessibility). Config thresholds in
config/release_audit.yml."
```

---

### Task 2: SimpleCov integration + coverage audit task

**Files:**
- Modify: `test/test_helper.rb`
- Create: `lib/tasks/release_audit_coverage.rake`

- [ ] **Step 1: Add SimpleCov to test_helper.rb**

Add at the very top of `test/test_helper.rb`, before any other requires — SimpleCov must start before any application code loads:

```ruby
# frozen_string_literal: true

if ENV['COVERAGE'] || ENV['RELEASE_AUDIT']
  require 'simplecov'
  SimpleCov.start 'rails' do
    enable_coverage :branch
    minimum_coverage line: 0  # Floor enforced by release audit task, not SimpleCov
    add_filter '/test/'
    add_filter '/db/'
    add_filter '/config/'
    add_filter '/vendor/'
  end
end
```

The `COVERAGE` or `RELEASE_AUDIT` env var gates SimpleCov so it doesn't slow down normal test runs. The floor is enforced by the rake task, not SimpleCov's built-in minimum (which would fail the test suite itself rather than producing a report).

- [ ] **Step 2: Write the coverage audit rake task**

Create `lib/tasks/release_audit_coverage.rake`:

```ruby
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
      unless last_run.exist?
        abort "Coverage data not found. Run tests first:\n  COVERAGE=1 rake test"
      end

      data = JSON.parse(last_run.read)
      line_pct = data.dig('result', 'line')&.round(1)

      unless line_pct
        abort 'Coverage data malformed — missing result.line in .last_run.json'
      end

      if line_pct >= floor
        puts "Coverage: #{line_pct}% (floor: #{floor}%) ✓"
      else
        abort "Coverage: #{line_pct}% — BELOW floor of #{floor}%"
      end
    end
  end
end
```

- [ ] **Step 3: Test it manually**

```bash
COVERAGE=1 rake test
rake release:audit:coverage
```

Expected: tests run with coverage instrumentation, then the coverage task reports the percentage and passes (assuming it's above 80%).

- [ ] **Step 4: Commit**

```bash
git add test/test_helper.rb lib/tasks/release_audit_coverage.rake
git commit -m "Add SimpleCov integration and coverage audit task

Coverage gated behind COVERAGE/RELEASE_AUDIT env vars to avoid slowing
normal test runs. rake release:audit:coverage reads SimpleCov output
and enforces the floor from config/release_audit.yml."
```

---

### Task 3: Dead code detection audit task

**Files:**
- Create: `lib/tasks/release_audit_dead_code.rake`
- Create: `config/debride_allowlist.txt`

- [ ] **Step 1: Generate initial allowlist by running debride**

```bash
bundle exec debride app/ lib/ 2>/dev/null
```

Review the output. Many results will be false positives (Rails callbacks, helper methods called from ERB, Stimulus targets, `perform`/`call` conventions). Collect the legitimate false positives.

- [ ] **Step 2: Create the allowlist**

Create `config/debride_allowlist.txt`. One method name per line. Comments start with `#`:

```
# Rails callbacks and lifecycle hooks
before_action
after_action
before_save
after_create
after_commit
after_update_commit
after_destroy

# ActiveJob convention
perform

# Rails conventions invoked by framework
call
default_url_options
set_current_tenant
current_kitchen
require_membership
allow_unauthenticated_access

# Helpers called from ERB templates
icon
app_version

# Stimulus action targets (invoked from data-action attributes in HTML)
connect
disconnect
toggle
open
close
submit
reset
search
clear
spin
```

This is a starting point — the actual allowlist will be populated by running debride and triaging each result. The task should add methods as needed during implementation.

- [ ] **Step 3: Write the dead code audit rake task**

Create `lib/tasks/release_audit_dead_code.rake`:

```ruby
# frozen_string_literal: true

# Runs debride to find potentially unreachable methods in app/ and lib/,
# then filters results against config/debride_allowlist.txt. Fails if
# any un-allowlisted dead methods are found.

namespace :release do
  namespace :audit do
    desc 'Detect unreachable methods (dead code)'
    task dead_code: :environment do
      allowlist_path = Rails.root.join('config/debride_allowlist.txt')
      allowlist = load_debride_allowlist(allowlist_path)

      output = `bundle exec debride app/ lib/ 2>/dev/null`
      methods = parse_debride_output(output)
      unapproved = methods.reject { |m| allowlist.include?(m[:name]) }

      if unapproved.empty?
        puts "Dead code: 0 unreachable methods ✓"
      else
        puts "\nPotentially unreachable methods:\n\n"
        unapproved.each { |m| puts "  #{m[:location]}  #{m[:name]}" }
        puts "\n#{unapproved.size} method(s) not in config/debride_allowlist.txt."
        puts "Review each — if legitimate, add to the allowlist with a comment."
        abort "\nDead code check failed."
      end
    end
  end
end

def load_debride_allowlist(path)
  return Set.new unless path.exist?

  path.readlines.filter_map { |line|
    stripped = line.strip
    stripped unless stripped.empty? || stripped.start_with?('#')
  }.to_set
end

def parse_debride_output(output)
  output.lines.filter_map { |line|
    match = line.match(/^\s+(\S+)\s+(.+):(\d+)$/)
    next unless match

    { name: match[1], location: "#{match[2]}:#{match[3]}" }
  }
end
```

- [ ] **Step 4: Test it manually**

```bash
rake release:audit:dead_code
```

Expected: either passes with "0 unreachable methods" or reports methods that need to be triaged into the allowlist.

- [ ] **Step 5: Triage results and update allowlist**

Run debride, review each flagged method, and add legitimate false positives to the allowlist. This is a one-time triage — future runs only flag *new* unreachable methods.

- [ ] **Step 6: Commit**

```bash
git add lib/tasks/release_audit_dead_code.rake config/debride_allowlist.txt
git commit -m "Add dead code detection audit task

Uses debride to scan app/ and lib/ for unreachable methods. Filters
against config/debride_allowlist.txt for Rails conventions, callbacks,
template helpers, and Stimulus actions."
```

---

### Task 4: Dependency health + license audit task

**Files:**
- Create: `lib/tasks/release_audit_deps.rake`
- Create: `config/license_allowlist.yml`

- [ ] **Step 1: Initialize license_finder**

```bash
bundle exec license_finder
```

This generates an initial report of all dependencies and their detected licenses. Review the output to identify any that need allowlisting.

- [ ] **Step 2: Create license allowlist**

Create `config/license_allowlist.yml`:

```yaml
# Gems whose detected license is overridden. Typically dual-licensed gems
# where license_finder picks up the GPL variant but MIT is also available.
#
# Format: gem_name: reason
# Example:
#   some-gem: "Dual-licensed MIT/GPL; we use under MIT terms"
```

Populate based on the license_finder output from step 1. This may start empty if all dependencies are permissive.

- [ ] **Step 3: Write the dependency audit rake task**

Create `lib/tasks/release_audit_deps.rake`:

```ruby
# frozen_string_literal: true

# Three dependency health checks:
# 1. bundler-audit — known CVEs (hard fail)
# 2. bundle outdated — available updates (informational)
# 3. license_finder — copyleft license detection (hard fail)

namespace :release do
  namespace :audit do
    desc 'Check dependency health: vulnerabilities, freshness, licenses'
    task deps: :environment do
      results = {}

      results[:vulnerabilities] = check_vulnerabilities
      results[:outdated] = check_outdated
      results[:licenses] = check_licenses

      print_dep_summary(results)
      abort "\nDependency check failed." if results[:vulnerabilities] == :fail || results[:licenses] == :fail
    end
  end
end

def check_vulnerabilities
  puts '--- Vulnerability scan (bundler-audit) ---'
  system('bundle exec bundle-audit check --update')
  $?.success? ? :pass : :fail
end

def check_outdated
  puts "\n--- Outdated dependencies ---"
  output = `bundle outdated 2>&1`
  if output.include?('Bundle up to date')
    puts '  All gems up to date.'
    { patch: 0, minor: 0, major: 0 }
  else
    counts = { patch: 0, minor: 0, major: 0 }
    output.lines.each do |line|
      next unless line.include?('(newest')

      if line.include?('major')
        counts[:major] += 1
      elsif line.include?('minor')
        counts[:minor] += 1
      else
        counts[:patch] += 1
      end
    end
    puts "  #{counts[:patch]} patch, #{counts[:minor]} minor, #{counts[:major]} major updates available"
    counts
  end
end

def check_licenses
  puts "\n--- License audit (license_finder) ---"
  config = YAML.load_file(Rails.root.join('config/release_audit.yml'))
  copyleft_families = config.dig('licenses', 'copyleft') || []
  allowlist = load_license_allowlist

  output = `bundle exec license_finder --format=csv 2>/dev/null`
  violations = []

  output.lines.drop(1).each do |line|
    fields = line.strip.split(',')
    next if fields.size < 3

    gem_name = fields[0]&.strip&.tr('"', '')
    license = fields[2]&.strip&.tr('"', '')
    next if allowlist.key?(gem_name)
    next unless copyleft_families.any? { |family| license&.include?(family) }

    violations << { gem: gem_name, license: license }
  end

  if violations.empty?
    puts '  All licenses permissive ✓'
    :pass
  else
    puts "\n  COPYLEFT LICENSES DETECTED:\n"
    violations.each { |v| puts "    #{v[:gem]}: #{v[:license]}" }
    puts "\n  Add to config/license_allowlist.yml if this is a false positive."
    :fail
  end
end

def load_license_allowlist
  path = Rails.root.join('config/license_allowlist.yml')
  return {} unless path.exist?

  YAML.load_file(path) || {}
end

def print_dep_summary(results)
  puts "\n--- Dependency summary ---"
  puts "  Vulnerabilities: #{results[:vulnerabilities] == :pass ? '0 known CVEs ✓' : 'FOUND — see above'}"
  outdated = results[:outdated]
  if outdated.is_a?(Hash)
    puts "  Outdated: #{outdated[:patch]} patch, #{outdated[:minor]} minor, #{outdated[:major]} major (info only)"
  end
  puts "  Licenses: #{results[:licenses] == :pass ? 'all permissive ✓' : 'COPYLEFT DETECTED'}"
end
```

- [ ] **Step 4: Test it manually**

```bash
rake release:audit:deps
```

Expected: vulnerability scan passes, outdated report prints, license check passes (or flags gems to triage).

- [ ] **Step 5: Commit**

```bash
git add lib/tasks/release_audit_deps.rake config/license_allowlist.yml
git commit -m "Add dependency health and license audit task

Combines bundler-audit (CVEs), bundle outdated (freshness report),
and license_finder (copyleft detection). License violations are a
hard fail; outdated deps are informational."
```

---

### Task 5: Database schema integrity audit task

**Files:**
- Create: `lib/tasks/release_audit_schema.rake`

- [ ] **Step 1: Write the schema audit rake task**

Create `lib/tasks/release_audit_schema.rake`:

```ruby
# frozen_string_literal: true

# Introspects ActiveRecord models and the database schema for:
# 1. Missing foreign keys — belongs_to without DB FK constraint
# 2. Missing indexes — frequently queried columns without indexes
# 3. Orphaned records — rows referencing nonexistent parents

namespace :release do
  namespace :audit do
    desc 'Check database schema integrity'
    task schema: :environment do
      config = YAML.load_file(Rails.root.join('config/release_audit.yml'))
      results = { missing_fks: [], missing_indexes: [], orphans: [] }

      check_foreign_keys(results)
      check_missing_indexes(results)
      check_orphaned_records(results)

      print_schema_summary(results, config)

      if config.dig('schema', 'fail_on_orphaned_records') && results[:orphans].any?
        abort "\nSchema integrity check failed — orphaned records found."
      end
    end
  end
end

def check_foreign_keys(results)
  connection = ActiveRecord::Base.connection
  existing_fks = connection.tables.flat_map { |table|
    connection.foreign_keys(table).map { |fk| [table, fk.column] }
  }.to_set

  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]

      table = model.table_name
      column = assoc.foreign_key.to_s
      next if existing_fks.include?([table, column])

      results[:missing_fks] << "#{table}.#{column} (#{model.name} belongs_to #{assoc.name})"
    end
  end
end

def check_missing_indexes(results)
  connection = ActiveRecord::Base.connection
  indexed_columns = connection.tables.flat_map { |table|
    connection.indexes(table).flat_map { |idx| idx.columns.map { |col| [table, col] } }
  }.to_set

  # Also count primary keys as indexed
  connection.tables.each { |table| indexed_columns.add([table, 'id']) }

  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]

      table = model.table_name
      column = assoc.foreign_key.to_s
      next if indexed_columns.include?([table, column])

      results[:missing_indexes] << "#{table}.#{column} (foreign key for #{assoc.name})"
    end
  end
end

def check_orphaned_records(results)
  ar_models.each do |model|
    model.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.options[:polymorphic]
      next if assoc.options[:optional]

      foreign_key = assoc.foreign_key.to_s
      parent_class = assoc.klass
      parent_table = parent_class.table_name
      child_table = model.table_name
      primary_key = assoc.association_primary_key.to_s

      count = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT COUNT(*) FROM #{child_table}
        WHERE #{foreign_key} IS NOT NULL
          AND #{foreign_key} NOT IN (SELECT #{primary_key} FROM #{parent_table})
      SQL

      next unless count.to_i.positive?

      results[:orphans] << "#{child_table}.#{foreign_key} → #{parent_table}: #{count} orphaned row(s)"
    end
  end
end

def ar_models
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.reject { |m| m.abstract_class? || m.table_name.blank? }
end

def print_schema_summary(results, config)
  fk_count = results[:missing_fks].size
  idx_count = results[:missing_indexes].size
  orphan_count = results[:orphans].size

  if results[:missing_fks].any?
    puts "\nMissing foreign keys (#{fk_count}):"
    results[:missing_fks].each { |fk| puts "  #{fk}" }
    fail_on_fk = config.dig('schema', 'fail_on_missing_fk')
    puts fail_on_fk ? '' : "  (warning only — fail_on_missing_fk: false)\n"
  end

  if results[:missing_indexes].any?
    puts "\nMissing indexes (#{idx_count}):"
    results[:missing_indexes].each { |idx| puts "  #{idx}" }
    puts "  (warning only — consider adding indexes for query performance)\n"
  end

  if results[:orphans].any?
    puts "\nOrphaned records (#{orphan_count}):"
    results[:orphans].each { |o| puts "  #{o}" }
  end

  puts "\nSchema FKs: #{fk_count} missing #{fk_count.zero? ? '✓' : '(warning)'}"
  puts "Schema indexes: #{idx_count} missing #{idx_count.zero? ? '✓' : '(warning)'}"
  puts "Orphaned records: #{orphan_count} #{orphan_count.zero? ? '✓' : '— FAIL'}"
end
```

- [ ] **Step 2: Test it manually**

```bash
rake release:audit:schema
```

Expected: reports missing FKs (if any) as warnings, checks for orphaned records.

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/release_audit_schema.rake
git commit -m "Add database schema integrity audit task

Checks for missing foreign keys (warning), missing indexes on
foreign key columns (warning), and orphaned records (hard fail).
Introspects ActiveRecord associations against actual DB constraints."
```

---

### Task 6: Doc-vs-app contract verification

**Files:**
- Create: `lib/tasks/release_audit_docs.rake`
- Create: `test/release/doc_contract_check.rb`

- [ ] **Step 1: Write the doc contract test file**

Create `test/release/doc_contract_check.rb`. This file verifies that routes and features mentioned in the help docs actually exist in the app:

```ruby
# frozen_string_literal: true

# Doc-vs-app contract verification. Parses help docs and checks that
# referenced routes, settings, and features exist. Run via:
#   ruby -Itest test/release/doc_contract_check.rb
#
# NOT named _test.rb to avoid inclusion in the normal test suite.

require_relative '../test_helper'

class DocContractCheck < ActionDispatch::IntegrationTest
  setup do
    @kitchen = Kitchen.create!(name: 'Doc Check', slug: 'doc-check')
    @user = User.create!(name: 'Doc Checker', email: 'doc@check.local')
    Membership.create!(kitchen: @kitchen, user: @user)
    ActsAsTenant.current_tenant = @kitchen
    log_in
  end

  test 'all help doc route references resolve' do
    routes = extract_route_references
    failures = []

    routes.each do |route_info|
      path = route_info[:path]
      begin
        get path
        unless response.status.in?([200, 301, 302])
          failures << "#{route_info[:source]}: #{path} returned #{response.status}"
        end
      rescue ActionController::RoutingError
        failures << "#{route_info[:source]}: #{path} — no matching route"
      end
    end

    assert failures.empty?, "Doc contract violations:\n#{failures.join("\n")}"
  end

  test 'settings mentioned in docs correspond to Kitchen columns' do
    doc_settings = extract_setting_references
    kitchen_columns = Kitchen.column_names.to_set

    missing = doc_settings.reject { |s| kitchen_columns.include?(s[:column]) }

    assert missing.empty?,
      "Settings in docs but not in Kitchen model:\n#{missing.map { |s| "  #{s[:source]}: #{s[:column]}" }.join("\n")}"
  end

  private

  def help_docs_path
    Rails.root.join('docs/help')
  end

  def help_doc_files
    Dir[help_docs_path.join('**/*.md')]
  end

  def extract_route_references
    routes = []
    help_doc_files.each do |file|
      relative = Pathname.new(file).relative_path_from(help_docs_path).to_s
      content = File.read(file)

      # Match relative URL paths like /recipes, /groceries, /settings
      content.scan(%r{(?:href=["']|navigate to |visit )(/[a-z][a-z0-9_/\-]*)}) do |match|
        path = match[0]
        # Substitute kitchen slug for dynamic segments
        path = path.gsub(':kitchen_slug', @kitchen.slug)
        routes << { path: path, source: relative }
      end
    end
    routes.uniq { |r| r[:path] }
  end

  def extract_setting_references
    settings = []
    help_doc_files.each do |file|
      relative = Pathname.new(file).relative_path_from(help_docs_path).to_s
      content = File.read(file)

      # Match references to kitchen settings (e.g., "USDA API key", "show nutrition")
      # Map doc language to column names
      setting_map = {
        'usda api key' => 'usda_api_key',
        'anthropic api key' => 'anthropic_api_key',
        'show nutrition' => 'show_nutrition',
        'decorate tags' => 'decorate_tags',
        'site title' => 'site_title',
        'heading' => 'heading',
        'subtitle' => 'subtitle'
      }

      setting_map.each do |phrase, column|
        next unless content.downcase.include?(phrase)

        settings << { column: column, source: relative }
      end
    end
    settings.uniq { |s| s[:column] }
  end
end
```

- [ ] **Step 2: Write the doc audit rake task**

Create `lib/tasks/release_audit_docs.rake`:

```ruby
# frozen_string_literal: true

# Runs the doc-vs-app contract verification tests. These check that
# routes, settings, and features referenced in docs/help/ actually
# exist in the application.

namespace :release do
  namespace :audit do
    desc 'Verify help docs match app behavior'
    task docs: :environment do
      puts '--- Doc contract verification ---'
      system('ruby -Itest test/release/doc_contract_check.rb')

      if $?.success?
        puts 'Doc contracts: verified ✓'
      else
        abort 'Doc contract verification failed — see above.'
      end
    end
  end
end
```

- [ ] **Step 3: Test it manually**

```bash
rake release:audit:docs
```

Expected: runs the doc contract tests and reports pass/fail.

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/release_audit_docs.rake test/release/doc_contract_check.rb
git commit -m "Add doc-vs-app contract verification

Parses help docs for route references and setting mentions, then
verifies they exist in the app. Catches drift between documentation
and implementation."
```

---

### Task 7: Tier 2 orchestrator and marker system

**Files:**
- Create: `lib/tasks/release_audit.rake`

- [ ] **Step 1: Write the orchestrator rake task**

Create `lib/tasks/release_audit.rake`:

```ruby
# frozen_string_literal: true

# Tier 2 release audit orchestrator. Runs all automated release-quality
# checks and writes a marker file on success. The pre-push hook and CI
# verify this marker before allowing tag pushes.
#
# Usage:
#   rake release:audit        — run all Tier 2 checks
#   rake release:audit:full   — run Tier 2 + Tier 3 (security, exploratory, a11y, perf)

namespace :release do
  desc 'Run all Tier 2 release audit checks'
  task audit: :environment do
    puts "=== Release Audit (Tier 2) ===\n\n"

    # Run tests with coverage first (produces SimpleCov data)
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
    warnings = []

    checks.each do |check|
      puts "\n--- #{check} ---"
      begin
        Rake::Task[check].invoke
      rescue SystemExit => e
        failures << check unless e.success?
      end
    end

    puts "\n#{'=' * 40}"
    puts "=== Release Audit Report ==="
    puts '=' * 40

    if failures.empty?
      write_marker('tmp/release_audit_pass.txt')
      puts "\nRESULT: PASS ✓"
      puts "Marker written to tmp/release_audit_pass.txt"
    else
      puts "\nFAILED CHECKS:"
      failures.each { |f| puts "  ✗ #{f}" }
      puts "\nRESULT: FAIL"
      abort
    end
  end

  namespace :audit do
    desc 'Run full audit (Tier 2 + Tier 3)'
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
        write_marker('tmp/release_audit_full_pass.txt')
        puts "\nFull audit PASS ✓"
        puts "Marker written to tmp/release_audit_full_pass.txt"
      else
        puts "\nFAILED Tier 3 CHECKS:"
        failures.each { |f| puts "  ✗ #{f}" }
        abort "\nFull audit FAIL"
      end
    end
  end
end

def write_marker(path)
  marker = Rails.root.join(path)
  sha = `git rev-parse HEAD`.strip
  File.write(marker, "#{sha}\n#{Time.now.utc.iso8601}\n")
end
```

- [ ] **Step 2: Test the orchestrator**

```bash
rake release:audit
```

Expected: runs test suite with coverage, then all Tier 2 checks in sequence, prints a consolidated report, writes the marker file.

- [ ] **Step 3: Verify marker file**

```bash
cat tmp/release_audit_pass.txt
```

Expected: first line is the git SHA, second line is a UTC timestamp.

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/release_audit.rake
git commit -m "Add Tier 2 release audit orchestrator

Runs tests with coverage, then all Tier 2 checks in sequence.
Writes SHA-stamped marker file on success for pre-push hook
verification."
```

---

## Milestone 2: Enforcement (hooks and CI)

### Task 8: Move pre-push hook into repo and add release audit enforcement

**Files:**
- Create: `bin/hooks/pre-push`
- Modify: `bin/setup`

- [ ] **Step 1: Create bin/hooks/ directory and the hook script**

Create `bin/hooks/pre-push`:

```bash
#!/usr/bin/env bash
#
# Pre-push hook: lint on every push, release audit enforcement on tag pushes.
# Canonical location: bin/hooks/pre-push (symlinked to .git/hooks/pre-push).

set -euo pipefail

echo "Running pre-push lint..."
bundle exec rake lint

# Detect tag pushes from stdin (git passes refs being pushed)
while read -r local_ref local_sha remote_ref remote_sha; do
  if [[ "$remote_ref" == refs/tags/v* ]]; then
    TAG="${remote_ref#refs/tags/}"
    # Strip optional letter suffix for classification (v0.5.4a → v0.5.4)
    BASE_TAG=$(echo "$TAG" | sed 's/[a-zA-Z]*$//')

    # Classify tag tier
    if echo "$BASE_TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
      TIER="patch"
    elif echo "$BASE_TAG" | grep -qE '^v[0-9]+(\.[0-9]+)?$'; then
      TIER="minor_or_major"
    else
      continue
    fi

    HEAD_SHA=$(git rev-parse HEAD)

    # Tier 2: require release:audit marker for all releases
    MARKER="tmp/release_audit_pass.txt"
    if [ ! -f "$MARKER" ]; then
      echo ""
      echo "ERROR: Release audit not run. Execute: rake release:audit"
      exit 1
    fi

    # Verify marker matches current HEAD (no commits since audit)
    MARKER_SHA=$(head -1 "$MARKER")
    if [ "$MARKER_SHA" != "$HEAD_SHA" ]; then
      echo ""
      echo "ERROR: Release audit was run against a different commit."
      echo "  Audit SHA: $MARKER_SHA"
      echo "  HEAD SHA:  $HEAD_SHA"
      echo "Re-run: rake release:audit"
      exit 1
    fi

    # Check marker freshness (48 hours = 172800 seconds)
    MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER" 2>/dev/null || echo 0) ))
    if [ "$MARKER_AGE" -gt 172800 ]; then
      echo ""
      echo "ERROR: Release audit is stale (>48h). Re-run: rake release:audit"
      exit 1
    fi

    # Tier 3: require full audit marker for minor/major
    if [ "$TIER" = "minor_or_major" ]; then
      FULL_MARKER="tmp/release_audit_full_pass.txt"
      if [ ! -f "$FULL_MARKER" ]; then
        echo ""
        echo "ERROR: Full release audit not run for $TIER release."
        echo "Execute: rake release:audit:full"
        exit 1
      fi
      FULL_SHA=$(head -1 "$FULL_MARKER")
      if [ "$FULL_SHA" != "$HEAD_SHA" ]; then
        echo ""
        echo "ERROR: Full audit was run against a different commit."
        echo "Re-run: rake release:audit:full"
        exit 1
      fi
      FULL_AGE=$(( $(date +%s) - $(stat -c %Y "$FULL_MARKER" 2>/dev/null || echo 0) ))
      if [ "$FULL_AGE" -gt 172800 ]; then
        echo ""
        echo "ERROR: Full release audit is stale (>48h). Re-run: rake release:audit:full"
        exit 1
      fi
    fi

    echo "Release audit verified for $TAG ($TIER) ✓"
  fi
done

echo "Pre-push checks passed."
```

- [ ] **Step 2: Make the hook executable**

```bash
chmod +x bin/hooks/pre-push
```

- [ ] **Step 3: Update bin/setup to install the hook**

Add hook installation to `bin/setup` after the dependency installation step:

```ruby
  puts "\n== Installing git hooks =="
  hooks_dir = File.join(APP_ROOT, '.git', 'hooks')
  source_hook = File.join(APP_ROOT, 'bin', 'hooks', 'pre-push')
  target_hook = File.join(hooks_dir, 'pre-push')
  if File.exist?(source_hook)
    FileUtils.ln_sf(source_hook, target_hook)
    puts "  Symlinked bin/hooks/pre-push → .git/hooks/pre-push"
  end
```

Add this block between the `bundle check` block and the "Removing old logs" block.

- [ ] **Step 4: Install the hook locally**

```bash
bin/setup --skip-server
```

Or manually:

```bash
ln -sf ../../bin/hooks/pre-push .git/hooks/pre-push
```

- [ ] **Step 5: Verify the symlink**

```bash
ls -la .git/hooks/pre-push
```

Expected: symlink pointing to `../../bin/hooks/pre-push`.

- [ ] **Step 6: Commit**

```bash
git add bin/hooks/pre-push bin/setup
git commit -m "Track pre-push hook in repo with bin/setup installation

Moves hook from untracked .git/hooks/ to bin/hooks/pre-push.
bin/setup symlinks it on project setup. Hook now enforces release
audit completion (SHA + freshness) before tag pushes."
```

---

### Task 9: Add Tier 2 audit to CI (docker.yml)

**Files:**
- Modify: `.github/workflows/docker.yml`

- [ ] **Step 1: Add release audit job to docker.yml**

Add a new `release-audit` job that runs before `build-and-push`. The `build-and-push` job gets a `needs: release-audit` dependency.

Insert this job before the existing `build-and-push` job:

```yaml
  release-audit:
    runs-on: ubuntu-latest
    timeout-minutes: 15

    env:
      RAILS_ENV: test
      CI: true
      RELEASE_AUDIT: '1'

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - name: Install JS dependencies
        run: npm ci

      - name: Build JS
        run: npm run build

      - name: Set up database
        run: bin/rails db:create db:migrate

      - name: Run tests with coverage
        run: bundle exec rake test

      - name: Release audit (Tier 2)
        run: |
          bundle exec rake release:audit:coverage
          bundle exec rake release:audit:dead_code
          bundle exec rake release:audit:deps
          bundle exec rake release:audit:schema
          bundle exec rake release:audit:docs
```

Then add `needs: release-audit` to the existing `build-and-push` job:

```yaml
  build-and-push:
    needs: release-audit
    runs-on: ubuntu-latest
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/docker.yml
git commit -m "Add Tier 2 release audit to CI on tag pushes

Runs coverage, dead code, dependency, schema, and doc contract
checks before Docker build. Safety net for when pre-push hook
is bypassed."
```

---

## Milestone 3: Tier 3 (browser-based checks)

### Task 10: Playwright config and test infrastructure

**Files:**
- Create: `test/release/exploratory/playwright.config.mjs`
- Create: `test/release/exploratory/setup.mjs`

- [ ] **Step 1: Create Playwright config**

Create `test/release/exploratory/playwright.config.mjs`:

```javascript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 30_000,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:3030',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { browserName: 'chromium' },
    },
  ],
});
```

- [ ] **Step 2: Create setup helpers**

Create `test/release/exploratory/setup.mjs`:

```javascript
// Shared helpers for release exploratory tests.
// Assumes a running dev server on localhost:3030 with MULTI_KITCHEN=true.

import { expect } from '@playwright/test';

/**
 * Log in as a specific user by hitting the dev login endpoint.
 * @param {import('@playwright/test').Page} page
 * @param {number} userId
 */
export async function loginAs(page, userId) {
  await page.goto(`/dev_login?id=${userId}`);
  await page.waitForLoadState('networkidle');
}

/**
 * Attach a console error listener. Returns a function that asserts no errors.
 * @param {import('@playwright/test').Page} page
 * @returns {function} assertNoErrors — call at end of test
 */
export function trackConsoleErrors(page) {
  const errors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errors.push(msg.text());
    }
  });
  return () => {
    expect(errors, 'JS console errors detected').toEqual([]);
  };
}

/**
 * Attach a network failure listener for 4xx/5xx responses.
 * @param {import('@playwright/test').Page} page
 * @returns {function} assertNoNetworkErrors
 */
export function trackNetworkErrors(page) {
  const failures = [];
  page.on('response', (response) => {
    const status = response.status();
    if (status >= 400 && !response.url().includes('favicon')) {
      failures.push(`${status} ${response.url()}`);
    }
  });
  return () => {
    expect(failures, 'Network errors detected').toEqual([]);
  };
}

/**
 * Read the user IDs file written by the security seed script.
 */
export async function readUserIds() {
  const fs = await import('fs/promises');
  const path = await import('path');
  const idsPath = path.join(process.cwd(), 'test', 'security', 'user_ids.json');
  const content = await fs.readFile(idsPath, 'utf-8');
  return JSON.parse(content);
}
```

- [ ] **Step 3: Commit**

```bash
git add test/release/exploratory/playwright.config.mjs test/release/exploratory/setup.mjs
git commit -m "Add Playwright config and helpers for release exploratory tests"
```

---

### Task 11: Security pen test rake task

**Files:**
- Create: `lib/tasks/release_audit_security.rake` (within the `release_audit.rake` file or separate)

Actually, this should be added to the existing `release_audit.rake` as part of the `audit` namespace. But to keep files focused, create a separate file.

- [ ] **Step 1: Write the security audit rake task**

Add to `lib/tasks/release_audit.rake` inside the `namespace :release do / namespace :audit do` block. Or create a small wrapper. Since the orchestrator already references `release:audit:security`, add it to the orchestrator file.

Append to `lib/tasks/release_audit.rake` inside the `namespace :release do / namespace :audit do` block:

```ruby
    desc 'Run Playwright security pen tests'
    task :security do
      puts '--- Security pen tests ---'
      puts 'Seeding security kitchens...'
      unless system('MULTI_KITCHEN=true bin/rails runner test/security/seed_security_kitchens.rb')
        abort 'Security seed failed.'
      end

      puts 'Running Playwright security specs...'
      unless system('npx playwright test test/security/ --reporter=list')
        abort 'Security pen tests failed — see above.'
      end

      puts 'Security pen tests: PASS ✓'
    end
```

Note: this task does NOT start/stop a server — it assumes one is already running (consistent with the existing security test workflow). The `rake release:audit:full` task should document this prerequisite.

- [ ] **Step 2: Commit**

```bash
git add lib/tasks/release_audit.rake
git commit -m "Add security pen test rake task

Wraps existing Playwright security specs into rake release:audit:security.
Seeds security kitchens, then runs all test/security/*.spec.mjs."
```

---

### Task 12: Exploratory QA Playwright specs

**Files:**
- Create: `test/release/exploratory/recipe_flows.spec.mjs`
- Create: `test/release/exploratory/menu_grocery_flows.spec.mjs`
- Create: `test/release/exploratory/ingredients_flows.spec.mjs`
- Create: `test/release/exploratory/settings_flows.spec.mjs`
- Create: `test/release/exploratory/multi_tenant.spec.mjs`
- Create: `test/release/exploratory/import_export.spec.mjs`
- Create: `test/release/exploratory/navigation.spec.mjs`

This is the largest task. Each spec file exercises one domain of the app. The implementation should follow the patterns established in `test/security/` and use the helpers from `setup.mjs`.

- [ ] **Step 1: Write recipe_flows.spec.mjs**

Create `test/release/exploratory/recipe_flows.spec.mjs`. This spec exercises recipe create, view, edit (graphical + plaintext), and delete:

```javascript
import { test, expect } from '@playwright/test';
import { loginAs, trackConsoleErrors, trackNetworkErrors, readUserIds } from './setup.mjs';

test.describe('Recipe lifecycle', () => {
  let userId;
  let kitchenSlug;

  test.beforeAll(async () => {
    const ids = await readUserIds();
    userId = ids.alice_id;
    kitchenSlug = 'kitchen-alpha';
  });

  test('create, view, edit, and delete a recipe', async ({ page }) => {
    const assertNoErrors = trackConsoleErrors(page);
    const assertNoNetworkErrors = trackNetworkErrors(page);

    await loginAs(page, userId);

    // Navigate to recipes index
    await page.goto(`/kitchens/${kitchenSlug}/recipes`);
    await expect(page).toHaveTitle(/recipes/i);

    // Create a new recipe via the editor
    await page.goto(`/kitchens/${kitchenSlug}/recipes/new`);
    await page.waitForLoadState('networkidle');

    // Fill in recipe details using the graphical editor
    // (Specific selectors will depend on actual editor UI — adjust during implementation)
    const titleInput = page.locator('[data-field="title"] input, input[name*="title"]').first();
    await titleInput.fill('Audit Test Recipe');

    // Save the recipe
    const saveButton = page.locator('button:has-text("Save"), input[type="submit"]').first();
    await saveButton.click();
    await page.waitForLoadState('networkidle');

    // Verify recipe was created and we're on the show page
    await expect(page.locator('h1')).toContainText('Audit Test Recipe');

    // Edit the recipe
    const editLink = page.locator('a:has-text("Edit")').first();
    await editLink.click();
    await page.waitForLoadState('networkidle');

    // Verify editor loaded
    await expect(page.locator('[data-field="title"] input, input[name*="title"]').first()).toHaveValue('Audit Test Recipe');

    // Delete the recipe (navigate to edit, find delete)
    // (Adjust selector based on actual delete UI)

    assertNoErrors();
    assertNoNetworkErrors();
  });
});
```

Note: this is a skeleton — the exact selectors and flow steps must be adjusted to match the actual app UI during implementation. The implementer should use `page.locator` with accessibility-first selectors (roles, labels, text content) and fall back to data attributes.

- [ ] **Step 2: Write remaining spec files**

Each spec follows the same pattern as recipe_flows.spec.mjs:
- Import helpers from setup.mjs
- Set up console/network error tracking
- Log in as the appropriate user
- Walk through the domain's key flows
- Assert key content is present after each action
- Assert no JS errors or network failures

Files to create:
- `menu_grocery_flows.spec.mjs` — add recipes to menu, verify grocery list, check items off, add custom items
- `ingredients_flows.spec.mjs` — view catalog, search ingredients, check coverage filter
- `settings_flows.spec.mjs` — edit kitchen branding, manage tags, spin dinner picker
- `multi_tenant.spec.mjs` — log in as alice (kitchen-alpha), verify can't see kitchen-beta data
- `import_export.spec.mjs` — export ZIP, re-import (if feasible without destructive reset)
- `navigation.spec.mjs` — search overlay, breadcrumbs, mobile viewport FAB

Each file should be 50–150 lines. Focus on the happy path — this is exploratory QA, not edge case testing.

- [ ] **Step 3: Write the exploratory QA rake task**

Append to `lib/tasks/release_audit.rake` inside the audit namespace:

```ruby
    desc 'Run Playwright exploratory QA walkthrough'
    task :explore do
      puts '--- Exploratory QA walkthrough ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'

      unless system('npx playwright test test/release/exploratory/ ' \
                     '--config=test/release/exploratory/playwright.config.mjs ' \
                     '--reporter=list')
        abort 'Exploratory QA failed — see above.'
      end

      puts 'Exploratory QA: PASS ✓'
    end
```

- [ ] **Step 4: Commit**

```bash
git add test/release/exploratory/*.spec.mjs lib/tasks/release_audit.rake
git commit -m "Add exploratory QA Playwright specs

Seven spec files covering recipe lifecycle, menu/groceries, ingredients,
settings, multi-tenant isolation, import/export, and navigation.
Exercises every major user flow with console and network error tracking."
```

---

### Task 13: Accessibility spot-check

**Files:**
- Create: `test/release/exploratory/accessibility.spec.mjs`

- [ ] **Step 1: Write the accessibility spec**

Create `test/release/exploratory/accessibility.spec.mjs`:

```javascript
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { loginAs, readUserIds } from './setup.mjs';

const PAGES_TO_CHECK = [
  { name: 'Recipe index', path: '/recipes' },
  { name: 'Groceries', path: '/groceries' },
  { name: 'Ingredients', path: '/ingredients' },
  { name: 'Settings (via dialog)', path: '/' },
];

test.describe('Accessibility spot-check (WCAG 2.1 AA)', () => {
  let userId;
  let kitchenSlug;

  test.beforeAll(async () => {
    const ids = await readUserIds();
    userId = ids.alice_id;
    kitchenSlug = 'kitchen-alpha';
  });

  for (const pageInfo of PAGES_TO_CHECK) {
    test(`${pageInfo.name} has no critical a11y violations`, async ({ page }) => {
      await loginAs(page, userId);
      await page.goto(`/kitchens/${kitchenSlug}${pageInfo.path}`);
      await page.waitForLoadState('networkidle');

      const results = await new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
        .analyze();

      const critical = results.violations.filter(v =>
        v.impact === 'critical' || v.impact === 'serious'
      );

      if (critical.length > 0) {
        const summary = critical.map(v =>
          `[${v.impact}] ${v.id}: ${v.description} (${v.nodes.length} instance(s))`
        ).join('\n');
        expect.soft(critical, `Critical a11y violations on ${pageInfo.name}:\n${summary}`).toEqual([]);
      }

      // Log moderate/minor as warnings
      const warnings = results.violations.filter(v =>
        v.impact === 'moderate' || v.impact === 'minor'
      );
      if (warnings.length > 0) {
        console.log(`\n  A11y warnings on ${pageInfo.name}:`);
        warnings.forEach(v => {
          console.log(`    [${v.impact}] ${v.id}: ${v.description}`);
        });
      }
    });
  }
});
```

- [ ] **Step 2: Write the a11y rake task**

Append to `lib/tasks/release_audit.rake` inside the audit namespace:

```ruby
    desc 'Run accessibility spot-check on key pages'
    task :a11y do
      puts '--- Accessibility spot-check ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'

      unless system('npx playwright test test/release/exploratory/accessibility.spec.mjs ' \
                     '--config=test/release/exploratory/playwright.config.mjs ' \
                     '--reporter=list')
        abort 'Accessibility check failed — critical/serious violations found.'
      end

      puts 'Accessibility: PASS ✓'
    end
```

- [ ] **Step 3: Commit**

```bash
git add test/release/exploratory/accessibility.spec.mjs lib/tasks/release_audit.rake
git commit -m "Add accessibility spot-check with axe-core

Injects axe-core into key pages via Playwright. Critical/serious
WCAG 2.1 AA violations fail; moderate/minor are logged as warnings."
```

---

### Task 14: Performance baseline capture

**Files:**
- Create: `test/release/exploratory/performance.spec.mjs`

- [ ] **Step 1: Write the performance spec**

Create `test/release/exploratory/performance.spec.mjs`:

```javascript
import { test } from '@playwright/test';
import { loginAs, readUserIds } from './setup.mjs';
import { writeFileSync } from 'fs';
import { join } from 'path';

const PAGES_TO_MEASURE = [
  { name: 'Recipe index', path: '/recipes' },
  { name: 'Groceries', path: '/groceries' },
  { name: 'Ingredients', path: '/ingredients' },
];

test.describe('Performance baseline', () => {
  let userId;
  let kitchenSlug;
  const measurements = {};

  test.beforeAll(async () => {
    const ids = await readUserIds();
    userId = ids.alice_id;
    kitchenSlug = 'kitchen-alpha';
  });

  for (const pageInfo of PAGES_TO_MEASURE) {
    test(`measure ${pageInfo.name}`, async ({ page }) => {
      await loginAs(page, userId);

      await page.goto(`/kitchens/${kitchenSlug}${pageInfo.path}`);
      await page.waitForLoadState('networkidle');

      const timing = await page.evaluate(() => {
        const nav = performance.getEntriesByType('navigation')[0];
        const resources = performance.getEntriesByType('resource');
        return {
          domContentLoaded: Math.round(nav.domContentLoadedEventEnd - nav.startTime),
          loadComplete: Math.round(nav.loadEventEnd - nav.startTime),
          resourceCount: resources.length,
          totalTransferSize: resources.reduce((sum, r) => sum + (r.transferSize || 0), 0),
        };
      });

      measurements[pageInfo.name] = timing;
      console.log(`  ${pageInfo.name}: DOM=${timing.domContentLoaded}ms, ` +
        `Load=${timing.loadComplete}ms, ` +
        `Resources=${timing.resourceCount}, ` +
        `Transfer=${Math.round(timing.totalTransferSize / 1024)}KB`);
    });
  }

  test.afterAll(async () => {
    const date = new Date().toISOString().split('T')[0];
    const outPath = join(process.cwd(), 'tmp', `perf_baseline_${date}.json`);
    const report = {
      date: new Date().toISOString(),
      commit: process.env.GIT_SHA || 'unknown',
      measurements,
    };
    writeFileSync(outPath, JSON.stringify(report, null, 2));
    console.log(`\n  Performance baseline written to ${outPath}`);
  });
});
```

- [ ] **Step 2: Write the perf rake task**

Append to `lib/tasks/release_audit.rake` inside the audit namespace:

```ruby
    desc 'Capture performance baseline for key pages'
    task :perf do
      puts '--- Performance baseline ---'
      puts 'NOTE: Requires a running dev server (MULTI_KITCHEN=true bin/dev)'

      sha = `git rev-parse HEAD`.strip
      system({ 'GIT_SHA' => sha },
        'npx playwright test test/release/exploratory/performance.spec.mjs ' \
        '--config=test/release/exploratory/playwright.config.mjs ' \
        '--reporter=list')

      puts 'Performance baseline captured.'
    end
```

Note: the perf task never fails — it's informational only.

- [ ] **Step 3: Commit**

```bash
git add test/release/exploratory/performance.spec.mjs lib/tasks/release_audit.rake
git commit -m "Add performance baseline capture

Measures DOM timing, resource counts, and transfer sizes for key
pages. Writes timestamped JSON to tmp/ for trend tracking."
```

---

## Milestone 4: Documentation

### Task 15: Update CLAUDE.md with release audit section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add Release Audit section to CLAUDE.md**

Add a new section between "Commands" and "Workflow". This is the operational view — what to run and when:

```markdown
## Release Audit

Three-tier quality gate system. Tier 1 (CI) runs automatically. Tier 2 and 3
are run before tagging releases.

**Tier 2 — every release (`rake release:audit`):**
Code coverage floor, dead code detection, dependency health + license audit,
database schema integrity, doc-vs-app contract verification. Writes a
SHA-stamped marker to `tmp/release_audit_pass.txt`.

**Tier 3 — minor/major releases (`rake release:audit:full`):**
Tier 2 + Playwright security pen tests, exploratory QA walkthrough,
accessibility spot-check (axe-core), performance baseline. Requires a running
dev server (`MULTI_KITCHEN=true bin/dev`). Writes marker to
`tmp/release_audit_full_pass.txt`.

**Enforcement:** Pre-push hook (installed by `bin/setup`) blocks tag pushes
unless the matching audit marker exists, is fresh (< 48h), and matches HEAD.
CI also runs Tier 2 on tag pushes as a safety net.

**Config:** `config/release_audit.yml` (thresholds), `config/debride_allowlist.txt`
(dead code false positives), `config/license_allowlist.yml` (license overrides).

```bash
rake release:audit           # Tier 2 (before any release)
rake release:audit:full      # Tier 2 + Tier 3 (before minor/major)
rake release:audit:security  # just security pen tests
rake release:audit:explore   # just exploratory QA
rake release:audit:a11y      # just accessibility check
rake release:audit:perf      # just performance baseline
```
```

- [ ] **Step 2: Update the Workflow section**

In the existing "Releases" subsection, add a note about the audit requirement:

```markdown
- **Run `rake release:audit` before tagging any release.** For minor/major
  releases, run `rake release:audit:full` (requires a running dev server).
  The pre-push hook enforces this — tag pushes are blocked without a fresh
  audit marker.
```

- [ ] **Step 3: Update the Commands section**

Add the release audit commands to the existing commands block:

```bash
rake release:audit       # full Tier 2 audit (before tagging)
rake release:audit:full  # Tier 2 + Tier 3 (before minor/major)
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Document release audit system in CLAUDE.md

Adds operational documentation for the three-tier audit system:
commands, enforcement, configuration. Updates Workflow and Commands
sections."
```

---

### Task 16: Final integration test

- [ ] **Step 1: Run the full Tier 2 audit end-to-end**

```bash
rake release:audit
```

Expected: all checks pass, marker written.

- [ ] **Step 2: Verify the pre-push hook enforcement**

```bash
# Create a test tag (don't actually push)
git tag v99.99.99

# Simulate what the hook checks
cat tmp/release_audit_pass.txt
head -1 tmp/release_audit_pass.txt  # should match git rev-parse HEAD
git rev-parse HEAD

# Clean up
git tag -d v99.99.99
```

- [ ] **Step 3: Run Tier 3 (if dev server available)**

```bash
# In one terminal:
MULTI_KITCHEN=true bin/dev

# In another:
rake release:audit:full
```

- [ ] **Step 4: Run CI checks locally to verify docker.yml changes**

```bash
RELEASE_AUDIT=1 rake test
rake release:audit:coverage
rake release:audit:dead_code
rake release:audit:deps
rake release:audit:schema
rake release:audit:docs
```

Expected: all pass, matching what CI will run.

- [ ] **Step 5: Final commit if any adjustments needed**

Fix any issues found during integration testing. Commit each fix individually with a descriptive message.

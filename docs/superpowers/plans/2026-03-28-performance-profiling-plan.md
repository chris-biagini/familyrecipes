# Performance Profiling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dev-time profiling tools, a CI bundle size gate, and a repeatable baseline rake task so performance is visible by default and regressions are caught automatically.

**Architecture:** Four gems (dev-only) for request profiling and N+1 detection, two npm packages for CI bundle size enforcement, one rake task for repeatable baseline measurement. No production dependencies. rack-mini-profiler's injected script uses the existing session-based CSP nonce.

**Tech Stack:** rack-mini-profiler, Bullet, stackprof, vernier, size-limit, GitHub Actions

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Gemfile` | Add profiling gems to dev group |
| Create | `config/initializers/mini_profiler.rb` | rack-mini-profiler config + CSP nonce wiring |
| Create | `config/initializers/bullet.rb` | Bullet N+1 detection config |
| Create | `lib/profile_baseline.rb` | ProfileBaseline class (page + asset profiling) |
| Create | `lib/tasks/profile.rake` | `rake profile:baseline` task (thin wrapper) |
| Modify | `package.json` | Add size-limit devDependencies + scripts |
| Create | `.size-limit.json` | Bundle size thresholds |
| Modify | `.github/workflows/test.yml` | Add size-limit CI step |
| Create | `test/lib/profile_baseline_test.rb` | Test for the baseline profiler |
| Modify | `.rubocop.yml` | Exclude profile rake task from Rails/Output |

---

### Task 1: Add Profiling Gems

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to the development group**

In `Gemfile`, add to the existing `group :development` block:

```ruby
group :development do
  gem 'bullet'
  gem 'rack-mini-profiler'
  gem 'rubocop', require: false
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'stackprof'
  gem 'vernier'
end
```

Keep gems alphabetically sorted within the group.

- [ ] **Step 2: Bundle install**

Run: `bundle install`
Expected: All gems install successfully. `Gemfile.lock` updated.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add profiling gems: rack-mini-profiler, bullet, stackprof, vernier"
```

---

### Task 2: Configure rack-mini-profiler

**Files:**
- Create: `config/initializers/mini_profiler.rb`

- [ ] **Step 1: Write the initializer**

Create `config/initializers/mini_profiler.rb`:

```ruby
# frozen_string_literal: true

# rack-mini-profiler: always-on performance badge in development.
# Shows request timing, SQL query count, and memory usage on every page.
# Flamegraphs available via ?pp=flamegraph (requires stackprof gem).
#
# Collaborators:
# - content_security_policy.rb — session-based nonce reused here so the
#   injected <script> tag satisfies strict CSP
# - stackprof — provides flamegraph data when ?pp=flamegraph is requested
if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.tap do |c|
    c.position = 'bottom-left'
    c.content_security_policy_nonce = ->(env, headers) {
      ActionDispatch::Request.new(env).content_security_policy_nonce
    }
  end
end
```

The `defined?` guard ensures this only runs in development where the gem is
loaded. The nonce lambda pulls from the same session-based nonce generator
configured in `content_security_policy.rb`, so the profiler's injected script
tag satisfies strict CSP.

- [ ] **Step 2: Verify manually**

Run: `bin/rails server -p 3030`
Visit any page in the browser. Confirm the rack-mini-profiler badge appears in
the bottom-left corner showing request time and query count. Click the badge to
see the detailed breakdown. Kill the server when done.

- [ ] **Step 3: Commit**

```bash
git add config/initializers/mini_profiler.rb
git commit -m "Configure rack-mini-profiler with CSP nonce support"
```

---

### Task 3: Configure Bullet

**Files:**
- Create: `config/initializers/bullet.rb`

- [ ] **Step 1: Write the initializer**

Create `config/initializers/bullet.rb`:

```ruby
# frozen_string_literal: true

# Bullet: automatic N+1 query detection in development and test.
# In dev, warnings appear in the page footer and Rails log. In test, Bullet
# raises so new N+1 regressions fail the test suite.
#
# Collaborators:
# - rack-mini-profiler — both add page footer badges; Bullet's appears below
# - test_helper.rb — Bullet.start!/end! wrapping handled by the integration
if defined?(Bullet)
  Bullet.enable = true
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
  Bullet.raise = Rails.env.test?
end
```

`Bullet.raise = true` in test mode means any N+1 introduced by new code will
fail the test that triggers it. This is the cheapest regression gate we can add.

- [ ] **Step 2: Wire Bullet into the test lifecycle**

Open `test/test_helper.rb`. Add Bullet setup/teardown hooks to
`ActiveSupport::TestCase` so Bullet tracks each test independently. Add after
the existing `require` lines at the top of the file, before the
`module ActiveSupport` block:

```ruby
# Bullet integration: start/end tracking around each test so N+1 queries
# introduced by new code are caught automatically.
if defined?(Bullet)
  module ActiveSupport
    class TestCase
      setup { Bullet.start_request }
      teardown { Bullet.end_request }
    end
  end
end
```

This must come before the existing `module ActiveSupport` / `class TestCase`
reopening so both blocks extend the same class.

- [ ] **Step 3: Run the test suite**

Run: `bundle exec rake test`
Expected: All tests pass. If any existing N+1 queries cause Bullet to raise,
add allowlists in the initializer using
`Bullet.add_safelist(type: :unused_eager_loading, ...)` as needed. This is
expected — it surfaces real issues.

- [ ] **Step 4: Commit**

```bash
git add config/initializers/bullet.rb test/test_helper.rb
git commit -m "Configure Bullet for N+1 detection in dev and test"
```

---

### Task 4: Add size-limit for CI Bundle Size Gate

**Files:**
- Modify: `package.json`
- Create: `.size-limit.json`

- [ ] **Step 1: Install size-limit packages**

Run: `npm install --save-dev size-limit @size-limit/file`

- [ ] **Step 2: Add npm scripts**

In `package.json`, add to the `"scripts"` section:

```json
"size": "size-limit",
"size:report": "size-limit --json"
```

- [ ] **Step 3: Build JS to get current bundle size**

Run: `npm run build`
Then: `npx size-limit --json`

Note the reported gzipped size for `app/assets/builds/application.js`. This
is the baseline.

- [ ] **Step 4: Create `.size-limit.json`**

Create `.size-limit.json` in the project root. Set the `limit` to the current
gzipped size rounded up to the nearest 10 KB + ~15% headroom. For example, if
the current size is 176 KB gzipped, set the limit to `"200 kB"`:

```json
[
  {
    "name": "Main JS bundle",
    "path": "app/assets/builds/application.js",
    "limit": "200 kB",
    "gzip": true
  }
]
```

The CodeMirror chunk (`public/chunks/`) is excluded — it is lazy-loaded and
does not affect initial page load.

- [ ] **Step 5: Run size-limit to verify it passes**

Run: `npx size-limit`
Expected: Passes with the bundle under the configured limit.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json .size-limit.json
git commit -m "Add size-limit for JS bundle size enforcement"
```

---

### Task 5: Add size-limit CI Step

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Add the CI step**

In `.github/workflows/test.yml`, add a new step after "JS tests" and before
"Set up database":

```yaml
      - name: Check JS bundle size
        run: npx size-limit
```

The full steps section should read (showing surrounding context):

```yaml
      - name: JS tests
        run: npm test

      - name: Check JS bundle size
        run: npx size-limit

      - name: Set up database
        run: bin/rails db:create db:migrate
```

This step runs after `npm run build` (which produces the bundle) and after JS
tests. It needs no database or Rails — just Node.js and the built bundle.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "Add JS bundle size gate to CI"
```

---

### Task 6: Baseline Profiling Rake Task

**Files:**
- Create: `lib/profile_baseline.rb`
- Create: `lib/tasks/profile.rake`
- Create: `test/lib/profile_baseline_test.rb`
- Modify: `.rubocop.yml` (add profile.rake to Rails/Output exclusion)

- [ ] **Step 1: Write a test for the baseline profiler**

Create `test/lib/profile_baseline_test.rb`:

```ruby
# frozen_string_literal: true

require 'test_helper'
require_relative '../../lib/profile_baseline'

class ProfileBaselineTest < ActiveSupport::TestCase
  setup do
    create_kitchen_and_user
    setup_test_category(name: 'Main Dishes')
    @recipe = create_recipe("## Step 1\nMix ingredients.", category_name: 'Main Dishes')
    MealPlan.find_or_create_by!(kitchen: @kitchen)
  end

  test 'page_profiles returns timing and query data for key pages' do
    profiler = ProfileBaseline.new(@kitchen, @user)
    results = profiler.page_profiles

    assert_kind_of Array, results
    assert results.size >= 4, "Expected at least 4 pages profiled, got #{results.size}"

    results.each do |result|
      assert result[:name].present?, 'Each result needs a page name'
      assert result[:time_ms].is_a?(Numeric), "#{result[:name]} time_ms should be numeric"
      assert result[:queries].is_a?(Integer), "#{result[:name]} queries should be integer"
      assert result[:html_bytes].is_a?(Integer), "#{result[:name]} html_bytes should be integer"
      assert result[:queries] >= 0, "#{result[:name]} query count should be non-negative"
      assert result[:html_bytes] > 0, "#{result[:name]} should return non-empty HTML"
    end
  end

  test 'asset_profiles returns bundle size data with gzipped sizes' do
    profiler = ProfileBaseline.new(@kitchen, @user)
    results = profiler.asset_profiles

    assert_kind_of Array, results

    results.each do |result|
      assert result[:name].present?
      assert result[:raw_bytes].is_a?(Integer)
      assert result[:gzipped_bytes].is_a?(Integer)
      assert result[:gzipped_bytes] <= result[:raw_bytes], "#{result[:name]} gzipped should be <= raw"
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `ruby -Itest test/lib/profile_baseline_test.rb`
Expected: FAIL — `ProfileBaseline` is not defined.

- [ ] **Step 3: Write the ProfileBaseline class**

Create `lib/profile_baseline.rb`:

```ruby
# frozen_string_literal: true

require 'zlib'

# Repeatable performance baseline for key pages and assets. Measures response
# time, SQL query count, and HTML size per page; raw and gzipped sizes for JS
# and CSS bundles. Output is a markdown table printed to stdout and appended
# to tmp/profile_baselines.log.
#
# Collaborators:
# - ActionDispatch::Integration::Session — makes requests without a running server
# - ActiveSupport::Notifications — counts SQL queries per request
# - db/seeds.rb — baseline reuses the seed kitchen/user pattern
class ProfileBaseline
  PAGES = [
    { name: 'Homepage', path: ->(_ks) { '/' } },
    { name: 'Menu', path: ->(ks) { "/kitchens/#{ks}/menu" } },
    { name: 'Groceries', path: ->(ks) { "/kitchens/#{ks}/groceries" } },
    { name: 'Recipe', path: ->(ks) { :recipe } }
  ].freeze

  WARMUP_RUNS = 1
  TIMED_RUNS = 3

  attr_reader :kitchen, :user

  def initialize(kitchen, user)
    @kitchen = kitchen
    @user = user
  end

  def page_profiles
    session = build_session
    log_in_session(session)

    PAGES.map { |page| profile_page(session, page) }
  end

  def asset_profiles
    asset_candidates.filter_map { |candidate| measure_asset(candidate) }
  end

  def format_report(page_results, asset_results)
    [page_table(page_results), asset_table(asset_results)].join("\n\n")
  end

  private

  def build_session
    ActionDispatch::Integration::Session.new(Rails.application)
  end

  # Path helpers are unavailable in Integration::Session outside tests
  def log_in_session(session)
    session.get "/dev_login/#{user.id}"
  end

  def profile_page(session, page)
    path = resolve_path(page)
    warmup(session, path)
    samples = collect_samples(session, path)
    summarize_samples(page[:name], samples)
  end

  def warmup(session, path)
    WARMUP_RUNS.times { session.get(path) }
  end

  def collect_samples(session, path)
    Array.new(TIMED_RUNS) do
      queries = count_queries { session.get(path) }
      { time_ms: extract_runtime(session), queries: queries, html_bytes: session.response.body.bytesize }
    end
  end

  def extract_runtime(session)
    session.response.headers['X-Runtime'].to_f * 1000
  end

  def summarize_samples(name, samples)
    { name: name,
      time_ms: samples.sum { |s| s[:time_ms] } / samples.size,
      queries: samples.map { |s| s[:queries] }.min,
      html_bytes: samples.last[:html_bytes] }
  end

  def resolve_path(page)
    result = page[:path].call(kitchen.slug)
    return result unless result == :recipe

    recipe = ActsAsTenant.with_tenant(kitchen) { Recipe.first }
    "/kitchens/#{kitchen.slug}/recipes/#{recipe.slug}"
  end

  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end

  def asset_candidates
    builds = Rails.root.join('app/assets/builds')
    chunks = Rails.root.join('public/chunks')

    [{ name: 'JS (main)', paths: [builds.join('application.js')].select(&:exist?) },
     { name: 'JS (CM chunk)', paths: chunks.exist? ? Dir.glob(chunks.join('*.js')) : [] },
     { name: 'CSS (total)', paths: Dir.glob(builds.join('*.css')) }]
  end

  def measure_asset(candidate)
    return if candidate[:paths].empty?

    raw = candidate[:paths].sum { |f| File.size(f) }
    gzipped = candidate[:paths].sum { |f| gzip_size(File.read(f)) }
    { name: candidate[:name], raw_bytes: raw, gzipped_bytes: gzipped }
  end

  def gzip_size(content)
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(content)
    gz.close
    io.string.bytesize
  end

  def page_table(results)
    header = "## Baseline — #{Time.now.strftime('%Y-%m-%d %H:%M')}\n\n"
    rows = results.map { |r| "| #{r[:name]} | #{r[:time_ms].round}ms | #{r[:queries]} | #{format_bytes(r[:html_bytes])} |" }
    header + "| Page | Time (avg) | Queries | HTML size |\n|------|-----------|---------|-----------|" \
      "\n#{rows.join("\n")}"
  end

  def asset_table(results)
    rows = results.map { |r| "| #{r[:name]} | #{format_bytes(r[:raw_bytes])} | #{format_bytes(r[:gzipped_bytes])} |" }
    "| Asset | Raw | Gzipped |\n|-------|-----|---------|" \
      "\n#{rows.join("\n")}"
  end

  def format_bytes(bytes)
    return '—' unless bytes

    "#{(bytes / 1024.0).round(1)} KB"
  end
end
```

- [ ] **Step 4: Write the rake task wrapper**

Create `lib/tasks/profile.rake`:

```ruby
# frozen_string_literal: true

require_relative '../profile_baseline'

namespace :profile do
  desc 'Run performance baseline: measure key pages and asset sizes'
  task baseline: :environment do
    kitchen = Kitchen.find_by!(slug: 'our-kitchen')
    user = kitchen.memberships.first&.user || User.first

    abort 'No kitchen or user found. Run db:seed first.' unless kitchen && user

    baseline = ProfileBaseline.new(kitchen, user)

    puts 'Profiling pages...'
    page_results = baseline.page_profiles

    puts 'Measuring assets...'
    asset_results = baseline.asset_profiles

    report = baseline.format_report(page_results, asset_results)
    puts "\n#{report}"

    log_path = Rails.root.join('tmp/profile_baselines.log')
    File.open(log_path, 'a') { |f| f.puts "\n#{report}\n" }
    puts "\nAppended to #{log_path}"
  end
end
```

- [ ] **Step 5: Add profile.rake to Rails/Output exclusion**

In `.rubocop.yml`, find the `Rails/Output` exclusion list (which already
includes `build_validator.rb` and `db/seeds.rb`) and add `lib/tasks/profile.rake`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `ruby -Itest test/lib/profile_baseline_test.rb`
Expected: Both tests pass.

- [ ] **Step 7: Run the full test suite**

Run: `bundle exec rake test`
Expected: All tests pass, including the new profile baseline tests.

- [ ] **Step 8: Run lint**

Run: `bundle exec rubocop`
Expected: No offenses.

- [ ] **Step 9: Commit**

```bash
git add lib/profile_baseline.rb lib/tasks/profile.rake test/lib/profile_baseline_test.rb .rubocop.yml
git commit -m "Add rake profile:baseline for repeatable performance measurement"
```

---

### Task 7: Verify End-to-End

- [ ] **Step 1: Run the full test suite with lint**

Run: `bundle exec rake`
Expected: All tests pass, no RuboCop offenses.

- [ ] **Step 2: Run size-limit**

Run: `npx size-limit`
Expected: Passes with the main bundle under the configured threshold.

- [ ] **Step 3: Run the baseline task against seed data**

If you have a seeded dev database:

Run: `bundle exec rake profile:baseline`
Expected: Markdown table printed with timing, query counts, and asset sizes for
all four pages. Report appended to `tmp/profile_baselines.log`.

If no seeded database exists, run `bin/rails db:seed` first.

- [ ] **Step 4: Verify rack-mini-profiler in browser**

Run: `bin/rails server -p 3030`
Visit any page. Confirm the mini-profiler badge shows in the bottom-left.
Click it to see query breakdown. Visit a page and append `?pp=flamegraph` to
generate a flamegraph. Kill the server.

- [ ] **Step 5: Update CLAUDE.md commands section**

Add `rake profile:baseline` to the commands block in CLAUDE.md:

```bash
rake profile:baseline  # performance baseline: page timing, queries, asset sizes (run quarterly + before releases)
```

- [ ] **Step 6: Final commit**

```bash
git add CLAUDE.md
git commit -m "Document rake profile:baseline in CLAUDE.md"
```

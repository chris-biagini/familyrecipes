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
    { name: 'Recipe', path: ->(_ks) { :recipe } }
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

  def log_in_session(session)
    session.get "/dev/login/#{user.id}"
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
      queries: samples.map { |s| s[:queries] }.min, # rubocop:disable Rails/Pluck
      html_bytes: samples.last[:html_bytes] }
  end

  def resolve_path(page)
    result = page[:path].call(kitchen.slug)
    return result unless result == :recipe

    recipe = ActsAsTenant.with_tenant(kitchen) { Recipe.first }
    "/kitchens/#{kitchen.slug}/recipes/#{recipe.slug}"
  end

  def count_queries(&)
    count = 0
    counter = lambda { |_name, _start, _finish, _id, payload|
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:cached]
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end

  def asset_candidates
    builds = Rails.root.join('app/assets/builds')
    chunks = Rails.public_path.join('chunks')

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
    rows = results.map { |r| page_row(r) }
    "## Baseline — #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}\n\n" \
      "| Page | Time (avg) | Queries | HTML size |\n|------|-----------|---------|-----------|" \
      "\n#{rows.join("\n")}"
  end

  def page_row(row)
    "| #{row[:name]} | #{row[:time_ms].round}ms | #{row[:queries]} | #{format_bytes(row[:html_bytes])} |"
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

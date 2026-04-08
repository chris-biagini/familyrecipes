#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 4: Generate ingredient-catalog.yaml entries from the reviewed
# search results. Fetches full USDA nutrient detail for each approved
# ingredient via the USDA API.
#
# Usage: USDA_API_KEY=xxx ruby scripts/seed_catalog/generate_yaml.rb
#        USDA_API_KEY=xxx ruby scripts/seed_catalog/generate_yaml.rb path/to/reviewed.json

require 'yaml'
require_relative 'shared'

REVIEWED_PATH = File.join(SeedCatalog::DATA_DIR, 'reviewed_results.json')
OUTPUT_PATH = File.join(SeedCatalog::DATA_DIR, 'seed_catalog.yaml')

EXISTING_CATALOG_PATH = File.join(
  File.expand_path('../../db/seeds/resources', __dir__),
  'ingredient-catalog.yaml'
)

def run(reviewed_path)
  client = build_client
  reviewed = SeedCatalog.read_json(reviewed_path)
  abort 'No reviewed data found. Export from the review page first.' if reviewed.empty?

  actionable = reviewed.select { |item| processable?(item) }
  puts "#{actionable.size} to process (#{reviewed.size} total)"

  catalog = fetch_catalog_entries(client, actionable)
  write_catalog(catalog)
  puts "Wrote #{catalog.size} entries to #{OUTPUT_PATH}"
end

def build_client
  api_key = ENV.fetch('USDA_API_KEY') { abort 'Set USDA_API_KEY environment variable' }
  FamilyRecipes::UsdaClient.new(api_key: api_key)
end

def fetch_catalog_entries(client, actionable) # rubocop:disable Metrics/MethodLength
  existing = load_existing_names

  actionable.each_with_object({}).with_index do |(item, catalog), index|
    name = item['name']
    label = "[#{index + 1}/#{actionable.size}] #{name}"

    if existing.include?(name.downcase)
      puts "#{label} — already in catalog, skipping"
      next
    end

    catalog[name] = fetch_entry(client, item, label)
    sleep 0.3
  rescue FamilyRecipes::UsdaClient::RateLimitError
    puts 'Rate limited — waiting 60s'
    sleep 60
    retry
  rescue FamilyRecipes::UsdaClient::Error => error
    puts "Error: #{error.message} — skipping"
  end
end

def fetch_entry(client, item, label)
  fdc_id = resolve_fdc_id(item)
  print "#{label} (FDC #{fdc_id})... "

  detail = client.fetch(fdc_id: fdc_id.to_s)
  review = item['review']
  aisle = review['aisle'] || item['aisle'] || 'Miscellaneous'
  aliases = review['aliases'] || item['aliases'] || []

  puts 'ok'
  SeedCatalog.build_catalog_entry(detail, aisle: aisle, aliases: aliases)
end

def processable?(item)
  status = item.dig('review', 'status')
  %w[accept override].include?(status)
end

def resolve_fdc_id(item)
  review = item['review']
  if review['status'] == 'override' && review['override_fdc_id']
    review['override_fdc_id']
  else
    item.dig('ai_pick', 'fdc_id')
  end
end

def load_existing_names
  return Set.new unless File.exist?(EXISTING_CATALOG_PATH)

  yaml = YAML.safe_load_file(
    EXISTING_CATALOG_PATH,
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  yaml.keys.to_set(&:downcase)
end

def write_catalog(catalog)
  sorted = catalog.sort_by { |name, _| name.downcase }.to_h
  File.write(OUTPUT_PATH, YAML.dump(sorted))
end

if $PROGRAM_NAME == __FILE__
  path = ARGV[0] || REVIEWED_PATH
  abort "Reviewed file not found: #{path}" unless File.exist?(path)
  run(path)
end

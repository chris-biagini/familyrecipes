#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 2a: Search USDA FoodData Central for each ingredient in the
# ingredient list. Writes results to usda_search_results.json.
# Resumable — skips ingredients already in the output file.
#
# Usage: USDA_API_KEY=xxx ruby scripts/seed_catalog/usda_search.rb
#        USDA_API_KEY=xxx ruby scripts/seed_catalog/usda_search.rb path/to/list.md

require_relative 'shared'

RESULTS_PATH = File.join(SeedCatalog::DATA_DIR, 'usda_search_results.json')
SEARCH_PAGE_SIZE = 15

def run(ingredient_list_path)
  client = build_client
  ingredients = SeedCatalog.parse_ingredient_list(ingredient_list_path)
  results = SeedCatalog.read_json(RESULTS_PATH)
  remaining = unsearched(ingredients, results)

  puts "#{ingredients.size} total, #{ingredients.size - remaining.size} already searched, #{remaining.size} remaining"
  search_each(client, remaining, results)
  puts "Done. Results saved to #{RESULTS_PATH}"
end

def build_client
  api_key = ENV.fetch('USDA_API_KEY') { abort 'Set USDA_API_KEY environment variable' }
  Mirepoix::UsdaClient.new(api_key: api_key)
end

def unsearched(ingredients, results)
  searched = results.to_set { |r| r['name'] }
  ingredients.reject { |i| searched.include?(i[:name]) }
end

def search_each(client, remaining, results)
  remaining.each_with_index do |ingredient, index|
    print "[#{index + 1}/#{remaining.size}] #{ingredient[:name]}... "

    response = client.search(ingredient[:name], page_size: SEARCH_PAGE_SIZE)
    results << build_result(ingredient, response[:foods])
    SeedCatalog.write_json(RESULTS_PATH, results)
    puts "#{response[:foods].size} results"

    sleep 0.3
  rescue Mirepoix::UsdaClient::RateLimitError
    puts 'Rate limited — waiting 60s'
    sleep 60
    retry
  rescue Mirepoix::UsdaClient::Error => error
    puts "Error: #{error.message} — skipping"
  end
end

def build_result(ingredient, foods)
  {
    'name' => ingredient[:name],
    'category' => ingredient[:category],
    'usda_results' => format_results(foods)
  }
end

def format_results(foods)
  foods.map do |food|
    {
      'fdc_id' => food[:fdc_id].to_s.to_i,
      'description' => food[:description],
      'dataset' => food[:data_type],
      'nutrient_summary' => food[:nutrient_summary]
    }
  end
end

if $PROGRAM_NAME == __FILE__
  list_path = ARGV[0] || File.join(SeedCatalog::DATA_DIR, 'ingredient_list.md')
  abort "Ingredient list not found: #{list_path}" unless File.exist?(list_path)
  run(list_path)
end

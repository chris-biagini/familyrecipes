# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module FamilyRecipes
  # HTTP client for the USDA FoodData Central API. Encapsulates search and
  # detail-fetch operations, error classification, and nutrient/portion
  # extraction. Used by bin/nutrition today; designed for future web integration.
  #
  # Collaborators: NutritionCalculator (consumes the nutrient hashes this
  # client produces), bin/nutrition (interactive CLI wrapper).
  class UsdaClient
    class Error < StandardError; end
    class NetworkError < Error; end
    class RateLimitError < Error; end
    class AuthError < Error; end
    class ServerError < Error; end
    class ParseError < Error; end

    BASE_URI = URI('https://api.nal.usda.gov')

    # USDA nutrient number -> our internal key (per 100g basis)
    NUTRIENT_MAP = {
      '208' => 'calories', '204' => 'fat', '606' => 'saturated_fat',
      '605' => 'trans_fat', '601' => 'cholesterol', '307' => 'sodium',
      '205' => 'carbs', '291' => 'fiber', '269' => 'total_sugars',
      '203' => 'protein'
    }.freeze

    VOLUME_UNITS = %w[cup cups tbsp tablespoon tablespoons tsp teaspoon teaspoons].freeze

    SEARCH_PREVIEW_NUTRIENTS = {
      '208' => 'cal', '204' => 'fat', '205' => 'carbs', '203' => 'protein'
    }.freeze

    def initialize(api_key:)
      @api_key = api_key
    end

    def search(query, page: 0, page_size: 10)
      body = { query: query, dataType: ['SR Legacy'], pageSize: page_size, pageNumber: page + 1 }
      format_search_response(post('/fdc/v1/foods/search', body), page)
    end

    def fetch(fdc_id:)
      format_fetch_response(get("/fdc/v1/food/#{fdc_id}"))
    end

    def self.load_api_key(project_root: nil)
      return ENV['USDA_API_KEY'] if ENV['USDA_API_KEY']

      parse_env_file(File.join(project_root || Dir.pwd, '.env'))
    end

    def self.parse_env_file(path)
      return nil unless File.exist?(path)

      File.readlines(path).each do |line|
        key, value = line.strip.split('=', 2)
        return value if key == 'USDA_API_KEY' && value && !value.empty?
      end
      nil
    end
    private_class_method :parse_env_file

    private

    def post(path, body)
      uri = URI.join(BASE_URI, path)
      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      request['X-Api-Key'] = @api_key
      request.body = body.to_json
      execute(uri, request)
    end

    def get(path)
      uri = URI.join(BASE_URI, path)
      request = Net::HTTP::Get.new(uri)
      request['X-Api-Key'] = @api_key
      execute(uri, request)
    end

    def execute(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      handle_response(response)
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => error
      raise NetworkError, error.message
    end

    def handle_response(response)
      return parse_json(response.body) if response.is_a?(Net::HTTPSuccess)

      code = response.code.to_i
      raise AuthError, "Authentication failed (#{code})" if [401, 403].include?(code)
      raise RateLimitError, "Rate limited (#{code})" if code == 429

      raise ServerError, "Server error (#{code})"
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise ParseError, error.message
    end

    def format_search_response(data, page)
      total = data['totalHits'] || 0
      page_size = data['pageSize'] || 10

      {
        foods: (data['foods'] || []).map { |f| format_search_result(f) },
        total_hits: total, total_pages: (total.to_f / page_size).ceil, current_page: page
      }
    end

    def format_search_result(food)
      {
        fdc_id: food['fdcId'], description: food['description'],
        data_type: food['dataType'], nutrient_summary: search_nutrient_summary(food)
      }
    end

    def search_nutrient_summary(food)
      lookup = (food['foodNutrients'] || []).to_h { |fn| [fn['nutrientNumber'], fn['value']] }
      SEARCH_PREVIEW_NUTRIENTS.map do |number, label|
        value = (lookup[number] || 0).round(0).to_i
        label == 'cal' ? "#{value} #{label}" : "#{value}g #{label}"
      end.join(' | ')
    end

    def format_fetch_response(data)
      {
        fdc_id: data['fdcId'], description: data['description'],
        data_type: data['dataType'] || 'SR Legacy',
        nutrients: extract_nutrients(data), portions: classify_portions(data)
      }
    end

    def extract_nutrients(food_detail)
      nutrients = NUTRIENT_MAP.each_value.with_object({ 'basis_grams' => 100.0 }) { |key, h| h[key] = 0.0 }
      (food_detail['foodNutrients'] || []).each do |fn|
        our_key = NUTRIENT_MAP[fn.dig('nutrient', 'number')]
        nutrients[our_key] = (fn['amount'] || 0.0).round(4) if our_key
      end
      # added_sugars not available in SR Legacy — hardcode to 0
      nutrients['added_sugars'] = 0.0
      nutrients
    end

    def classify_portions(food_detail)
      (food_detail['foodPortions'] || []).each_with_object(volume: [], non_volume: []) do |portion, result|
        entry = build_portion_entry(portion)
        next unless entry

        bucket = volume_unit?(portion['modifier']) ? :volume : :non_volume
        result[bucket] << entry
      end
    end

    def build_portion_entry(portion)
      modifier = portion['modifier'].to_s
      return if modifier.empty?

      grams = portion['gramWeight']
      return unless grams&.positive?

      { modifier: modifier, grams: grams, amount: portion['amount'] || 1.0 }
    end

    def volume_unit?(modifier)
      VOLUME_UNITS.include?(modifier.to_s.downcase.sub(/\s*\(.*\)/, '').strip)
    end
  end
end

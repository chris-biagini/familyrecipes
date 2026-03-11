# frozen_string_literal: true

require_relative 'test_helper'

class UsdaClientTest < Minitest::Test
  def setup
    @client = FamilyRecipes::UsdaClient.new(api_key: 'test-key')
  end

  # -- search --

  def test_search_returns_structured_results_with_pagination
    body = {
      'totalHits' => 25,
      'pageSize' => 10,
      'foods' => [
        {
          'fdcId' => 168_913,
          'description' => 'Flour, white, all-purpose',
          'dataType' => 'SR Legacy',
          'foodNutrients' => [
            { 'nutrientNumber' => '208', 'value' => 364.0 },
            { 'nutrientNumber' => '204', 'value' => 1.0 },
            { 'nutrientNumber' => '205', 'value' => 76.0 },
            { 'nutrientNumber' => '203', 'value' => 10.0 }
          ]
        }
      ]
    }

    with_api_response(200, body) do
      result = @client.search('flour', page: 0, page_size: 10)

      assert_equal 25, result[:total_hits]
      assert_equal 3, result[:total_pages]
      assert_equal 0, result[:current_page]
      assert_equal 1, result[:foods].size

      food = result[:foods].first

      assert_equal 168_913, food[:fdc_id]
      assert_equal 'Flour, white, all-purpose', food[:description]
      assert_equal '364 cal | 1g fat | 76g carbs | 10g protein', food[:nutrient_summary]
    end
  end

  def test_search_with_empty_results
    body = { 'totalHits' => 0, 'pageSize' => 10, 'foods' => [] }

    with_api_response(200, body) do
      result = @client.search('xyznonexistent')

      assert_equal 0, result[:total_hits]
      assert_equal 0, result[:total_pages]
      assert_empty result[:foods]
    end
  end

  # -- fetch --

  def test_fetch_extracts_nutrients_correctly
    body = sample_food_detail

    with_api_response(200, body) do
      result = @client.fetch(fdc_id: 168_913)

      assert_equal 168_913, result[:fdc_id]

      nutrients = result[:nutrients]

      assert_in_delta 100.0, nutrients['basis_grams']
      assert_in_delta 364.0, nutrients['calories']
      assert_in_delta 1.0, nutrients['fat']
      assert_in_delta 0.0, nutrients['added_sugars']
    end
  end

  def test_fetch_returns_flat_portions_array
    body = sample_food_detail

    with_api_response(200, body) do
      result = @client.fetch(fdc_id: 168_913)
      portions = result[:portions]

      assert_kind_of Array, portions
      assert_equal 2, portions.size
      assert_equal 'cup', portions.first[:modifier]
      assert_in_delta 125.0, portions.first[:grams]
      assert_equal 'serving', portions.last[:modifier]
    end
  end

  def test_fetch_skips_portions_with_empty_modifier
    body = {
      'fdcId' => 100, 'description' => 'Test',
      'foodNutrients' => [],
      'foodPortions' => [
        { 'modifier' => '', 'gramWeight' => 50.0, 'amount' => 1.0 },
        { 'modifier' => 'cup', 'gramWeight' => 125.0, 'amount' => 1.0 }
      ]
    }

    with_api_response(200, body) do
      result = @client.fetch(fdc_id: 100)

      assert_equal 1, result[:portions].size
      assert_equal 'cup', result[:portions].first[:modifier]
    end
  end

  # -- error handling --

  def test_raises_network_error_on_socket_error
    Net::HTTP.stub(:start, ->(*) { raise SocketError, 'getaddrinfo failed' }) do
      assert_raises(FamilyRecipes::UsdaClient::NetworkError) { @client.search('flour') }
    end
  end

  def test_raises_network_error_on_timeout
    Net::HTTP.stub(:start, ->(*) { raise Net::ReadTimeout, 'read timeout' }) do
      assert_raises(FamilyRecipes::UsdaClient::NetworkError) { @client.fetch(fdc_id: 1) }
    end
  end

  def test_raises_auth_error_on_unauthorized
    with_api_response(401, { 'error' => 'Unauthorized' }) do
      error = assert_raises(FamilyRecipes::UsdaClient::AuthError) { @client.search('flour') }

      assert_match(/401/, error.message)
    end
  end

  def test_raises_auth_error_on_forbidden
    with_api_response(403, { 'error' => 'Forbidden' }) do
      assert_raises(FamilyRecipes::UsdaClient::AuthError) { @client.search('flour') }
    end
  end

  def test_raises_rate_limit_error_on_too_many_requests
    with_api_response(429, { 'error' => 'Too Many Requests' }) do
      error = assert_raises(FamilyRecipes::UsdaClient::RateLimitError) { @client.search('flour') }

      assert_match(/429/, error.message)
    end
  end

  def test_raises_server_error_on_internal_error
    with_api_response(500, { 'error' => 'Internal Server Error' }) do
      error = assert_raises(FamilyRecipes::UsdaClient::ServerError) { @client.search('flour') }

      assert_match(/500/, error.message)
    end
  end

  def test_raises_parse_error_on_malformed_json
    with_api_response(200, 'not json at all') do
      assert_raises(FamilyRecipes::UsdaClient::ParseError) { @client.search('flour') }
    end
  end

  # -- load_api_key --

  def test_load_api_key_from_env
    original = ENV.fetch('USDA_API_KEY', nil)
    ENV['USDA_API_KEY'] = 'env-key-123'

    assert_equal 'env-key-123', FamilyRecipes::UsdaClient.load_api_key
  ensure
    restore_env('USDA_API_KEY', original)
  end

  def test_load_api_key_from_env_file
    original = ENV.fetch('USDA_API_KEY', nil)
    ENV.delete('USDA_API_KEY')

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.env'), "USDA_API_KEY=file-key-456\n")

      assert_equal 'file-key-456', FamilyRecipes::UsdaClient.load_api_key(project_root: dir)
    end
  ensure
    restore_env('USDA_API_KEY', original)
  end

  def test_load_api_key_returns_nil_when_missing
    original = ENV.fetch('USDA_API_KEY', nil)
    ENV.delete('USDA_API_KEY')

    Dir.mktmpdir do |dir|
      assert_nil FamilyRecipes::UsdaClient.load_api_key(project_root: dir)
    end
  ensure
    restore_env('USDA_API_KEY', original)
  end

  private

  def restore_env(key, value)
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end

  def with_api_response(code, body, &)
    body_string = body.is_a?(String) ? body : body.to_json
    mock_http = build_mock_http(code, body_string)

    Net::HTTP.stub(:start, ->(*, &blk) { blk.call(mock_http) }, &)
  end

  def build_mock_http(code, body_string)
    response = Net::HTTPResponse::CODE_TO_OBJ[code.to_s].new('1.1', code.to_s, '')
    response.instance_variable_set(:@body, body_string)
    response.instance_variable_set(:@read, true)

    mock = Object.new
    mock.define_singleton_method(:request) { |_| response }
    mock
  end

  def sample_food_detail
    {
      'fdcId' => 168_913,
      'description' => 'Flour, white, all-purpose, enriched, unbleached',
      'dataType' => 'SR Legacy',
      'foodNutrients' => [
        { 'nutrient' => { 'number' => '208' }, 'amount' => 364.0 },
        { 'nutrient' => { 'number' => '204' }, 'amount' => 1.0 },
        { 'nutrient' => { 'number' => '606' }, 'amount' => 0.15 },
        { 'nutrient' => { 'number' => '605' }, 'amount' => 0.0 },
        { 'nutrient' => { 'number' => '601' }, 'amount' => 0.0 },
        { 'nutrient' => { 'number' => '307' }, 'amount' => 2.0 },
        { 'nutrient' => { 'number' => '205' }, 'amount' => 76.0 },
        { 'nutrient' => { 'number' => '291' }, 'amount' => 2.7 },
        { 'nutrient' => { 'number' => '269' }, 'amount' => 0.27 },
        { 'nutrient' => { 'number' => '203' }, 'amount' => 10.0 }
      ],
      'foodPortions' => [
        { 'modifier' => 'cup', 'gramWeight' => 125.0, 'amount' => 1.0 },
        { 'modifier' => 'serving', 'gramWeight' => 30.0, 'amount' => 1.0 }
      ]
    }
  end
end

# frozen_string_literal: true

require 'test_helper'

class UsdaSearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    @kitchen.update!(usda_api_key: 'test-key-123')
  end

  # --- search ---

  test 'search returns paginated results as JSON' do
    mock_results = {
      foods: [{ fdc_id: 9003, description: 'Apples, raw', data_type: 'SR Legacy',
                nutrient_summary: '52 cal | 0g fat | 14g carbs | 0g protein' }],
      total_hits: 42, total_pages: 5, current_page: 0
    }

    stub_client_search('cream cheese', page: 0, result: mock_results) do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cream cheese', page: 0 }, as: :json
    end

    assert_response :success

    body = response.parsed_body

    assert_equal 42, body['total_hits']
    assert_equal 5, body['total_pages']
    assert_equal 1, body['foods'].size
    assert_equal 9003, body['foods'].first['fdc_id']
  end

  test 'search passes page parameter' do
    mock_results = { foods: [], total_hits: 0, total_pages: 0, current_page: 3 }

    stub_client_search('flour', page: 3, result: mock_results) do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'flour', page: 3 }, as: :json
    end

    assert_response :success
    assert_equal 3, response.parsed_body['current_page']
  end

  test 'search returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cheese' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'search returns error on UsdaClient failure' do
    mock_client = Minitest::Mock.new
    mock_client.expect :search, nil do
      raise FamilyRecipes::UsdaClient::NetworkError, 'connection refused'
    end

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cheese' }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal 'connection refused', response.parsed_body['error']
  end

  test 'search requires membership' do
    delete logout_path

    get usda_search_path(kitchen_slug: kitchen_slug), params: { q: 'cheese' }, as: :json

    assert_response :forbidden
  end

  # --- show ---

  test 'show returns import-ready data' do
    detail = usda_detail_fixture

    stub_client_fetch(9003, result: detail) do
      get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :success

    body = response.parsed_body

    assert body.key?('nutrients')
    assert body.key?('source')
    assert body.key?('portions')
    assert_equal 'usda', body['source']['type']
    assert_equal 9003, body['source']['fdc_id']
    assert_in_delta(52.0, body['nutrients']['calories'])
  end

  test 'show returns density when volume candidates exist' do
    detail = usda_detail_fixture(portions: [
                                   { modifier: 'cup, sliced', grams: 110.0, amount: 1.0 },
                                   { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 }
                                 ])

    stub_client_fetch(9003, result: detail) do
      get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :success

    body = response.parsed_body

    assert body.key?('density_candidates')
    assert_not_nil body['density']
  end

  test 'show returns no_api_key error when key is blank' do
    @kitchen.update!(usda_api_key: nil)

    get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'show returns error on UsdaClient failure' do
    mock_client = Minitest::Mock.new
    mock_client.expect :fetch, nil do
      raise FamilyRecipes::UsdaClient::AuthError, 'Authentication failed (403)'
    end

    FamilyRecipes::UsdaClient.stub :new, mock_client do
      get usda_show_path(9003, kitchen_slug: kitchen_slug), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal 'Authentication failed (403)', response.parsed_body['error']
  end

  private

  def usda_detail_fixture(portions: nil)
    {
      fdc_id: 9003, description: 'Apples, raw, with skin', data_type: 'SR Legacy',
      nutrients: {
        'basis_grams' => 100.0, 'calories' => 52.0, 'fat' => 0.17,
        'saturated_fat' => 0.028, 'trans_fat' => 0.0, 'cholesterol' => 0.0,
        'sodium' => 1.0, 'carbs' => 13.81, 'fiber' => 2.4,
        'total_sugars' => 10.39, 'added_sugars' => 0.0, 'protein' => 0.26
      },
      portions: portions || [
        { modifier: 'cup, quartered or chopped', grams: 125.0, amount: 1.0 },
        { modifier: 'medium (3" dia)', grams: 182.0, amount: 1.0 }
      ]
    }
  end

  def stub_client_search(query, page:, result:, &)
    mock_client = Minitest::Mock.new
    mock_client.expect :search, result, [query], page: page

    FamilyRecipes::UsdaClient.stub(:new, mock_client, &)

    mock_client.verify
  end

  def stub_client_fetch(fdc_id, result:, &)
    mock_client = Minitest::Mock.new
    mock_client.expect :fetch, result, [], fdc_id: fdc_id.to_s

    FamilyRecipes::UsdaClient.stub(:new, mock_client, &)

    mock_client.verify
  end
end

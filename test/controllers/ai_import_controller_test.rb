# frozen_string_literal: true

require 'test_helper'

class AiImportControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    @kitchen.update!(anthropic_api_key: 'sk-ant-test-key')
  end

  test 'create returns markdown on success' do
    mock_result = AiImportService::Result.new(markdown: '# Pancakes', error: nil)

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'pancake recipe' }, as: :json
    end

    assert_response :success
    assert_equal '# Pancakes', response.parsed_body['markdown']
  end

  test 'create returns 422 when no API key' do
    mock_result = AiImportService::Result.new(markdown: nil, error: 'no_api_key')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal 'no_api_key', response.parsed_body['error']
  end

  test 'create returns 422 on invalid API key' do
    mock_result = AiImportService::Result.new(markdown: nil,
                                              error: 'Invalid Anthropic API key. Check your key in Settings.')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['error'], 'API key'
  end

  test 'create returns 422 when text is blank' do
    post ai_import_path(kitchen_slug: kitchen_slug),
         params: { text: '' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'Text is required', response.parsed_body['error']
  end

  test 'create returns 503 on API failure' do
    mock_result = AiImportService::Result.new(markdown: nil, error: 'Could not reach the Anthropic API.')

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'recipe' }, as: :json
    end

    assert_response :service_unavailable
    assert_includes response.parsed_body['error'], 'Anthropic'
  end

  test 'create requires membership' do
    delete logout_path

    post ai_import_path(kitchen_slug: kitchen_slug),
         params: { text: 'recipe' }, as: :json

    assert_response :forbidden
  end
end

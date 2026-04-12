# frozen_string_literal: true

require 'test_helper'

class AiImportControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_kitchen_and_user
    log_in
    ENV['ANTHROPIC_API_KEY'] = 'sk-ant-test-key'
  end

  teardown do
    ENV.delete('ANTHROPIC_API_KEY')
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

  test 'create passes expert mode to service' do
    captured_mode = nil
    original_call = AiImportService.method(:call)

    AiImportService.define_singleton_method(:call) do |text:, kitchen:, mode: :faithful|
      captured_mode = mode
      original_call.call(text:, kitchen:, mode:)
    end

    mock_result = AiImportService::Result.new(markdown: '# Tacos', error: nil)
    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'taco recipe', mode: 'expert' }, as: :json
    end

    assert_response :success
  end

  test 'create defaults to faithful mode' do
    mock_result = AiImportService::Result.new(markdown: '# Tacos', error: nil)

    AiImportService.stub :call, mock_result do
      post ai_import_path(kitchen_slug: kitchen_slug),
           params: { text: 'taco recipe' }, as: :json
    end

    assert_response :success
  end

  test 'create requires membership' do
    delete logout_path

    post ai_import_path(kitchen_slug: kitchen_slug),
         params: { text: 'recipe' }, as: :json

    assert_response :forbidden
  end
end

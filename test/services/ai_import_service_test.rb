# frozen_string_literal: true

require 'test_helper'

class AiImportServiceTest < ActiveSupport::TestCase
  MockContent = Struct.new(:type, :text)
  MockResponse = Struct.new(:content)

  setup do
    setup_test_kitchen
    @kitchen.update!(anthropic_api_key: 'sk-test-key-123')
    Category.find_or_create_for(@kitchen, 'Baking')
    Category.find_or_create_for(@kitchen, 'Mains')
  end

  test 'returns markdown on successful API call' do
    result = with_anthropic_response("# Bagels\n\nStep one\n- 3 cups flour") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\nStep one\n- 3 cups flour", result.markdown
    assert_nil result.error
  end

  test 'returns error when no API key configured' do
    @kitchen.update!(anthropic_api_key: nil)

    result = AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)

    assert_nil result.markdown
    assert_equal 'no_api_key', result.error
  end

  test 'sends single user message' do
    captured_messages = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Simple')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_messages = kwargs[:messages]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'some recipe', kitchen: @kitchen)
    end

    assert_equal 1, captured_messages.size
    assert_equal 'user', captured_messages[0][:role]
  end

  test 'interpolates kitchen categories into prompt' do
    captured_system = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Test')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_system = kwargs[:system]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'recipe', kitchen: @kitchen)
    end

    assert_includes captured_system, 'Baking'
    assert_includes captured_system, 'Mains'
    assert_includes captured_system, 'Miscellaneous'
  end

  test 'uses sonnet model' do
    captured_model = nil
    mock_response = MockResponse.new([MockContent.new(:text, '# Test')])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) do |**kwargs|
      captured_model = kwargs[:model]
      mock_response
    end

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub :new, mock_client do
      AiImportService.call(text: 'recipe', kitchen: @kitchen)
    end

    assert_equal 'claude-sonnet-4-6', captured_model
  end

  test 'strips code fences from response' do
    result = with_anthropic_response("```markdown\n# Bagels\n\n- 3 cups flour\n```") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\n- 3 cups flour", result.markdown
  end

  test 'strips leading text before first heading' do
    result = with_anthropic_response("Here is your recipe:\n\n# Bagels\n\n- 3 cups flour") do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_equal "# Bagels\n\n- 3 cups flour", result.markdown
  end

  test 'returns error on authentication failure' do
    result = with_anthropic_error(Anthropic::Errors::AuthenticationError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Invalid Anthropic API key. Check your key in Settings.', result.error
  end

  test 'returns error on rate limit' do
    result = with_anthropic_error(Anthropic::Errors::RateLimitError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Rate limited by Anthropic. Wait a moment and try again.', result.error
  end

  test 'returns error on connection failure' do
    result = with_anthropic_error(Anthropic::Errors::APIConnectionError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Could not reach the Anthropic API. Check your connection.', result.error
  end

  test 'returns error on timeout' do
    result = with_anthropic_error(Anthropic::Errors::APITimeoutError) do
      AiImportService.call(text: 'recipe for bagels', kitchen: @kitchen)
    end

    assert_nil result.markdown
    assert_equal 'Request timed out. Try again.', result.error
  end

  private

  def with_anthropic_response(text, &)
    mock_response = MockResponse.new([MockContent.new(:text, text)])

    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) { |**_kwargs| mock_response }

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub(:new, mock_client, &)
  end

  def build_error(error_class)
    if error_class <= Anthropic::Errors::APIStatusError
      error_class.new(url: 'https://api.anthropic.com', status: 400, headers: {},
                      body: nil, request: {}, response: {}, message: 'test error')
    else
      error_class.new(url: 'https://api.anthropic.com', message: 'test error')
    end
  end

  def with_anthropic_error(error_class, &)
    err = build_error(error_class)
    mock_messages = Object.new
    mock_messages.define_singleton_method(:create) { |**_kwargs| raise err }

    mock_client = Object.new
    mock_client.define_singleton_method(:messages) { mock_messages }

    Anthropic::Client.stub(:new, mock_client, &)
  end
end

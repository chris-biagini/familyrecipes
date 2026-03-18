# frozen_string_literal: true

# Sends user-pasted text to the Anthropic API for conversion into the app's
# Markdown recipe format. Pure function — no database writes or side effects.
# Multi-turn support: pass previous_result + feedback for iterative refinement.
#
# - Kitchen#anthropic_api_key: encrypted API key for Anthropic
# - Kitchen::AI_MODEL: model identifier (e.g. claude-sonnet-4-6)
# - lib/familyrecipes/ai_import_prompt.md: system prompt defining output format
class AiImportService
  Result = Data.define(:markdown, :error)

  SYSTEM_PROMPT = Rails.root.join('lib/familyrecipes/ai_import_prompt.md').read.freeze
  MAX_TOKENS = 8192

  def self.call(text:, kitchen:, previous_result: nil, feedback: nil)
    new(kitchen:).call(text:, previous_result:, feedback:)
  end

  def initialize(kitchen:)
    @api_key = kitchen.anthropic_api_key
  end

  def call(text:, previous_result: nil, feedback: nil)
    return Result.new(markdown: nil, error: 'no_api_key') if @api_key.blank?

    markdown = fetch_completion(text:, previous_result:, feedback:)
    Result.new(markdown: clean_output(markdown), error: nil)
  rescue Anthropic::Errors::AuthenticationError
    Result.new(markdown: nil, error: 'Invalid Anthropic API key. Check your key in Settings.')
  rescue Anthropic::Errors::RateLimitError
    Result.new(markdown: nil, error: 'Rate limited by Anthropic. Wait a moment and try again.')
  rescue Anthropic::Errors::APITimeoutError
    Result.new(markdown: nil, error: 'Request timed out. Try again.')
  rescue Anthropic::Errors::APIConnectionError
    Result.new(markdown: nil, error: 'Could not reach the Anthropic API. Check your connection.')
  rescue Anthropic::Errors::APIError => error
    Result.new(markdown: nil, error: "AI import failed: #{error.message}")
  end

  private

  def fetch_completion(text:, previous_result:, feedback:)
    response = client.messages.create(
      model: Kitchen::AI_MODEL,
      max_tokens: MAX_TOKENS,
      system: SYSTEM_PROMPT,
      messages: build_messages(text:, previous_result:, feedback:)
    )
    response.content.find { |block| block.type == :text }&.text || ''
  end

  def build_messages(text:, previous_result:, feedback:)
    messages = [{ role: 'user', content: text }]
    return messages unless previous_result && feedback

    messages << { role: 'assistant', content: previous_result }
    messages << { role: 'user', content: feedback }
  end

  def clean_output(text)
    text = strip_code_fences(text)
    strip_leading_preamble(text)
  end

  def strip_code_fences(text)
    text.gsub(/\A```\w*\n/, '').delete_suffix("\n```")
  end

  def strip_leading_preamble(text)
    heading_index = text.index(/^# /)
    heading_index ? text[heading_index..] : text
  end

  def client
    Anthropic::Client.new(api_key: @api_key, timeout: 90)
  end
end

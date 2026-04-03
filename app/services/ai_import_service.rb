# frozen_string_literal: true

# Sends user-pasted text to the Anthropic API for conversion into the app's
# Markdown recipe format. Pure function — no database writes or side effects.
# One-shot pipeline: text in, formatted recipe out.
#
# The system prompt is a template with {{CATEGORIES}} and {{TAGS}} placeholders
# interpolated from the kitchen's current taxonomy at call time.
#
# - Kitchen#anthropic_api_key: encrypted API key for Anthropic
# - Kitchen::AI_MODEL: model identifier (claude-haiku-4-5)
# - lib/familyrecipes/ai_import_prompt.md: prompt template with dynamic slots
class AiImportService
  Result = Data.define(:markdown, :error)

  PROMPT_TEMPLATE = Rails.root.join('lib/familyrecipes/ai_import_prompt.md').read.freeze
  MAX_TOKENS = 8192

  def self.call(text:, kitchen:)
    new(kitchen:).call(text:)
  end

  def initialize(kitchen:)
    @api_key = kitchen.anthropic_api_key
    @kitchen = kitchen
  end

  def call(text:)
    return Result.new(markdown: nil, error: 'no_api_key') if @api_key.blank?

    markdown = fetch_completion(text:)
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

  def fetch_completion(text:)
    response = client.messages.create(
      model: Kitchen::AI_MODEL,
      max_tokens: MAX_TOKENS,
      system: build_system_prompt,
      messages: [{ role: 'user', content: text }]
    )
    response.content.find { |block| block.type == :text }&.text || ''
  end

  def build_system_prompt
    categories = @kitchen.categories.pluck(:name).sort
    categories << 'Miscellaneous' unless categories.include?('Miscellaneous')

    PROMPT_TEMPLATE.gsub('{{CATEGORIES}}', categories.join(', '))
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
    Anthropic::Client.new(api_key: @api_key, timeout: 30)
  end
end

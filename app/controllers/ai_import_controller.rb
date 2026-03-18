# frozen_string_literal: true

# Thin JSON adapter for AI-powered recipe import. Accepts pasted recipe text,
# delegates to AiImportService for Anthropic API call, returns generated Markdown.
# The no_api_key error returns 422; upstream API failures return 503.
#
# Collaborators:
# - AiImportService (API call orchestration)
# - Kitchen#anthropic_api_key (key presence check)
class AiImportController < ApplicationController
  before_action :require_membership

  def create
    text = params[:text].to_s.strip
    return render json: { error: 'Text is required' }, status: :unprocessable_content if text.blank?

    result = AiImportService.call(text:, kitchen: current_kitchen)

    if result.markdown
      render json: { markdown: result.markdown }
    elsif result.error == 'no_api_key' || result.error&.include?('API key')
      render json: { error: result.error }, status: :unprocessable_content
    else
      render json: { error: result.error }, status: :service_unavailable
    end
  end
end

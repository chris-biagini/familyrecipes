# frozen_string_literal: true

# JSON API for USDA FoodData Central search and detail fetch. Reads the USDA
# API key from the current kitchen's encrypted settings. Search returns
# paginated results with nutrient previews; show fetches full detail and pipes
# it through UsdaImportService to produce editor-ready form values.
#
# Collaborators:
# - UsdaClient (HTTP adapter for USDA FoodData Central)
# - UsdaImportService (transforms raw USDA detail into catalog form values)
# - Kitchen#usda_api_key (encrypted API key storage)
class UsdaSearchController < ApplicationController
  before_action :require_membership
  before_action :require_api_key

  def search
    result = usda_client.search(params[:q], page: params.fetch(:page, 0).to_i)
    render json: result
  rescue Mirepoix::UsdaClient::Error => error
    render json: { error: error.message }, status: :unprocessable_content
  end

  def show
    detail = usda_client.fetch(fdc_id: params[:fdc_id])
    import = UsdaImportService.call(detail)
    render json: import
  rescue Mirepoix::UsdaClient::Error => error
    render json: { error: error.message }, status: :unprocessable_content
  end

  private

  def require_api_key
    return if current_kitchen.usda_api_key.present?

    render json: { error: 'no_api_key' }, status: :unprocessable_content
  end

  def usda_client
    Mirepoix::UsdaClient.new(api_key: current_kitchen.usda_api_key)
  end
end

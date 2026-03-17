# frozen_string_literal: true

class AddAnthropicApiKeyToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :anthropic_api_key, :string
  end
end

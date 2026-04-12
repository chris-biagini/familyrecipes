# frozen_string_literal: true

class RemoveApiKeysFromKitchens < ActiveRecord::Migration[8.0]
  def change
    remove_column :kitchens, :usda_api_key, :string
    remove_column :kitchens, :anthropic_api_key, :string
  end
end

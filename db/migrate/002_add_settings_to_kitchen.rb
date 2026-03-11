# frozen_string_literal: true

class AddSettingsToKitchen < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :site_title, :string, default: 'Family Recipes'
    add_column :kitchens, :homepage_heading, :string, default: 'Our Recipes'
    add_column :kitchens, :homepage_subtitle, :string, default: "A collection of our family\u2019s favorite recipes."
    add_column :kitchens, :usda_api_key, :string
  end
end

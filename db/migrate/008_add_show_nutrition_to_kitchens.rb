# frozen_string_literal: true

class AddShowNutritionToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :show_nutrition, :boolean, default: false, null: false
  end
end

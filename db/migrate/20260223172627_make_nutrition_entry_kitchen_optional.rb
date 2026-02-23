# frozen_string_literal: true

class MakeNutritionEntryKitchenOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :nutrition_entries, :kitchen_id, true

    add_index :nutrition_entries, :ingredient_name,
              unique: true,
              where: 'kitchen_id IS NULL',
              name: 'index_nutrition_entries_global_unique'
  end
end

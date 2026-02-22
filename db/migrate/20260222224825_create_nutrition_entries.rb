# frozen_string_literal: true

class CreateNutritionEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :nutrition_entries do |t|
      t.references :kitchen, null: false, foreign_key: true

      t.string :ingredient_name, null: false
      t.decimal :basis_grams, null: false

      # 11 FDA-label nutrients
      t.decimal :calories
      t.decimal :fat
      t.decimal :saturated_fat
      t.decimal :trans_fat
      t.decimal :cholesterol
      t.decimal :sodium
      t.decimal :carbs
      t.decimal :fiber
      t.decimal :total_sugars
      t.decimal :added_sugars
      t.decimal :protein

      # Density data for volume unit resolution
      t.decimal :density_grams
      t.decimal :density_volume
      t.string :density_unit

      # Named portions (e.g., { "stick" => 113.0 })
      t.jsonb :portions, default: {}

      # Source provenance (e.g., [{ "type" => "usda", "fdc_id" => 168913 }])
      t.jsonb :sources, default: []

      t.timestamps
    end

    add_index :nutrition_entries, %i[kitchen_id ingredient_name], unique: true
  end
end

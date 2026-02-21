# frozen_string_literal: true

class CreateNutritionEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :nutrition_entries do |t|
      t.string :ingredient_name, null: false
      t.decimal :basis_grams, null: false
      t.decimal :calories, null: false
      t.decimal :fat, null: false
      t.decimal :saturated_fat, null: false
      t.decimal :trans_fat, null: false
      t.decimal :cholesterol, null: false
      t.decimal :sodium, null: false
      t.decimal :carbs, null: false
      t.decimal :fiber, null: false
      t.decimal :total_sugars, null: false
      t.decimal :added_sugars, null: false
      t.decimal :protein, null: false
      t.decimal :density_grams
      t.decimal :density_volume
      t.string :density_unit
      t.jsonb :portions
      t.jsonb :sources

      t.timestamps
    end

    add_index :nutrition_entries, :ingredient_name, unique: true
  end
end

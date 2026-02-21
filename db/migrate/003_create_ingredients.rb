# frozen_string_literal: true

class CreateIngredients < ActiveRecord::Migration[8.0]
  def change
    create_table :ingredients do |t|
      t.references :step, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.string :quantity
      t.string :prep_note

      t.timestamps
    end
  end
end

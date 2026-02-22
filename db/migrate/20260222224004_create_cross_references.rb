# frozen_string_literal: true

class CreateCrossReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :cross_references do |t|
      t.references :step, null: false, foreign_key: true
      t.references :kitchen, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.decimal :multiplier, precision: 8, scale: 2, default: 1.0, null: false
      t.string :prep_note
      t.integer :position, null: false

      t.timestamps
    end

    add_index :cross_references, %i[step_id position], unique: true
  end
end

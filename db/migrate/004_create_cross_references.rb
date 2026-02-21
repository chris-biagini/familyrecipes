# frozen_string_literal: true

class CreateCrossReferences < ActiveRecord::Migration[8.0]
  def change
    create_table :cross_references do |t|
      t.references :step, null: false, foreign_key: true
      t.references :recipe, null: false, foreign_key: true
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }
      t.integer :position, null: false
      t.decimal :multiplier, null: false, default: 1.0
      t.string :prep_note

      t.timestamps
    end
  end
end

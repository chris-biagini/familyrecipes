# frozen_string_literal: true

class CreateSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :steps do |t|
      t.references :recipe, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.text :instructions

      t.timestamps
    end
  end
end

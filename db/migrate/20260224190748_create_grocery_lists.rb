# frozen_string_literal: true

class CreateGroceryLists < ActiveRecord::Migration[8.1]
  def change
    create_table :grocery_lists do |t|
      t.references :kitchen, null: false, foreign_key: true, index: { unique: true }
      t.integer :version, null: false, default: 0
      t.jsonb :state, null: false, default: {}
      t.timestamps
    end
  end
end

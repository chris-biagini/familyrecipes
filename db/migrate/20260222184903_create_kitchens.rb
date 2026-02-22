# frozen_string_literal: true

class CreateKitchens < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchens do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :kitchens, :slug, unique: true
  end
end

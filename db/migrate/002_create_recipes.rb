# frozen_string_literal: true

class CreateRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :recipes do |t|
      t.references :category, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.decimal :makes_quantity
      t.string :makes_unit_noun
      t.integer :serves
      t.text :footer
      t.text :markdown_source, null: false

      t.timestamps
    end

    add_index :recipes, :slug, unique: true
  end
end

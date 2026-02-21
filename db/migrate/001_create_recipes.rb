# frozen_string_literal: true

class CreateRecipes < ActiveRecord::Migration[8.0]
  def change
    create_table :recipes do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category, null: false
      t.string :makes
      t.integer :serves
      t.text :footer
      t.text :source_markdown, null: false
      t.string :version_hash, null: false
      t.boolean :quick_bite, null: false, default: false

      t.timestamps
    end

    add_index :recipes, :slug, unique: true
    add_index :recipes, :category
  end
end

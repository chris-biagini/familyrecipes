# frozen_string_literal: true

class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.references :kitchen, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :tags, %i[kitchen_id name], unique: true

    create_table :recipe_tags do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :recipe_tags, %i[recipe_id tag_id], unique: true
  end
end

# frozen_string_literal: true

class AddKitchenIdToExistingTables < ActiveRecord::Migration[8.1]
  def change
    add_reference :categories, :kitchen, null: false, foreign_key: true
    add_reference :recipes, :kitchen, null: false, foreign_key: true
    add_reference :site_documents, :kitchen, null: false, foreign_key: true

    # Replace globally-unique slug/name indexes with kitchen-scoped composites
    remove_index :categories, :slug
    add_index :categories, %i[kitchen_id slug], unique: true

    remove_index :recipes, :slug
    add_index :recipes, %i[kitchen_id slug], unique: true

    remove_index :site_documents, :name
    add_index :site_documents, %i[kitchen_id name], unique: true
  end
end

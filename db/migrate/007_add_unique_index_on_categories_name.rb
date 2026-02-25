# frozen_string_literal: true

class AddUniqueIndexOnCategoriesName < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, %i[kitchen_id name], unique: true
  end
end

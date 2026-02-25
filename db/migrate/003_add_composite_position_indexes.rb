# frozen_string_literal: true

class AddCompositePositionIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :steps, %i[recipe_id position], unique: true
    add_index :ingredients, %i[step_id position], unique: true

    remove_index :steps, :recipe_id
    remove_index :ingredients, :step_id
  end
end

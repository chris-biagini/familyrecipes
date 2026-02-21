# frozen_string_literal: true

class CreateRecipeDependencies < ActiveRecord::Migration[8.0]
  def change
    create_table :recipe_dependencies do |t|
      t.references :source_recipe, null: false, foreign_key: { to_table: :recipes }
      t.references :target_recipe, null: false, foreign_key: { to_table: :recipes }

      t.timestamps
    end

    add_index :recipe_dependencies, %i[source_recipe_id target_recipe_id], unique: true
  end
end

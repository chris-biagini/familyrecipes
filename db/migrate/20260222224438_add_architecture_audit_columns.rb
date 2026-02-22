# frozen_string_literal: true

class AddArchitectureAuditColumns < ActiveRecord::Migration[8.1]
  def change
    add_reference :recipe_dependencies, :kitchen, null: true, foreign_key: true
    add_column :recipes, :nutrition_data, :jsonb
    add_column :steps, :processed_instructions, :text

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE recipe_dependencies
          SET kitchen_id = recipes.kitchen_id
          FROM recipes
          WHERE recipe_dependencies.source_recipe_id = recipes.id
        SQL

        change_column_null :recipe_dependencies, :kitchen_id, false
      end
    end
  end
end

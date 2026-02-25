# frozen_string_literal: true

class AddDeferredCrossReferenceColumns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :cross_references, :target_recipe_id, true

    add_column :cross_references, :target_slug, :string
    add_column :cross_references, :target_title, :string

    # Backfill from existing resolved references
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE cross_references
          SET target_slug = (SELECT slug FROM recipes WHERE recipes.id = cross_references.target_recipe_id),
              target_title = (SELECT title FROM recipes WHERE recipes.id = cross_references.target_recipe_id)
          WHERE target_recipe_id IS NOT NULL
        SQL
      end
    end

    change_column_null :cross_references, :target_slug, false
    change_column_null :cross_references, :target_title, false
  end
end

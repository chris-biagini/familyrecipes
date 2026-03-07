# frozen_string_literal: true

class AddNocaseToIngredientName < ActiveRecord::Migration[8.0]
  def up
    change_column :ingredient_catalog, :ingredient_name, :string, null: false, collation: 'NOCASE'
  end

  def down
    change_column :ingredient_catalog, :ingredient_name, :string, null: false
  end
end

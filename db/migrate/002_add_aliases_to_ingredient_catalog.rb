# frozen_string_literal: true

class AddAliasesToIngredientCatalog < ActiveRecord::Migration[8.1]
  def change
    add_column :ingredient_catalog, :aliases, :json, default: []
  end
end

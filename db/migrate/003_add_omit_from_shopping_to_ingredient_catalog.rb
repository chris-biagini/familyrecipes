# frozen_string_literal: true

class AddOmitFromShoppingToIngredientCatalog < ActiveRecord::Migration[8.0]
  def up
    add_column :ingredient_catalog, :omit_from_shopping, :boolean, default: false, null: false
    execute "UPDATE ingredient_catalog SET omit_from_shopping = 1, aisle = NULL WHERE aisle = 'omit'"
  end

  def down
    execute "UPDATE ingredient_catalog SET aisle = 'omit' WHERE omit_from_shopping = 1"
    remove_column :ingredient_catalog, :omit_from_shopping
  end
end
